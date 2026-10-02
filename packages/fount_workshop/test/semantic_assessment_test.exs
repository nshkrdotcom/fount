defmodule FountWorkshop.SemanticAssessmentTest do
  use ExUnit.Case, async: true

  alias FountWorkshop.SemanticAssessment

  test "SI02 model and reasoning policy is exact and has no silent fallback" do
    assert SemanticAssessment.model() == "gpt-6.1-sol"
    assert SemanticAssessment.reasoning_effort() == :low

    assert {:error, :semantic_model_policy_mismatch} =
             SemanticAssessment.build_client(model: "another-model")

    assert {:error, :semantic_model_policy_mismatch} =
             SemanticAssessment.preflight(reasoning_effort: :medium)
  end

  test "preflight fails closed when the configured executable is unavailable" do
    assert {:error, :codex_executable_unavailable} =
             SemanticAssessment.preflight(
               cli_path: "/definitely/not/a/codex/executable",
               auth_asserted: true
             )
  end
end
