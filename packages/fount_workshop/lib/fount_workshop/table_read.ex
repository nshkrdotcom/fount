defmodule FountWorkshop.TableRead do
  @moduledoc "Routes ordered screenplay dialogue to human table-read packets and optional caller-supplied speech engines."
  alias Fount.Screenplay
  alias Fount.Selection
  alias Fount.Writing.CanonicalJSON
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
           sha256: sha256(body)
         }}
      end
    end
  end

  def export(_, _, _), do: {:error, :invalid_export_request}

  @doc "Builds a provider-free human read packet with exact selected material, scene context and roles."
  @spec packet(Screenplay.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def packet(%Screenplay{} = model, selection \\ %{"whole_screenplay" => true}, opts \\ [])
      when is_map(selection) do
    with {:ok, selected_ids} <- Selection.selected_ids(model, selection),
         {:ok, units} <- Selection.select(model, selection),
         {:ok, turns} <- selected_turns(model, selected_ids) do
      scenes = selected_scenes(model, selected_ids)
      pages = selected_pages(model, scenes, units)
      roles = roles(turns)
      source = %{"screenplay_id" => model.id, "revision_id" => model.revision.id}
      selection_sha256 = CanonicalJSON.hash(selection)

      packet_id =
        "read_" <>
          (CanonicalJSON.hash(%{
             "source" => source,
             "selection" => selection,
             "turn_ids" => Enum.map(turns, & &1.id)
           })
           |> String.slice(0, 24))

      {:ok,
       %{
         "version" => 1,
         "id" => packet_id,
         "kind" => "fount.human_table_read",
         "source" => source,
         "selection" => selection,
         "selection_sha256" => selection_sha256,
         "scene_context" => scene_context(model, scenes),
         "roles" => roles,
         "selected_pages" => pages,
         "turns" => Enum.map(turns, &plain_turn/1),
         "reactions" => [],
         "reading" => %{
           "speech_required" => false,
           "delivery" => Keyword.get(opts, :delivery, "human"),
           "listening_conditions" => Keyword.get(opts, :listening_conditions)
         },
         "claims" => %{
           "audience_response_measured" => false,
           "generated_transcript_is_audience_feedback" => false,
           "synthesized_voice_is_performance_validation" => false
         }
       }}
    end
  end

  def packet(_, _, _), do: {:error, :invalid_table_read_packet_request}

  @doc "Writes a human table-read packet. No speech engine is required."
  @spec export_packet(Screenplay.t(), Path.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def export_packet(%Screenplay{} = model, path, selection \\ %{"whole_screenplay" => true}, opts \\ [])
      when is_binary(path) do
    with {:ok, packet} <- packet(model, selection, opts),
         body <- Jason.encode!(packet, pretty: true),
         :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, body) do
      {:ok,
       %{
         path: path,
         format: :json,
         packet_id: packet["id"],
         scene_count: length(packet["scene_context"]),
         role_count: length(packet["roles"]),
         sha256: sha256(body)
       }}
    end
  end

  @doc "Adds one caller-supplied human reaction while retaining wording, delivery and conditions as separate fields."
  @spec record_reaction(map(), map()) :: {:ok, map()} | {:error, term()}
  def record_reaction(%{"kind" => "fount.human_table_read"} = packet, attrs) when is_map(attrs) do
    observer = Map.get(attrs, "observer", "human")
    reaction = attrs["reaction"]

    cond do
      observer != "human" ->
        {:error, :human_observer_required}

      not is_binary(reaction) or String.trim(reaction) == "" ->
        {:error, :reaction_required}

      true ->
        item = %{
          "id" =>
            "reaction_" <>
              (CanonicalJSON.hash(%{
                 "packet_id" => packet["id"],
                 "index" => length(packet["reactions"] || []),
                 "reaction" => reaction,
                 "reader_id" => attrs["reader_id"]
               })
               |> String.slice(0, 24)),
          "observer" => "human",
          "reader_id" => attrs["reader_id"],
          "reaction" => reaction,
          "script_wording" => attrs["script_wording"],
          "reader_delivery" => attrs["reader_delivery"],
          "listening_conditions" => attrs["listening_conditions"],
          "source" => packet["source"],
          "read_packet_id" => packet["id"],
          "selection_sha256" => packet["selection_sha256"]
        }

        {:ok, Map.update(packet, "reactions", [item], &(&1 ++ [item]))}
    end
  end

  def record_reaction(_, _), do: {:error, :invalid_table_read_packet}

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

  defp selected_turns(model, selected_ids) do
    selected_blocks =
      model.ir.dialogue_blocks
      |> Enum.filter(fn block ->
        Enum.any?([block.cue_id | block.body_ids], &MapSet.member?(selected_ids, &1))
      end)
      |> MapSet.new(& &1.id)

    with {:ok, turns} <- all_turns(model) do
      {:ok, Enum.filter(turns, &MapSet.member?(selected_blocks, &1.id))}
    end
  end

  defp selected_scenes(model, selected_ids) do
    Enum.filter(model.ir.scenes, fn scene ->
      not scene.omitted? and Enum.any?(scene.element_ids, &MapSet.member?(selected_ids, &1))
    end)
  end

  defp selected_pages(model, scenes, units) do
    by_scene = Enum.group_by(units, & &1["scene_id"])

    Enum.map(scenes, fn scene ->
      heading = Screenplay.node(model, scene.heading_id)

      %{
        "scene_id" => scene.id,
        "heading" => heading && heading.text,
        "elements" => Map.get(by_scene, scene.id, [])
      }
    end)
  end

  defp scene_context(model, scenes) do
    ordinal_by_id = model.ir.scenes |> Enum.with_index(1) |> Map.new(fn {scene, n} -> {scene.id, n} end)

    Enum.map(scenes, fn scene ->
      heading = Screenplay.node(model, scene.heading_id)

      %{
        "scene_id" => scene.id,
        "ordinal" => ordinal_by_id[scene.id],
        "heading" => heading && heading.text,
        "scene_number" => scene.number
      }
    end)
  end

  defp roles(turns) do
    turns
    |> Enum.map(&%{"character_id" => &1.character_id, "cue" => &1.cue})
    |> Enum.uniq()
  end

  defp plain_turn(turn) do
    %{
      "id" => turn.id,
      "scene_id" => turn.scene_id,
      "cue" => turn.cue,
      "character_id" => turn.character_id,
      "dialogue" => turn.dialogue,
      "parentheticals" => turn.parentheticals,
      "dual_with" => turn.dual_with,
      "side" => turn.side && to_string(turn.side)
    }
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
  @spec synthesize(Screenplay.t(), String.t(), map(), (String.t(), term() ->
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

  defp sha256(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
end
