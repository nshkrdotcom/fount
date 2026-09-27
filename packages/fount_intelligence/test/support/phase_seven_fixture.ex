defmodule Fount.Intelligence.TestSupport.PhaseSevenFixture do
  @moduledoc false

  alias Fount.Intelligence.Reader.Event
  alias Fount.Intelligence.StoryWorld
  alias Fount.Intelligence.StoryWorld.Evidence
  alias Fount.Screenplay

  def screenplay do
    Screenplay.new(
      id: "d408df76-82e0-4f91-9f4f-7f514e870007",
      scenes: [
        %{
          heading: "INT. SERVICE OFFICE - NIGHT",
          elements: [
            %{
              type: :action,
              text:
                "Mara turns a cracked silver watch over. The initials D.R. are cut into the back."
            },
            %{type: :character, text: "MARA"},
            %{type: :dialogue, text: "You said you threw it out."},
            %{type: :character, text: "DAN"},
            %{type: :dialogue, text: "I said it was gone."},
            %{
              type: :action,
              text:
                "Dan watches her thumb stop on the initials, then looks at the locked archive door."
            }
          ]
        },
        %{
          heading: "EXT. SERVICE ROAD - YEARS EARLIER",
          elements: [
            %{
              type: :action,
              text:
                "Dan presses the same uncracked watch into Mara's palm before she gets on the bus."
            },
            %{type: :character, text: "DAN"},
            %{type: :dialogue, text: "If I lose it, you keep it."},
            %{type: :character, text: "MARA"},
            %{type: :dialogue, text: "That's not how losing works."}
          ]
        },
        %{
          heading: "INT. ARCHIVE CORRIDOR - NIGHT",
          elements: [
            %{
              type: :action,
              text: "Mara blocks Dan from the archive door with the watch in her fist."
            },
            %{type: :character, text: "MARA"},
            %{type: :dialogue, text: "What does D.R. open?"},
            %{type: :character, text: "DAN"},
            %{type: :dialogue, text: "Nothing you want."},
            %{type: :character, text: "MARA"},
            %{type: :dialogue, text: "That's not an answer."},
            %{type: :character, text: "DAN"},
            %{type: :dialogue, text: "Locker nineteen. Lower hinge."}
          ]
        },
        %{
          heading: "INT. ARCHIVE - CONTINUOUS",
          elements: [
            %{
              type: :action,
              text: "Mara fits the watch stem into a scar beside locker nineteen's lower hinge."
            },
            %{
              type: :action,
              text:
                "The false hinge releases. Inside is the missing audit ledger wrapped in Dan's old bus map."
            },
            %{type: :character, text: "MARA"},
            %{type: :dialogue, text: "Gone."}
          ]
        },
        %{
          heading: "EXT. LOADING DOCK - PRE-DAWN",
          elements: [
            %{
              type: :action,
              text:
                "Mara leaves the watch on the ledger and pushes both toward the waiting investigator."
            },
            %{type: :character, text: "DAN"},
            %{type: :dialogue, text: "You could keep one thing."},
            %{type: :character, text: "MARA"},
            %{type: :dialogue, text: "I did."}
          ]
        }
      ]
    )
  end

  def actions(screenplay), do: Enum.filter(screenplay.ir.elements, &(&1.type == :action))
  def evidence(screenplay, element), do: Evidence.canonical_element(screenplay, element)
  def scene_events(screenplay), do: Enum.map(screenplay.ir.scenes, &("scene:" <> &1.id))

  def records(screenplay) do
    [scene_1, scene_2, scene_3, scene_4, scene_5] = scene_events(screenplay)
    [a1, a2, a3, a4, a5, a6, a7] = actions(screenplay)

    [
      record("event", "watch-initials-seen", a1, %{
        "kind" => "reveal",
        "label" => "Mara sees the D.R. initials on the cracked watch",
        "participants" => %{"characters" => ["Mara"]}
      }),
      record("event", "office-watch-pressure", a2, %{
        "kind" => "interaction",
        "label" => "Dan notices Mara connect the watch to the archive",
        "participants" => %{"characters" => ["Mara", "Dan"]}
      }),
      record("event", "watch-gift-origin", a3, %{
        "kind" => "reveal",
        "label" => "Years earlier Dan gives Mara the watch",
        "participants" => %{"characters" => ["Mara", "Dan"]}
      }),
      record("event", "corridor-confrontation", a4, %{
        "kind" => "interaction",
        "label" => "Mara confronts Dan about D.R.",
        "participants" => %{"characters" => ["Mara", "Dan"]}
      }),
      record("event", "watch-opens-locker", a5, %{
        "kind" => "action",
        "label" => "The watch releases locker nineteen's false hinge",
        "participants" => %{"characters" => ["Mara"]}
      }),
      record("event", "ledger-found", a6, %{
        "kind" => "reveal",
        "label" => "Mara finds the missing audit ledger",
        "participants" => %{"characters" => ["Mara"]}
      }),
      record("event", "watch-and-ledger-handoff", a7, %{
        "kind" => "decision",
        "label" => "Mara gives the investigator both the watch and ledger",
        "participants" => %{"characters" => ["Mara", "Dan"]}
      }),
      record("goal", "mara-find-ledger", a1, %{
        "owner" => "Mara",
        "description" => "Find the missing audit ledger before the investigators arrive.",
        "level" => "sequence",
        "status" => "active",
        "active_at" => [scene_1, scene_3, scene_4]
      }),
      interaction(
        "office-watch-exchange",
        a2,
        "office-watch-pressure",
        ["Mara", "Dan"],
        ["Mara tests Dan's denial", "Dan keeps the watch's purpose concealed"],
        ["accusation", "semantic dodge"],
        %{
          "knowledge_asymmetry" => "Dan still knows what D.R. means",
          "status" => "Dan holds information"
        }
      ),
      interaction(
        "corridor-locker-exchange",
        a4,
        "corridor-confrontation",
        ["Mara", "Dan"],
        ["Mara gets the watch's function", "Dan delays disclosure"],
        ["direct question", "evasion", "pressure", "concession"],
        %{"knowledge_asymmetry" => "narrows", "status" => "Mara gains leverage"}
      ),
      beat("beat-office-watch", a1, hd(screenplay.ir.scenes).id, %{
        "objective" => "Mara tests whether Dan lied about the watch.",
        "tactic" => "show the object and force him to react",
        "information_change" => "D.R. appears meaningful to Dan.",
        "relationship_delta" => "denial becomes guarded recognition",
        "value_delta" => "the watch becomes an active lead",
        "outcome" => "the watch points toward the archive."
      }),
      beat("beat-flashback-watch", a3, Enum.at(screenplay.ir.scenes, 1).id, %{
        "objective" => "Show why Mara has the watch.",
        "tactic" => "recontextualize the object through an earlier gift",
        "information_change" => "Dan voluntarily gave Mara the watch years earlier.",
        "relationship_delta" => "the object gains intimacy and obligation",
        "value_delta" => "the watch becomes evidence of an older bond",
        "outcome" => "the first-presented clue acquires an earlier origin."
      }),
      beat("beat-corridor", a4, Enum.at(screenplay.ir.scenes, 2).id, %{
        "objective" => "Mara gets the meaning of D.R. from Dan.",
        "tactic" => "repeat and sharpen the unanswered question",
        "information_change" => "D.R. points to locker nineteen's lower hinge.",
        "relationship_delta" => "Dan loses informational leverage",
        "value_delta" => "Mara gains a concrete route to the ledger",
        "outcome" => "Mara can act without further explanation."
      }),
      beat("beat-locker", a6, Enum.at(screenplay.ir.scenes, 3).id, %{
        "objective" => "Use the watch clue to find the ledger.",
        "tactic" => "test the watch against locker nineteen",
        "information_change" =>
          "the watch is a physical key and the ledger is hidden behind the false hinge.",
        "relationship_delta" => nil,
        "value_delta" => "Mara obtains the missing ledger",
        "outcome" => "the sequence objective is achieved."
      }),
      beat("beat-dock", a7, Enum.at(screenplay.ir.scenes, 4).id, %{
        "objective" => "Decide what to do with the recovered evidence.",
        "tactic" => "hand both objects to the investigator",
        "information_change" => "Mara refuses Dan's invitation to preserve the private token.",
        "relationship_delta" => "private bond yields to public accountability",
        "value_delta" => "Mara relinquishes possession but controls the disclosure",
        "outcome" => "the evidence leaves both characters' control."
      }),
      transition(
        "corridor-status-shift",
        a4,
        %{"from" => "Mara", "to" => "Dan"},
        "relationship.status",
        "Dan controls the answer",
        "Mara controls the next action",
        "corridor-confrontation"
      ),
      transition(
        "corridor-knowledge-shift",
        a4,
        "Mara",
        "knowledge.locker_access",
        "unknown",
        "locker nineteen lower hinge",
        "corridor-confrontation"
      ),
      transition(
        "ledger-possession",
        a6,
        "Mara",
        "possession.audit_ledger",
        "absent",
        "held",
        "ledger-found"
      ),
      record("commitment", "watch-origin-setup", a1, %{
        "kind" => "reader_setup",
        "from" => "screenplay",
        "to" => "reader",
        "terms" =>
          "The D.R. watch has an origin and significance that the screenplay will clarify.",
        "active_at" => ["watch-initials-seen"]
      }),
      record("commitment", "locker-access-setup", a4, %{
        "kind" => "reader_setup",
        "from" => "screenplay",
        "to" => "reader",
        "terms" => "Locker nineteen's lower hinge will make the watch clue actionable.",
        "active_at" => ["corridor-confrontation"]
      }),
      record("motif", "silver-watch", a1, %{
        "kind" => "object",
        "label" => "cracked silver watch",
        "occurrences" => [
          %{"event_id" => "watch-initials-seen", "function" => "question and clue"},
          %{"event_id" => "watch-gift-origin", "function" => "relationship origin"},
          %{"event_id" => "watch-opens-locker", "function" => "physical key"},
          %{"event_id" => "watch-and-ledger-handoff", "function" => "relinquished private bond"}
        ]
      }),
      causal("watch-origin-payoff", a3, "pays_off", "watch-origin-setup", "watch-gift-origin"),
      causal("locker-access-payoff", a5, "pays_off", "locker-access-setup", "watch-opens-locker"),
      causal("locker-opens-ledger", a6, "causes", "watch-opens-locker", "ledger-found"),
      causal("ledger-enables-handoff", a7, "enables", "ledger-found", "watch-and-ledger-handoff"),
      story_time("gift-before-initials", a3, "watch-gift-origin", "watch-initials-seen"),
      story_time("initials-before-corridor", a4, "watch-initials-seen", "corridor-confrontation"),
      story_time("corridor-before-locker", a5, "corridor-confrontation", "watch-opens-locker"),
      story_time("locker-before-ledger", a6, "watch-opens-locker", "ledger-found"),
      story_time("ledger-before-handoff", a7, "ledger-found", "watch-and-ledger-handoff"),
      story_time("flashback-scene-before-office-scene", a3, scene_2, scene_1),
      story_time("office-scene-before-corridor", a4, scene_1, scene_3),
      story_time("corridor-before-archive", a5, scene_3, scene_4),
      story_time("archive-before-dock", a7, scene_4, scene_5)
    ]
  end

  def reader_events(screenplay) do
    [a1, _a2, a3, a4, _a5, a6, a7] = actions(screenplay)

    [
      event("watch-origin-question", "question", "open", a1, screenplay,
        key: "where-did-watch-come-from",
        data: %{"text" => "Why does Mara have Dan's D.R. watch?"}
      ),
      event("watch-expectation", "expectation", "open", a1, screenplay,
        key: "watch-will-matter",
        claim_class: "model_estimated_reader_interpretation",
        data: %{"expectation" => "The watch and D.R. will matter to the archive problem."}
      ),
      event("watch-curiosity", "curiosity", "open", a1, screenplay,
        key: "watch-function",
        claim_class: "model_estimated_reader_interpretation",
        data: %{"gap" => "What does D.R. mean and why is Dan watching the initials?"}
      ),
      event("watch-forward-pull", "forward_pull", "open", a1, screenplay,
        key: "watch-forward",
        claim_class: "model_estimated_reader_interpretation",
        data: %{"next_question" => "What happened when Dan gave her the watch?"}
      ),
      event("flashback-origin-reveal", "reveal", "explicit", a3, screenplay,
        key: "watch-origin",
        data: %{"proposition" => "Dan gave Mara the watch years earlier."}
      ),
      event("watch-origin-resolve", "question", "resolve", a3, screenplay,
        key: "where-did-watch-come-from",
        data: %{"answer" => "Dan gave it to Mara before she left."}
      ),
      event("locker-question", "question", "open", a4, screenplay,
        key: "what-does-dr-open",
        data: %{"text" => "What does D.R. open?"}
      ),
      event("corridor-suspense", "suspense", "set", a4, screenplay,
        key: "locker-pressure",
        claim_class: "model_estimated_reader_interpretation",
        data: %{
          "components" => %{
            "desired_outcome" => "Mara reaches the ledger before investigators arrive",
            "threat" => "Dan can still withhold the access clue",
            "uncertainty" => "whether he will disclose it"
          }
        }
      ),
      event("locker-forward", "forward_pull", "redirect", a4, screenplay,
        key: "watch-forward",
        claim_class: "model_estimated_reader_interpretation",
        data: %{"next_question" => "Will the watch actually open locker nineteen?"}
      ),
      event("locker-reveal", "reveal", "explicit", a6, screenplay,
        key: "watch-function-reveal",
        data: %{
          "proposition" => "The watch stem releases the false hinge and exposes the ledger."
        }
      ),
      event("locker-question-resolve", "question", "resolve", a6, screenplay,
        key: "what-does-dr-open",
        data: %{"answer" => "The false hinge at locker nineteen."}
      ),
      event("corridor-suspense-resolve", "suspense", "resolve", a6, screenplay,
        key: "locker-pressure",
        claim_class: "model_estimated_reader_interpretation",
        data: %{
          "components" => %{
            "desired_outcome" => "Mara reaches the ledger before investigators arrive",
            "threat" => "Dan can still withhold the access clue",
            "uncertainty" => "whether he will disclose it"
          },
          "outcome" => "Mara finds the ledger."
        }
      ),
      event("dock-forward-resolve", "forward_pull", "resolve", a7, screenplay,
        key: "watch-forward",
        claim_class: "model_estimated_reader_interpretation",
        data: %{"outcome" => "Mara decides what to keep and what to surrender."}
      )
    ]
  end

  def story_world(screenplay \\ screenplay()) do
    {:ok, world} = StoryWorld.compile(screenplay, [], records: records(screenplay))
    world
  end

  def event(id, kind, action, element, screenplay, opts \\ []) do
    {:ok, value} =
      Event.new(%{
        "id" => id,
        "kind" => kind,
        "action" => action,
        "point" => element.id,
        "key" => Keyword.get(opts, :key),
        "claim_class" => Keyword.get(opts, :claim_class, "deterministic_derived_narrative_state"),
        "visibility" => Keyword.get(opts, :visibility, "reader_visible"),
        "data" => Keyword.get(opts, :data, %{}),
        "evidence" => [evidence(screenplay, element)],
        "dependencies" => Keyword.get(opts, :dependencies, [])
      })

    value
  end

  defp interaction(id, element, event_id, participants, objectives, tactics, changes),
    do:
      record("interaction", id, element, %{
        "event_id" => event_id,
        "participants" => participants,
        "objectives" => objectives,
        "tactics" => tactics,
        "changes" => changes
      })

  defp beat(id, element, scene_id, attrs),
    do: record("beat", id, element, Map.put(attrs, "scene_id", scene_id))

  defp transition(id, element, subject, attribute, from, to, event_id),
    do:
      record("state_transition", id, element, %{
        "subject" => subject,
        "attribute" => attribute,
        "from" => from,
        "to" => to,
        "event_id" => event_id
      })

  defp causal(id, element, kind, from, to),
    do: record("causal_relation", id, element, %{"kind" => kind, "from" => from, "to" => to})

  defp story_time(id, element, left, right),
    do:
      record("story_time_constraint", id, element, %{
        "left" => left,
        "right" => right,
        "relations" => ["before"]
      })

  defp record(type, id, element, attrs) do
    %{
      "record_type" => type,
      "id" => id,
      "evidence" => [%{"element_id" => element.id}]
    }
    |> Map.merge(attrs)
  end
end
