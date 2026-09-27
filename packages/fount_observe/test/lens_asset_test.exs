defmodule Fount.Observe.LensAssetTest do
  use ExUnit.Case, async: true
  alias Fount.Observe.{Error, Lens, Question, Registry}

  test "lens content identity is distinct from caller wording and uses effective questions" do
    questions = [relevant: Question.noul("Original wording")]
    assert {:ok, compiled, lens} = Lens.compile(questions, "retrieval.relevance")
    assert lens["id"] == "retrieval.relevance"
    refute Map.has_key?(lens, "version")
    assert String.length(lens["sha256"]) == 64
    refute Question.specifications(questions) == Question.specifications(compiled)
    assert {:ok, same, same_lens} = Lens.compile(questions, "retrieval.relevance")
    assert compiled == same
    assert lens == same_lens
  end

  test "lens IDs cannot escape the closed installed registry" do
    assert {:error, %Error{class: :lens_not_applicable}} = Lens.load("../other")
    assert {:error, %Error{class: :lens_not_applicable}} = Lens.load("Elixir.File")
    for id <- Registry.lenses(), do: assert({:ok, _} = Lens.load(id))
  end
end
