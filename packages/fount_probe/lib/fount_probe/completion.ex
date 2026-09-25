defmodule FountProbe.Completion do
  @moduledoc """
  Structured or JSON-text completion through Inference.

  A trusted local validator is mandatory. Text fallback uses the same validator
  as structured responses, permits only a whole JSON value/code fence, and never
  searches an arbitrary provider response for a convenient JSON substring.
  """

  def complete(client, prompt, schema, validator, opts \\ [])
      when is_binary(prompt) and is_map(schema) and is_function(validator, 1) do
    name = Keyword.get(opts, :name, "fount_writing")
    repairs = Keyword.get(opts, :decode_repairs, 1)
    capabilities = Inference.capabilities(client)
    structured = Inference.Capability.supported?(capabilities, :response_format_json_schema)
    mode = if structured, do: "json_schema", else: "json_text"
    original = prompt
    max_bytes = Keyword.get(opts, :max_context_bytes, 100_000)
    if byte_size(prompt) + byte_size(Jason.encode!(schema)) > max_bytes do
      {:error, :context_limit, []}
    else
      attempt(client, original, original, schema, name, validator, mode, repairs, [], opts)
    end
  end

  def decode(text) when is_binary(text) do
    trimmed = String.trim(text)

    json =
      case Regex.run(~r/\A```(?:json)?\s*\n(.*)\n```\z/s, trimmed, capture: :all_but_first) do
        [body] -> body
        nil -> trimmed
      end

    case Jason.decode(json) do
      {:ok, object} when is_map(object) -> {:ok, object}
      {:ok, _} -> {:error, :expected_json_object}
      {:error, _} -> {:error, :invalid_json_response}
    end
  end

  def decode(_), do: {:error, :missing_response_text}

  defp attempt(client, original, prompt, schema, name, validator, mode, repairs, trace, opts) do
    options =
      if mode == "json_schema" do
        [response_format: {:json_schema, %{name: name, strict: true, schema: schema}}]
      else
        []
      end

    request =
      if mode == "json_text" do
        prompt <>
          "\nReturn exactly one JSON object conforming to this schema:\n" <>
          Jason.encode!(schema)
      else
        prompt
      end

    result = cond do
      byte_size(request) + byte_size(Jason.encode!(schema)) > Keyword.get(opts, :max_context_bytes, 100_000) -> {:error, :context_limit}
      FountProbe.Budget.take(Keyword.get(opts, :budget), :inference, 1) == 0 -> {:error, :session_inference_limit}
      true -> Inference.complete(client, request, options)
    end
    case result do
      {:error, error} ->
        {:error, error, Enum.reverse(trace)}

      {:ok, response} ->
        entry = %{
          "mode" => mode,
          "request_sha256" => hash(request),
          "response_sha256" =>
            hash(
              Jason.encode!(%{
                "text" => Map.get(response, :text),
                "object" => Map.get(response, :object)
              })
            ),
          "model" => Map.get(response, :model),
          "finish_reason" => Map.get(response, :finish_reason),
          "response_id" => Map.get(response, :id), "usage" => Map.get(response, :usage)
        }

        decoded =
          if mode == "json_schema" do
            case Map.get(response, :object) do
              object when is_map(object) -> {:ok, object}
              _ -> {:error, :missing_structured_object}
            end
          else
            decode(Map.get(response, :text))
          end

        validated =
          with {:ok, object} <- decoded,
               :ok <- validator.(object) do
            {:ok, object}
          end

        case validated do
          {:ok, object} ->
            {:ok, object, Enum.reverse([entry | trace])}

          {:error, errors} when repairs > 0 ->
            repair_prompt =
              original <>
                "\nThe previous response failed local validation. Correct only the output " <>
                "representation and these errors. Do not alter writer requirements or base IDs.\n" <>
                inspect(errors, limit: 100, printable_limit: 8_000)

            attempt(client, original, repair_prompt, schema, name, validator, mode, repairs - 1, [
              Map.put(entry, "validation", "failed") | trace
            ], opts)

          {:error, errors} ->
            {:error, {:invalid_completion, errors},
             Enum.reverse([Map.put(entry, "validation", "failed") | trace])}

          other ->
            {:error, {:invalid_validator_result, other}, Enum.reverse([entry | trace])}
        end
    end
  end

  defp hash(text), do: :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)
end
