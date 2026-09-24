defmodule FountWorkshop.DevelopTest do
  use ExUnit.Case, async: true
  alias Fount.{Query, Screenplay}
  alias FountWorkshop.Develop

  defp client(scenes) do
    object = %{"approach" => "A specific dramatic route", "scenes" => scenes}

    Inference.Client.new!(
      adapter: Inference.Adapters.Mock,
      provider: :mock,
      adapter_opts: [response_text: Jason.encode!(object)]
    )
  end

  test "develop creates actual screenplay pages from an empty accepted root" do
    root = Screenplay.new(title: [{"Title", "The Debt"}])

    scenes = [
      %{
        "heading" => "INT. BANK VAULT - NIGHT",
        "elements" => [
          %{
            "type" => "action",
            "text" => "Mara presses a bloodied thumb to the vault glass. The lock stays red."
          },
          %{"type" => "character", "text" => "MARA"},
          %{"type" => "dialogue", "text" => "It was my thumb yesterday."}
        ]
      }
    ]

    assert {:ok, [first, second]} =
             Develop.develop(
               root,
               "A banker discovers her fingerprints were replaced.",
               client(scenes),
               clients: [
                 client(scenes),
                 client(
                   put_in(
                     scenes,
                     [Access.at(0), "elements", Access.at(2), "text"],
                     "Then why is the lock green?"
                   )
                 )
               ]
             )

    assert root.ir.scenes == []
    assert length(first.screenplay.ir.scenes) == 1
    assert length(second.screenplay.ir.scenes) == 1
    assert first.screenplay.revision.id != second.screenplay.revision.id
    assert first.screenplay.revision.parent_id == root.revision.id
    assert Screenplay.to_fountain(first.screenplay) =~ "INT. BANK VAULT - NIGHT"
    assert Screenplay.to_fountain(first.screenplay) =~ "It was my thumb yesterday."
    assert Fount.Validate.screenplay(first.screenplay) == []
  end

  test "continuation retains neighboring scene identities" do
    root =
      Screenplay.new(
        scenes: [
          %{heading: "INT. LOBBY - NIGHT", elements: [%{type: :action, text: "Mara enters."}]}
        ]
      )

    original = hd(root.ir.scenes)

    scenes = [
      %{
        "heading" => "EXT. BANK - NIGHT",
        "elements" => [%{"type" => "action", "text" => "A car pulls away."}]
      }
    ]

    assert {:ok, [candidate]} =
             Develop.develop(root, "Continue outside the bank.", client(scenes),
               approaches: ["A chase"]
             )

    assert hd(candidate.screenplay.ir.scenes).id == original.id
    assert Query.scene(candidate.screenplay, original.id)
    assert length(candidate.screenplay.ir.scenes) == 2
  end

  test "a failed later completion retains the earlier materialized route" do
    root = Screenplay.new()

    scenes = [
      %{
        "heading" => "INT. SHOP - DAY",
        "elements" => [
          %{"type" => "action", "text" => "Mara locks the door."}
        ]
      }
    ]

    failed =
      Inference.Client.new!(
        adapter: Inference.Adapters.Mock,
        provider: :mock,
        adapter_opts: [error: :timeout]
      )

    assert {:partial, [first], {:completion_failed, 2, _, _}} =
             Develop.develop(root, "Mara has five minutes.", client(scenes),
               clients: [client(scenes), failed]
             )

    assert Screenplay.to_fountain(first.screenplay) =~ "Mara locks the door."
  end

  test "orphan dialogue is rejected by the completion validator" do
    root = Screenplay.new()

    scenes = [
      %{
        "heading" => "INT. SHOP - DAY",
        "elements" => [
          %{"type" => "action", "text" => "Mara enters."},
          %{"type" => "dialogue", "text" => "Where are you?"}
        ]
      }
    ]

    assert {:error, {:completion_failed, 1, {:invalid_completion, :invalid_scene_shape}, trace}} =
             Develop.develop(root, "Mara searches the shop.", client(scenes),
               approaches: ["A direct search"]
             )

    assert length(trace) == 2
    assert root.ir.scenes == []
  end
end
