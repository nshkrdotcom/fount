defmodule FountWorkshop.Speech.Espeak do
  @moduledoc "Optional real WAV rendering through an installed eSpeak executable."

  @doc "Synthesizes one utterance to a WAV file, returning an explicit error on failure."
  def render(text, voice, path, opts \\ [])

  def render(text, voice, path, opts)
      when is_binary(text) and is_binary(voice) and is_binary(path) do
    executable =
      Keyword.get(opts, :executable) ||
        System.find_executable("espeak-ng") || System.find_executable("espeak")

    cond do
      String.trim(text) == "" ->
        {:error, :empty_utterance}

      executable == nil ->
        {:error, :espeak_not_installed}

      true ->
        run_espeak(executable, text, voice, path)
    end
  end

  def render(_, _, _, _), do: {:error, :invalid_speech_request}

  defp run_espeak(executable, text, voice, path) do
    with :ok <- File.mkdir_p(Path.dirname(path)) do
      case System.cmd(executable, ["-v", voice, "-w", path, text], stderr_to_stdout: true) do
        {_, 0} -> verify_wav(path)
        {output, code} -> {:error, {:espeak_failed, code, String.slice(output, 0, 500)}}
      end
    end
  end

  defp verify_wav(path) do
    case File.read(path) do
      {:ok, <<"RIFF", _size::binary-size(4), "WAVE", _rest::binary>> = data}
      when byte_size(data) > 44 ->
        {:ok,
         %{
           path: path,
           bytes: byte_size(data),
           sha256: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
         }}

      {:ok, _} ->
        {:error, :invalid_wav}

      error ->
        error
    end
  end
end
