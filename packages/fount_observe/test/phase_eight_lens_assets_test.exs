defmodule Fount.Observe.PhaseEightLensAssetsTest do
  use ExUnit.Case, async: true

  alias Fount.Observe.{Lens, Registry}

  @lenses ~w(emotional.value_movement theme.meaning genre.lens_pack revision.intelligence)

  test "Phase-8 installed lenses remain closed declarative Observe assets" do
    for id <- @lenses do
      assert Registry.lens?(id)
      assert {:ok, asset} = Lens.load(id)
      assert asset["output_contract"] == "observe.answer_set"
      assert asset["context_contract"]["allow_unknown"] == false
      refute Map.has_key?(asset, "module")
      refute Map.has_key?(asset, "function")
      refute Map.has_key?(asset, "endpoint")
      refute Map.has_key?(asset, "credentials")
    end
  end

  test "project declarative lens validates, previews, installs disabled and enables explicitly" do
    declaration = project_lens()

    assert {:ok, validated} = Fount.Observe.validate_declarative_lens(declaration)
    assert is_binary(validated["sha256"])
    assert {:ok, preview} = Fount.Observe.preview_declarative_lens(declaration)
    assert preview["enabled"] == false
    assert preview["question"]["kind"] == "choice"

    catalog = Fount.Observe.new_declarative_lens_catalog()
    assert {:ok, catalog} = Fount.Observe.install_declarative_lens(catalog, declaration)
    assert {:ok, installed} = Fount.Observe.fetch_declarative_lens(catalog, declaration["id"])
    assert installed["enabled"] == false

    assert {:ok, catalog} = Fount.Observe.enable_declarative_lens(catalog, declaration["id"])
    assert {:ok, enabled} = Fount.Observe.fetch_declarative_lens(catalog, declaration["id"])
    assert enabled["enabled"] == true

    assert {:ok, questions, lens, execution_opts} =
             Fount.Observe.compile_declarative_lens(declaration)

    assert [{"project.reversal_visibility", _}] = questions
    assert lens["projection"] == "explicit_state"
    assert execution_opts == []
  end

  test "declarative lens rejects executable and provider-authority keys" do
    for {key, value} <- [
          {"module", "MyApp.Runner"},
          {"function", "run"},
          {"endpoint", "https://example.test"},
          {"credentials", %{"token" => "secret"}},
          {"shell", "rm -rf /"}
        ] do
      declaration = Map.put(project_lens(), key, value)
      assert {:error, _} = Fount.Observe.validate_declarative_lens(declaration)
    end
  end

  defp project_lens do
    %{
      "id" => "project.reversal_visibility",
      "description" =>
        "Project-specific question about whether a reversal is externally legible without explaining it away.",
      "trust" => "project",
      "source" => %{"label" => "writers room", "revision" => "2026-09-27", "owner" => "project"},
      "kind" => "choice",
      "instructions" =>
        "How legible is the selected reversal from observable screenplay evidence?",
      "criteria" => %{
        "legible" =>
          "observable setup makes the reversal legible without requiring hidden author intent",
        "partly_legible" =>
          "some support is visible but a material inference remains unsupported",
        "unclear" => "the selected material does not establish enough evidence"
      },
      "projection" => "explicit_state",
      "output_contract" => "observe.answer_set",
      "context_contract" => %{"required" => %{}, "optional" => %{}, "allow_unknown" => false},
      "interpretation_policy" => %{
        "support_probability" => 0.8,
        "unsupported_probability" => 0.2,
        "minimum_confidence" => 0.7,
        "minimum_margin" => 0.15
      },
      "resource_policy_request" => %{
        "max_states" => 120,
        "max_provider_requests" => 120,
        "max_questions" => 8
      },
      "calibration_refs" => [],
      "resource_class" => "small"
    }
  end
end
