defmodule Fount.Intelligence.Capabilities.ThemeMeaning do
  @moduledoc "Pure Phase-8 thematic hypothesis synthesis with support and counterevidence, never an authoritative theme or depth score."

  alias Fount.Intelligence.Capabilities.{Result, Support}
  alias Fount.Screenplay.Model

  @keys ~w(value_conflict conflict_axis choice_embodies_conflict consequence_complicates_conflict motif_reinforces_question contrast_reinforces_question ending_recontextualizes_question writer_intent_alignment contradictory_signal)a

  def analyze(world, subject, entries, opts \\ []) do
    hypotheses = hypotheses(entries)
    motifs = world.motifs |> Map.values() |> Enum.sort_by(& &1.id)
    transitions = world.state_transitions |> Map.values() |> Enum.sort_by(& &1.id)
    diagnoses = diagnoses(entries, hypotheses)

    %Result{
      family: "theme_meaning",
      source_revision: world.revision_id,
      subject: Model.plain(subject),
      status: status(entries),
      evidence:
        Support.merge_evidence([
          Support.measurement_evidence(entries),
          Support.evidence(motifs),
          Support.evidence(transitions)
        ]),
      measurements: %{"keys" => Enum.map(@keys, &to_string/1), "entries" => entries},
      derived_state: %{
        "thematic_hypotheses" => hypotheses,
        "motif_map" => Support.plain_objects(motifs),
        "value_transition_map" => Support.plain_objects(transitions),
        "writer_intent_comparison" => writer_intent(entries, Keyword.get(opts, :intent, %{}))
      },
      trajectories: %{
        "measurements" => Support.measurement_trajectory(entries, @keys),
        "conflict_axis_by_scene" =>
          Enum.map(
            entries,
            &%{
              "scene_id" => &1["scene_id"],
              "conflict_axis" => Support.choice(&1, :conflict_axis)
            }
          )
      },
      diagnoses: diagnoses,
      uncertainty: uncertainty(entries),
      next_investigations: next_investigations(hypotheses, diagnoses),
      limitations: [
        "Thematic outputs are competing hypotheses about recurring value conflict and meaning-making evidence, not an authoritative statement of what the screenplay means.",
        "Conflict-axis labels are a practical measurement vocabulary, not a closed taxonomy; 'other_or_unclear' preserves material that does not fit the installed rubric.",
        "No depth, importance, prestige, or overall quality score is produced.",
        "Writer intent is evidence about intended meaning, not proof that a first-time reader will infer it."
      ],
      metadata: %{"family_version" => 1, "intent" => Model.plain(Keyword.get(opts, :intent, %{}))}
    }
  end

  defp hypotheses(entries) do
    entries
    |> Enum.filter(&Support.supported?(&1, :value_conflict))
    |> Enum.group_by(&Support.choice(&1, :conflict_axis))
    |> Enum.reject(fn {axis, items} -> axis in [nil, "other_or_unclear"] or length(items) < 2 end)
    |> Enum.map(fn {axis, items} ->
      support =
        Enum.map(items, & &1["scene_id"]) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()

      counter =
        entries
        |> Enum.filter(&Support.supported?(&1, :contradictory_signal))
        |> Enum.map(& &1["scene_id"])
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.sort()

      %{
        "id" => "theme.axis.#{axis}",
        "claim_class" => "model_estimated_interpretation",
        "hypothesis" =>
          "The selected material repeatedly stages the value-conflict axis '#{axis}'.",
        "support_scene_ids" => support,
        "counterevidence_scene_ids" => counter,
        "choice_embodiment_scene_ids" => scenes(items, :choice_embodies_conflict),
        "consequence_complication_scene_ids" => scenes(items, :consequence_complicates_conflict),
        "motif_reinforcement_scene_ids" => scenes(items, :motif_reinforces_question)
      }
    end)
    |> Enum.sort_by(& &1["id"])
  end

  defp writer_intent(entries, intent) do
    %{
      "declared" => Model.plain(intent),
      "aligned_scene_ids" => scenes(entries, :writer_intent_alignment),
      "contradictory_scene_ids" => scenes(entries, :contradictory_signal),
      "claim" => "intent_and_observed_evidence_kept_separate"
    }
  end

  defp diagnoses(entries, hypotheses) do
    support = measurement_ids(entries)

    []
    |> maybe_diag(
      hypotheses == [] and Support.any_supported?(entries, :value_conflict),
      Support.diagnosis(
        "theme.recurring_question_not_yet_specific_candidate",
        "Value conflict is visible, but the installed conflict-axis vocabulary does not yet support a recurring specific hypothesis.",
        "Value-conflict measurement is supported while no recurring non-generic axis has enough support.",
        support,
        uncertainty: "high"
      )
    )
    |> maybe_diag(
      Support.any_supported?(entries, :contradictory_signal),
      Support.diagnosis(
        "theme.contradictory_signal_candidate",
        "Some choices or consequences may point against a currently supported thematic hypothesis.",
        "Contradictory-signal measurement is supported in the selected material.",
        support,
        limitations: [
          "Counterevidence can deepen or complicate a thematic question rather than weaken it."
        ]
      )
    )
    |> maybe_diag(
      Support.any_supported?(entries, :motif_reinforces_question) and
        Support.all_not_supported?(entries, :choice_embodies_conflict),
      Support.diagnosis(
        "theme.motif_without_choice_connection_candidate",
        "A recurring motif may be carrying thematic emphasis without a visible connection to consequential character choice in the selected scope.",
        "Motif reinforcement is supported while choice embodiment is unsupported.",
        support,
        uncertainty: "high"
      )
    )
    |> Enum.sort_by(& &1["id"])
  end

  defp scenes(entries, key) do
    entries
    |> Enum.filter(&Support.supported?(&1, key))
    |> Enum.map(& &1["scene_id"])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp uncertainty(entries) do
    for entry <- entries,
        key <- @keys,
        Support.status(entry, key) in ["uncertain", "insufficient_evidence", "unavailable"] do
      %{
        "scene_id" => entry["scene_id"],
        "measurement" => to_string(key),
        "status" => Support.status(entry, key)
      }
    end
  end

  defp next_investigations(hypotheses, diagnoses) do
    base =
      Enum.map(hypotheses, fn item ->
        "Trace the choices and consequences that support #{item["id"]}, then inspect its listed counterevidence before strengthening the hypothesis."
      end)

    if diagnoses == [],
      do: base,
      else:
        Enum.uniq(
          base ++
            [
              "Compare recurring value conflict against the ending and the writer's declared thematic intent without forcing a single reading."
            ]
        )
  end

  defp measurement_ids(entries) do
    entries
    |> Enum.flat_map(&(get_in(&1, ["provenance", "measurement_ids"]) || []))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp status(entries),
    do: if(Enum.all?(entries, &(&1["status"] == "complete")), do: "complete", else: "partial")

  defp maybe_diag(list, true, diagnosis), do: list ++ [diagnosis]
  defp maybe_diag(list, false, _diagnosis), do: list
end
