defmodule Fount.Observe.PhaseSixLensAssetsTest do
  use ExUnit.Case, async: true

  alias Fount.Observe.{Lens, Registry}

  test "all Phase-6 capability lenses are installed closed data assets" do
    ids = ~w(scene.engine agency.causality character.trajectory relationship.dynamics)

    Enum.each(ids, fn id ->
      assert Registry.lens?(id)
      assert {:ok, asset} = Lens.load(id)
      assert asset["context_contract"]["allow_unknown"] == false
      assert asset["output_contract"] == "observe.answer_set"
      refute Map.has_key?(asset, "module")
      refute Map.has_key?(asset, "function")
    end)
  end
end
