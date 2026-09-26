defmodule Fount.LiveArtifacts do
  @moduledoc "Real-example artifact recording. It records executed work only and never substitutes a fake service."
  alias Fount.CLI.Support

  def fixture do
    path = Application.app_dir(:fount, "priv/fixtures/last_light.fountain")
    raw = File.read!(path)
    model = raw |> Fount.parse!() |> Fount.Screenplay.from_document(cast_resolution: :literal_cues)
    {model, raw}
  end

  def run(mode, output, fun) when is_function(fun, 1) do
    directory = Path.join(output, mode <> "-" <> Fount.ID.v4())
    File.mkdir_p!(directory)
    started = System.monotonic_time(:millisecond)

    try do
      result = fun.(directory)
      finish(directory, mode, started, "complete", result)
      {:ok, result}
    rescue
      error ->
        finish(directory, mode, started, "failed", %{"exception" => inspect(error.__struct__)})

        reraise RuntimeError,
                [message: "Real #{mode} example failed; inspect #{directory}/run.json. No mock fallback was used."],
                __STACKTRACE__
    catch
      :throw, {:live_failure, result} ->
        finish(directory, mode, started, "partial", result)
        {:error, :partial_live_run}
    end
  end

  def require!({:ok, result}), do: result

  def require!({:error, _, session}) when is_map(session),
    do: throw({:live_failure, %{"session_id" => session["id"], "progress" => session["progress"]}})

  def require!({:error, reason}), do: throw({:live_failure, %{"reason" => safe(reason)}})
  def require!(other), do: throw({:live_failure, %{"unexpected_result" => safe(other)}})
  defp safe(%{__struct__: type}), do: inspect(type)
  defp safe(value) when is_atom(value), do: to_string(value)
  defp safe(value) when is_tuple(value), do: safe(elem(value, 0))
  defp safe(_), do: "operation_failed"
  def write!(directory, name, data), do: Support.write_json(Path.join(directory, name), data) |> require!()

  defp finish(directory, mode, started, status, result) do
    files =
      Path.wildcard(Path.join(directory, "**/*"))
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(fn path ->
        %{
          "path" => Path.relative_to(path, directory),
          "bytes" => File.stat!(path).size,
          "sha256" => :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)
        }
      end)

    write!(directory, "run.json", %{
      "mode" => mode,
      "status" => status,
      "completed_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "elapsed_ms" => System.monotonic_time(:millisecond) - started,
      "result" => result,
      "files" => files,
      "services" => "real-only; see result/report provenance for actual calls",
      "verification" => "This file is produced only when the local example is actually run."
    })
  end
end
