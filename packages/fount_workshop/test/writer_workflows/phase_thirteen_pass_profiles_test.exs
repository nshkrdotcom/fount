defmodule FountWorkshop.PhaseThirteenPassProfilesTest do
  use ExUnit.Case, async: true

  alias Fount.Screenplay
  alias FountWorkshop.{Pass, Request}

  test "W04 ships visual, sound-space, stillness-rhythm and transition pass directions without banning silence or voiceover" do
    base =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. KITCHEN - DAY",
            elements: [%{type: :action, text: "Mara waits in silence."}]
          }
        ]
      )

    for profile <- ~w(action_visual sound_space cinematic_rhythm transition) do
      assert profile in Pass.profiles()
      assert {:ok, shipped} = Pass.profile(profile)
      assert is_binary(shipped["goal"])

      request = %{
        "version" => 1,
        "workflow" => "pass",
        "mode" => "revise",
        "base_revision_id" => base.revision.id,
        "instruction" => "Keep the silence and existing voiceover.",
        "selection" => %{"whole_screenplay" => true},
        "constraints" => [],
        "options" => %{"profile" => profile}
      }

      assert {:ok, _} = Request.validate(base, request)
    end
  end
end
