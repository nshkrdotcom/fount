defmodule Fount.Observe.Providers.SystemOne do
  @moduledoc "SystemOneSDK adapter. All SDK-native questions, clients, responses and errors terminate here."
  @behaviour Fount.Observe.Provider
  alias Fount.Observe.{Context, Distribution, Error, Provider, ProviderResult, Question}
  alias Fount.Writing.CanonicalJSON
  @client_options [:api_key, :base_url, :model, :timeout_ms, :retry]
  @request_options [
    :model,
    :extra_body,
    :retry,
    :timeout_ms,
    :attempt_timeout_ms,
    :task_timeout_ms,
    :max_concurrency,
    :max_pending,
    :probability_tolerance,
    :max_request_bytes
  ]

  @doc "Creates an isolated client for the official service or an explicit generic endpoint. Keys remain only in the opaque handle."
  def new(opts \\ [])

  def new(opts) when is_list(opts) do
    kind = Keyword.get(opts, :endpoint_kind, :typesafe)
    allowed = @client_options ++ [:endpoint_kind]

    with true <- Keyword.keyword?(opts) and Keyword.keys(opts) -- allowed == [],
         true <- kind in [:typesafe, :endpoint] do
      client_opts = Keyword.take(opts, @client_options)

      client =
        case kind do
          :typesafe ->
            SystemOneSDK.new_client(
              provider: SystemOneSDK.Providers.TypeSafe,
              provider_opts: client_opts
            )

          :endpoint ->
            SystemOneSDK.new_client(
              provider: SystemOneSDK.Providers.Endpoint,
              provider_opts: client_opts
            )
        end

      {:ok,
       %Provider{
         sensor_id: "system_one",
         state: %{client: client},
         fingerprint: %{
           "provider" => "system_one",
           "endpoint_kind" => to_string(kind),
           "model" => client.default_model,
           "stability" => "mutable_alias_or_unknown",
           "session" => Fount.ID.v4()
         }
       }}
    else
      _ -> {:error, Error.at(:invalid_request, ["provider_options"])}
    end
  rescue
    _ -> {:error, Error.new(:provider_unconfigured)}
  end

  def new(_opts), do: {:error, Error.at(:invalid_request, ["provider_options"])}

  @impl true
  def identity(_state, _request), do: %{}

  @impl true
  def execute(state, requests, questions, opts) do
    native = Enum.map(questions, fn {key, q} -> {key, native_question(q)} end)

    case SystemOneSDK.prepare(native) do
      {:ok, prepared} ->
        sdk_opts =
          opts
          |> Keyword.take(@request_options)
          |> Keyword.put(:ordered, false)
          |> Keyword.put(:on_error, :collect)

        states = Enum.map(requests, &semantic_input/1)
        results = SystemOneSDK.evaluate_stream(state.client, states, prepared, sdk_opts)
        {:ok, Enum.map(results, &normalize(&1, questions))}

      {:error, error} ->
        {:error, normalize_error(error)}
    end
  rescue
    _ -> {:error, Error.new(:provider_rejected)}
  catch
    _, _ -> {:error, Error.new(:provider_unavailable)}
  end

  @doc false
  def semantic_input(request) do
    # Hashing uses this exact envelope too: nothing visible to the model is dropped.
    CanonicalJSON.encode!(%{
      "state" => request.input,
      "context" => Context.to_map(request.context)
    })
  end

  defp native_question(%Question{kind: :noul} = q),
    do: SystemOneSDK.noul(q.instructions, extra: q.extra)

  defp native_question(%Question{kind: :choice} = q),
    do: SystemOneSDK.choice(q.instructions, q.criteria, extra: q.extra)

  defp native_question(%Question{kind: :score} = q),
    do: SystemOneSDK.score(q.instructions, q.levels, extra: q.extra)

  defp normalize({:ok, %SystemOneSDK.SystemOneResponse{} = response}, questions) do
    case answers(response.answers, questions) do
      {:ok, normalized} ->
        %ProviderResult{
          batch_index: response.batch_index,
          answers: normalized,
          metadata: metadata(response)
        }

      {:error, error} ->
        %ProviderResult{batch_index: response.batch_index, error: error}
    end
  end

  defp normalize({:error, %SystemOneSDK.Error{} = error}, _questions),
    do: %ProviderResult{
      batch_index:
        Map.get(error.details || %{}, :batch_index, Map.get(error.details || %{}, "batch_index")),
      error: normalize_error(error)
    }

  defp normalize(_, _),
    do: %ProviderResult{batch_index: nil, error: Error.new(:invalid_provider_response)}

  defp answers(answers, questions) when is_map(answers) do
    Enum.reduce_while(questions, {:ok, %{}}, fn {key, q}, {:ok, acc} ->
      case distribution(Map.get(answers, key), q) do
        {:ok, distribution} -> {:cont, {:ok, Map.put(acc, key, distribution)}}
        error -> {:halt, error}
      end
    end)
  end

  defp answers(_, _), do: {:error, Error.new(:invalid_provider_response)}

  defp distribution(%SystemOneSDK.NoulAnswer{noul: p}, %Question{kind: :noul}),
    do: Distribution.proposition(p)

  defp distribution(%SystemOneSDK.ChoiceAnswer{} = answer, %Question{kind: :choice} = q) do
    if Enum.map(answer.option_order, &to_string/1) == Question.domain(q),
      do:
        Distribution.choice(
          answer.probabilities,
          Question.domain(q),
          answer.choice,
          answer.confidence
        ),
      else: {:error, Error.new(:invalid_provider_response)}
  end

  defp distribution(%SystemOneSDK.ScoreAnswer{} = answer, %Question{kind: :score} = q),
    do:
      Distribution.score(
        answer.probabilities,
        Enum.map(q.levels, &elem(&1, 1)),
        answer.score,
        answer.confidence
      )

  defp distribution(_, _), do: {:error, Error.new(:invalid_provider_response)}

  defp metadata(response) do
    %{
      "model" => text(response.model),
      "request_id" => text(response.request_id),
      "usage" => usage(response.usage),
      "prepared_fingerprint" => text(response.prepared_fingerprint)
    }
  end

  defp usage(value) when is_map(value) do
    value = if is_struct(value), do: Map.from_struct(value), else: value

    Map.new(
      for {key, number} <- value,
          key in [:input_tokens, :output_tokens, :total_tokens],
          is_number(number),
          do: {to_string(key), number}
    )
  end

  defp usage(_), do: %{}
  defp text(value) when is_binary(value), do: value
  defp text(_), do: nil

  defp normalize_error(%SystemOneSDK.Error{} = error) do
    class =
      case error.type do
        :timeout ->
          :provider_timeout

        :cancelled ->
          :provider_cancelled

        type when type in [:authentication, :permission_denied, :configuration] ->
          :provider_unconfigured

        type when type in [:response_contract, :response_validation] ->
          :invalid_provider_response

        type
        when type in [
               :invalid_request,
               :request_too_large,
               :bad_request,
               :model_not_found,
               :unprocessable_entity
             ] ->
          :provider_rejected

        _ ->
          :provider_unavailable
      end

    # Provider body, exception text, endpoint, headers and cause are deliberately excluded.
    Error.new(class, nil, %{
      "provider_error_class" => to_string(error.type),
      "http_status" => error.status
    })
  end
end
