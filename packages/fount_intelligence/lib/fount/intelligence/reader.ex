defmodule Fount.Intelligence.Reader do
  @moduledoc """
  Pure, strict forward Reader reducer over canonical screenplay presentation order.

  Reader state never consumes a later presentation point while constructing an
  earlier snapshot. Canonical notes, boneyards and omitted material are excluded
  from the visible checkpoint stream unless another phase explicitly creates a
  private event, which this reducer ignores rather than exposing to the reader.
  """

  alias Fount.Intelligence.Reader.{Event, Snapshot, State}
  alias Fount.Intelligence.StoryWorld
  alias Fount.Screenplay.Model
  alias Fount.Writing.CanonicalJSON

  @enforce_keys [:screenplay_id, :revision_id]
  defstruct [
    :screenplay_id,
    :revision_id,
    points: [],
    snapshots: [],
    event_ids: [],
    ignored_private_event_ids: [],
    dependency_index: %{},
    metadata: %{}
  ]

  @type t :: %__MODULE__{}

  @doc "Compiles deterministic presentation checkpoints and reduces source-backed Reader events once, forward only."
  def compile(%Fount.Screenplay{} = screenplay, events, opts \\ []) when is_list(events) do
    with {:ok, points} <- discourse_points(screenplay),
         {:ok, normalized, private_ids} <- normalize_events(events),
         :ok <- unique_event_ids(normalized, private_ids),
         {:ok, visible} <- validate_events(screenplay, points, normalized),
         {:ok, snapshots} <- reduce_snapshots(points, visible) do
      {:ok,
       %__MODULE__{
         screenplay_id: screenplay.id,
         revision_id: screenplay.revision.id,
         points: points,
         snapshots: snapshots,
         event_ids: Enum.map(visible, & &1.id),
         ignored_private_event_ids: private_ids,
         dependency_index: dependency_index(visible, points),
         metadata: Model.plain(Keyword.get(opts, :metadata, %{}))
       }}
    end
  end

  def reduce(_screenplay, _events, _opts), do: {:error, :invalid_reader_input}

  @doc "Compatibility convenience for callers that prefer compiler terminology."
  def compile(screenplay, events, opts \ []), do: reduce(screenplay, events, opts)

  @doc "Resolves a snapshot by Reader point id, canonical element id, or 0-based point ordinal."
  def snapshot_at(%__MODULE__{} = reader, ref) do
    case point_for(reader.points, ref) do
      nil -> {:error, {:unknown_reader_point, ref}}
      point -> {:ok, Enum.find(reader.snapshots, &(&1.point["id"] == point["id"]))}
    end
  end

  @doc "Returns the first-exposure snapshot prefix through a visible checkpoint."
  def prefix(%__MODULE__{} = reader, ref) do
    case point_for(reader.points, ref) do
      nil -> {:error, {:unknown_reader_point, ref}}
      point -> {:ok, Enum.take(reader.snapshots, point["ordinal"] + 1)}
    end
  end

  @doc "Returns the Reader snapshot at the last visible performed element of a scene."
  def scene_exit_snapshot(%__MODULE__{} = reader, scene_id) when is_binary(scene_id) do
    case Enum.find(reader.points, &(&1["scene_id"] == scene_id and &1["scene_exit"] == true)) do
      nil -> {:error, {:unknown_reader_scene, scene_id}}
      point -> snapshot_at(reader, point["id"])
    end
  end

  @doc "Returns only questions whose ledger status is still open or partially answered."
  def open_questions(%Snapshot{state: %State{} = state}) do
    state.open_questions
    |> Map.values()
    |> Enum.filter(&(&1["status"] in ["open", "partially_answered"]))
    |> Enum.sort_by(& &1["id"])
  end

  def open_questions(%__MODULE__{snapshots: snapshots}) do
    case List.last(snapshots) do
      nil -> []
      snapshot -> open_questions(snapshot)
    end
  end

  @doc "Presentation-relative change trajectory for an inspectable Reader state track/key."
  def trajectory(%__MODULE__{} = reader, track, key) do
    with {:ok, track} <- normalize_track(track) do
      {points, _last} =
        Enum.reduce(reader.snapshots, {[], :__reader_missing__}, fn snapshot, {acc, previous} ->
          value = snapshot.state |> Map.from_struct() |> Map.get(track, %{}) |> Map.get(key)

          if value == previous do
            {acc, previous}
          else
            {acc ++ [%{"point" => snapshot.point, "value" => Model.plain(value)}], value}
          end
        end)

      %{
        "semantics" => "presentation_relative",
        "track" => Atom.to_string(track),
        "key" => key,
        "points" => points
      }
    end
  end

  @doc "Compares the Reader's model of a character with event-qualified StoryWorld knowledge."
  def knowledge_differential(
        %__MODULE__{} = reader,
        %StoryWorld{} = world,
        character,
        point_ref,
        event_id,
        opts \\ []
      ) do
    with {:ok, %Snapshot{} = snapshot} <- snapshot_at(reader, point_ref) do
      proposition = Keyword.get(opts, :proposition)

      reader_entries =
        snapshot.state.character_models
        |> Map.values()
        |> Enum.filter(fn entry ->
          same_value?(entry["character"], character) and
            (is_nil(proposition) or same_value?(entry["proposition"], proposition))
        end)
        |> Enum.sort_by(& &1["id"])

      diegetic =
        world
        |> StoryWorld.knowledge_at(character, event_id, opts)
        |> Enum.filter(fn assertion ->
          is_nil(proposition) or same_value?(assertion.object, proposition) or
            same_value?(assertion.subject, proposition)
        end)
        |> Enum.sort_by(& &1.id)
        |> Enum.map(&Model.plain/1)

      reader_signatures = epistemic_signatures(reader_entries)
      diegetic_signatures = epistemic_signatures(diegetic)

      {:ok,
       %{
         "semantics" => "reader_presentation_vs_diegetic_story_time",
         "point" => snapshot.point,
         "story_event_id" => event_id,
         "character" => Model.plain(character),
         "reader_model" => reader_entries,
         "diegetic_knowledge" => diegetic,
         "reader_epistemic_signatures" => reader_signatures,
         "diegetic_epistemic_signatures" => diegetic_signatures,
         "different" => reader_signatures != diegetic_signatures
       }}
    end
  end

  @doc "Earliest presentation checkpoint affected by dependencies, plus the resulting suffix."
  def recomputation_boundary(%__MODULE__{} = reader, changed_dependencies)
      when is_list(changed_dependencies) do
    entries =
      changed_dependencies
      |> Enum.map(&to_string/1)
      |> Enum.uniq()
      |> Enum.flat_map(&Map.get(reader.dependency_index, &1, []))

    case Enum.min_by(entries, & &1["ordinal"], fn -> nil end) do
      nil ->
        :unaffected

      earliest ->
        %{
          "semantics" => "presentation_suffix",
          "from_point_id" => earliest["point_id"],
          "from_ordinal" => earliest["ordinal"],
          "event_ids" => entries |> Enum.map(& &1["event_id"]) |> Enum.uniq() |> Enum.sort(),
          "snapshot_ids" =>
            reader.points
            |> Enum.filter(&(&1["ordinal"] >= earliest["ordinal"]))
            |> Enum.map(& &1["id"])
        }
    end
  end

  @doc "Writer-facing, provenance-preserving Reader packet; no human-response claim is synthesized."
  def inspection_packet(%__MODULE__{} = reader) do
    final = List.last(reader.snapshots)

    %{
      "screenplay_id" => reader.screenplay_id,
      "revision_id" => reader.revision_id,
      "semantics" => "presentation_relative_forward_only",
      "checkpoint_count" => length(reader.points),
      "event_ids" => reader.event_ids,
      "ignored_private_event_ids" => reader.ignored_private_event_ids,
      "claim_classes" => reader_claim_classes(reader),
      "final_state" => if(final, do: Model.plain(final.state), else: Model.plain(%State{})),
      "limitations" => [
        "Reader state is deterministic ledger state derived from supplied reader-visible events.",
        "Model-estimated interpretations remain labeled as such.",
        "No human-calibrated reader response is claimed."
      ]
    }
  end

  def render_json(%__MODULE__{} = reader), do: Jason.encode!(inspection_packet(reader), pretty: true)

  def render_markdown(%__MODULE__{} = reader) do
    packet = inspection_packet(reader)
    state = packet["final_state"]

    [
      "# Forward Reader State",
      "",
      "- Semantics: presentation-relative, strict forward-only",
      "- Checkpoints: #{packet["checkpoint_count"]}",
      "- Reader-visible events: #{length(packet["event_ids"])}",
      "- Ignored private events: #{length(packet["ignored_private_event_ids"])}",
      "",
      "## Open questions",
      markdown_entries(state["open_questions"]),
      "",
      "## Reveals",
      markdown_entries(state["reveals"]),
      "",
      "## Forward pull",
      markdown_entries(state["forward_pull"]),
      "",
      "## Claim limits",
      "This packet contains deterministic ledger state and explicitly labeled model estimates only. It does not claim human reader agreement."
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp discourse_points(screenplay) do
    with {:ok, units} <- Fount.Selection.select(screenplay, %{"whole_screenplay" => true}) do
      base =
        units
        |> Enum.sort_by(&{&1["ordinal"], &1["target"]["id"], &1["evidence_id"]})
        |> Enum.uniq_by(& &1["target"]["id"])
        |> Enum.with_index()
        |> Enum.map(fn {unit, ordinal} ->
          %{
            "id" => "reader:" <> unit["target"]["id"],
            "ordinal" => ordinal,
            "scene_id" => unit["scene_id"],
            "element_id" => unit["target"]["id"],
            "element_ordinal" => unit["ordinal"],
            "type" => unit["type"],
            "boundary" => "after_element",
            "scene_exit" => false
          }
        end)

      last_by_scene =
        base
        |> Enum.reject(&is_nil(&1["scene_id"]))
        |> Enum.group_by(& &1["scene_id"])
        |> Map.new(fn {scene_id, points} ->
          {scene_id, points |> Enum.max_by(& &1["ordinal"]) |> Map.fetch!("id")}
        end)

      {:ok,
       Enum.map(base, fn point ->
         %{point | "scene_exit" => Map.get(last_by_scene, point["scene_id"]) == point["id"]}
       end)}
    end
  end

  defp normalize_events(events) do
    Enum.reduce_while(events, {:ok, [], []}, fn raw, {:ok, visible, private} ->
      case Event.new(raw) do
        {:ok, %Event{visibility: "private"} = event} ->
          {:cont, {:ok, visible, private ++ [event.id]}}

        {:ok, event} ->
          {:cont, {:ok, visible ++ [event], private}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp unique_event_ids(events, private_ids) do
    ids = Enum.map(events, & &1.id) ++ private_ids
    if length(ids) == length(Enum.uniq(ids)), do: :ok, else: {:error, :duplicate_reader_event_id}
  end

  defp validate_events(screenplay, points, events) do
    point_by_element = Map.new(points, &{&1["element_id"], &1})
    point_by_id = Map.new(points, &{&1["id"], &1})

    Enum.reduce_while(events, {:ok, []}, fn event, {:ok, acc} ->
      point = point_by_id[event.point] || point_by_element[event.point]

      case validate_event(screenplay, point_by_element, point, event) do
        :ok ->
          event = enrich_event_dependencies(%{event | point: point["id"]})
          {:cont, {:ok, acc ++ [event]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_event(_screenplay, _point_by_element, nil, event),
    do: {:error, {:reader_event_not_visible, event.id, event.point}}

  defp validate_event(screenplay, point_by_element, point, event) do
    with :ok <- validate_evidence_present(event),
         :ok <- validate_event_shape(event),
         :ok <- validate_evidence_order(screenplay, point_by_element, point, event) do
      :ok
    end
  end

  defp validate_evidence_present(%Event{evidence: []} = event),
    do: {:error, {:reader_event_without_evidence, event.id}}

  defp validate_evidence_present(_event), do: :ok

  defp validate_evidence_order(screenplay, point_by_element, point, event) do
    Enum.reduce_while(event.evidence, :ok, fn evidence, :ok ->
      case evidence_identity(evidence) do
        {:ok, revision_id, element_id, evidence_id} ->
          source_point = point_by_element[element_id]

          cond do
            revision_id != screenplay.revision.id ->
              {:halt, {:error, {:reader_evidence_revision_mismatch, event.id, evidence_id}}}

            is_nil(source_point) ->
              {:halt, {:error, {:reader_evidence_not_visible, event.id, evidence_id, element_id}}}

            source_point["ordinal"] > point["ordinal"] ->
              {:halt,
               {:error,
                {:future_reader_evidence, event.id, evidence_id, source_point["id"], point["id"]}}}

            true ->
              {:cont, :ok}
          end

        :error ->
          {:halt, {:error, {:invalid_reader_evidence, event.id}}}
      end
    end)
  end

  defp validate_event_shape(%Event{kind: "character_epistemic", data: data} = event) do
    require_fields(event, data, ~w(character proposition stance))
  end

  defp validate_event_shape(%Event{kind: "relationship", data: data} = event) do
    with :ok <- require_fields(event, data, ~w(from to dimensions)) do
      if is_map(data["dimensions"]), do: :ok, else: {:error, {:invalid_reader_relationship, event.id}}
    end
  end

  defp validate_event_shape(%Event{kind: "suspense", data: data} = event) do
    if is_map(data["components"]), do: :ok, else: {:error, {:invalid_reader_suspense, event.id}}
  end

  defp validate_event_shape(%Event{kind: kind})
       when kind in ~w(question expectation promise threat reveal curiosity surprise comprehension_risk alignment forward_pull),
       do: :ok

  defp validate_event_shape(event), do: {:error, {:unsupported_reader_event_kind, event.id, event.kind}}

  defp require_fields(event, data, fields) do
    missing = Enum.filter(fields, &(is_nil(data[&1])))
    if missing == [], do: :ok, else: {:error, {:missing_reader_event_fields, event.id, missing}}
  end

  defp evidence_identity(%{revision_id: revision_id, target: target} = evidence),
    do: evidence_identity_map(revision_id, target, Map.get(evidence, :id))

  defp evidence_identity(%{} = evidence) do
    revision_id = evidence["revision_id"] || evidence[:revision_id]
    target = evidence["target"] || evidence[:target]
    id = evidence["id"] || evidence[:id] || evidence["evidence_id"] || evidence[:evidence_id]
    evidence_identity_map(revision_id, target, id)
  end

  defp evidence_identity(_), do: :error

  defp evidence_identity_map(revision_id, %{} = target, id) do
    kind = target["kind"] || target[:kind]
    element_id = target["id"] || target[:id]

    if kind in ["element", :element] and is_binary(element_id),
      do: {:ok, revision_id, element_id, id || element_id},
      else: :error
  end

  defp evidence_identity_map(_revision_id, _target, _id), do: :error

  defp enrich_event_dependencies(event) do
    evidence_dependencies =
      Enum.flat_map(event.evidence, fn evidence ->
        case evidence_identity(evidence) do
          {:ok, _revision_id, element_id, evidence_id} ->
            ["canonical:#{element_id}", "evidence:#{evidence_id}"]

          :error ->
            []
        end
      end)

    %{event | dependencies: Enum.sort(Enum.uniq(event.dependencies ++ evidence_dependencies))}
  end

  defp reduce_snapshots(points, events) do
    events_by_point = Enum.group_by(events, & &1.point)

    result =
      Enum.reduce_while(points, {:ok, %State{}, []}, fn point, {:ok, state, snapshots} ->
        point_events = Map.get(events_by_point, point["id"], [])

        case Enum.reduce_while(point_events, {:ok, state}, fn event, {:ok, acc} ->
               case apply_event(acc, event, point) do
                 {:ok, next} -> {:cont, {:ok, next}}
                 {:error, reason} -> {:halt, {:error, reason}}
               end
             end) do
          {:ok, next_state} ->
            snapshot = %Snapshot{
              point: point,
              state: next_state,
              event_ids: Enum.map(point_events, & &1.id)
            }

            {:cont, {:ok, next_state, snapshots ++ [snapshot]}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, _state, snapshots} -> {:ok, snapshots}
      error -> error
    end
  end

  defp apply_event(state, %Event{kind: "question"} = event, point),
    do: lifecycle(state, :open_questions, event, point, ~w(open reinforce partial resolve abandon))

  defp apply_event(state, %Event{kind: "expectation"} = event, point),
    do: lifecycle(state, :expectations, event, point, ~w(open strengthen delay complicate fulfill subvert abandon))

  defp apply_event(state, %Event{kind: "promise"} = event, point),
    do: lifecycle(state, :promises, event, point, ~w(open reinforce delay complicate fulfill subvert abandon))

  defp apply_event(state, %Event{kind: "threat"} = event, point),
    do: lifecycle(state, :threats, event, point, ~w(open reinforce delay complicate fulfill subvert abandon resolve))

  defp apply_event(state, %Event{kind: "comprehension_risk"} = event, point),
    do: lifecycle(state, :comprehension_risks, event, point, ~w(open reinforce complicate resolve abandon))

  defp apply_event(state, %Event{kind: "forward_pull"} = event, point),
    do: lifecycle(state, :forward_pull, event, point, ~w(open strengthen delay redirect resolve abandon))

  defp apply_event(state, %Event{kind: "reveal"} = event, point) do
    statuses = %{
      "hint" => "hinted",
      "inferable" => "inferable",
      "likely_inferred" => "likely_inferred",
      "explicit" => "explicit",
      "confirm" => "confirmed",
      "complicate" => "complicated",
      "overturn" => "overturned"
    }

    case Map.fetch(statuses, event.action) do
      :error -> {:error, {:invalid_reader_event_action, event.id, event.action}}
      {:ok, status} -> {:ok, put_observation(state, :reveals, event, point, status)}
    end
  end

  defp apply_event(state, %Event{kind: "character_epistemic"} = event, point) do
    if event.action in ~w(set support withdraw complicate) do
      key = event.key || stable_key([event.data["character"], event.data["proposition"]])
      prior = Map.get(state.character_models, key, %{"id" => key, "history" => []})

      entry =
        prior
        |> Map.merge(%{
          "character" => event.data["character"],
          "proposition" => event.data["proposition"],
          "stance" => event.data["stance"],
          "status" => event.action,
          "claim_class" => event.claim_class,
          "updated_at" => point["id"],
          "evidence" => Model.plain(event.evidence),
          "dependencies" => event.dependencies
        })
        |> append_history(event, point)

      {:ok, %{state | character_models: Map.put(state.character_models, key, entry)}}
    else
      {:error, {:invalid_reader_event_action, event.id, event.action}}
    end
  end

  defp apply_event(state, %Event{kind: "relationship"} = event, point) do
    if event.action in ~w(set change reinforce complicate) do
      key = event.key || stable_key([event.data["from"], event.data["to"]])
      prior = Map.get(state.relationships, key, %{"id" => key, "history" => []})

      entry =
        prior
        |> Map.merge(%{
          "from" => event.data["from"],
          "to" => event.data["to"],
          "dimensions" => event.data["dimensions"],
          "status" => event.action,
          "claim_class" => event.claim_class,
          "updated_at" => point["id"],
          "evidence" => Model.plain(event.evidence),
          "dependencies" => event.dependencies
        })
        |> append_history(event, point)

      {:ok, %{state | relationships: Map.put(state.relationships, key, entry)}}
    else
      {:error, {:invalid_reader_event_action, event.id, event.action}}
    end
  end

  defp apply_event(state, %Event{kind: "suspense"} = event, point) do
    if event.action in ~w(set update resolve) do
      status = if(event.action == "resolve", do: "resolved", else: "active")
      {:ok, put_observation(state, :suspense, event, point, status)}
    else
      {:error, {:invalid_reader_event_action, event.id, event.action}}
    end
  end

  defp apply_event(state, %Event{kind: kind} = event, point)
       when kind in ~w(curiosity surprise alignment) do
    if event.action in ~w(open set update opportunity realize resolve abandon) do
      field = String.to_existing_atom(kind)
      status = observation_status(event.action)
      {:ok, put_observation(state, field, event, point, status)}
    else
      {:error, {:invalid_reader_event_action, event.id, event.action}}
    end
  end

  defp lifecycle(state, field, event, point, allowed) do
    if event.action in allowed do
      entries = Map.fetch!(state, field)
      key = event.key || event.id
      prior = Map.get(entries, key, %{"id" => key, "history" => []})
      status = lifecycle_status(event.kind, event.action, Map.get(prior, "status"))

      entry =
        prior
        |> Map.merge(%{
          "status" => status,
          "claim_class" => event.claim_class,
          "data" => event.data,
          "updated_at" => point["id"],
          "evidence" => Model.plain(event.evidence),
          "dependencies" => event.dependencies
        })
        |> maybe_opened_at(point)
        |> maybe_closed_at(status, point)
        |> append_history(event, point)

      {:ok, Map.put(state, field, Map.put(entries, key, entry))}
    else
      {:error, {:invalid_reader_event_action, event.id, event.action}}
    end
  end

  defp observation_status("resolve"), do: "resolved"
  defp observation_status("abandon"), do: "abandoned"
  defp observation_status("realize"), do: "realized"
  defp observation_status(action), do: action

  defp lifecycle_status("question", "partial", _prior), do: "partially_answered"
  defp lifecycle_status("question", "resolve", _prior), do: "resolved"
  defp lifecycle_status("question", "abandon", _prior), do: "abandoned"
  defp lifecycle_status("question", _action, _prior), do: "open"
  defp lifecycle_status(_kind, "fulfill", _prior), do: "fulfilled"
  defp lifecycle_status(_kind, "subvert", _prior), do: "subverted"
  defp lifecycle_status(_kind, "resolve", _prior), do: "resolved"
  defp lifecycle_status(_kind, "abandon", _prior), do: "abandoned"
  defp lifecycle_status(_kind, "delay", _prior), do: "delayed"
  defp lifecycle_status(_kind, "complicate", _prior), do: "complicated"
  defp lifecycle_status(_kind, "redirect", _prior), do: "redirected"
  defp lifecycle_status(_kind, _action, prior), do: prior || "open"

  defp put_observation(state, field, event, point, status) do
    entries = Map.fetch!(state, field)
    key = event.key || event.id
    prior = Map.get(entries, key, %{"id" => key, "history" => []})

    entry =
      prior
      |> Map.merge(%{
        "status" => status,
        "data" => event.data,
        "claim_class" => event.claim_class,
        "updated_at" => point["id"],
        "evidence" => Model.plain(event.evidence),
        "dependencies" => event.dependencies
      })
      |> append_history(event, point)

    Map.put(state, field, Map.put(entries, key, entry))
  end

  defp append_history(entry, event, point) do
    history = Map.get(entry, "history", [])

    Map.put(entry, "history", history ++ [
      %{
        "event_id" => event.id,
        "action" => event.action,
        "point_id" => point["id"],
        "claim_class" => event.claim_class
      }
    ])
  end

  defp maybe_opened_at(entry, point) do
    if Map.has_key?(entry, "opened_at"), do: entry, else: Map.put(entry, "opened_at", point["id"])
  end

  defp maybe_closed_at(entry, status, point) when status in ~w(resolved abandoned fulfilled subverted),
    do: Map.put(entry, "closed_at", point["id"])

  defp maybe_closed_at(entry, _status, _point), do: entry

  defp dependency_index(events, points) do
    by_id = Map.new(points, &{&1["id"], &1})

    Enum.reduce(events, %{}, fn event, acc ->
      point = by_id[event.point]

      Enum.reduce(event.dependencies, acc, fn dependency, nested ->
        entry = %{"event_id" => event.id, "point_id" => event.point, "ordinal" => point["ordinal"]}
        Map.update(nested, dependency, [entry], &[entry | &1])
      end)
    end)
    |> Map.new(fn {dependency, entries} ->
      {dependency, Enum.sort_by(entries, &{&1["ordinal"], &1["event_id"]})}
    end)
  end

  defp point_for(points, ordinal) when is_integer(ordinal), do: Enum.at(points, ordinal)

  defp point_for(points, ref) when is_binary(ref),
    do: Enum.find(points, &(&1["id"] == ref or &1["element_id"] == ref))

  defp point_for(_points, _ref), do: nil

  @reader_tracks ~w(
    open_questions expectations promises threats reveals character_models suspense curiosity
    surprise comprehension_risks alignment relationships forward_pull
  )a

  defp normalize_track(track) when is_atom(track) do
    if track in @reader_tracks, do: {:ok, track}, else: {:error, {:unknown_reader_track, track}}
  end

  defp normalize_track(track) when is_binary(track) do
    case Enum.find(@reader_tracks, &(Atom.to_string(&1) == track)) do
      nil -> {:error, {:unknown_reader_track, track}}
      known -> {:ok, known}
    end
  end

  defp normalize_track(track), do: {:error, {:unknown_reader_track, track}}

  defp epistemic_signatures(entries) do
    entries
    |> Enum.map(fn entry ->
      proposition = entry["proposition"] || entry[:proposition] || entry["object"] || entry[:object]
      stance = entry["stance"] || entry[:stance] || entry["status"] || entry[:status]

      %{
        "proposition" => Model.plain(proposition),
        "stance" => normalize_epistemic_stance(stance)
      }
    end)
    |> Enum.uniq()
    |> Enum.sort_by(&CanonicalJSON.hash/1)
  end

  defp normalize_epistemic_stance(value) do
    case to_string(value || "") |> String.downcase() do
      value when value in ["know", "known", "knows", "knowledge", "established"] -> "knows"
      value when value in ["believe", "believes", "belief", "set", "support"] -> "believes"
      value when value in ["suspect", "suspects", "suspicion"] -> "suspects"
      value -> value
    end
  end

  defp reader_claim_classes(reader) do
    reader.snapshots
    |> Enum.flat_map(fn snapshot ->
      snapshot.state
      |> Map.from_struct()
      |> Map.values()
      |> Enum.flat_map(fn entries ->
        entries |> Map.values() |> Enum.map(& &1["claim_class"])
      end)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp stable_key(value), do: "reader_" <> CanonicalJSON.hash(Model.plain(value))
  defp same_value?(left, right), do: CanonicalJSON.hash(Model.plain(left)) == CanonicalJSON.hash(Model.plain(right))

  defp markdown_entries(entries) when map_size(entries) == 0, do: "_None_"

  defp markdown_entries(entries) do
    entries
    |> Map.values()
    |> Enum.sort_by(& &1["id"])
    |> Enum.map(fn entry -> "- `#{entry["id"]}` — #{entry["status"]}" end)
  end
end
