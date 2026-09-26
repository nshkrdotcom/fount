defmodule FountWorkshop.TableRead do
  @moduledoc "Routes ordered screenplay dialogue to a caller-supplied speech engine."
  alias FountWorkshop.Speech.Espeak

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

  @doc "Writes real per-turn WAV clips and a synchronization manifest; simultaneous pairs share a start time."
  def render_audio(model, directory, voices, opts \\ []) when is_map(voices) do
    with {:ok, turns} <- all_turns(model),
         :ok <- File.mkdir_p(directory),
         {:ok, clips, duration, _} <-
           Enum.reduce_while(
             turns,
             {:ok, [], 0.0, %{}},
             &render_turn(&1, &2, directory, voices, opts)
           ) do
      manifest = %{
        "screenplay_id" => model.id,
        "revision_id" => model.revision.id,
        "duration_seconds" => duration,
        "clips" => clips,
        "playback" =>
          "Per-turn WAV clips; dual partners share timestamps. No mixed master file is claimed."
      }

      File.write!(Path.join(directory, "audio.json"), Jason.encode!(manifest, pretty: true))
      {:ok, manifest}
    end
  end

  defp render_turn(turn, {:ok, clips, clock, starts}, directory, voices, opts) do
    voice = voices[turn.character_id] || voices[turn.cue]

    if is_nil(voice) do
      {:halt, {:error, {:voice_not_configured, turn.cue}}}
    else
      path = Path.join(directory, turn.id <> ".wav")

      with {:ok, audio} <- Espeak.render(turn.dialogue, voice, path, opts),
           {:ok, duration} <- wav_duration(path) do
        append_clip(turn, audio, path, duration, clips, clock, starts)
      else
        error -> {:halt, error}
      end
    end
  end

  defp append_clip(turn, audio, path, duration, clips, clock, starts) do
    partner = Map.get(turn, :dual_with)
    start = if partner && Map.has_key?(starts, partner), do: starts[partner], else: clock

    clip = %{
      "block_id" => turn.id,
      "scene_id" => turn.scene_id,
      "character_id" => turn.character_id,
      "path" => path,
      "sha256" => audio.sha256,
      "start_seconds" => start,
      "duration_seconds" => duration,
      "dual_with" => partner
    }

    {:cont, {:ok, clips ++ [clip], max(clock, start + duration), Map.put(starts, turn.id, start)}}
  end

  defp wav_duration(path) do
    case File.read(path) do
      {:ok, <<"RIFF", _::little-32, "WAVE", rest::binary>>} -> chunks(rest, nil, nil)
      _ -> {:error, :invalid_wav_header}
    end
  end

  defp chunks(<<>>, rate, bytes) when is_integer(rate) and rate > 0 and is_integer(bytes),
    do: {:ok, bytes / rate}

  defp chunks(
         <<kind::binary-size(4), size::little-32, body::binary-size(size), rest::binary>>,
         rate,
         bytes
       ) do
    rest =
      if rem(size, 2) == 1 and byte_size(rest) > 0,
        do: binary_part(rest, 1, byte_size(rest) - 1),
        else: rest

    case {kind, body} do
      {"fmt ",
       <<_format::little-16, _channels::little-16, _sample_rate::little-32, byte_rate::little-32,
         _::binary>>} ->
        chunks(rest, byte_rate, bytes)

      {"data", _} ->
        chunks(rest, rate, size)

      _ ->
        chunks(rest, rate, bytes)
    end
  end

  defp chunks(_, _, _), do: {:error, :wav_duration_unavailable}

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
        ~s(<article data-scene-id="#{escape(turn.scene_id)}" data-block-id="#{escape(turn.id)}">) <>
          "<h2>#{escape(turn.cue)}</h2><p>#{escape(turn.dialogue) |> String.replace("\n", "<br>")}</p></article>"
      end)

    ~s(<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Table Read</title>) <>
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
