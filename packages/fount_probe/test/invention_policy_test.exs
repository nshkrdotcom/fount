defmodule FountProbe.InventionPolicyTest do
  use ExUnit.Case, async: true

  test "prohibited facts are unknown until candidate and base are semantically compared" do
    model =
      Fount.Screenplay.new(
        scenes: [%{heading: "INT. ROOM - DAY", elements: [%{type: :action, text: "Mara waits."}]}]
      )

    constraint = %{
      "id" => "no-forgery",
      "kind" => "invention_policy",
      "target" => %{"kind" => "screenplay", "id" => model.id},
      "spec" => %{"allowed_categories" => [], "prohibited_facts" => ["Mara forged the ledger"]},
      "severity" => "required"
    }

    assert [%{"status" => "unknown", "evaluation" => "semantic"}] =
             FountProbe.Constraints.deterministic(model, model, [constraint], inventions: [])

    strict = put_in(constraint, ["spec", "policy"], "none")

    assert [%{"status" => "fail"}] =
             FountProbe.Constraints.deterministic(model, model, [strict],
               inventions: [%{"category" => "forgery"}]
             )
  end
end
