defmodule Fount.Intelligence.InterpretationThresholdTest do
  use ExUnit.Case, async: true
  alias Fount.Intelligence.Capabilities.Interpretation
  alias Fount.Observe.{Distribution, Lens}

  test "effective thresholds change interpretation without changing the raw Noul measurement" do
    {:ok, distribution} = Distribution.proposition(0.6)
    assert Interpretation.answer(distribution)["status"] == "uncertain"
    assert Interpretation.answer(distribution, supported: 0.5)["status"] == "supported"
    assert distribution.values == [{"true", 0.6}, {"false", 0.4}]
    assert distribution.confidence == nil
  end

  test "invalid policy thresholds cannot masquerade as a lens policy" do
    assert Lens.valid_thresholds?(%{
             "support_probability" => 0.6,
             "unsupported_probability" => 0.2
           })

    refute Lens.valid_thresholds?(%{
             "support_probability" => 0.1,
             "unsupported_probability" => 0.2
           })

    refute Lens.valid_thresholds?(%{"support_probability" => 1.5})
  end
end
