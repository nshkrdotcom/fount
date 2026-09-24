defmodule FountWorkshop.TargetedRewriteTest do
  use ExUnit.Case, async: true

  alias Fount.{Query, Screenplay}
  alias FountWorkshop.TargetedRewrite

  defp client(changes) do
    Inference.Client.new!(
      adapter: Inference.Adapters.Mock,
      provider: :mock,
      adapter_opts: [response_text: Jason.encode!(%{"changes" => changes})]
    )
  end

  test "rewrites an exact dialogue element without moving the neighboring scene" do
    base =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. OFFICE - DAY",
            elements: [
              %{type: :character, text: "MARA"},
              %{type: :dialogue, text: "I know what you did."}
            ]
          },
          %{
            heading: "EXT. STREET - DAY",
            elements: [
              %{type: :action, text: "Dan waits outside."}
            ]
          }
        ]
      )

    [first, second] = base.ir.scenes
    original = Enum.find(base.ir.elements, &(&1.text == "I know what you did."))
    replacement = "The ledger is still wet."

    assert {:ok, candidate} =
             TargetedRewrite.propose(
               base,
               [original.id],
               "Make the accusation indirect.",
               client([%{"element_id" => original.id, "text" => replacement}])
             )

    assert Query.node(candidate.screenplay, original.id).text == replacement
    assert Query.scene(candidate.screenplay, first.id)
    assert Query.scene(candidate.screenplay, second.id)
    assert Query.node(base, original.id).text == "I know what you did."
    assert candidate.screenplay.revision.parent_id == base.revision.id
  end

  test "rejects an invented target in a completion" do
    base =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. OFFICE - DAY",
            elements: [
              %{type: :action, text: "A ledger burns."}
            ]
          }
        ]
      )

    target = Enum.find(base.ir.elements, &(&1.type == :action))

    assert {:error, {:completion_failed, {:invalid_completion, :invalid_rewrite_targets}, trace}} =
             TargetedRewrite.propose(
               base,
               [target.id],
               "Make this visual.",
               client([%{"element_id" => Fount.ID.v4(), "text" => "A page curls in the flame."}])
             )

    assert length(trace) == 2
  end
end
