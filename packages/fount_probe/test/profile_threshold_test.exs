defmodule FountProbe.ProfileThresholdTest do
  use ExUnit.Case, async: true

  test "effective profile thresholds change Noul and Choice interpretation" do
    assert FountProbe.Jev.answer(%SystemOneSDK.NoulAnswer{noul: 0.6})["status"] == "uncertain"

    assert FountProbe.Jev.answer(%SystemOneSDK.NoulAnswer{noul: 0.6}, supported: 0.5)["status"] ==
             "supported"
  end

  test "invalid policy thresholds cannot masquerade as a profile" do
    assert FountProbe.Profile.valid_thresholds?(%{
             "support_probability" => 0.6,
             "unsupported_probability" => 0.2
           })

    refute FountProbe.Profile.valid_thresholds?(%{
             "support_probability" => 0.1,
             "unsupported_probability" => 0.2
           })

    refute FountProbe.Profile.valid_thresholds?(%{"support_probability" => 1.5})
  end
end
