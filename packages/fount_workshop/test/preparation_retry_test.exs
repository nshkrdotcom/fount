defmodule FountWorkshop.PreparationRetryTest do
  alias FountWorkshop.Writing.Preparation
  use ExUnit.Case, async: true

  test "only incomplete inspections are scheduled from cached preparation" do
    model =
      Fount.Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [%{type: :action, text: "Mara pockets the key."}]
          }
        ]
      )

    selection = %{"whole_screenplay" => true}

    request = %{
      "workflow" => "propagate",
      "selection" => selection,
      "options" => %{"change" => "The key is lost", "destination" => %{"kind" => "start"}}
    }

    context = %{
      selection: selection,
      data: %{
        "inspections" => [
          %{"status" => "complete", "provenance" => %{"request_id" => "dependencies"}},
          %{"status" => "partial", "provenance" => %{"request_id" => "continuity"}}
        ]
      }
    }

    assert [%{"id" => "continuity"}] =
             Preparation.retry_requests(model, request, context)
  end
end
