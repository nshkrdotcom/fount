defmodule FountWorkshop.Launcher do
  @moduledoc "Environment configuration is confined to launchers; libraries receive explicit clients."
  def voices do
    case System.get_env("FOUNT_VOICES_FILE") do
      nil ->
        {:ok, %{}}

      path ->
        load_voices(path)
    end
  end

  defp load_voices(path) do
    with {:ok, bytes} <- File.read(path),
         {:ok, voices} when is_map(voices) <- Jason.decode(bytes),
         true <-
           Enum.all?(voices, fn {key, voice} ->
             is_binary(key) and is_binary(voice) and String.trim(voice) != ""
           end) do
      {:ok, voices}
    else
      _ -> {:error, :invalid_voice_configuration}
    end
  end

  def clients(opts \\ []) do
    inference =
      if Keyword.get(opts, :inference, true) do
        model = System.get_env("FOUNT_CODEX_MODEL")

        if is_nil(model) or String.trim(model) == "",
          do: raise(ArgumentError, "FOUNT_CODEX_MODEL is required")

        Inference.Client.agent_session!(
          adapter: Inference.Adapters.ASM,
          provider: :codex,
          model: model,
          adapter_opts: [query_opts: [stream_timeout_ms: 180_000] ++ reasoning_effort()]
        )
      end

    analytical =
      if Keyword.get(opts, :observe, true) do
        kind = case System.get_env("FOUNT_SYSTEM_ONE_ENDPOINT_KIND", "typesafe") do
          "typesafe" -> :typesafe
          "endpoint" -> :endpoint
          _ -> raise ArgumentError, "invalid FOUNT_SYSTEM_ONE_ENDPOINT_KIND"
        end
        options = [endpoint_kind: kind, api_key: System.get_env("SYSTEM_ONE_API_KEY"),
          base_url: System.get_env("SYSTEM_ONE_BASE_URL"), model: System.get_env("SYSTEM_ONE_MODEL")]
          |> Enum.reject(fn {_, value} -> is_nil(value) end)
        case Fount.Intelligence.Acquisition.Configuration.provider(options) do
          {:ok, provider} -> provider
          {:error, _} -> raise ArgumentError, "invalid analytical provider configuration"
        end
      end

    {:ok, %{inference: inference, observe: analytical}}
  rescue
    _ in ArgumentError -> {:error, :explicit_provider_configuration_required}
  end

  defp reasoning_effort do
    case System.get_env("FOUNT_CODEX_REASONING_EFFORT") do
      nil -> []
      "none" -> [reasoning_effort: :none]
      "low" -> [reasoning_effort: :low]
      "medium" -> [reasoning_effort: :medium]
      "high" -> [reasoning_effort: :high]
      "xhigh" -> [reasoning_effort: :xhigh]
      "max" -> [reasoning_effort: :max]
      _ -> raise ArgumentError, "invalid FOUNT_CODEX_REASONING_EFFORT"
    end
  end
end
