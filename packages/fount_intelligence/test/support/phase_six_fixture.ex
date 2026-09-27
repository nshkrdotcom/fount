defmodule Fount.Intelligence.TestSupport.PhaseSixFixture do
  @moduledoc false

  alias Fount.Intelligence.StoryWorld
  alias Fount.Intelligence.StoryWorld.Evidence
  alias Fount.Screenplay

  def screenplay do
    Screenplay.new(
      id: "f62fdb6b-85d8-45c2-bccc-0fa10a0ee006",
      scenes: [
        %{
          heading: "INT. SERVICE OFFICE - NIGHT",
          elements: [
            %{type: :action, text: "Mara asks Dan for the archive ledger before the morning audit."},
            %{type: :dialogue, character: "MARA", text: "I need the ledger tonight."},
            %{type: :action, text: "Dan keeps the archive key in his palm instead of answering."}
          ]
        },
        %{
          heading: "INT. SERVICE CORRIDOR - YEARS EARLIER",
          elements: [
            %{type: :action, text: "Dan refuses to open the archive. Mara takes the spare key herself."},
            %{type: :dialogue, character: "DAN", text: "Not for you."}
          ]
        },
        %{
          heading: "INT. ARCHIVE - LATER",
          elements: [
            %{type: :action, text: "Mara gives Dan the key and chooses to let him open the cabinet."},
            %{type: :action, text: "Dan opens it. The ledger is inside."}
          ]
        },
        %{
          heading: "EXT. LOADING DOCK - PRE-DAWN",
          elements: [
            %{type: :action, text: "Dan gives the ledger to the waiting investigator before Mara can take it."},
            %{type: :dialogue, character: "MARA", text: "You already chose."}
          ]
        },
        %{
          heading: "EXT. SERVICE ROAD - DAWN",
          elements: [
            %{type: :action, text: "Mara walks away alone as the audit vans arrive."}
          ]
        }
      ]
    )
  end

  def actions(screenplay), do: Enum.filter(screenplay.ir.elements, &(&1.type == :action))
  def scene_events(screenplay), do: Enum.map(screenplay.ir.scenes, &("scene:" <> &1.id))
  def evidence(screenplay, element), do: Evidence.canonical_element(screenplay, element)

  def records(screenplay) do
    [scene_1, scene_2, scene_3, scene_4, scene_5] = scene_events(screenplay)
    [a1, a2, a3, a4, a5, a6, a7] = actions(screenplay)

    [
      record("event", "mara-asks", a1, %{
        "kind" => "action",
        "label" => "Mara asks Dan for the ledger",
        "participants" => %{"characters" => ["Mara", "Dan"]}
      }),
      record("event", "dan-refuses-access", a3, %{
        "kind" => "action",
        "label" => "Dan refuses Mara access to the archive",
        "participants" => %{"characters" => ["Dan", "Mara"]}
      }),
      record("event", "mara-takes-key", a3, %{
        "kind" => "decision",
        "label" => "Mara takes the spare key after Dan refuses",
        "participants" => %{"characters" => ["Mara", "Dan"]}
      }),
      record("event", "mara-trust-decision", a4, %{
        "kind" => "decision",
        "label" => "Mara chooses to trust Dan with the key",
        "participants" => %{"characters" => ["Mara", "Dan"]}
      }),
      record("event", "dan-opens-ledger", a5, %{
        "kind" => "action",
        "label" => "Dan opens the cabinet containing the ledger",
        "participants" => %{"characters" => ["Dan", "Mara"]}
      }),
      record("event", "dan-handoff", a6, %{
        "kind" => "consequence",
        "label" => "Dan gives the ledger to the investigator",
        "participants" => %{"characters" => ["Dan", "Mara"]}
      }),
      record("event", "mara-leaves", a7, %{
        "kind" => "consequence",
        "label" => "Mara walks away before the audit",
        "participants" => %{"characters" => ["Mara"]}
      }),
      record("goal", "mara-get-ledger", a1, %{
        "owner" => "Mara",
        "description" => "Get the archive ledger before the morning audit.",
        "level" => "sequence",
        "status" => "active",
        "active_at" => [scene_1, scene_3]
      }),
      record("goal", "dan-control-ledger", a2, %{
        "owner" => "Dan",
        "description" => "Control who receives the archive ledger.",
        "level" => "sequence",
        "status" => "active",
        "active_at" => [scene_1, scene_3, scene_4]
      }),
      interaction("office-negotiation", a1, scene_1, ["Mara", "Dan"],
        ["Mara wants the ledger", "Dan wants to control access"],
        ["direct request", "withholding"],
        %{"leverage" => "Dan retains the key"}
      ),
      interaction("flashback-refusal", a3, scene_2, ["Mara", "Dan"],
        ["Mara wants access", "Dan refuses access"],
        ["refusal", "self-help"],
        %{"trust" => "guarded"}
      ),
      interaction("archive-trust", a4, scene_3, ["Mara", "Dan"],
        ["Mara tests trust", "Dan opens the cabinet"],
        ["delegation", "cooperation"],
        %{"trust" => "tentative"}
      ),
      interaction("dock-betrayal", a6, scene_4, ["Mara", "Dan"],
        ["Dan hands off the ledger", "Mara confronts the choice"],
        ["preemption", "recognition"],
        %{"trust" => "broken", "leverage" => "investigator controls evidence"}
      ),
      beat("beat-office", a1, hd(screenplay.ir.scenes).id, %{
        "objective" => "Mara gets the ledger from Dan.",
        "tactic" => "direct request",
        "information_change" => "Dan reveals he controls the key.",
        "relationship_delta" => "guarded to transactional",
        "value_delta" => "access remains blocked",
        "outcome" => "Mara still lacks the ledger."
      }),
      beat("beat-flashback", a3, Enum.at(screenplay.ir.scenes, 1).id, %{
        "objective" => "Mara gets access despite Dan's refusal.",
        "tactic" => "take the spare key herself",
        "information_change" => "The refusal predates the present negotiation.",
        "relationship_delta" => "open to guarded",
        "value_delta" => "Mara gains the key",
        "outcome" => "Mara acts without Dan."
      }),
      beat("beat-archive", a4, Enum.at(screenplay.ir.scenes, 2).id, %{
        "objective" => "Mara gets the ledger while testing Dan.",
        "tactic" => "delegate access",
        "information_change" => "The ledger is confirmed inside.",
        "relationship_delta" => "transactional to tentative",
        "value_delta" => "access opens",
        "outcome" => "Dan can reach the ledger first."
      }),
      beat("beat-dock", a6, Enum.at(screenplay.ir.scenes, 3).id, %{
        "objective" => "Mara secures the ledger before the audit.",
        "tactic" => "arrive for the handoff",
        "information_change" => "Dan has already chosen the investigator.",
        "relationship_delta" => "tentative to broken",
        "value_delta" => "Mara loses control of the evidence",
        "outcome" => "The investigator receives the ledger."
      }),
      transition("mara-plan-self-help", a3, "Mara", "plan.archive_access", "ask Dan", "take spare key", "mara-takes-key"),
      transition("mara-belief-dan-maybe-trustworthy", a4, "Mara", "belief.Dan", "guarded", "tentatively trustworthy", "mara-trust-decision"),
      transition("mara-belief-dan-betrayed", a6, "Mara", "belief.Dan", "tentatively trustworthy", "betrayed trust", "dan-handoff"),
      transition("trust-flashback", a3, %{"from" => "Mara", "to" => "Dan"}, "relationship.trust", "open", "guarded", "mara-takes-key"),
      transition("trust-office", a1, %{"from" => "Mara", "to" => "Dan"}, "relationship.trust", "guarded", "transactional", "mara-asks"),
      transition("trust-archive", a4, %{"from" => "Mara", "to" => "Dan"}, "relationship.trust", "transactional", "tentative", "mara-trust-decision"),
      transition("trust-dock", a6, %{"from" => "Mara", "to" => "Dan"}, "relationship.trust", "tentative", "broken", "dan-handoff"),
      transition("leverage-office", a2, %{"from" => "Dan", "to" => "Mara"}, "relationship.leverage", "medium", "high", "mara-asks"),
      transition("leverage-dock", a6, %{"from" => "Dan", "to" => "Mara"}, "relationship.leverage", "high", "low", "dan-handoff"),
      transition("obligation-archive", a4, %{"from" => "Mara", "to" => "Dan"}, "relationship.obligation", "none", "owes trust", "mara-trust-decision"),
      record("commitment", "dan-ledger-promise", a5, %{
        "kind" => "promise",
        "from" => "Dan",
        "to" => "Mara",
        "terms" => "Dan will hand Mara the ledger after opening the cabinet.",
        "active_at" => ["dan-opens-ledger"]
      }),
      record("assertion", "mara-knows-audit-deadline", a1, %{
        "subject" => "audit",
        "predicate" => "deadline",
        "object" => "morning",
        "stance" => "knows",
        "epistemic_owner" => "Mara",
        "story_time_refs" => ["mara-asks"]
      }),
      causal("refusal-motivates-take", a3, "motivates", "dan-refuses-access", "mara-takes-key"),
      causal("take-enables-later-choice", a4, "enables", "mara-takes-key", "mara-trust-decision"),
      causal("trust-enables-open", a5, "enables", "mara-trust-decision", "dan-opens-ledger"),
      causal("open-enables-handoff", a6, "enables", "dan-opens-ledger", "dan-handoff"),
      causal("handoff-causes-exit", a7, "causes", "dan-handoff", "mara-leaves"),
      causal("promise-paid-off-by-handoff", a6, "pays_off", "dan-ledger-promise", "dan-handoff"),
      story_time("flashback-before-office", a3, scene_2, scene_1),
      story_time("office-before-archive", a4, scene_1, scene_3),
      story_time("archive-before-dock", a6, scene_3, scene_4),
      story_time("dock-before-road", a7, scene_4, scene_5),
      story_time("refusal-before-take", a3, "dan-refuses-access", "mara-takes-key"),
      story_time("take-before-ask", a3, "mara-takes-key", "mara-asks"),
      story_time("ask-before-trust", a4, "mara-asks", "mara-trust-decision"),
      story_time("trust-before-open", a5, "mara-trust-decision", "dan-opens-ledger"),
      story_time("open-before-handoff", a6, "dan-opens-ledger", "dan-handoff"),
      story_time("handoff-before-leave", a7, "dan-handoff", "mara-leaves")
    ]
  end

  def story_world(screenplay \\ screenplay()) do
    {:ok, world} = StoryWorld.compile(screenplay, [], records: records(screenplay))
    world
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
