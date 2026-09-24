defmodule FountWorkshop.TableRead do
  @moduledoc "Routes ordered screenplay dialogue to a caller-supplied speech engine."

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
