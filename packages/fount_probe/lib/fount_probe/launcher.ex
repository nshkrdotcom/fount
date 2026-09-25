defmodule FountProbe.Launcher do
  @moduledoc "Environment configuration is confined to launchers; libraries receive explicit clients."
  def voices do
    case System.get_env("FOUNT_VOICES_FILE") do
      nil ->
        {:ok, %{}}

      path ->
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

    jev =
      if Keyword.get(opts, :jev, true) do
        key = System.get_env("SYSTEM_ONE_API_KEY")

        if is_nil(key) or String.trim(key) == "",
          do: raise(ArgumentError, "SYSTEM_ONE_API_KEY is required")

        SystemOneSDK.new_client(api_key: key)
      end

    {:ok, %{inference: inference, system_one: jev}}
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
