defmodule FountWorkshop.TableRead do
  @moduledoc "Routes ordered screenplay dialogue to a caller-supplied speech engine."

  @doc "Exports all active speaking turns as actual JSON or a readable HTML table read."
  def export(model, path, format) when format in [:json, :html] and is_binary(path) do
    with {:ok, turns} <- all_turns(model) do
      body =
        if format == :json,
          do:
            Jason.encode!(
              %{screenplay_id: model.id, revision_id: model.revision.id, turns: turns},
              pretty: true
            ),
          else: html(model, turns)

      with :ok <- File.mkdir_p(Path.dirname(path)),
           :ok <- File.write(path, body) do
        {:ok,
         %{
           path: path,
           format: format,
           turn_count: length(turns),
           sha256: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
         }}
      end
    end
  end

  def export(_, _, _), do: {:error, :invalid_export_request}

  defp all_turns(model) do
    model.ir.scenes
    |> Enum.reject(& &1.omitted?)
    |> Enum.reduce_while({:ok, []}, fn scene, {:ok, acc} ->
      case Fount.Writer.table_read(model, scene.id) do
        {:ok, turns} -> {:cont, {:ok, acc ++ turns}}
        error -> {:halt, error}
      end
    end)
  end

  defp html(model, turns) do
    rows =
      Enum.map_join(turns, "\n", fn turn ->
        "<article data-scene-id=\"#{escape(turn.scene_id)}\" data-block-id=\"#{escape(turn.id)}\">" <>
          "<h2>#{escape(turn.cue)}</h2><p>#{escape(turn.dialogue) |> String.replace("\n", "<br>")}</p></article>"
      end)

    "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>Table Read</title>" <>
      "<style>body{max-width:48rem;margin:3rem auto;padding:0 1rem;font:18px/1.5 Georgia,serif}" <>
      "article{border-bottom:1px solid #ddd;padding:1rem 0}h2{font:700 1rem sans-serif;margin:0 0 .4rem}" <>
      "p{margin:0;white-space:normal}</style></head><body><main data-revision-id=\"" <>
      escape(model.revision.id) <> "\">" <> rows <> "</main></body></html>"
  end

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  @doc "Synthesizes each speaking turn; voices may be keyed by cast ID or literal cue."
  @spec synthesize(Fount.Screenplay.t(), String.t(), map(), (String.t(), term() ->
                                                               {:ok, term()} | {:error, term()})) ::
          {:ok, [map()]} | {:error, term()}
  def synthesize(model, scene_id, voices, speech)
      when is_map(voices) and is_function(speech, 2) do
    with {:ok, turns} <- Fount.Writer.table_read(model, scene_id) do
      synthesize_turns(turns, voices, speech)
    end
  end

  defp synthesize_turns(turns, voices, speech) do
    Enum.reduce_while(turns, {:ok, []}, fn turn, {:ok, clips} ->
      case speak_turn(turn, voices, speech) do
        {:ok, clip} -> {:cont, {:ok, [clip | clips]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, clips} -> {:ok, Enum.reverse(clips)}
      error -> error
    end
  end

  defp speak_turn(turn, voices, speech) do
    voice = Map.get(voices, turn.character_id) || Map.get(voices, turn.cue)

    if is_nil(voice) do
      {:error, {:voice_not_configured, turn.cue}}
    else
      case speech.(turn.dialogue, voice) do
        {:ok, audio} -> {:ok, Map.put(turn, :audio, audio)}
        {:error, reason} -> {:error, {:speech_failed, turn.id, reason}}
      end
    end
  end
end
