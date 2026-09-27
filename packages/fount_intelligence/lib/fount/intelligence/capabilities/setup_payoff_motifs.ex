defmodule Fount.Intelligence.Capabilities.SetupPayoffMotifs do
  @moduledoc "Pure Phase-7 setup/payoff lifecycle and motif/callback reasoning with separate presentation and diegetic-time semantics."

  alias Fount.Intelligence.Capabilities.{Result, Support}
  alias Fount.Intelligence.{StoryWorld, Temporal}
  alias Fount.Screenplay.Model

  @keys ~w(setup_signal reinforcement transformation payoff subversion abandonment unsupported_payoff orphaned_setup motif_callback motif_function_change over_signaled revision_break_candidate)a

  def analyze(world, subject, entries, opts \\ []) do
    ledger = Temporal.setup_payoff_ledger(world)
    lifecycle = Enum.map(ledger["entries"], &qualify_lifecycle(world, &1))
    motifs = motif_packets(world)
    diagnoses = diagnoses(entries, lifecycle, motifs)

    %Result{
      family: "setup_payoff_motifs",
      source_revision: world.revision_id,
      subject: Model.plain(subject),
      status: result_status(entries),
      evidence:
        Support.merge_evidence([
          Support.measurement_evidence(entries),
          Support.evidence(Map.values(world.commitments)),
          Support.evidence(Map.values(world.motifs)),
          Support.evidence(Support.causal_edges(world))
        ]),
      measurements: %{
        "keys" => Enum.map(@keys, &to_string/1),
        "entries" => entries
      },
      derived_state: %{
        "setup_payoff_lifecycle" => lifecycle,
        "motif_occurrences" => motifs,
        "transformation_links" => transformation_links(entries, lifecycle, motifs),
        "broken_chain_candidates" => broken_chain_candidates(entries, lifecycle)
      },
      trajectories: %{
        "setup_payoff" => lifecycle,
        "motifs" => motifs,
        "semantics" => %{
          "presentation" => "reader_visible_order",
          "story_time" => "partial_diegetic_relations",
          "causality" => "independent_typed_edges"
        }
      },
      diagnoses: diagnoses,
      uncertainty: uncertainty(entries, lifecycle),
      next_investigations: next_investigations(diagnoses, lifecycle),
      limitations: [
        "A setup need not receive a conventional payoff. Transformation, subversion, denial, or deliberate abandonment can be valid writer intent.",
        "Payoff presentation position and diegetic chronology are qualified separately; a later-presented flashback may explain or transform an earlier-presented setup while depicting an earlier story event.",
        "Motif recurrence is descriptive. Recurrence does not by itself establish theme, symbolism, or quality.",
        "Broken-chain diagnoses require visible evidence or explicit frozen dependencies; absent setup/payoff records remain unknown rather than being invented."
      ],
      metadata: %{
        "family_version" => 1,
        "ledger_entry_count" => length(lifecycle),
        "motif_count" => length(motifs),
        "options" => safe_options(opts)
      }
    }
  end

  defp qualify_lifecycle(world, entry) do
    setup_id = entry["setup_id"]
    commitment = world.commitments[setup_id]
    setup_event_id = commitment && first_known_event(world, commitment.active_at)

    payoffs =
      Enum.map(entry["payoffs"] || [], fn payoff ->
        payoff_event_id = payoff["to"]
        presentation = presentation_relation(world, setup_event_id, payoff_event_id)
        story_time = story_time_relation(world, setup_event_id, payoff_event_id)

        payoff
        |> Map.put("setup_event_id", setup_event_id)
        |> Map.put("payoff_event_id", payoff_event_id)
        |> Map.put("presentation_relation", presentation)
        |> Map.put("story_time_relation", story_time)
        |> Map.put("presentation_story_time_diverge", diverge?(presentation, story_time))
      end)

    entry
    |> Map.put("setup_event_id", setup_event_id)
    |> Map.put("payoffs", payoffs)
  end

  defp first_known_event(world, active_at) do
    active_at
    |> List.wrap()
    |> Enum.find(&Map.has_key?(world.events, &1))
  end

  defp presentation_relation(_world, nil, _right), do: "unknown"
  defp presentation_relation(_world, _left, nil), do: "unknown"

  defp presentation_relation(world, left, right) do
    left_key = Support.event_presentation_key(world, left)
    right_key = Support.event_presentation_key(world, right)

    cond do
      left_key < right_key -> "before"
      left_key > right_key -> "after"
      true -> "same_or_unknown"
    end
  end

  defp story_time_relation(_world, nil, _right), do: "unknown"
  defp story_time_relation(_world, _left, nil), do: "unknown"

  defp story_time_relation(world, left, right),
    do: world |> StoryWorld.story_time_relation(left, right) |> Model.plain()

  defp diverge?("before", %{"status" => "known", "relations" => relations}),
    do: "after" in relations

  defp diverge?("after", %{"status" => "known", "relations" => relations}),
    do: "before" in relations

  defp diverge?(_, _), do: false

  defp motif_packets(world) do
    world.motifs
    |> Map.values()
    |> Enum.sort_by(& &1.id)
    |> Enum.map(fn motif ->
      %{
        "id" => motif.id,
        "label" => motif.label,
        "kind" => motif.kind,
        "occurrences" => Model.plain(motif.occurrences),
        "occurrence_count" => length(motif.occurrences),
        "callback_candidate" => length(motif.occurrences) >= 2,
        "evidence" => Model.plain(motif.evidence),
        "dependencies" => motif.dependencies,
        "metadata" => Model.plain(motif.metadata)
      }
    end)
  end

  defp transformation_links(entries, lifecycle, motifs) do
    measured =
      for entry <- entries,
          key <- [:transformation, :subversion, :motif_function_change],
          Support.supported?(entry, key) do
        %{
          "source" => "measurement",
          "scene_id" => entry["scene_id"],
          "kind" => to_string(key),
          "measurement_ids" => get_in(entry, ["provenance", "measurement_ids"]) || []
        }
      end

    recorded =
      Enum.flat_map(lifecycle, &recorded_transformation_links/1)

    motif_links =
      for motif <- motifs, motif["callback_candidate"] do
        %{
          "source" => "motif",
          "motif_id" => motif["id"],
          "occurrence_count" => motif["occurrence_count"]
        }
      end

    measured ++ recorded ++ motif_links
  end

  defp recorded_transformation_links(item) do
    for payoff <- item["payoffs"] || [],
        payoff["type"] in ["complicates", "resolves", "pays_off"] do
      %{"source" => "story_world", "setup_id" => item["setup_id"], "edge" => payoff}
    end
  end

  defp broken_chain_candidates(entries, lifecycle) do
    measured =
      for entry <- entries,
          key <- [:unsupported_payoff, :orphaned_setup, :revision_break_candidate],
          Support.supported?(entry, key) do
        %{
          "scene_id" => entry["scene_id"],
          "kind" => to_string(key),
          "measurement_ids" => get_in(entry, ["provenance", "measurement_ids"]) || []
        }
      end

    open =
      for item <- lifecycle, item["lifecycle"] == "open" do
        %{"kind" => "open_setup", "setup_id" => item["setup_id"]}
      end

    measured ++ open
  end

  defp diagnoses(entries, lifecycle, motifs) do
    support = measurement_ids(entries)
    open = Enum.filter(lifecycle, &(&1["lifecycle"] == "open"))
    orphan = Enum.filter(lifecycle, &(&1["setup_kind"] == "explicit_causal_reference"))

    []
    |> maybe_diag(
      Support.any_supported?(entries, :orphaned_setup) and open != [],
      Support.diagnosis(
        "setup_payoff.orphaned_setup_candidate",
        "A visible setup may remain open without a recorded payoff, transformation, subversion, or deliberate abandonment in the selected scope.",
        "Orphaned-setup measurement is supported and the frozen setup/payoff ledger contains one or more open commitments.",
        support ++ Enum.map(open, & &1["setup_id"]),
        uncertainty: "high",
        limitations: [
          "An open setup may intentionally survive beyond the selected scope or remain unresolved by design."
        ]
      )
    )
    |> maybe_diag(
      Support.any_supported?(entries, :unsupported_payoff) or orphan != [],
      Support.diagnosis(
        "setup_payoff.unsupported_payoff_candidate",
        "An apparent payoff may not have a visible or explicitly recorded setup dependency in the supplied scope.",
        "Unsupported-payoff measurement is supported or the typed payoff ledger contains a causal payoff reference whose source is not a recorded commitment.",
        support,
        uncertainty: "high"
      )
    )
    |> maybe_diag(
      Support.any_supported?(entries, :over_signaled),
      Support.diagnosis(
        "setup_payoff.over_signaled_candidate",
        "A setup or recurring motif may be signaled strongly enough that its later use becomes easy to anticipate.",
        "Over-signaled measurement is supported in the selected material.",
        support,
        limitations: [
          "Prediction can be desirable when the intended pleasure is dread, inevitability, dramatic irony, recognition, or comic setup."
        ]
      )
    )
    |> maybe_diag(
      Support.any_supported?(entries, :revision_break_candidate),
      Support.diagnosis(
        "setup_payoff.revision_chain_break_candidate",
        "A setup/payoff or motif dependency may have been disconnected by revision.",
        "Revision-break measurement is supported in the selected material.",
        support,
        uncertainty: "high"
      )
    )
    |> maybe_diag(
      Enum.any?(motifs, &(&1["occurrence_count"] >= 4)) and
        Support.any_supported?(entries, :motif_callback),
      Support.diagnosis(
        "setup_payoff.motif_recurrence_for_writer_inspection",
        "A recurring motif has enough visible occurrences to merit checking how its function changes rather than merely counting repetition.",
        "The frozen motif record has at least four occurrences and motif-callback measurement is supported.",
        support,
        uncertainty: "medium",
        limitations: [
          "Occurrence count is not a defect threshold; the writer should inspect function, placement, and transformation."
        ]
      )
    )
    |> Enum.sort_by(& &1["id"])
  end

  defp uncertainty(entries, lifecycle) do
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

    chronology =
      lifecycle
      |> Enum.flat_map(&(&1["payoffs"] || []))
      |> Enum.filter(
        &(&1["story_time_relation"] == "unknown" or
            match?(
              %{"status" => status} when status in ["ambiguous", "contradiction"],
              &1["story_time_relation"]
            ))
      )
      |> Enum.map(
        &Map.take(
          &1,
          ~w(setup_event_id payoff_event_id presentation_relation story_time_relation)
        )
      )

    measured ++ chronology
  end

  defp next_investigations(diagnoses, lifecycle) do
    base =
      Enum.map(diagnoses, fn diagnosis ->
        case diagnosis["id"] do
          "setup_payoff.orphaned_setup_candidate" ->
            "Trace each open setup through reinforcement, transformation, subversion, abandonment, and later scopes before deciding it is forgotten."

          "setup_payoff.unsupported_payoff_candidate" ->
            "Identify the exact earlier object, fact, promise, image, phrase, behavior, rule, threat, or question that should make the later use legible."

          "setup_payoff.revision_chain_break_candidate" ->
            "Compare the setup/payoff dependency chain against the prior revision and identify which source element or causal link moved, changed, or disappeared."

          _ ->
            "Inspect motif/setup occurrences by function, not count alone, and compare reader-visible placement with known story-time relations."
        end
      end)

    if Enum.any?(lifecycle, fn item ->
         Enum.any?(item["payoffs"] || [], & &1["presentation_story_time_diverge"])
       end),
       do:
         Enum.uniq(
           base ++
             [
               "For the non-linear payoff, inspect what the reader learns at the later presentation point separately from when the depicted event occurs in story time."
             ]
         ),
       else: Enum.uniq(base)
  end

  defp measurement_ids(entries) do
    entries
    |> Enum.flat_map(&(get_in(&1, ["provenance", "measurement_ids"]) || []))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp result_status(entries),
    do: if(Enum.all?(entries, &(&1["status"] == "complete")), do: "complete", else: "partial")

  defp safe_options(_opts), do: %{}
  defp maybe_diag(list, true, diagnosis), do: list ++ [diagnosis]
  defp maybe_diag(list, false, _diagnosis), do: list
end
