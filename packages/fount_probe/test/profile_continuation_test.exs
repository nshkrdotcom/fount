defmodule FountProbe.ProfileContinuationTest do
  use ExUnit.Case, async: true
  test "profile identity is distinct from request preparation and uses actual questions" do
    questions = [relevant: SystemOneSDK.noul("Original wording")]
    assert {:ok, compiled, profile} = FountProbe.Profile.compile(questions, "retrieval")
    assert profile["version"] == 1
    assert String.length(profile["sha256"]) == 64
    refute FountProbe.Jev.question_profile(questions) == FountProbe.Jev.question_profile(compiled)
  end
  test "profile paths cannot escape the trusted profile directory" do
    assert {:error, :invalid_profile_id} = FountProbe.Profile.load("../other")
  end
end
