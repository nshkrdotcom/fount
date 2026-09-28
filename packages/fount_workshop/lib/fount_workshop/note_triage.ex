defmodule FountWorkshop.NoteTriage do
  @moduledoc """
  Durable note triage that preserves raw notes, disagreement, and draft anchors.

  Triage records live in Workshop session progress. They can be linked to an
  ordinary candidate, but they never mutate screenplay canon or silently merge
  conflicting requests.
  """

  alias Fount.Query
  alias Fount.Screenplay
  alias FountWorkshop.CandidateAPI
  alias FountWorkshop.Store
  alias FountWorkshop.Writing.NoteConflicts

  @actions ~w(investigate experiment adopt defer decline ask_note_giver)
  @decision_states ~w(accepted rejected undecided)
  @anchor_states ~w(exact relocated_with_evidence ambiguous orphaned)
  @scopes ~w(local sequence whole_draft)

  @doc "Captures raw notes with source, original draft identity, anchor, and separated interpretation fields."
  def capture(session_id, notes, services, opts \\ [])

  def capture(session_id, notes, services, opts)
      when is_binary(session_id) and is_list(notes) and notes != [] do
    with :ok <- validate_notes(notes),
         {:ok, session} <- Store.call(services[:store], :session, [session_id]),
         {:ok, base} <-
           Store.call(services[:store], :load_revision, [
             session["screenplay_id"],
             session["base_revision_id"]
           ]),
         records <- Enum.map(notes, &normalize_note(&1, session, opts)),
         :ok <- unique_notes(session, records) do
      conflicts =
        NoteConflicts.detect(
          base,
          Enum.map(records, fn record ->
            %{
              "id" => record["id"],
              "target" => get_in(record, ["anchor", "target"]),
              "value" => record["raw"]
            }
          end)
        )

      triage = triage_state(session)

      next = %{
        "notes" => triage["notes"] ++ records,
        "conflicts" => triage["conflicts"] ++ conflicts
      }

      updated = put_in(session, ["progress", "note_triage"], next)

      case Store.call(services[:store], :save_session, [updated]) do
        {:ok, _saved} -> {:ok, %{"notes" => records, "conflicts" => conflicts}}
        error -> error
      end
    end
  end

  def capture(_, _, _, _), do: {:error, :invalid_note_capture}

  @doc "Records an explicit writer decision while keeping concern and requested treatment separate."
  def decide(session_id, note_id, decision, services, opts \\ [])

  def decide(session_id, note_id, decision, services, opts)
      when is_binary(session_id) and is_binary(note_id) and is_map(decision) do
    with :ok <- validate_decision(decision),
         {:ok, session} <- Store.call(services[:store], :session, [session_id]),
         {:ok, notes, index} <- find_note(session, note_id) do
      current = Enum.at(notes, index)

      decided =
        current
        |> Map.put("decision", %{
          "action" => decision["action"],
          "concern" => Map.get(decision, "concern", "undecided"),
          "treatment" => Map.get(decision, "treatment", "undecided"),
          "alternative_treatment" => decision["alternative_treatment"],
          "reason" => decision["reason"],
          "actor" => Keyword.get(opts, :actor, "writer"),
          "at" => timestamp()
        })

      save_notes(session, List.replace_at(notes, index, decided), services, decided)
    end
  end

  def decide(_, _, _, _, _), do: {:error, :invalid_note_decision}

  @doc "Re-evaluates one note anchor against a later draft using exact identity/text evidence only."
  def reanchor(session_id, note_id, %Screenplay{} = current, services, opts \\ []) do
    with {:ok, session} <- Store.call(services[:store], :session, [session_id]),
         true <- session["screenplay_id"] == current.id or {:error, :different_screenplay},
         {:ok, notes, index} <- find_note(session, note_id) do
      note = Enum.at(notes, index)
      result = anchor_status(note, current)

      history = (note["anchor_history"] || []) ++ [Map.put(result, "at", timestamp())]

      updated_note =
        note
        |> Map.put("current_anchor", result)
        |> Map.put("anchor_history", history)
        |> maybe_put_manual_resolution(opts)

      save_notes(session, List.replace_at(notes, index, updated_note), services, updated_note)
    end
  end

  def reanchor(_, _, _, _, _), do: {:error, :invalid_note_anchor}

  @doc "Classifies an anchor as exact, relocated with evidence, ambiguous, or orphaned."
  def anchor_status(note, %Screenplay{} = model) when is_map(note) do
    anchor = note["anchor"] || %{}
    target = anchor["target"] || %{}
    excerpt = anchor["excerpt"]

    case {target["kind"], target["id"], excerpt} do
      {"element", id, text} when is_binary(id) and is_binary(text) ->
        classify_element_anchor(model, id, text)

      _ ->
        %{"status" => "orphaned", "reason" => "unsupported_or_incomplete_anchor"}
    end
  end

  def anchor_status(_, _), do: %{"status" => "orphaned", "reason" => "invalid_anchor"}

  @doc "Builds a writer-origin candidate linked to decided notes and a declared consequence plan."
  def candidate(session_id, note_ids, operations, services, opts \\ [])

  def candidate(session_id, note_ids, operations, services, opts)
      when is_binary(session_id) and is_list(note_ids) and note_ids != [] and
             is_list(operations) and operations != [] do
    actor = Keyword.get(opts, :actor)

    with true <- valid_text?(actor) or {:error, :missing_actor},
         {:ok, session} <- Store.call(services[:store], :session, [session_id]),
         {:ok, notes} <- selected_decisions(session, note_ids),
         :ok <- validate_candidate_scope(opts),
         :ok <- consequence_plan(Keyword.get(opts, :consequence_plan, %{})) do
      lineage = %{
        "note_decisions" => Enum.map(notes, &decision_lineage/1),
        "phase14" => %{
          "scope" => Keyword.get(opts, :scope, "local"),
          "preserved" => Keyword.get(opts, :preserved, []),
          "approved_scene_ids" => Keyword.get(opts, :approved_scene_ids, []),
          "consequence_plan" => Keyword.get(opts, :consequence_plan, %{}),
          "created_from_note_triage" => true
        }
      }

      CandidateAPI.manual(
        session_id,
        operations,
        services,
        actor: actor,
        label: Keyword.get(opts, :label, "Note decision experiment"),
        summary: Keyword.get(opts, :summary, "Writer-authored note response experiment"),
        title: Keyword.get(opts, :title, "Note response"),
        addresses_notes: note_ids,
        intelligence_lineage: lineage
      )
    end
  end

  def candidate(_, _, _, _, _), do: {:error, :invalid_note_candidate}

  @doc "Returns the durable note records and unmerged conflict indicators."
  def list(session) when is_map(session), do: triage_state(session)

  defp classify_element_anchor(model, id, excerpt) do
    case Query.node(model, id) do
      %{text: ^excerpt} ->
        %{
          "status" => "exact",
          "target" => %{"kind" => "element", "id" => id},
          "evidence" => %{"kind" => "stable_identity_and_exact_text", "excerpt" => excerpt}
        }

      _ ->
        matches = Enum.filter(model.ir.elements, &(&1.text == excerpt))

        case matches do
          [element] ->
            %{
              "status" => "relocated_with_evidence",
              "target" => %{"kind" => "element", "id" => element.id},
              "evidence" => %{
                "kind" => "unique_exact_text_match",
                "excerpt" => excerpt,
                "previous_target_id" => id
              }
            }

          [] ->
            %{
              "status" => "orphaned",
              "previous_target_id" => id,
              "excerpt" => excerpt,
              "reason" => "no_exact_identity_or_text_match"
            }

          many ->
            %{
              "status" => "ambiguous",
              "previous_target_id" => id,
              "excerpt" => excerpt,
              "candidate_targets" =>
                Enum.map(many, &%{"kind" => "element", "id" => &1.id}),
              "reason" => "multiple_exact_text_matches"
            }
        end
    end
  end

  defp validate_notes(notes) do
    if Enum.all?(notes, &valid_note?/1), do: :ok, else: {:error, :invalid_note_capture}
  end

  defp valid_note?(note) when is_map(note) do
    allowed =
      ~w(id raw source confidentiality reaction interpretation requested_treatment anchor)

    anchor = note["anchor"] || %{}
    target = anchor["target"] || %{}

    Map.keys(note) -- allowed == [] and optional_id?(note["id"]) and valid_text?(note["raw"]) and
      is_map(note["source"]) and valid_text?(note["source"]["label"]) and
      optional_text?(note["confidentiality"]) and optional_text?(note["reaction"]) and
      optional_text?(note["interpretation"]) and optional_text?(note["requested_treatment"]) and
      is_map(anchor) and target["kind"] == "element" and valid_text?(target["id"]) and
      valid_text?(anchor["excerpt"])
  end

  defp valid_note?(_), do: false

  defp normalize_note(note, session, opts) do
    id = note["id"] || Fount.ID.v4()

    %{
      "id" => id,
      "raw" => note["raw"],
      "source" => note["source"],
      "confidentiality" => note["confidentiality"],
      "reaction" => note["reaction"],
      "interpretation" => note["interpretation"],
      "requested_treatment" => note["requested_treatment"],
      "draft" => %{
        "screenplay_id" => session["screenplay_id"],
        "revision_id" => session["base_revision_id"]
      },
      "anchor" => note["anchor"],
      "current_anchor" => Map.put(note["anchor"], "status", "exact"),
      "anchor_history" => [],
      "decision" => nil,
      "captured_by" => Keyword.get(opts, :actor, "writer"),
      "captured_at" => timestamp()
    }
  end

  defp validate_decision(decision) do
    allowed = ~w(action concern treatment alternative_treatment reason)

    cond do
      Map.keys(decision) -- allowed != [] -> {:error, :unknown_note_decision_field}
      decision["action"] not in @actions -> {:error, :invalid_note_action}
      Map.get(decision, "concern", "undecided") not in @decision_states -> {:error, :invalid_concern_decision}
      Map.get(decision, "treatment", "undecided") not in @decision_states -> {:error, :invalid_treatment_decision}
      not optional_text?(decision["alternative_treatment"]) -> {:error, :invalid_alternative_treatment}
      not optional_text?(decision["reason"]) -> {:error, :invalid_note_decision_reason}
      true -> :ok
    end
  end

  defp selected_decisions(session, ids) do
    notes = triage_state(session)["notes"]
    selected = Enum.filter(notes, &(&1["id"] in ids))

    cond do
      length(selected) != length(Enum.uniq(ids)) -> {:error, :unknown_note}
      Enum.any?(selected, &is_nil(&1["decision"])) -> {:error, :note_requires_decision}
      true -> {:ok, selected}
    end
  end

  defp decision_lineage(note) do
    %{
      "note_id" => note["id"],
      "raw" => note["raw"],
      "source" => note["source"],
      "draft" => note["draft"],
      "anchor" => note["current_anchor"],
      "decision" => note["decision"],
      "confidentiality" => note["confidentiality"]
    }
  end

  defp validate_candidate_scope(opts) do
    scope = Keyword.get(opts, :scope, "local")
    preserved = Keyword.get(opts, :preserved, [])
    approved = Keyword.get(opts, :approved_scene_ids, [])

    cond do
      scope not in @scopes -> {:error, :invalid_revision_scope}
      not is_list(preserved) or Enum.any?(preserved, &(not valid_text?(&1))) ->
        {:error, :invalid_preserved_items}
      not valid_ids?(approved) -> {:error, :invalid_approved_scene_ids}
      true -> :ok
    end
  end

  defp consequence_plan(plan) when is_map(plan) do
    supported = Map.get(plan, "supported", [])
    uncertain = Map.get(plan, "uncertain", [])
    unresolved = Map.get(plan, "unresolved", [])
    checked = Map.get(plan, "checked_scene_ids", [])
    not_analyzed = Map.get(plan, "not_analyzed_scene_ids", [])

    cond do
      Map.keys(plan) -- ~w(supported uncertain unresolved checked_scene_ids not_analyzed_scene_ids) != [] ->
        {:error, :unknown_consequence_plan_field}

      not valid_consequences?(supported, "supported_dependency") ->
        {:error, :invalid_supported_consequence}

      not valid_consequences?(uncertain, "hypothesis") ->
        {:error, :invalid_uncertain_consequence}

      not is_list(unresolved) or Enum.any?(unresolved, &(not valid_text?(&1))) ->
        {:error, :invalid_unresolved_consequence}

      not valid_ids?(checked) or not valid_ids?(not_analyzed) ->
        {:error, :invalid_consequence_scene_ids}

      true -> :ok
    end
  end

  defp consequence_plan(_), do: {:error, :invalid_consequence_plan}

  defp valid_consequences?(items, expected_basis) when is_list(items) do
    Enum.all?(items, fn item ->
      is_map(item) and item["basis"] == expected_basis and valid_text?(item["why"]) and
        valid_text?(item["target"])
    end)
  end

  defp valid_consequences?(_, _), do: false

  defp valid_ids?(ids), do: is_list(ids) and Enum.all?(ids, &valid_text?/1)

  defp find_note(session, id) do
    notes = triage_state(session)["notes"]

    case Enum.find_index(notes, &(&1["id"] == id)) do
      nil -> {:error, :unknown_note}
      index -> {:ok, notes, index}
    end
  end

  defp save_notes(session, notes, services, record) do
    updated = put_in(session, ["progress", "note_triage", "notes"], notes)

    case Store.call(services[:store], :save_session, [updated]) do
      {:ok, _saved} -> {:ok, record}
      error -> error
    end
  end

  defp maybe_put_manual_resolution(note, opts) do
    case Keyword.get(opts, :resolved_target_id) do
      id when is_binary(id) and id != "" ->
        current = note["current_anchor"] || %{}

        if current["status"] in @anchor_states do
          Map.put(note, "manual_resolution", %{
            "target" => %{"kind" => "element", "id" => id},
            "actor" => Keyword.get(opts, :actor, "writer"),
            "at" => timestamp()
          })
        else
          note
        end

      _ ->
        note
    end
  end

  defp unique_notes(session, records) do
    ids = Enum.map(triage_state(session)["notes"] ++ records, & &1["id"])
    if length(ids) == MapSet.size(MapSet.new(ids)), do: :ok, else: {:error, :duplicate_note_id}
  end

  defp triage_state(session) do
    get_in(session, ["progress", "note_triage"]) || %{"notes" => [], "conflicts" => []}
  end

  defp valid_text?(value), do: is_binary(value) and String.trim(value) != ""
  defp optional_text?(nil), do: true
  defp optional_text?(value), do: valid_text?(value)
  defp optional_id?(nil), do: true
  defp optional_id?(value), do: valid_text?(value)
  defp timestamp, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
