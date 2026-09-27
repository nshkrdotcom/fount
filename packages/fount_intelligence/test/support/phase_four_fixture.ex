defmodule Fount.Intelligence.TestSupport.PhaseFourFixture do
  @moduledoc false

  alias Fount.Intelligence.Reader.Event
  alias Fount.Intelligence.StoryWorld
  alias Fount.Intelligence.StoryWorld.Evidence
  alias Fount.Screenplay

  def screenplay do
    Screenplay.new(
      id: "9cc8db45-9ae9-4cbb-ae13-2d67a2a9ff40",
      scenes: [
        %{
          heading: "INT. SERVICE CORRIDOR - NIGHT",
          elements: [
            %{type: :action, text: "Mara pockets the brass key while Dan watches."},
            %{type: :note, text: "[[Writer note: the key opens the archive.]]"}
          ]
        },
        %{
          heading: "INT. ARCHIVE DOOR - LATER",
          elements: [%{type: :action, text: "Mara tries the brass key. The archive door opens."}]
        },
        %{
          heading: "INT. SERVICE CORRIDOR - YEARS EARLIER",
          elements: [%{type: :action, text: "Young Mara sees the brass key behind glass."}]
        },
        %{
          heading: "EXT. LOADING DOCK - DAWN",
          elements: [%{type: :action, text: "Mara hands Dan the ledger she recovered from the archive."}]
        }
      ]
    )
  end

  def actions(screenplay), do: Enum.filter(screenplay.ir.elements, &(&1.type == :action))
  def note(screenplay), do: Enum.find(screenplay.ir.elements, &(&1.type == :note))
  def scene_events(screenplay), do: Enum.map(screenplay.ir.scenes, &("scene:" <> &1.id))

  def evidence(screenplay, element), do: Evidence.canonical_element(screenplay, element)

  def story_world(screenplay) do
    [scene_1, scene_2, scene_3, scene_4] = scene_events(screenplay)
    [action_1, action_2, action_3, action_4] = actions(screenplay)

    records = [
      record("state_transition", "mara-has-key", action_1, %{
        "subject" => "Mara",
        "attribute" => "possession.key",
        "from" => false,
        "to" => true,
        "event_id" => scene_1,
        "dependencies" => ["fixture:key"]
      }),
      record("state_transition", "mara-opens-archive", action_2, %{
        "subject" => "Mara",
        "attribute" => "access.archive",
        "from" => false,
        "to" => true,
        "event_id" => scene_2,
        "dependencies" => ["fixture:archive"]
      }),
      record("state_transition", "mara-trusts-dan-low", action_1, %{
        "subject" => %{"from" => "Mara", "to" => "Dan"},
        "attribute" => "relationship.trust",
        "from" => nil,
        "to" => "guarded",
        "event_id" => scene_1,
        "dependencies" => ["fixture:relationship"]
      }),
      record("state_transition", "mara-trusts-dan-higher", action_4, %{
        "subject" => %{"from" => "Mara", "to" => "Dan"},
        "attribute" => "relationship.trust",
        "from" => "guarded",
        "to" => "tentative",
        "event_id" => scene_4,
        "dependencies" => ["fixture:relationship"]
      }),
      record("state_transition", "dan-leverage-mara", action_1, %{
        "subject" => %{"from" => "Dan", "to" => "Mara"},
        "attribute" => "relationship.leverage",
        "from" => nil,
        "to" => "high",
        "event_id" => scene_1,
        "dependencies" => ["fixture:relationship"]
      }),
      record("assertion", "mara-knows-key-origin", action_3, %{
        "subject" => "key",
        "predicate" => "origin",
        "object" => "service corridor display case",
        "stance" => "knows",
        "epistemic_owner" => "Mara",
        "story_time_refs" => [scene_3],
        "dependencies" => ["fixture:key-origin"]
      }),
      record("commitment", "promise-key", action_1, %{
        "kind" => "promise",
        "from" => "Mara",
        "to" => "Dan",
        "terms" => "If the key works, Dan gets the ledger.",
        "active_at" => [scene_1],
        "dependencies" => ["fixture:promise"]
      }),
      record("causal_relation", "promise-key-payoff", action_4, %{
        "kind" => "pays_off",
        "from" => "promise-key",
        "to" => scene_4,
        "dependencies" => ["fixture:promise"]
      }),
      record("story_time_constraint", "flashback-before-pickup", action_3, %{
        "left" => scene_3,
        "right" => scene_1,
        "relations" => ["before"],
        "dependencies" => ["fixture:timeline"]
      }),
      record("story_time_constraint", "pickup-before-open", action_2, %{
        "left" => scene_1,
        "right" => scene_2,
        "relations" => ["before"],
        "dependencies" => ["fixture:timeline"]
      }),
      record("story_time_constraint", "open-before-payoff", action_4, %{
        "left" => scene_2,
        "right" => scene_4,
        "relations" => ["before"],
        "dependencies" => ["fixture:timeline"]
      })
    ]

    {:ok, world} = StoryWorld.compile(screenplay, [], records: records)
    world
  end

  def reader_events(screenplay) do
    [action_1, action_2, _action_3, action_4] = actions(screenplay)
    note = note(screenplay)

    [
      event("question-open", "question", "open", action_1, screenplay,
        key: "what-does-key-open",
        data: %{"text" => "What does the brass key open?"},
        dependencies: ["reader:key-question"]
      ),
      event("promise-open", "promise", "open", action_1, screenplay,
        key: "ledger-promise",
        data: %{"text" => "Dan expects the ledger if the key works."},
        dependencies: ["reader:promise"]
      ),
      event("reveal-explicit", "reveal", "explicit", action_2, screenplay,
        key: "archive-key-reveal",
        data: %{"proposition" => "The brass key opens the archive."},
        dependencies: ["reader:key-reveal"]
      ),
      event("question-resolve", "question", "resolve", action_2, screenplay,
        key: "what-does-key-open",
        data: %{"answer" => "The archive."},
        dependencies: ["reader:key-question", "reader:key-reveal"]
      ),
      event("reader-mara-knows", "character_epistemic", "set", action_2, screenplay,
        key: "mara-knows-key-purpose",
        data: %{
          "character" => "Mara",
          "proposition" => "The key opens the archive.",
          "stance" => "believes"
        },
        dependencies: ["reader:mara-model"]
      ),
      event("flashback-origin-reveal", "reveal", "explicit", Enum.at(actions(screenplay), 2), screenplay,
        key: "key-origin-reveal",
        data: %{"proposition" => "Mara saw the key years earlier."},
        dependencies: ["reader:flashback-origin"]
      ),
      event("corridor-pressure", "suspense", "set", action_1, screenplay,
        key: "corridor-pressure",
        claim_class: "model_estimated_reader_interpretation",
        data: %{
          "components" => %{
            "desired_outcome" => "Mara leaves unseen",
            "threat" => "Dan may stop her",
            "uncertainty" => "whether Dan will intervene"
          }
        },
        dependencies: ["reader:pressure"]
      ),
      event("handoff-pull", "forward_pull", "open", action_2, screenplay,
        key: "what-is-in-archive",
        data: %{"next_question" => "What did Mara recover?"},
        dependencies: ["reader:forward-pull"]
      ),
      event("promise-fulfilled", "promise", "fulfill", action_4, screenplay,
        key: "ledger-promise",
        data: %{"outcome" => "Mara gives Dan the ledger."},
        dependencies: ["reader:promise"]
      ),
      event("private-note", "reveal", "explicit", note, screenplay,
        visibility: "private",
        key: "private-archive-note",
        data: %{"proposition" => "The key opens the archive."},
        dependencies: ["reader:private-note"]
      )
    ]
  end

  def event(id, kind, action, element, screenplay, opts \\ []) do
    {:ok, event} =
      Event.new(%{
        "id" => id,
        "kind" => kind,
        "action" => action,
        "point" => element.id,
        "key" => Keyword.get(opts, :key),
        "claim_class" =>
          Keyword.get(opts, :claim_class, "deterministic_derived_narrative_state"),
        "visibility" => Keyword.get(opts, :visibility, "reader_visible"),
        "data" => Keyword.get(opts, :data, %{}),
        "evidence" => [evidence(screenplay, element)],
        "dependencies" => Keyword.get(opts, :dependencies, [])
      })

    event
  end

  defp record(type, id, element, extra) do
    %{
      "record_type" => type,
      "id" => id,
      "evidence" => [%{"element_id" => element.id}]
    }
    |> Map.merge(extra)
  end
end
