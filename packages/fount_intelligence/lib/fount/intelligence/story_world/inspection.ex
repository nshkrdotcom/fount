defmodule Fount.Intelligence.StoryWorld.Inspection do
  @moduledoc "Writer-facing StoryWorld reference packet. It exposes evidence and uncertainty without turning Phase 3 state into diagnosis or revision advice."

  alias Fount.Intelligence.StoryWorld.{Query, StoryTime}
  alias Fount.Screenplay.Model
  alias Fount.Writing.CanonicalJSON

  def packet(world, opts \\ []) do
    focus_ids = Keyword.get(opts, :focus_ids, []) |> List.wrap() |> Enum.map(&to_string/1)

    question =
      Keyword.get(
        opts,
        :question,
        "What does the current source-grounded story-world model establish, leave ambiguous, or leave unknown?"
      )

    protected_strengths = Keyword.get(opts, :protected_strengths, []) |> List.wrap()
    selected = select_objects(world, focus_ids)

    %{
      "packet_type" => "story_world_reference",
      "source_revision" => world.revision_id,
      "screenplay_id" => world.screenplay_id,
      "question" => question,
      "claim_class" => "derived_narrative_state",
      "summary" => summary(world),
      "reference" => reference(world, selected),
      "evidence" => selected_evidence(world, selected),
      "uncertainty" => uncertainty(world),
      "protected_strengths" => Enum.map(protected_strengths, &Model.plain/1),
      "diagnoses" => [],
      "strategies" => [],
      "limitations" => [
        "Phase 3 reports source-grounded interpreted narrative state; it does not diagnose screenplay quality or recommend revisions.",
        "Unknown and ambiguous story chronology are retained rather than converted into scene-order chronology.",
        "No human reader-response, audience-effect, or calibrated creative-quality claim is made by this packet."
      ]
    }
  end

  defp summary(world) do
    %{
      "entities" => map_size(world.entities),
      "events" => map_size(world.events),
      "assertions" => map_size(world.assertions),
      "state_transitions" => map_size(world.state_transitions),
      "story_time_constraints" => map_size(world.story_time.constraints),
      "causal_relations" => map_size(world.causal.edges),
      "conflicts" => length(world.conflicts),
      "unknown_story_time_pairs" => length(StoryTime.unresolved_pairs(world.story_time))
    }
  end

  defp reference(world, :all) do
    %{
      "scopes" => plain_values(world.scopes),
      "entities" => plain_values(world.entities),
      "events" => plain_values(world.events),
      "interactions" => plain_values(world.interactions),
      "assertions" => plain_values(world.assertions),
      "goals" => plain_values(world.goals),
      "commitments" => plain_values(world.commitments),
      "state_transitions" => plain_values(world.state_transitions),
      "beats" => plain_values(world.beats),
      "motifs" => plain_values(world.motifs),
      "story_time_nodes" => plain_values(world.story_time.nodes),
      "story_time_constraints" => plain_values(world.story_time.constraints),
      "causal_relations" => plain_values(world.causal.edges),
      "conflicts" => world.conflicts |> Enum.sort_by(& &1.id) |> Model.plain()
    }
  end

  defp reference(_world, selected) do
    selected
    |> Enum.sort_by(& &1.id)
    |> Model.plain()
  end

  defp select_objects(_world, []), do: :all

  defp select_objects(world, ids) do
    ids
    |> Enum.map(&Query.find_object(world, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp selected_evidence(world, :all) do
    collections = [
      world.entities,
      world.mentions,
      world.events,
      world.interactions,
      world.assertions,
      world.goals,
      world.commitments,
      world.state_transitions,
      world.beats,
      world.motifs,
      world.story_time.constraints,
      world.causal.edges
    ]

    collections
    |> Enum.flat_map(&Map.values/1)
    |> Kernel.++(world.conflicts)
    |> Enum.flat_map(&Map.get(&1, :evidence, []))
    |> uniq_evidence()
    |> Model.plain()
  end

  defp selected_evidence(_world, selected) do
    selected
    |> Enum.flat_map(&Map.get(&1, :evidence, []))
    |> uniq_evidence()
    |> Model.plain()
  end

  defp uncertainty(world) do
    %{
      "ambiguous_story_time" => direct_temporal(world, :ambiguous),
      "contradictory_story_time" => direct_temporal(world, :contradiction),
      "unknown_story_time_pairs" =>
        StoryTime.unresolved_pairs(world.story_time)
        |> Enum.map(fn {left, right} -> %{"left" => left, "right" => right} end),
      "competing_assertions" => competing_assertions(world)
    }
  end

  defp direct_temporal(world, status) do
    world.story_time.constraints
    |> Map.values()
    |> Enum.group_by(&{&1.left, &1.right})
    |> Enum.flat_map(fn {{left, right}, _constraints} ->
      case StoryTime.relation(world.story_time, left, right) do
        %{status: ^status} = packet ->
          [
            %{
              "left" => left,
              "right" => right,
              "relations" => packet.relations,
              "constraint_ids" => packet.constraint_ids
            }
          ]

        _ ->
          []
      end
    end)
    |> Enum.uniq()
    |> Enum.sort_by(&{&1["left"], &1["right"]})
  end

  defp competing_assertions(world) do
    world.assertions
    |> Map.values()
    |> Enum.group_by(fn assertion ->
      {assertion.predicate, assertion.scope_id, key(assertion.subject)}
    end)
    |> Enum.flat_map(fn {{predicate, scope, _subject_key}, assertions} ->
      objects = Enum.uniq_by(assertions, &key(&1.object))

      if length(objects) > 1 do
        [
          %{
            "predicate" => predicate,
            "scope_id" => scope,
            "assertion_ids" => assertions |> Enum.map(& &1.id) |> Enum.sort()
          }
        ]
      else
        []
      end
    end)
    |> Enum.sort_by(&{&1["predicate"], &1["scope_id"], &1["assertion_ids"]})
  end

  defp plain_values(map), do: map |> Map.values() |> Enum.sort_by(& &1.id) |> Model.plain()
  defp key(value), do: CanonicalJSON.hash(Model.plain(value))

  defp uniq_evidence(evidence),
    do: evidence |> Enum.uniq_by(& &1.id) |> Enum.sort_by(& &1.id)
end
