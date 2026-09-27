defmodule Fount.Intelligence.StoryWorld.Consistency do
  @moduledoc "Practical, local StoryWorld consistency checks. This is deliberately not a general interval theorem prover."

  alias Fount.Intelligence.StoryWorld.{Conflict, StoryTime}

  def check(world) do
    conflicting_state_writes(world) ++ transition_from_mismatches(world)
  end

  defp conflicting_state_writes(world) do
    world.state_transitions
    |> Map.values()
    |> Enum.group_by(fn transition ->
      {value_key(transition.subject), transition.attribute, transition.event_id, transition.scope_id}
    end)
    |> Enum.flat_map(fn {_key, transitions} ->
      values = transitions |> Enum.map(&value_key(&1.to)) |> Enum.uniq()

      if length(values) > 1 do
        ids = transitions |> Enum.map(& &1.id) |> Enum.sort()

        [
          %Conflict{
            id: conflict_id("state_write", ids),
            kind: "state_contradiction",
            message: "Multiple supported transitions assign incompatible values at the same story event.",
            severity: "error",
            involved_ids: ids,
            evidence: transitions |> Enum.flat_map(& &1.evidence) |> uniq_evidence(),
            dependencies: Enum.map(ids, &"story:#{&1}")
          }
        ]
      else
        []
      end
    end)
  end

  defp transition_from_mismatches(world) do
    transitions = Map.values(world.state_transitions)

    Enum.flat_map(transitions, fn transition ->
      if is_nil(transition.from) do
        []
      else
        prior =
          transitions
          |> Enum.filter(fn candidate ->
            candidate.id != transition.id and candidate.scope_id == transition.scope_id and
              candidate.attribute == transition.attribute and
              value_key(candidate.subject) == value_key(transition.subject) and
              strictly_before?(world, candidate.event_id, transition.event_id)
          end)
          |> maximal_before(world)

        values = prior |> Enum.map(& &1.to) |> Enum.uniq_by(&value_key/1)

        case values do
          [known] ->
            if value_key(known) == value_key(transition.from) do
              []
            else
              ids = [transition.id | Enum.map(prior, & &1.id)] |> Enum.sort()

              [
                %Conflict{
                  id: conflict_id("transition_from", ids),
                  kind: "state_precondition_conflict",
                  message: "A state transition's declared prior value disagrees with the latest supported prior state.",
                  severity: "warning",
                  involved_ids: ids,
                  evidence: ([transition] ++ prior) |> Enum.flat_map(& &1.evidence) |> uniq_evidence(),
                  dependencies: Enum.map(ids, &"story:#{&1}")
                }
              ]
            end

          _ ->
            []
        end
      end
    end)
  end

  defp maximal_before(transitions, world) do
    Enum.reject(transitions, fn transition ->
      Enum.any?(transitions, fn other ->
        other.id != transition.id and strictly_before?(world, transition.event_id, other.event_id)
      end)
    end)
  end

  defp strictly_before?(world, left, right) do
    case StoryTime.relation(world.story_time, left, right) do
      %{status: :known, relations: ["before"]} -> true
      _ -> false
    end
  end

  defp value_key(value), do: Fount.Writing.CanonicalJSON.hash(Fount.Screenplay.Model.plain(value))
  defp conflict_id(kind, ids), do: "sw_conflict_" <> Fount.ID.hash([kind, ":", Enum.join(ids, "|")])

  defp uniq_evidence(evidence),
    do: evidence |> Enum.uniq_by(& &1.id) |> Enum.sort_by(& &1.id)
end
