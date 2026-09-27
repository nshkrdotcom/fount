defmodule Fount.Intelligence.Capabilities.GenreLensPacks do
  @moduledoc "Pure Phase-8 interpretation of optional genre-pack measurements. Packs change analytical salience; they are never mandatory genre rules."

  alias Fount.Intelligence.Capabilities.{Result, Support}
  alias Fount.Screenplay.Model

  @keys ~w(expectation_present expectation_satisfied expectation_subverted intentional_subversion_visible specialized_pressure conflict_with_writer_intent)a

  def analyze(world, subject, entries, opts \\ []) do
    pack = pack(subject)
    diagnoses = diagnoses(entries, pack)

    %Result{
      family: "genre_lens_packs",
      source_revision: world.revision_id,
      subject: Model.plain(subject),
      status: status(entries),
      evidence: Support.measurement_evidence(entries),
      measurements: %{"keys" => Enum.map(@keys, &to_string/1), "entries" => entries},
      derived_state: %{
        "pack" => Model.plain(pack),
        "expectation_trajectory" => Support.measurement_trajectory(entries, @keys),
        "subversion_alignment" => subversion_alignment(entries, pack),
        "effective_salience" => Map.get(pack, "diagnostic_salience", %{}),
        "composed_primitives" => %{
          "lenses" => Map.get(pack, "lenses", []),
          "capability_families" => Map.get(pack, "capability_families", []),
          "playbooks" => Map.get(pack, "playbooks", [])
        }
      },
      trajectories: %{
        "measurements" => Support.measurement_trajectory(entries, @keys),
        "semantics" => "optional_pack_relative_not_universal_genre_rules"
      },
      diagnoses: diagnoses,
      uncertainty: uncertainty(entries),
      next_investigations: next_investigations(diagnoses, pack),
      limitations: [
        "Genre packs are optional analytical emphasis. Failing an expectation is not automatically a screenplay defect.",
        "Intentional subversion and anti-genre intent suppress defect-style interpretation and remain visible in the packet.",
        "The initial mystery/thriller/horror/romance/comedy/action packs are useful starting assets, not a closed list of genres Fount supports.",
        "No genre-conformity or overall quality score is produced."
      ],
      metadata: %{
        "family_version" => 1,
        "pack_id" => pack["id"],
        "pack_sha256" => pack["sha256"],
        "pack_trust" => pack["trust"],
        "intent" => Model.plain(Keyword.get(opts, :intent, %{}))
      }
    }
  end

  defp pack(%{"genre_pack" => pack}) when is_map(pack), do: pack
  defp pack(pack) when is_map(pack), do: pack
  defp pack(_), do: %{}

  defp diagnoses(entries, pack) do
    support = measurement_ids(entries)
    explicit_subversion = subversions(pack) != []

    []
    |> maybe_diag(
      not explicit_subversion and Support.any_supported?(entries, :expectation_present) and
        Support.any_supported?(entries, :conflict_with_writer_intent),
      Support.diagnosis(
        "genre.intent_conflict_candidate",
        "An enabled genre expectation may conflict with the writer's declared intent in the selected material.",
        "The pack expectation is visible and conflict-with-intent measurement is supported without a declared pack subversion.",
        support,
        uncertainty: "high"
      )
    )
    |> maybe_diag(
      not explicit_subversion and Support.any_supported?(entries, :expectation_present) and
        Support.all_not_supported?(entries, :expectation_satisfied) and
        Support.all_not_supported?(entries, :expectation_subverted),
      Support.diagnosis(
        "genre.expectation_gap_candidate",
        "A pack-specific expectation is present but neither fulfilled nor visibly subverted in the supplied scope.",
        "Expectation-present is supported while fulfillment and visible subversion are unsupported.",
        support,
        uncertainty: "high",
        limitations: ["The expectation may resolve outside the selected scope or be intentionally omitted."]
      )
    )
    |> Enum.sort_by(& &1["id"])
  end

  defp subversion_alignment(entries, pack) do
    declared = subversions(pack)

    %{
      "declared_subversions" => declared,
      "visible_scene_ids" => scenes(entries, :intentional_subversion_visible),
      "subverted_expectation_scene_ids" => scenes(entries, :expectation_subverted),
      "diagnostic_defect_inference_suppressed" => declared != []
    }
  end

  defp subversions(pack), do: get_in(pack, ["intent", "subversions"]) || []

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
      %{"scene_id" => entry["scene_id"], "measurement" => to_string(key), "status" => Support.status(entry, key)}
    end
  end

  defp next_investigations(diagnoses, pack) do
    if diagnoses == [] do
      ["Inspect the pack's specialized pressure and subversion outputs as optional evidence; do not force convention where the writer's intent rejects it."]
    else
      ["Compare the cited expectation against the pack's declared subversions/opt-out guidance and the writer's stated intent before treating the gap as actionable."]
    end ++ Enum.map(subversions(pack), &("Declared subversion to preserve: " <> &1))
  end

  defp measurement_ids(entries) do
    entries
    |> Enum.flat_map(&(get_in(&1, ["provenance", "measurement_ids"]) || []))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp status(entries), do: if(Enum.all?(entries, &(&1["status"] == "complete")), do: "complete", else: "partial")
  defp maybe_diag(list, true, diagnosis), do: list ++ [diagnosis]
  defp maybe_diag(list, false, _diagnosis), do: list
end
