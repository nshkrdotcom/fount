defmodule Fount.Intelligence.Capabilities.AudienceReaderExperience do
  @moduledoc "Pure Phase-7 audience/reader reasoning over frozen measurements plus an optional strict-forward Reader reducer."

  alias Fount.Intelligence.Capabilities.{Result, Support}
  alias Fount.Intelligence.Reader
  alias Fount.Screenplay.Model

  @keys ~w(open_question expectation visible_threat valued_uncertainty curiosity_gap surprise_candidate comprehension_risk intentional_ambiguity reveal_changes_inference forward_pull)a
  @reader_tracks ~w(open_questions expectations promises threats suspense curiosity surprise comprehension_risks forward_pull)a

  def analyze(world, subject, entries, opts \\ []) do
    reader = Keyword.get(opts, :reader)
    checkpoint_trajectory = checkpoint_trajectory(reader)
    reader_packet = reader_packet(reader)
    diagnoses = diagnoses(entries, reader_packet)

    %Result{
      family: "audience_reader_experience",
      source_revision: world.revision_id,
      subject: Model.plain(subject),
      status: result_status(entries, reader),
      evidence: Support.measurement_evidence(entries),
      measurements: %{
        "keys" => Enum.map(@keys, &to_string/1),
        "entries" => entries
      },
      derived_state: %{
        "reader" => reader_packet,
        "question_ledger" => final_track(reader_packet, "open_questions"),
        "anticipation_ledger" => %{
          "expectations" => final_track(reader_packet, "expectations"),
          "promises" => final_track(reader_packet, "promises"),
          "threats" => final_track(reader_packet, "threats")
        },
        "suspense_components" => final_track(reader_packet, "suspense"),
        "curiosity_components" => final_track(reader_packet, "curiosity"),
        "surprise_candidates" => final_track(reader_packet, "surprise"),
        "comprehension_risks" => final_track(reader_packet, "comprehension_risks"),
        "handoff_pressure" => final_track(reader_packet, "forward_pull")
      },
      trajectories: %{
        "measurements" => Support.measurement_trajectory(entries, @keys),
        "reader_checkpoints" => checkpoint_trajectory,
        "semantics" => "presentation_relative_forward_only"
      },
      diagnoses: diagnoses,
      uncertainty: uncertainty(entries, reader),
      next_investigations: next_investigations(diagnoses, reader),
      limitations: [
        "Reader ledger state is produced only from supplied reader-visible events at or before each presentation checkpoint; later-page evidence is rejected by Reader.reduce/3.",
        "Measurement answers are uncalibrated model estimates over selected source excerpts and do not establish human reader agreement.",
        "Suspense, curiosity, surprise, comprehension, and forward pull remain separate components rather than one universal quality score.",
        "If no reader_events are supplied, the family can still surface excerpt measurements but reports partial Reader coverage rather than inventing a trajectory."
      ],
      metadata: %{
        "family_version" => 1,
        "reader_event_count" => reader_event_count(reader),
        "reader_checkpoint_count" => reader_checkpoint_count(reader),
        "options" => safe_options(opts)
      }
    }
  end

  defp checkpoint_trajectory(%Reader{} = reader) do
    Enum.map(reader.snapshots, fn snapshot ->
      state = snapshot.state |> Map.from_struct() |> Model.plain()

      %{
        "point" => snapshot.point,
        "event_ids" => snapshot.event_ids,
        "tracks" => Map.take(state, Enum.map(@reader_tracks, &to_string/1))
      }
    end)
  end

  defp checkpoint_trajectory(_), do: []

  defp reader_packet(%Reader{} = reader), do: Reader.inspection_packet(reader)

  defp reader_packet(_),
    do: %{
      "semantics" => "presentation_relative_forward_only",
      "status" => "not_supplied",
      "checkpoint_count" => 0,
      "event_ids" => [],
      "ignored_private_event_ids" => [],
      "final_state" => %{}
    }

  defp final_track(%{"final_state" => state}, key) when is_map(state),
    do: Map.get(state, key, %{})

  defp final_track(_, _), do: %{}

  defp diagnoses(entries, packet) do
    final = packet["final_state"] || %{}
    open_questions = map_size(Map.get(final, "open_questions", %{}))
    threats = map_size(Map.get(final, "threats", %{}))
    suspense = map_size(Map.get(final, "suspense", %{}))
    risks = map_size(Map.get(final, "comprehension_risks", %{}))
    pull = map_size(Map.get(final, "forward_pull", %{}))
    support = measurement_ids(entries)

    []
    |> maybe_diag(
      Support.any_supported?(entries, :comprehension_risk) and
        not Support.any_supported?(entries, :intentional_ambiguity),
      Support.diagnosis(
        "audience.comprehension_risk_candidate",
        "The selected passage may require a reader connection that is not yet legible.",
        "Comprehension-risk measurement is supported without equally visible evidence that the ambiguity is deliberate.",
        support,
        limitations: [
          "Intentional withholding can be dramatically useful; inspect the exact missing connection before changing pages."
        ]
      )
    )
    |> maybe_diag(
      open_questions > 0 and pull == 0 and Support.all_not_supported?(entries, :forward_pull),
      Support.diagnosis(
        "audience.open_question_without_handoff_candidate",
        "An open reader question may not be creating useful forward pressure at the current handoff.",
        "The Reader ledger retains open questions while forward-pull measurement remains unsupported and no forward-pull ledger item is active.",
        support,
        uncertainty: "high"
      )
    )
    |> maybe_diag(
      threats > 0 and suspense == 0 and Support.any_supported?(entries, :valued_uncertainty),
      Support.diagnosis(
        "audience.threat_without_suspense_component_candidate",
        "A visible threat and valued uncertainty may not yet be represented as sustained suspense pressure.",
        "Reader threat state is active and valued uncertainty is measured, but no supplied suspense ledger component is active.",
        support,
        uncertainty: "high"
      )
    )
    |> maybe_diag(
      risks > 0,
      Support.diagnosis(
        "audience.reader_ledger_comprehension_risk",
        "A supplied Reader event records a current comprehension risk.",
        "The strict-forward Reader ledger carries one or more comprehension-risk entries at the final checkpoint.",
        support,
        uncertainty: "low"
      )
    )
    |> Enum.sort_by(& &1["id"])
  end

  defp uncertainty(entries, reader) do
    measured =
      for entry <- entries,
          key <- @keys,
          Support.status(entry, key) in ["uncertain", "insufficient_evidence", "unavailable"] do
        %{
          "scene_id" => entry["scene_id"],
          "measurement" => to_string(key),
          "status" => Support.status(entry, key)
        }
      end

    if match?(%Reader{}, reader),
      do: measured,
      else: measured ++ [%{"kind" => "reader_events_not_supplied", "status" => "unknown"}]
  end

  defp next_investigations(diagnoses, reader) do
    from_diagnoses =
      Enum.map(diagnoses, fn diagnosis ->
        case diagnosis["id"] do
          "audience.comprehension_risk_candidate" ->
            "Locate the exact first-exposure fact, identity, causal link, or goal the reader must connect at the cited checkpoint."

          "audience.open_question_without_handoff_candidate" ->
            "Compare the open-question ledger against the next scene's first beat and decide whether the handoff should sharpen, redirect, or intentionally release pressure."

          _ ->
            "Inspect the cited first-exposure checkpoint and distinguish deliberate withholding from accidental information loss."
        end
      end)

    if match?(%Reader{}, reader),
      do: Enum.uniq(from_diagnoses),
      else:
        Enum.uniq(
          from_diagnoses ++
            [
              "Supply source-backed reader_events to obtain a strict-forward question, expectation, threat, suspense, curiosity, surprise, comprehension, and handoff trajectory."
            ]
        )
  end

  defp result_status(entries, %Reader{}) do
    if Enum.all?(entries, &(&1["status"] == "complete")), do: "complete", else: "partial"
  end

  defp result_status(_entries, _), do: "partial"

  defp reader_event_count(%Reader{} = reader), do: length(reader.event_ids)
  defp reader_event_count(_), do: 0
  defp reader_checkpoint_count(%Reader{} = reader), do: length(reader.snapshots)
  defp reader_checkpoint_count(_), do: 0

  defp measurement_ids(entries) do
    entries
    |> Enum.flat_map(&(get_in(&1, ["provenance", "measurement_ids"]) || []))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp safe_options(opts),
    do: %{"reader_supplied" => match?(%Reader{}, Keyword.get(opts, :reader))}

  defp maybe_diag(list, true, diagnosis), do: list ++ [diagnosis]
  defp maybe_diag(list, false, _diagnosis), do: list
end
