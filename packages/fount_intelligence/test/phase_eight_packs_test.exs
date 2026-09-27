defmodule Fount.Intelligence.PhaseEightPacksTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.Packs

  test "six core genre packs are optional disabled assets in a caller-owned catalog" do
    assert Packs.core_ids() ==
             ~w(genre.mystery genre.thriller genre.horror genre.romance genre.comedy genre.action)

    catalog = Packs.new_catalog()
    assert Enum.all?(Packs.list(catalog), &(&1["enabled"] == false))
    assert Packs.enabled(catalog) == []

    assert {:ok, catalog} = Packs.enable(catalog, "genre.mystery")
    assert [%{"id" => "genre.mystery"}] = Enum.map(Packs.enabled(catalog), &Map.take(&1, ["id"]))
  end

  test "custom hybrid pack can compose an explicitly enabled safe declarative lens" do
    declaration = project_lens()
    lens_catalog = Fount.Observe.new_declarative_lens_catalog()
    {:ok, lens_catalog} = Fount.Observe.install_declarative_lens(lens_catalog, declaration)
    {:ok, lens_catalog} = Fount.Observe.enable_declarative_lens(lens_catalog, declaration["id"])

    pack = %{
      "id" => "project.character_first_mystery",
      "description" => "Project hybrid that keeps mystery information pressure while intentionally becoming character-first after midpoint.",
      "purpose" => "Add project-specific reversal visibility to ordinary mystery/character analysis without executable extension code.",
      "trust" => "project",
      "source" => %{"label" => "writers room", "revision" => "3", "owner" => "project"},
      "lenses" => ["audience.reader_experience", declaration["id"]],
      "capability_families" => ["audience_reader_experience", "theme_meaning"],
      "playbooks" => ["suspense_audit", "submission_read"],
      "diagnostic_salience" => %{"premature_inference" => 1.0, "reversal_visibility" => 0.8},
      "writer_intent_prompts" => ["After midpoint, preserve character-first emphasis even if mystery pressure drops."],
      "intent" => %{
        "subversions" => ["Do not treat early culprit identification as a defect after midpoint."],
        "opt_out" => ["late culprit reveal"]
      },
      "resource_policy_request" => %{
        "max_targets" => 120,
        "max_states" => 120,
        "max_provider_requests" => 120,
        "max_wall_ms" => 60_000
      }
    }

    assert {:ok, validated} = Packs.validate(pack, custom_lenses: lens_catalog)
    assert validated["trust"] == "project"
    assert validated["effective_resource_policy"]["max_provider_requests"] == 120

    catalog = Packs.new_catalog()
    assert {:ok, catalog} = Packs.install(catalog, pack, custom_lenses: lens_catalog)
    assert {:ok, installed} = Packs.fetch(catalog, pack["id"])
    assert installed["enabled"] == false
    assert {:error, :genre_pack_not_enabled} = Packs.resolve(installed, custom_lenses: lens_catalog)

    assert {:ok, catalog} = Packs.enable(catalog, pack["id"])
    assert {:ok, enabled} = Packs.fetch(catalog, pack["id"])
    assert {:ok, resolved} = Packs.resolve(enabled, custom_lenses: lens_catalog)
    assert resolved["id"] == pack["id"]
  end

  test "pack validation rejects executable authority and resource requests above host caps" do
    {:ok, mystery} = Packs.core("genre.mystery")

    executable = Map.put(mystery |> Map.drop(["sha256", "effective_resource_policy"]), "module", "Bad.Loader")
    assert {:error, :invalid_genre_pack} = Packs.validate(executable)

    oversized =
      mystery
      |> Map.drop(["sha256", "effective_resource_policy"])
      |> put_in(["resource_policy_request", "max_provider_requests"], 50_000)

    assert {:error, :invalid_genre_pack} = Packs.validate(oversized)
  end

  defp project_lens do
    %{
      "id" => "project.reversal_visibility",
      "description" => "Project-specific observable reversal visibility.",
      "trust" => "project",
      "source" => %{"label" => "writers room", "revision" => "3", "owner" => "project"},
      "kind" => "noul",
      "instructions" => "Is the reversal legible from observable screenplay evidence?",
      "projection" => "explicit_state",
      "output_contract" => "observe.answer_set",
      "context_contract" => %{"required" => %{}, "optional" => %{}, "allow_unknown" => false},
      "interpretation_policy" => %{
        "support_probability" => 0.8,
        "unsupported_probability" => 0.2,
        "minimum_confidence" => 0.7,
        "minimum_margin" => 0.15
      },
      "resource_policy_request" => %{"max_states" => 80, "max_provider_requests" => 80, "max_questions" => 4},
      "calibration_refs" => [],
      "resource_class" => "small"
    }
  end
end
