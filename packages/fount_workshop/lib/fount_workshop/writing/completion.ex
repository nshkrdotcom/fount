defmodule FountWorkshop.Writing.Completion do
  @moduledoc """
  Structured or JSON-text completion through Inference.

  A trusted local validator is mandatory. Text fallback uses the same validator
  as structured responses, permits only a whole JSON value/code fence, and never
  searches an arbitrary provider response for a convenient JSON substring.
  """
  alias FountWorkshop.Writing.Budget

  def complete(client, prompt, schema, validator, opts \\ [])
      when is_binary(prompt) and is_map(schema) and is_function(validator, 1) do
    name = Keyword.get(opts, :name, "fount_writing")
    repairs = Keyword.get(opts, :decode_repairs, 1)
    capabilities = Inference.capabilities(client)
    structured = Inference.Capability.supported?(capabilities, :response_format_json_schema)

    mode =
      if structured and not Keyword.get(opts, :force_json_text, false),
        do: "json_schema",
        else: "json_text"

    original = prompt
    schema_prompt = Keyword.get(opts, :schema_prompt, Jason.encode!(schema))
    max_bytes = Keyword.get(opts, :max_context_bytes, 100_000)

    if byte_size(prompt) +
         byte_size(if(mode == "json_text", do: schema_prompt, else: Jason.encode!(schema))) >
         max_bytes do
      {:error, :context_limit, []}
    else
      attempt(client, %{
        original: original,
        prompt: original,
        schema: schema,
        schema_prompt: schema_prompt,
        name: name,
        validator: validator,
        mode: mode,
        repairs: repairs,
        initial_repairs: repairs,
        transport_retry: 0,
        trace: [],
        opts: opts
      })
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

  defp attempt(client, state) do
    %{
      original: original,
      prompt: prompt,
      schema: schema,
      schema_prompt: schema_prompt,
      name: name,
      validator: validator,
      mode: mode,
      repairs: repairs,
      trace: trace,
      opts: opts
    } = state

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
          schema_prompt
      else
        prompt
      end

    options = Keyword.merge(Keyword.get(opts, :inference_options, []), options)
    result = request_completion(client, request, options, state)

    case result do
      {:error, error} ->
        {:error, safe_provider_error(error), Enum.reverse(trace)}

      {:ok, response} ->
        entry = %{
          "purpose" => name,
          "mode" => mode,
          "request_sha256" => hash(request),
          "response_sha256" =>
            hash(
              Jason.encode!(%{
                "text" => Map.get(response, :text),
                "object" => Map.get(response, :object)
              })
            ),
          "model" => json_value(Map.get(response, :model)),
          "provider" => json_value(Map.get(response, :provider)),
          "finish_reason" => json_value(Map.get(response, :finish_reason)),
          "response_id" => Map.get(response, :id),
          "usage" => json_value(Map.get(response, :usage))
        }

        decoded = decode_response(mode, response)

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

            repair_prompt =
              choose_repair_prompt(mode, errors, response, schema_prompt, opts, repair_prompt)

            attempt(client, %{
              state
              | prompt: repair_prompt,
                repairs: repairs - 1,
                trace: [Map.put(entry, "validation", "failed") | trace]
            })

          {:error, errors} ->
            {:error, {:invalid_completion, errors},
             Enum.reverse([Map.put(entry, "validation", "failed") | trace])}

          other ->
            {:error, {:invalid_validator_result, other}, Enum.reverse([entry | trace])}
        end
    end
  end

  defp decode_response("json_schema", response) do
    case Map.get(response, :object) do
      object when is_map(object) -> {:ok, object}
      _ -> {:error, :missing_structured_object}
    end
  end

  defp decode_response(_, response), do: decode(Map.get(response, :text))

  defp choose_repair_prompt(
         "json_text",
         :invalid_json_response,
         response,
         schema_prompt,
         opts,
         fallback
       ) do
    case Map.get(response, :text) do
      previous when is_binary(previous) ->
        syntax_prompt =
          "Repair the JSON syntax in the following previous response. Preserve its " <>
            "screenplay text, IDs, operations, and writer choices exactly. Return only " <>
            "one complete JSON object; do not explain the changes.\n" <> previous

        if byte_size(syntax_prompt) + byte_size(schema_prompt) <=
             Keyword.get(opts, :max_context_bytes, 100_000),
           do: syntax_prompt,
           else: fallback

      _ ->
        fallback
    end
  end

  defp choose_repair_prompt(_, _, _, _, _, fallback), do: fallback

  defp request_completion(client, request, options, state) do
    schema_bytes =
      if state.mode == "json_schema", do: byte_size(Jason.encode!(state.schema)), else: 0

    cond do
      byte_size(request) + schema_bytes > Keyword.get(state.opts, :max_context_bytes, 100_000) ->
        {:error, :context_limit}

      Budget.take(Keyword.get(state.opts, :budget), :inference, 1) == 0 ->
        {:error, :session_inference_limit}

      true ->
        dispatch_completion(client, request, options, state)
    end
  end

  defp dispatch_completion(client, request, options, state) do
    dispatch = %{
      name: state.name,
      request_snapshot: %{
        "purpose" => state.name,
        "prompt" => request,
        "schema" => state.schema,
        "provider" => json_value(Map.get(client, :provider)),
        "model" => json_value(Keyword.get(options, :model, Map.get(client, :model))),
        "reasoning_effort" =>
          json_value(get_in(Keyword.get(options, :options, []), [:reasoning_effort])),
        "mode" => state.mode
      },
      mode: state.mode,
      request_sha256: hash(request),
      dispatch_index: length(state.trace) + 1,
      transport_retry: state.transport_retry,
      malformed_repair: state.repairs < state.initial_repairs,
      reserved_cost_microunits: Keyword.get(state.opts, :reserved_cost_microunits),
      currency: Keyword.get(state.opts, :currency)
    }

    case dispatch_hook(state.opts, :before, dispatch) do
      :ok ->
        result = Inference.complete(client, request, options)
        record_dispatch_result(client, request, options, state, dispatch, result)

      {:reuse, response} when is_map(response) ->
        {:ok, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp record_dispatch_result(client, request, options, state, dispatch, result) do
    case dispatch_hook(state.opts, :after, Map.put(dispatch, :result, dispatch_result(result))) do
      :ok -> maybe_transport_retry(client, request, options, state, result)
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_transport_retry(client, request, options, state, {:error, error} = result) do
    limit = Keyword.get(state.opts, :transient_retries, 0)

    if transient_error?(error) and state.transport_retry < limit do
      request_completion(client, request, options, %{
        state
        | transport_retry: state.transport_retry + 1
      })
    else
      result
    end
  end

  defp maybe_transport_retry(_client, _request, _options, _state, result), do: result

  defp transient_error?(%Inference.Error{category: category}),
    do: category in [:timeout, :rate_limited, :adapter_exception, :provider_error]

  defp dispatch_hook(opts, phase, payload) do
    case Keyword.get(opts, :dispatch_hook) do
      nil -> :ok
      hook when is_function(hook, 2) -> hook.(phase, payload)
      _ -> {:error, :invalid_dispatch_hook}
    end
  end

  defp dispatch_result({:ok, response}) do
    %{
      "status" => "ok",
      "id" => Map.get(response, :id),
      "text" => Map.get(response, :text),
      "object" => json_value(Map.get(response, :object)),
      "model" => json_value(Map.get(response, :model)),
      "provider" => json_value(Map.get(response, :provider)),
      "finish_reason" => json_value(Map.get(response, :finish_reason)),
      "usage" => json_value(Map.get(response, :usage) || %{})
    }
  end

  defp dispatch_result({:error, %Inference.Error{category: category}}),
    do: %{"status" => "error", "category" => to_string(category)}

  defp json_value(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {to_string(key), json_value(item)} end)
  end

  defp json_value(value) when is_list(value), do: Enum.map(value, &json_value/1)
  defp json_value(value) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  defp json_value(value), do: value

  defp safe_provider_error(%Inference.Error{category: category})
       when category in [
              :invalid,
              :missing_dependency,
              :missing_credentials,
              :timeout,
              :rate_limited,
              :invalid_response,
              :unsupported_capability,
              :adapter_exception,
              :provider_error
            ],
       do: {:completion_provider_error, category}

  defp safe_provider_error(reason) when reason in [:context_limit, :session_inference_limit],
    do: reason

  defp safe_provider_error(_), do: {:completion_provider_error, :provider_error}

  defp hash(text), do: :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)
end
