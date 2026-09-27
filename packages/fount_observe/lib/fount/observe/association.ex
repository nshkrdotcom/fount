defmodule Fount.Observe.Association do
  @moduledoc "Reassembles neutral batch results by exact index. Duplicate indexes invalidate all competing answers."
  alias Fount.Observe.{Error, ProviderResult, Request}

  def assemble(requests, results) when is_list(requests) and is_list(results) do
    size = length(requests)

    {valid, invalid} =
      Enum.split_with(results, fn
        %ProviderResult{batch_index: index} -> is_integer(index) and index >= 0 and index < size
        _ -> false
      end)

    indexed = Enum.group_by(valid, & &1.batch_index)

    global_errors =
      Enum.map(invalid, fn _ ->
        Error.new(:association_error, nil, %{"reason" => "invalid_batch_index"})
      end)

    entries =
      requests
      |> Enum.with_index()
      |> Enum.map(fn {%Request{} = request, index} ->
        result =
          case Map.get(indexed, index, []) do
            [one] -> one
            [] -> failure(index, request.id, "missing_response")
            _ -> failure(index, request.id, "duplicate_response")
          end

        result =
          if match?(%Error{}, result.error),
            do: %{result | error: %{result.error | request_id: request.id}},
            else: result

        {request, result}
      end)

    errors = for {_, %ProviderResult{error: %Error{} = error}} <- entries, do: error
    {entries, global_errors ++ errors}
  end

  defp failure(index, id, reason),
    do: %ProviderResult{
      batch_index: index,
      error: Error.new(:association_error, id, %{"reason" => reason})
    }
end
