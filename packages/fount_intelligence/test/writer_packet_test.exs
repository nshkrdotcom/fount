defmodule Fount.Intelligence.WriterPacketTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.Reporting.{Renderer, WriterPacket}

  test "writer packet preserves semantic layers and renders deterministically" do
    {:ok, packet} =
      WriterPacket.new(
        "scene_doctor",
        "rev-1",
        %{"id" => "c1", "statement" => "The scene loses pressure."},
        %{
          scope: %{"scene_ids" => ["scene-1"]},
          intent: %{"desired_effect" => "sustained pressure"},
          finding: "The current evidence supports one diagnostic hypothesis.",
          evidence: [%{"id" => "ev-1", "excerpt" => "Mara looks away."}],
          derived_state: %{"reader_question" => "Will she answer?"},
          diagnoses: [%{"id" => "d1", "hypothesis" => "The tactic stops changing.", "uncertainty" => "medium", "support" => [], "counterevidence" => []}],
          strategies: ["change_tactic_without_changing_reveal"],
          candidate: nil
        }
      )

    map = WriterPacket.to_map(packet)
    assert map["scope"] == %{"scene_ids" => ["scene-1"]}
    assert map["finding"] =~ "supports one"
    assert Map.has_key?(map, "evidence")
    assert Map.has_key?(map, "derived_state")
    assert Map.has_key?(map, "diagnoses")
    assert Map.has_key?(map, "strategies")
    assert map["candidate"] == nil
    assert WriterPacket.compatible?(packet)

    assert {:ok, markdown_a} = Renderer.render(packet, :markdown)
    assert {:ok, markdown_b} = Renderer.render(packet, :markdown)
    assert markdown_a == markdown_b
    assert markdown_a =~ "## Finding"
    assert markdown_a =~ "## Intended experience and scope"
    assert markdown_a =~ "## Evidence"
    assert markdown_a =~ "## Diagnoses"
    assert markdown_a =~ "## Strategies"
  end
end
