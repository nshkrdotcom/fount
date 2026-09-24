defmodule FountWorkshop.PassTest do
  use ExUnit.Case, async: true

  alias Fount.{Query, Screenplay}
  alias FountWorkshop.Pass

  defp client(object) do
    Inference.Client.new!(
      adapter: Inference.Adapters.Mock,
      provider: :mock,
      adapter_opts: [response_text: Jason.encode!(object)]
    )
  end

  test "all six profiles load from their real assets" do
    assert length(Pass.profiles()) == 6

    for id <- Pass.profiles() do
      assert {:ok, %{"id" => ^id, "goal" => goal, "creative_prompt" => prompt}} = Pass.profile(id)
      assert is_binary(goal) and is_binary(prompt)
    end
  end

  test "dialogue and visual passes touch their selected element types" do
    base =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [
              %{type: :action, text: "Mara worries about the key."},
              %{type: :character, text: "MARA"},
              %{type: :dialogue, text: "I am very angry with you."}
            ]
          }
        ]
      )

    [scene] = base.ir.scenes
    action = Enum.find(base.ir.elements, &(&1.type == :action))
    dialogue = Enum.find(base.ir.elements, &(&1.type == :dialogue))

    assert {:ok, dialogue_pass} =
             Pass.propose(
               base,
               "dialogue_subtext",
               [scene.id],
               "Make Mara deflect.",
               client(%{
                 "changes" => [
                   %{"element_id" => dialogue.id, "text" => "You kept the spare."}
                 ]
               })
             )

    assert Query.node(dialogue_pass.screenplay, dialogue.id).text == "You kept the spare."
    assert Query.node(dialogue_pass.screenplay, action.id).text == action.text

    assert {:ok, visual_pass} =
             Pass.propose(
               base,
               "action_visual",
               [scene.id],
               "Show her concern physically.",
               client(%{
                 "changes" => [
                   %{"element_id" => action.id, "text" => "Mara checks her empty key ring twice."}
                 ]
               })
             )

    assert Query.node(visual_pass.screenplay, action.id).text ==
             "Mara checks her empty key ring twice."

    assert Query.node(visual_pass.screenplay, dialogue.id).text == dialogue.text
  end

  test "tension profile returns a scene replacement, not a prose suggestion" do
    base =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [
              %{type: :action, text: "Mara waits."}
            ]
          }
        ]
      )

    [scene] = base.ir.scenes

    replacement = %{
      "approach" => "A locked door changes her plan",
      "scenes" => [
        %{
          "heading" => "INT. ROOM - DAY",
          "elements" => [
            %{
              "type" => "action",
              "text" => "Mara reaches the door. The lock turns from the other side."
            }
          ]
        }
      ]
    }

    assert {:ok, proposal} =
             Pass.propose(
               base,
               "tension",
               [scene.id],
               "Make the exit a problem.",
               client(replacement),
               target_scene_count: 1
             )

    assert Query.scene(proposal.screenplay, scene.id)
    assert Screenplay.to_fountain(proposal.screenplay) =~ "The lock turns"
  end
end
