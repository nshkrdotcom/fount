defmodule FountWorkshop.TableReadTest do
  use ExUnit.Case, async: true

  alias Fount.Screenplay
  alias FountWorkshop.TableRead

  test "routes ordered dialogue to distinct voices and leaves missing voices explicit" do
    model =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [
              %{type: :character, text: "MARA"},
              %{type: :dialogue, text: "Come in."},
              %{type: :character, text: "JOHN"},
              %{type: :dialogue, text: "No."}
            ]
          }
        ]
      )

    {model, mara} = Screenplay.add_character(model, "Mara")
    cue = Enum.find(model.ir.elements, &(&1.type == :character and &1.text == "MARA"))
    {:ok, model} = Screenplay.link_cue(model, cue.id, mara.id)
    scene = hd(model.ir.scenes)

    synthesize = fn text, voice -> {:ok, "#{voice}:#{text}"} end
    voices = %{mara.id => "alto", "JOHN" => "bass"}
    assert {:ok, clips} = TableRead.synthesize(model, scene.id, voices, synthesize)
    assert Enum.map(clips, & &1.audio) == ["alto:Come in.", "bass:No."]
    assert Enum.map(clips, & &1.cue) == ["MARA", "JOHN"]

    assert {:error, {:voice_not_configured, "JOHN"}} =
             TableRead.synthesize(model, scene.id, %{mara.id => "alto"}, synthesize)
  end
end
