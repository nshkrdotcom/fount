defmodule Fount.Intelligence.WriterRegistryTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.Playbooks.WriterRegistry

  test "Phase-5 writer registry contains exactly the ten baseline playbooks" do
    assert WriterRegistry.ids() == [
             "scene_doctor",
             "dialogue_pass",
             "character_trajectory",
             "relationship_pass",
             "suspense_audit",
             "sequence_momentum",
             "setup_payoff",
             "notes_diagnosis",
             "submission_read",
             "revision_regression"
           ]

    for definition <- WriterRegistry.list() do
      assert is_binary(definition["purpose"])
      assert is_list(definition["foundational_tools"])
      refute inspect(definition) =~ "Elixir."
      refute Map.has_key?(definition, "module")
      refute Map.has_key?(definition, "function")
    end
  end
end
