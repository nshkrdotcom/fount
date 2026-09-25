defmodule FountProbe.InvestigationContractTest do
  use ExUnit.Case, async: true

  test "plan hypotheses are structured and cite known request IDs" do
    model = Fount.Screenplay.new()
    request = %{"id" => "search_1", "tool" => "search", "params" => %{"query" => "key"}}

    valid = %{
      "hypotheses" => [
        %{
          "id" => "h1",
          "claim" => "The key is unexplained",
          "reason" => "Its use may lack setup",
          "request_ids" => ["search_1"]
        }
      ],
      "requests" => [request]
    }

    assert :ok = FountProbe.Investigation.validate_plan(model, valid)

    assert {:error, _} =
             FountProbe.Investigation.validate_plan(
               model,
               put_in(valid, ["hypotheses", Access.at(0), "request_ids"], ["missing"])
             )

    assert {:error, _} =
             FountProbe.Investigation.validate_plan(
               model,
               Map.put(valid, "hypotheses", ["loose prose"])
             )
  end

  test "follow-up requests are finite and valid catalog requests" do
    model = Fount.Screenplay.new()

    base = %{
      "answer" => "Unclear",
      "revised_hypotheses" => [
        %{
          "id" => "h1",
          "claim" => "Key setup is missing",
          "reason" => "No setup found",
          "status" => "unresolved",
          "evidence_ids" => []
        }
      ],
      "uncertainties" => [],
      "evidence_ids" => [],
      "strategies" =>
        for(
          n <- 1..3,
          do: %{
            "id" => "s#{n}",
            "title" => "Route #{n}",
            "dramatic_mechanism" => "Different choice",
            "beats" => [],
            "evidence_ids" => []
          }
        ),
      "follow_up_requests" => [
        %{
          "id" => "search_2",
          "tool" => "search",
          "params" => %{"query" => "key"},
          "reason" => "Check earlier setup"
        }
      ]
    }

    assert :ok = FountProbe.Investigation.validate_explanation(model, base, [], 1)
    assert :ok = FountProbe.Investigation.validate_explanation(model, base, [], 1, ["h1"])

    assert {:error, :unrevised_hypotheses} =
             FountProbe.Investigation.validate_explanation(model, base, [], 1, ["h2"])

    assert {:error, :invalid_hypothesis_ids} =
             FountProbe.Investigation.validate_explanation(
               model,
               Map.put(base, "revised_hypotheses", []),
               [],
               1
             )

    assert {:error, _} = FountProbe.Investigation.validate_explanation(model, base, [], 0)

    assert {:error, _} =
             FountProbe.Investigation.validate_explanation(
               model,
               put_in(base, ["follow_up_requests", Access.at(0), "tool"], "shell"),
               [],
               1
             )
  end
end
