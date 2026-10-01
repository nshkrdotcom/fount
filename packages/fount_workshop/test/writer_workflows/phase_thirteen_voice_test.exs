defmodule FountWorkshop.PhaseThirteenVoiceTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.Playbooks.Constraints
  alias Fount.Screenplay
  alias Fount.Writing.{CanonicalJSON, Principal, Review}
  alias FountWorkshop.Request
  alias FountWorkshop.Writing.Context
  alias FountWorkshop.Writing.ReviewGate

  test "A04 protects exact repetition, Unicode and code-switching while surfacing human language review" do
    protected = "Not today. Not today. Aujourd'hui non. \u{4ECA}\u{65E5}\u{306F}\u{9055}\u{3046}."

    base =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. KITCHEN - MORNING",
            elements: [
              %{type: :action, text: "Mara. Still. At the sink."},
              %{type: :character, text: "MARA (V.O.)"},
              %{type: :dialogue, text: protected}
            ]
          }
        ]
      )

    action = Enum.find(base.ir.elements, &(&1.type == :action))
    cue = Enum.find(base.ir.elements, &(&1.type == :character))
    dialogue = Enum.find(base.ir.elements, &(&1.type == :dialogue))

    request = %{
      "version" => 1,
      "workflow" => "pass",
      "mode" => "revise",
      "base_revision_id" => base.revision.id,
      "instruction" => "Try a visual pass without smoothing the voice.",
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "options" => %{
        "profile" => "action_visual",
        "voice_exemplars" => [%{"kind" => "element", "id" => dialogue.id}],
        "style_preferences" => ["Keep clipped action fragments", "Keep purposeful repetition"],
        "protected_text" => [
          %{
            "id" => "voiceover-cue",
            "target" => %{"kind" => "element", "id" => cue.id},
            "text" => "MARA (V.O.)"
          },
          %{
            "id" => "not-today",
            "target" => %{"kind" => "element", "id" => dialogue.id},
            "text" => protected
          }
        ]
      }
    }

    assert {:ok, validated} = Request.validate(base, request)
    assert {:ok, ^validated} = Request.validate(base, validated)
    [pin | rest] = validated["constraints"]
    conflicting = %{pin | "severity" => "advisory"}

    assert {:error, :duplicate_constraint_id} =
             Request.validate(base, %{validated | "constraints" => [conflicting | rest]})

    assert {:error, :invalid_voice_exemplars} =
             Request.validate(base, put_in(request, ["options", "voice_exemplars"], "not a list"))

    pins = Enum.filter(validated["constraints"], &(&1["kind"] == "pin_text"))
    assert length(pins) == 2
    assert Enum.all?(pins, &(&1["severity"] == "required"))
    assert Enum.any?(pins, &(&1["spec"]["text"] == "MARA (V.O.)"))
    pin = Enum.find(pins, &(&1["spec"]["text"] == protected))

    assert {:ok, context} = Context.build(base, validated)
    voice = context.data["voice_protection"]
    assert Enum.any?(voice["exemplars"], &(&1["text"] == protected))

    assert Enum.any?(
             voice["limitations"],
             &String.contains?(&1, "language or cultural authenticity")
           )

    assert {:ok, revised, _} =
             Screenplay.apply(base, [
               %{
                 "kind" => "replace_text",
                 "target" => %{"kind" => "element", "id" => action.id},
                 "value" => "Mara. Still. The tap ticks twice."
               }
             ])

    checks = Constraints.deterministic(base, revised, pins)
    assert Enum.all?(checks, &(&1["status"] == "pass"))

    required =
      Enum.map(
        checks,
        &%{
          "constraint_id" => &1["constraint_id"],
          "evaluation" => &1["evaluation"],
          "overridable" => false
        }
      )

    fingerprint =
      CanonicalJSON.hash(%{"required_checks" => required, "checks" => checks, "report_ids" => []})

    {:ok, principal} = Principal.new(:human, "writer")

    {:ok, review} =
      Review.new(
        reviewer: principal,
        candidate_id: "voice-candidate",
        base_revision_id: base.revision.id,
        content_hash: revised.revision.content_hash,
        report_ids: [],
        check_set_fingerprint: fingerprint,
        recommendation: :approve
      )

    candidate = %{
      "id" => "voice-candidate",
      "base_revision_id" => base.revision.id,
      "content_hash" => revised.revision.content_hash,
      "report_ids" => [],
      "structural_errors" => [],
      "checks" => checks,
      "required_checks" => required,
      "check_set_fingerprint" => fingerprint
    }

    assert :ok = ReviewGate.validate(candidate, review, principal)

    assert {:ok, normalized, _} =
             Screenplay.apply(base, [
               %{
                 "kind" => "replace_text",
                 "target" => %{"kind" => "element", "id" => dialogue.id},
                 "value" => "Not today."
               }
             ])

    [failed] = Constraints.deterministic(base, normalized, [pin])
    assert failed["status"] == "fail"

    blocked_required = [
      %{
        "constraint_id" => failed["constraint_id"],
        "evaluation" => failed["evaluation"],
        "overridable" => false
      }
    ]

    blocked_fp =
      CanonicalJSON.hash(%{
        "required_checks" => blocked_required,
        "checks" => [failed],
        "report_ids" => []
      })

    blocked = %{
      candidate
      | "content_hash" => normalized.revision.content_hash,
        "checks" => [failed],
        "required_checks" => blocked_required,
        "check_set_fingerprint" => blocked_fp
    }

    {:ok, blocked_review} =
      Review.new(
        reviewer: principal,
        candidate_id: "voice-candidate",
        base_revision_id: base.revision.id,
        content_hash: normalized.revision.content_hash,
        report_ids: [],
        check_set_fingerprint: blocked_fp,
        recommendation: :approve
      )

    assert {:error, {:review_blockers, blockers}} =
             ReviewGate.validate(blocked, blocked_review, principal)

    assert Enum.any?(blockers, &(&1["reason"] == "required_check_not_passing"))

    {:ok, override_review} =
      Review.new(
        reviewer: principal,
        candidate_id: "voice-candidate",
        base_revision_id: base.revision.id,
        content_hash: normalized.revision.content_hash,
        report_ids: [],
        check_set_fingerprint: blocked_fp,
        recommendation: :approve,
        overrides: [%{"constraint_id" => pin["id"], "reason" => "Writer reviewed"}]
      )

    assert {:error, :invalid_override_target} =
             ReviewGate.validate(blocked, override_review, principal)
  end
end
