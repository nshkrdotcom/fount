defmodule FountProbe.Dialogue do
  @moduledoc "Exact dialogue patterns and contextual lenses; repeated phrases are observations, not deletion orders."
  alias FountProbe.{Projection, Jev, Report}

  def run(model, params, clients, opts \\ []) do
    with {:ok, units} <- Projection.select(model, params["selection"]),
         {:ok, whole} <- Projection.select(model, %{"whole_screenplay" => true}) do
      lines = Enum.filter(units, &(&1["type"] == "dialogue"))

      turns =
        model.ir.dialogue_blocks
        |> Enum.flat_map(fn b ->
          selected = Enum.filter(lines, &(&1["target"]["id"] in b.body_ids))

          speaker =
            Enum.find(
              Map.values(model.mentions),
              &(&1.element_id == b.cue_id and &1.role == :speaker_cue and &1.status == :confirmed)
            )

          ids = Map.get(params, "character_ids", [])

          if selected != [] and (ids == [] or (speaker && speaker.character_id in ids)),
            do: [
              %{
                id: b.id,
                cue_id: b.cue_id,
                character_id: speaker && speaker.character_id,
                text: Enum.map_join(selected, " ", & &1["text"]),
                units: selected
              }
            ],
            else: []
        end)

      counts =
        turns
        |> Enum.group_by(& &1.character_id)
        |> Enum.map(fn {id, ts} ->
          words = Enum.flat_map(ts, &tokens(&1.text))

          phrases =
            Enum.flat_map(ts, fn t ->
              tokens(t.text) |> Enum.chunk_every(2, 1, :discard) |> Enum.map(&Enum.join(&1, " "))
            end)

          %{
            "character_id" => id,
            "turn_count" => length(ts),
            "words" => length(words),
            "frequent_words" => repeated(words),
            "repeated_bigrams" => repeated(phrases)
          }
        end)

      duplicates =
        turns
        |> Enum.group_by(&(String.downcase(&1.text) |> String.replace(~r/\s+/, " ")))
        |> Enum.flat_map(fn {text, ts} ->
          if length(ts) > 1,
            do: [%{"text" => text, "block_ids" => Enum.map(ts, & &1.id)}],
            else: []
        end)

      lenses = params["lenses"]
      qs = []

      qs =
        if "responsiveness" in lenses,
          do:
            qs ++
              [
                responsive:
                  SystemOneSDK.noul(
                    "Does the current turn respond to the immediately preceding turn, including a playable refusal or deflection?"
                  )
              ],
          else: qs

      qs =
        if "subtext" in lenses,
          do:
            qs ++
              [
                explicit_intention:
                  SystemOneSDK.noul(
                    "Does this turn explicitly state the speaker's emotion or intention? Direct speech is allowed; this is descriptive."
                  )
              ],
          else: qs

      qs =
        if "exposition" in lenses,
          do:
            qs ++
              [
                information:
                  SystemOneSDK.noul("Does this turn primarily communicate story information?"),
                reason_to_say:
                  SystemOneSDK.noul(
                    "Does the supplied scene show a specific reason for the speaker to say this now?"
                  )
              ],
          else: qs

      qs =
        if "repetition" in lenses,
          do:
            qs ++
              [
                repeats:
                  SystemOneSDK.noul(
                    "Does the current turn repeat the same audience information in the supplied prior turns without an evident new purpose?"
                  )
              ],
          else: qs

      qs =
        if "tactic" in lenses,
          do:
            qs ++
              [
                tactic:
                  SystemOneSDK.noul(
                    "Does the speaker use this turn to change the partner's action, belief or decision, including refusal or evasion? Describe the supplied exchange, not a requirement for all dialogue."
                  )
              ],
          else: qs

      contexts =
        Enum.map(turns, fn turn ->
          scene = Fount.Query.scene_for(model, turn.cue_id)
          scene_blocks = Enum.filter(model.ir.dialogue_blocks, &(&1.cue_id in scene.element_ids))
          prior = Enum.take_while(scene_blocks, &(&1.id != turn.id))
          previous = List.last(prior)
          selected = Enum.filter(whole, &(&1["scene_id"] == scene.id))

          text_for = fn block ->
            Enum.filter(
              selected,
              &(&1["target"]["id"] in block.body_ids and &1["type"] == "dialogue")
            )
            |> Enum.map_join(" ", & &1["text"])
          end

          {%{
             "id" => turn.id,
             "state" => %{
               "previous" => if(previous, do: text_for.(previous)),
               "current" => turn.text,
               "prior_turns" => Enum.map(prior, text_for),
               "scene_context" => Projection.compact(selected),
               "listener_access" => "unknown unless separately checked by knowledge_trace"
             }
           }, selected}
        end)

      inputs = Enum.map(contexts, &elem(&1, 0))

      context_evidence =
        contexts
        |> Enum.flat_map(&elem(&1, 1))
        |> Projection.evidence()
        |> Enum.uniq_by(& &1["evidence_id"])

      unassessed = Enum.filter(lenses, &(&1 in ["knowledge", "voice"]))

      rhythm =
        Enum.map(
          turns,
          &%{
            "block_id" => &1.id,
            "words" => length(tokens(&1.text)),
            "sentence_lengths" =>
              Regex.split(~r/(?<=[.!?])\s+/u, &1.text)
              |> Enum.map(fn sentence -> length(tokens(sentence)) end)
          }
        )

      evaluated =
        if qs == [],
          do: {:ok, %{"status" => "complete", "entries" => [], "scheduled" => 0}},
          else:
            Jev.evaluate(
              clients[:system_one],
              inputs,
              qs,
              Keyword.put_new(opts, :profile_id, "dialogue")
            )

      with {:ok, result} <- evaluated do
        {:ok,
         Report.new(model, "dialogue", params, %{
           status: if(unassessed == [], do: result["status"], else: "partial"),
           data: %{
             "counts" => counts,
             "exact_duplicates" => duplicates,
             "turns" => result["entries"],
             "rhythm" => rhythm,
             "unassessed_lenses" => unassessed,
             "listener_knowledge" =>
               "unknown: use an access-aware knowledge trace for a specified listener/proposition"
           },
           evidence: context_evidence,
           coverage: %{
             "block_ids" => Enum.map(turns, & &1.id),
             "lenses" => lenses,
             "automatic_deletions" => false
           },
           provenance: result
         })}
      end
    end
  end

  defp tokens(text),
    do:
      Regex.scan(~r/[\p{L}\p{N}]+(?:['\x{2019}][\p{L}\p{N}]+)*/u, String.downcase(text))
      |> List.flatten()

  defp repeated(words),
    do:
      words
      |> Enum.frequencies()
      |> Enum.filter(fn {_, n} -> n > 1 end)
      |> Enum.sort_by(fn {word, n} -> {-n, word} end)
      |> Enum.map(fn {word, n} -> %{"text" => word, "count" => n} end)
end
