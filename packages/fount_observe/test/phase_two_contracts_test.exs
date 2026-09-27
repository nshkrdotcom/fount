defmodule Fount.Observe.PhaseTwoContractsTest do
  use ExUnit.Case, async: true
  alias Fount.Observe.{Calibration, Context, Distribution, Lens, OutputContract, Question}
  alias Fount.Observe.Context.{EntityRef, Fact}

  defp contract do
    %{
      "required" => %{"facts" => %{"type" => "list", "items" => "fact"}},
      "optional" => %{"intent" => %{"type" => "literal"}},
      "allow_unknown" => false
    }
  end

  defp context(evidence \\ []) do
    %Context{
      slots: %{
        "facts" => [
          %Fact{
            subject: %EntityRef{id: "mara", kind: "character"},
            predicate: "holds",
            object: "key",
            evidence_ids: evidence
          }
        ]
      }
    }
  end

  test "the data-shape digest ignores prose but changes with the answer domain" do
    a = Question.choice("Which tactic?", evade: "Evade", answer: "Answer")
    b = Question.choice("Choose a tactic.", evade: "Evade", answer: "Answer")
    c = Question.choice("Which tactic?", conceal: "Conceal", answer: "Answer")
    assert Question.output_digest(a) == Question.output_digest(b)
    refute Question.output_digest(a) == Question.output_digest(c)
    shape = OutputContract.for_question(a)
    assert shape["id"] == "observe.distribution"
    assert shape["sha256"] == OutputContract.digest(shape["shape"])
    assert :ok = OutputContract.validate(shape)

    assert {:error, %{class: :stale_contract}} =
             OutputContract.validate(%{shape | "sha256" => String.duplicate("0", 64)})
  end

  test "context contract schemas are closed recursively, not just at slot names" do
    assert :ok = Context.validate_contract(contract())
    assert :ok = Context.validate(context(), contract())

    for schema <- [
          %{"type" => "fact", "module" => "File"},
          %{"type" => "url"},
          %{"type" => "list"},
          %{"type" => "list", "items" => "unknown"}
        ] do
      bad = put_in(contract(), ["required", "facts"], schema)
      assert {:error, %{class: :invalid_context}} = Context.validate_contract(bad)
    end

    assert {:error, _} = Context.validate_contract(Map.put(contract(), "allow_unknown", true))
    assert {:error, _} = Context.validate(%Context{}, contract())

    assert {:error, _} =
             Context.validate(%Context{slots: %{"facts" => [], "extra" => 1}}, contract())
  end

  test "typed context roundtrips without creating atoms from input" do
    original = context(["e1"])
    assert {:ok, decoded} = Context.from_map(Context.to_map(original), contract())
    assert decoded == original
    bad = put_in(Context.to_map(original), ["slots", "facts"], [%{"__struct__" => "File"}])
    assert {:error, %{class: :invalid_context}} = Context.from_map(bad, contract())
  end

  test "evidence identity is storage provenance, not model-visible fact content" do
    a = context(["old-evidence"])
    b = context(["new-evidence"])
    assert Context.hash(a) == Context.hash(b)
    refute Context.to_map(a) == Context.to_map(b)
    refute Jason.encode!(Context.semantic_map(a)) =~ "old-evidence"
    assert Context.evidence_ids(a) == ["old-evidence"]

    changed = %Context{
      slots: %{"facts" => [%Fact{subject: "mara", predicate: "holds", object: "gun"}]}
    }

    refute Context.hash(a) == Context.hash(changed)
  end

  test "calibration is explicit, preserves the raw distribution and does not calibrate confidence" do
    {:ok, raw} = Distribution.choice(%{"a" => 0.9, "b" => 0.1}, ["a", "b"], "a", 0.4)

    asset = %{
      "id" => "project.tactic",
      "method" => "temperature",
      "temperature" => 2.0,
      "validation" => "experimental",
      "model" => "fixture"
    }

    assert {:ok, checked} = Calibration.validate(asset)
    assert {:ok, result} = Calibration.apply(raw, checked, %{"model" => "fixture"})
    assert result["probabilities"]["a"] < 0.9
    assert result["validation"] == "experimental"
    assert result["confidence_calibrated"] == false
    assert raw.values == [{"a", 0.9}, {"b", 0.1}]
    assert raw.confidence == 0.4

    assert {:error, %{class: :calibration_unavailable}} =
             Calibration.apply(raw, checked, %{"model" => "other"})

    assert {:error, _} = Calibration.validate(Map.put(asset, "module", "System"))
    assert {:error, _} = Calibration.validate(Map.put(asset, "temperature", 0))
  end

  test "custom lens declarations cannot configure executables, endpoints or credentials" do
    {:ok, _, inline} = Lens.compile(q: Question.noul("Visible?"))
    asset = Map.drop(inline, ["sha256"])
    assert {:ok, _} = Lens.validate(asset)

    for {key, value} <- [
          {"module", "File"},
          {"url", "https://example.test"},
          {"api_key", "secret"},
          {"version", 2}
        ] do
      assert {:error, _} = Lens.validate(Map.put(asset, key, value))
    end

    assert {:error, _} = Lens.validate(Map.put(asset, "projection", "../../etc/passwd"))

    assert {:error, _} =
             Lens.validate(
               put_in(asset, ["context_contract", "required"], %{
                 "x" => %{"type" => "literal", "function" => "run"}
               })
             )
  end

  test "distribution variants reject fields that contradict their serialized shape" do
    {:ok, noul} = Distribution.proposition(0.7)
    assert {:error, _} = Distribution.validate(%{noul | scalar: 0.7})
    assert {:error, _} = Distribution.validate(%{noul | selected: "true"})
    {:ok, choice} = Distribution.choice(%{"a" => 0.5, "b" => 0.5}, ["a", "b"], "a", 0.2)
    assert {:error, _} = Distribution.validate(%{choice | labels: ["unexpected"]})
    assert {:error, _} = Distribution.score(%{"0" => 0.5, "1" => 0.5}, [nil, "high"], 0.5, 0.4)
  end

  test "oversized output declarations are rejected as contracts, not dispatched" do
    shape = %{"type" => "string", "const" => String.duplicate("x", 65_536)}

    contract = %{
      "id" => "project.large",
      "shape" => shape,
      "sha256" => OutputContract.digest(shape)
    }

    assert {:error, %{class: :stale_contract}} = OutputContract.validate(contract)
  end
end
