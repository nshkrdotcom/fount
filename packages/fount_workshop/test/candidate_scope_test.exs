defmodule FountWorkshop.CandidateScopeTest do
  use ExUnit.Case, async: true

  alias FountWorkshop.{Candidate, Writing.Context}

  defp base do
    Fount.Screenplay.new(
      scenes: [
        %{
          heading: "INT. OFFICE - DAY",
          elements: [%{type: :action, text: "Mara keeps the key."}]
        },
        %{
          heading: "EXT. DOCK - NIGHT",
          elements: [%{type: :action, text: "Dan waits for the ferry."}]
        }
      ]
    )
  end

  defp proposal(model, operation) do
    %{
      "version" => 1,
      "base_revision_id" => model.revision.id,
      "strategy_id" => nil,
      "summary" => "A scoped revision",
      "groups" => [
        %{
          "id" => "revision",
          "title" => "Revision",
          "reason" => "Writer requested change",
          "depends_on" => [],
          "addresses_notes" => [],
          "evidence_ids" => [],
          "operations" => List.wrap(operation),
          "origin" => "generated_text"
        }
      ],
      "inventions" => [],
      "unresolved_questions" => []
    }
  end

  test "a selected scene does not authorize insertion into another scene" do
    model = base()
    [office, dock] = model.ir.scenes

    operation = %{
      "kind" => "insert_elements",
      "target" => %{"kind" => "scene", "id" => dock.id},
      "value" => %{
        "position" => "end",
        "anchor_id" => nil,
        "elements" => [
          %{
            "local_id" => "new:beat",
            "type" => "action",
            "text" => "A flare burns.",
            "attrs" => %{}
          }
        ]
      }
    }

    assert {:error, {:outside_editable_scope, _}} =
             Candidate.compile(model, proposal(model, operation),
               editable_selection: %{"targets" => [%{"kind" => "scene", "id" => office.id}]}
             )
  end

  test "an unselected scene cannot be moved while retaining its text" do
    model = base()
    [office, dock] = model.ir.scenes

    operation = %{
      "kind" => "move_scene",
      "target" => %{"kind" => "scene", "id" => dock.id},
      "value" => %{"after_scene_id" => nil}
    }

    assert {:error, {:outside_editable_scope, _}} =
             Candidate.compile(model, proposal(model, operation),
               editable_selection: %{"targets" => [%{"kind" => "scene", "id" => office.id}]}
             )
  end

  test "a selected scene authorizes changing its own heading" do
    model = base()
    [office | _] = model.ir.scenes

    operation = %{
      "kind" => "set_scene_heading",
      "target" => %{"kind" => "scene", "id" => office.id},
      "value" => "INT. OFFICE - NIGHT"
    }

    assert {:ok, candidate} =
             Candidate.compile(model, proposal(model, operation),
               editable_selection: %{"targets" => [%{"kind" => "scene", "id" => office.id}]}
             )

    assert Fount.Query.node(candidate["screenplay"], office.heading_id).text ==
             "INT. OFFICE - NIGHT"
  end

  test "a selected byte span authorizes only a span-targeted replacement" do
    model = base()
    action = Enum.find(model.ir.elements, &(&1.type == :action))

    selection = %{
      "targets" => [
        %{
          "kind" => "element",
          "id" => action.id,
          "span" => %{"byte_start" => 5, "byte_end" => 10}
        }
      ]
    }

    target = %{"kind" => "element", "id" => action.id}

    assert {:error, {:outside_editable_scope, _}} =
             Candidate.compile(
               model,
               proposal(model, %{
                 "kind" => "replace_text",
                 "target" => target,
                 "value" => "Mara drops the key."
               }),
               editable_selection: selection
             )

    operation = %{
      "kind" => "replace_text",
      "target" => Map.put(target, "span", %{"byte_start" => 5, "byte_end" => 10}),
      "value" => "drops"
    }

    assert {:ok, candidate} =
             Candidate.compile(model, proposal(model, operation), editable_selection: selection)

    assert Fount.Query.node(candidate["screenplay"], action.id).text == "Mara drops the key."
  end

  test "replayed span operations cannot shift a later edit into protected text" do
    model = base()
    action = Enum.find(model.ir.elements, &(&1.type == :action))
    span = %{"byte_start" => 5, "byte_end" => 10}
    selection = %{"targets" => [%{"kind" => "element", "id" => action.id, "span" => span}]}
    target = %{"kind" => "element", "id" => action.id, "span" => span}

    operations = [
      %{"kind" => "replace_text", "target" => target, "value" => "x"},
      %{"kind" => "replace_text", "target" => target, "value" => "drops"}
    ]

    assert {:error, {:outside_editable_scope, _}} =
             Candidate.compile(model, proposal(model, operations), editable_selection: selection)
  end

  test "character workspace intersects confirmed appearances with the writer restriction" do
    model =
      Fount.parse!(
        "INT. OFFICE - DAY\n\nMARA\nWait here.\n\nEXT. DOCK - NIGHT\n\nMARA\nCome aboard.\n"
      )
      |> Fount.Screenplay.from_document(cast_resolution: :literal_cues)

    [office, dock] = model.ir.scenes
    character = Enum.find_value(model.cast, fn {id, c} -> if c.display_name == "MARA", do: id end)

    selection =
      Context.editable_selection(model, %{
        "workflow" => "character",
        "options" => %{"character_id" => character},
        "selection" => %{"targets" => [%{"kind" => "scene", "id" => office.id}]}
      })

    assert {:ok, units} = FountProbe.Projection.select(model, selection)
    assert Enum.any?(units, &(&1["scene_id"] == office.id))
    refute Enum.any?(units, &(&1["scene_id"] == dock.id))
  end

  test "a screenplay target in a character request still limits edits to appearance scenes" do
    model =
      Fount.parse!(
        "INT. OFFICE - DAY\n\nMARA\nWait here.\n\nEXT. DOCK - NIGHT\n\nA ferry leaves.\n"
      )
      |> Fount.Screenplay.from_document(cast_resolution: :literal_cues)

    [office, dock] = model.ir.scenes
    character = Enum.find_value(model.cast, fn {id, c} -> if c.display_name == "MARA", do: id end)

    selection =
      Context.editable_selection(model, %{
        "workflow" => "character",
        "options" => %{"character_id" => character},
        "selection" => %{"targets" => [%{"kind" => "screenplay", "id" => model.id}]}
      })

    assert selection == %{"targets" => [%{"kind" => "scene", "id" => office.id}]}
    assert {:ok, units} = FountProbe.Projection.select(model, selection)
    refute Enum.any?(units, &(&1["scene_id"] == dock.id))
  end

  test "a narrow scene selection cannot overwrite an existing character record" do
    model = base()
    {model, character} = Fount.Screenplay.add_character(model, "Mara")
    office = hd(model.ir.scenes)

    operation = %{
      "kind" => "put_character",
      "value" => %{
        "id" => character.id,
        "display_name" => "New Mara",
        "notes" => nil,
        "aliases" => [],
        "attributes" => %{}
      }
    }

    assert {:error, {:outside_editable_scope, _}} =
             Candidate.compile(model, proposal(model, operation),
               editable_selection: %{"targets" => [%{"kind" => "scene", "id" => office.id}]}
             )
  end

  test "a narrow scene selection cannot overwrite an existing authored item" do
    original = base()
    [office, dock] = original.ir.scenes

    item = %{
      "local_id" => "new:note",
      "namespace" => "writer",
      "kind" => "note",
      "target" => %{"kind" => "scene", "id" => dock.id},
      "value" => %{"instruction" => "Keep the ferry."},
      "dependencies" => [],
      "status" => "active",
      "provenance" => %{}
    }

    {:ok, model, changes} =
      Fount.Screenplay.apply(original, [%{"kind" => "put_authored_item", "value" => item}])

    id = changes.local_references["new:note"]

    replacement =
      item
      |> Map.delete("local_id")
      |> Map.put("id", id)
      |> Map.put("value", %{"instruction" => "Remove the ferry."})

    assert {:error, {:outside_editable_scope, _}} =
             Candidate.compile(
               model,
               proposal(model, %{"kind" => "put_authored_item", "value" => replacement}),
               editable_selection: %{"targets" => [%{"kind" => "scene", "id" => office.id}]}
             )
  end
end
