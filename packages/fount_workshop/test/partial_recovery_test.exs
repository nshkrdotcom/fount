defmodule FountWorkshop.PartialRecoveryTest do
  alias FountWorkshop.Writing.RecoveryCopy
  use ExUnit.Case, async: true

  test "restores only an explicit historical fragment into an explicit destination span" do
    source =
      Fount.Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [%{type: :action, text: "Mara hides the brass key beneath the mat."}]
          }
        ]
      )

    element = List.last(source.ir.elements)

    {:ok, current, _} =
      Fount.Screenplay.apply(source, [
        %{
          "kind" => "replace_text",
          "target" => %{"kind" => "element", "id" => element.id},
          "value" => "Mara hides the wrong key beneath the mat."
        }
      ])

    source_start = :binary.match(element.text, "brass key") |> elem(0)
    current_text = List.last(current.ir.elements).text
    current_start = :binary.match(current_text, "wrong key") |> elem(0)

    source_span = %{
      "byte_start" => source_start,
      "byte_end" => source_start + byte_size("brass key")
    }

    current_span = %{
      "byte_start" => current_start,
      "byte_end" => current_start + byte_size("wrong key")
    }

    req = %{
      "workflow" => "recover",
      "base_revision_id" => current.revision.id,
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "options" => %{
        "adapt" => false,
        "source_revision_id" => source.revision.id,
        "source_targets" => [%{"kind" => "element", "id" => element.id, "span" => source_span}],
        "destination" => %{
          "kind" => "replace_element_span",
          "element_id" => element.id,
          "span" => current_span
        }
      }
    }

    registry = Map.new(source.ir.elements ++ source.ir.scenes, &{&1.id, &1})

    context = %{
      selection: req["selection"],
      evidence: [],
      source_models: [source, current],
      restore_registry: registry,
      data: %{
        "historical_source" => %{
          "screenplay_id" => source.id,
          "revision_id" => source.revision.id,
          "scene_specs" => []
        }
      }
    }

    assert {:ok, candidate} =
             RecoveryCopy.propose(
               current,
               req,
               %{"id" => "restore", "title" => "Restore fragment"},
               context,
               []
             )

    assert Fount.Query.node(candidate["screenplay"], element.id).text == element.text

    assert hd(candidate["change_groups"])["operations"] |> hd() |> get_in(["target", "span"]) ==
             current_span
  end

  test "restores an exact contiguous partial-scene range with historical IDs" do
    source =
      Fount.Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [
              %{type: :action, text: "First beat."},
              %{type: :action, text: "Second beat."},
              %{type: :action, text: "Third beat."}
            ]
          }
        ]
      )

    [_, first, second, third] = source.ir.elements

    {:ok, current, _} =
      Fount.Screenplay.apply(source, [
        %{"kind" => "delete_elements", "value" => %{"ids" => [second.id, third.id]}}
      ])

    req = %{
      "workflow" => "recover",
      "base_revision_id" => current.revision.id,
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "options" => %{
        "adapt" => false,
        "source_revision_id" => source.revision.id,
        "source_targets" => [
          %{"kind" => "element", "id" => second.id},
          %{"kind" => "element", "id" => third.id}
        ],
        "destination" => %{"kind" => "insert_after_element", "element_id" => first.id}
      }
    }

    registry = Map.new(source.ir.elements ++ source.ir.scenes, &{&1.id, &1})

    context = %{
      selection: req["selection"],
      evidence: [],
      source_models: [source, current],
      restore_registry: registry,
      data: %{
        "historical_source" => %{
          "screenplay_id" => source.id,
          "revision_id" => source.revision.id,
          "scene_specs" => []
        }
      }
    }

    assert {:ok, candidate} =
             RecoveryCopy.propose(
               current,
               req,
               %{"id" => "range", "title" => "Restore range"},
               context,
               []
             )

    assert Enum.map(candidate["screenplay"].ir.elements, & &1.id) ==
             Enum.map(source.ir.elements, & &1.id)
  end
end
