defmodule Fount.WritingPersistenceIntegrationTest do
  use ExUnit.Case, async: false
  alias Ecto.Adapters.SQL
  alias Fount.{ID, Persistence, Query, Repo, Screenplay}
  alias Fount.Writing.{Approval, Authority, Principal}

  setup_all do
    url = System.fetch_env!("FOUNT_DATABASE_URL")
    start_supervised!({Repo, url: url, pool_size: 2})
    :ok
  end

  defp direct_approval(candidate_id, type \\ :human, principal_id \\ "writer", opts \\ []) do
    {:ok, candidate} = Persistence.candidate(Repo, candidate_id)
    {:ok, principal} = Principal.new(type, principal_id)
    {:ok, authority} = Authority.new(principal, candidate["screenplay_id"], [:approve])
    approval_id = Keyword.get(opts, :approval_id, ID.v4())
    {:ok, approval} = Approval.direct(candidate, principal, approval_id, opts)
    {approval, authority}
  end

  test "session checkpoints persist strategy and review states" do
    root = Screenplay.new()
    assert {:ok, _} = Persistence.create(Repo, "session-status-#{ID.v4()}", root)

    assert {:ok, session} =
             Persistence.save_session(Repo, %{
               screenplay_id: root.id,
               base_revision_id: root.revision.id,
               workflow: "develop",
               request: %{},
               status: "open"
             })

    assert {:ok, strategies} =
             Persistence.save_session(Repo, %{session | status: "strategies_ready"})

    assert {:ok, review} =
             Persistence.save_session(Repo, %{strategies | status: "review_ready"})

    assert {:ok, reopened} = Persistence.session(Repo, review.id)
    assert reopened["status"] == "review_ready"
  end

  test "accepted revisions reload with immutable history and scoped structural rows" do
    key = "writing-#{ID.v4()}"

    root =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - NIGHT",
            elements: [
              %{type: :action, text: "Mara waits."}
            ]
          }
        ]
      )

    assert {:ok, ^root} = Persistence.create(Repo, key, root)
    assert {:ok, loaded} = Persistence.load(Repo, key)
    assert Screenplay.to_fountain(loaded) == Screenplay.to_fountain(root)
    line = Enum.find(root.ir.elements, &(&1.type == :action))

    assert {:ok, edited, _} =
             Screenplay.apply(
               root,
               [
                 %{
                   "kind" => "replace_text",
                   "target" => %{"kind" => "element", "id" => line.id},
                   "value" => "Mara leaves."
                 }
               ],
               []
             )

    assert {:error, :approval_required} =
             Persistence.save_edit(Repo, key, edited, expected_revision: root.revision.id)
    assert {:error, :approval_required} =
             Persistence.save(Repo, key, edited, expected_revision: root.revision.id)
    assert {:error, :not_found} = Persistence.load_revision(Repo, root.id, edited.revision.id)

    assert {:ok, candidate} =
             Persistence.save_edit_candidate(Repo, key, edited,
               expected_revision: root.revision.id,
               operations: [%{"kind" => "replace_text", "target" => %{"kind" => "element", "id" => line.id}, "value" => "Mara leaves."}]
             )

    assert {:ok, still_root} = Persistence.load(Repo, key)
    assert Query.node(still_root, line.id).text == "Mara waits."
    {approval, authority} = direct_approval(candidate.id)
    assert {:ok, ^edited} = Persistence.accept_candidate(Repo, candidate.id, approval: approval, authority: authority)
    assert {:ok, head} = Persistence.load(Repo, key)
    assert Query.node(head, line.id).text == "Mara leaves."
    assert {:ok, old} = Persistence.load_revision(Repo, root.id, root.revision.id)
    assert Query.node(old, line.id).text == "Mara waits."
    assert Enum.map(Persistence.history(Repo, root.id), & &1.id) == [edited.revision.id, root.revision.id]
  end

  test "candidate save preserves head; review acceptance moves it exactly once" do
    key = "candidates-#{ID.v4()}"
    root = Screenplay.new()
    assert {:ok, _} = Persistence.create(Repo, key, root)

    session = %{
      screenplay_id: root.id,
      base_revision_id: root.revision.id,
      workflow: "develop",
      request: %{"brief" => "A banker follows the wrong person."},
      status: "open"
    }

    assert {:ok, session} = Persistence.save_session(Repo, session)
    assert {:error, :stale_session} = Persistence.save_session(Repo, %{session | lock_version: 0})

    op = %{
      "kind" => "insert_scene",
      "value" => %{
        "after_scene_id" => nil,
        "scene" => %{
          "local_id" => "new:one",
          "heading" => "EXT. STATION - NIGHT",
          "elements" => [
            %{"local_id" => "new:action", "type" => "action", "text" => "Mara misses the last train.", "attrs" => %{}}
          ]
        }
      }
    }

    assert {:ok, materialized, changes} = Screenplay.apply(root, [op], [])

    candidate = %{
      screenplay: materialized,
      label: "Missed train",
      change_groups: [%{"id" => "scene", "operations" => changes.operations}]
    }

    assert {:ok, candidate} = Persistence.save_candidate(Repo, session.id, candidate)
    assert {:ok, still_root} = Persistence.load(Repo, key)
    assert still_root.revision.id == root.revision.id
    assert {:ok, _} = Persistence.load_revision(Repo, root.id, materialized.revision.id)

    {approval, authority} = direct_approval(candidate.id)
    wrong_content = %{approval | content_hash: "wrong"}

    assert {:error, :approval_content_mismatch} =
             Persistence.accept_candidate(Repo, candidate.id, approval: wrong_content, authority: authority)

    assert {:ok, accepted} =
             Persistence.accept_candidate(Repo, candidate.id, approval: approval, authority: authority)

    assert accepted.revision.id == materialized.revision.id
    assert {:ok, head} = Persistence.load(Repo, key)
    assert head.revision.id == materialized.revision.id

    assert {:ok, repeated} =
             Persistence.accept_candidate(Repo, candidate.id, approval: approval, authority: authority)

    assert repeated.revision.id == accepted.revision.id

    changed_review = %{approval.review | findings: [%{"kind" => "changed-after-retry"}]}
    changed_same_id = %{approval | review: changed_review}
    assert {:error, :approval_identity_conflict} =
             Persistence.accept_candidate(Repo, candidate.id, approval: changed_same_id, authority: authority)

    {other, other_authority} = direct_approval(candidate.id, :human, "another-writer")
    assert {:error, :acceptance_identity_conflict} =
             Persistence.accept_candidate(Repo, candidate.id, approval: other, authority: other_authority)

    assert {:error, :already_accepted} = Persistence.reject_candidate(Repo, candidate.id, actor: "writer")
  end

  test "failed candidate insert rolls back its revision and preserves the accepted head" do
    key = "candidate-rollback-#{ID.v4()}"

    root =
      Screenplay.new(
        scenes: [
          %{heading: "INT. ROOM - DAY", elements: [%{type: :action, text: "Mara waits."}]}
        ]
      )

    assert {:ok, _} = Persistence.create(Repo, key, root)

    assert {:ok, session} =
             Persistence.save_session(Repo, %{
               screenplay_id: root.id,
               base_revision_id: root.revision.id,
               workflow: "pass",
               request: %{},
               status: "open"
             })

    line = Enum.find(root.ir.elements, &(&1.type == :action))

    assert {:ok, draft, _} =
             Screenplay.apply(root, [
               %{
                 "kind" => "replace_text",
                 "target" => %{"kind" => "element", "id" => line.id},
                 "value" => "Mara leaves."
               }
             ], [])

    assert_raise Postgrex.Error, fn ->
      Persistence.save_candidate(Repo, session.id, %{
        screenplay: draft,
        parent_candidate_id: ID.v4()
      })
    end

    assert {:error, :not_found} = Persistence.load_revision(Repo, root.id, draft.revision.id)
    assert Persistence.candidates_for_session(Repo, session.id) == []
    assert {:ok, accepted} = Persistence.load(Repo, key)
    assert accepted.revision.id == root.revision.id
  end

  test "an exact pending candidate replay attaches the required-check snapshot after upgrade" do
    root = Screenplay.new()
    key = "pending-upgrade-#{ID.v4()}"
    assert {:ok, _} = Persistence.create(Repo, key, root)

    assert {:ok, session} =
             Persistence.save_session(Repo, %{
               screenplay_id: root.id,
               base_revision_id: root.revision.id,
               workflow: "pass",
               request: %{},
               status: "open"
             })

    operation = %{
      "kind" => "insert_scene",
      "value" => %{
        "after_scene_id" => nil,
        "scene" => %{
          "local_id" => "new:scene",
          "heading" => "INT. ROOM - DAY",
          "elements" => [
            %{"local_id" => "new:action", "type" => "action", "text" => "Mara waits.", "attrs" => %{}}
          ]
        }
      }
    }

    assert {:ok, draft, _} = Screenplay.apply(root, [operation], [])
    input = %{id: ID.v4(), screenplay: draft, label: "Legacy pending"}
    assert {:ok, candidate} = Persistence.save_candidate(Repo, session.id, input)

    SQL.query!(
      Repo,
      "UPDATE writing_candidates SET required_checks='[]'::jsonb,check_set_fingerprint=NULL WHERE id=$1::text::uuid",
      [candidate.id],
      log: false
    )

    assert {:ok, replayed} = Persistence.save_candidate(Repo, session.id, input)
    assert replayed.id == candidate.id
    assert {:ok, stored} = Persistence.candidate(Repo, candidate.id)
    assert is_binary(stored["check_set_fingerprint"])
    assert {:error, :candidate_identity_conflict} =
             Persistence.save_candidate(Repo, session.id, %{input | label: "Changed payload"})

    changed_revision_metadata = %{draft | revision: %{draft.revision | actor: "forged-replay"}}
    assert {:error, :candidate_identity_conflict} =
             Persistence.save_candidate(Repo, session.id, %{input | screenplay: changed_revision_metadata})

    {approval, authority} = direct_approval(candidate.id)
    assert {:ok, _} = Persistence.accept_candidate(Repo, candidate.id, approval: approval, authority: authority)

    SQL.query!(
      Repo,
      "UPDATE writing_candidates SET required_checks='[]'::jsonb,check_set_fingerprint=NULL WHERE id=$1::text::uuid",
      [candidate.id],
      log: false
    )

    assert {:error, :candidate_identity_conflict} = Persistence.save_candidate(Repo, session.id, input)
    assert {:ok, historical} = Persistence.candidate(Repo, candidate.id)
    assert historical["check_set_fingerprint"] == nil

    assert {:ok, head} = Persistence.load(Repo, key)
    assert head.revision.id == draft.revision.id
  end

  test "imported Fountain bytes survive a round trip through PostgreSQL" do
    raw = "Title: The Debt\r\n\r\nINT. VAULT - NIGHT\r\n\r\nMARA\r\nGive me the clé.\r\n"
    key = "fountain-#{ID.v4()}"
    root = raw |> Fount.parse!() |> Screenplay.from_document(cast_resolution: :literal_cues)
    assert {:ok, _} = Persistence.create(Repo, key, root)
    assert {:ok, loaded} = Persistence.load(Repo, key)
    assert Screenplay.to_fountain(loaded) == raw
    assert length(loaded.ir.dialogue_blocks) == 1
    assert length(Fount.Query.characters(loaded)) == 1
  end

  test "a report cannot cite uninspected evidence or a changed excerpt" do
    root =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [
              %{type: :action, text: "Mara pockets the key."}
            ]
          }
        ]
      )

    assert {:ok, _} = Persistence.create(Repo, "report-#{ID.v4()}", root)
    line = Enum.find(root.ir.elements, &(&1.type == :action))

    evidence = %{
      "evidence_id" => "e1",
      "screenplay_id" => root.id,
      "revision_id" => root.revision.id,
      "target" => %{"kind" => "element", "id" => line.id},
      "excerpt" => line.text
    }

    base = %{
      screenplay_id: root.id,
      primary_revision_id: root.revision.id,
      tool: "continuity",
      fingerprint: "probe-v1",
      payload: %{"evidence" => [evidence], "citations" => ["e1"]}
    }

    assert {:ok, _} = Persistence.save_report(Repo, base)

    assert {:error, :uninspected_citation} =
             Persistence.save_report(
               Repo,
               %{base | payload: %{"evidence" => [evidence], "citations" => ["missing"]}}
             )

    assert {:error, :evidence_excerpt_mismatch} =
             Persistence.save_report(
               Repo,
               %{base | payload: %{"evidence" => [%{evidence | "excerpt" => "Mara drops the key."}]}}
             )
  end

  test "acceptance rejects a sibling report even when candidate lineage claims its revision" do
    root = Screenplay.new(scenes: [%{heading: "INT. ROOM - DAY", elements: [%{type: :action, text: "Mara waits."}]}])
    key = "report-lineage-#{ID.v4()}"
    assert {:ok, _} = Persistence.create(Repo, key, root)

    assert {:ok, session} =
             Persistence.save_session(Repo, %{
               screenplay_id: root.id,
               base_revision_id: root.revision.id,
               workflow: "pass",
               request: %{},
               status: "open"
             })

    line = Enum.find(root.ir.elements, &(&1.type == :action))

    op = fn text ->
      %{"kind" => "replace_text", "target" => %{"kind" => "element", "id" => line.id}, "value" => text}
    end

    assert {:ok, chosen, _} = Screenplay.apply(root, [op.("Mara leaves.")], [])
    assert {:ok, sibling, _} = Screenplay.apply(root, [op.("Mara hides.")], [])
    assert {:ok, _} = Persistence.save_candidate(Repo, session.id, %{screenplay: sibling})

    assert {:ok, report} =
             Persistence.save_report(Repo, %{
               screenplay_id: root.id,
               primary_revision_id: sibling.revision.id,
               session_id: session.id,
               tool: "continuity",
               fingerprint: "sibling-report",
               payload: %{"evidence" => []}
             })

    assert {:ok, candidate} =
             Persistence.save_candidate(Repo, session.id, %{
               screenplay: chosen,
               lineage: [%{"source_revision_id" => sibling.revision.id}],
               provenance: %{"report_ids" => [report.id]}
             })

    {approval, authority} = direct_approval(candidate.id)

    assert {:error, :report_lineage_mismatch} =
             Persistence.accept_candidate(Repo, candidate.id, approval: approval, authority: authority)

    assert {:ok, head} = Persistence.load(Repo, key)
    assert head.revision.id == root.revision.id
  end

  test "acceptance permits a report on its own candidate result" do
    root = Screenplay.new(scenes: [%{heading: "INT. ROOM - DAY", elements: [%{type: :action, text: "Mara waits."}]}])
    key = "result-report-#{ID.v4()}"
    assert {:ok, _} = Persistence.create(Repo, key, root)

    assert {:ok, session} =
             Persistence.save_session(Repo, %{
               screenplay_id: root.id,
               base_revision_id: root.revision.id,
               workflow: "pass",
               request: %{},
               status: "open"
             })

    line = Enum.find(root.ir.elements, &(&1.type == :action))

    operation = %{
      "kind" => "replace_text",
      "target" => %{"kind" => "element", "id" => line.id},
      "value" => "Mara leaves."
    }

    assert {:ok, result, _} = Screenplay.apply(root, [operation], [])

    assert {:ok, report} =
             Persistence.save_report(
               Repo,
               %{
                 screenplay_id: root.id,
                 primary_revision_id: result.revision.id,
                 session_id: session.id,
                 tool: "continuity",
                 fingerprint: "own-result",
                 payload: %{"evidence" => []}
               },
               source_models: [result]
             )

    assert {:ok, candidate} =
             Persistence.save_candidate(Repo, session.id, %{
               screenplay: result,
               provenance: %{"report_ids" => [report.id]}
             })

    {approval, authority} = direct_approval(candidate.id)

    assert {:ok, accepted} =
             Persistence.accept_candidate(Repo, candidate.id, approval: approval, authority: authority)

    assert accepted.revision.id == result.revision.id
  end
  test "human agent and service principals advance canon only through typed approval audit" do
    Enum.each([:human, :agent, :service], fn type ->
      root = Screenplay.new()
      key = "principal-#{type}-#{ID.v4()}"
      assert {:ok, _} = Persistence.create(Repo, key, root, actor: "fixture-genesis")
      assert {:ok, session} = Persistence.save_session(Repo, %{
        screenplay_id: root.id, base_revision_id: root.revision.id, workflow: "pass", request: %{}, status: "open"
      })
      op = %{"kind" => "insert_scene", "value" => %{"after_scene_id" => nil, "scene" => %{
        "local_id" => "new:scene", "heading" => "INT. ROOM - DAY",
        "elements" => [%{"local_id" => "new:action", "type" => "action", "text" => "Mara waits.", "attrs" => %{}}]
      }}}
      assert {:ok, draft, _} = Screenplay.apply(root, [op], [])
      assert {:ok, candidate} = Persistence.save_candidate(Repo, session.id, %{screenplay: draft})
      {approval, authority} = direct_approval(candidate.id, type, "#{type}-approver")
      assert {:ok, accepted} = Persistence.accept_candidate(Repo, candidate.id, approval: approval, authority: authority)
      assert accepted.revision.id == draft.revision.id

      row = Ecto.Adapters.SQL.query!(Repo,
        "SELECT acceptance_kind,approver_type,approver_id,reviewer_type,reviewer_id,approval_hash FROM acceptances WHERE approval_id=$1::text::uuid",
        [approval.id], log: false)
      assert [["approved", principal_type, approver_id, reviewer_type, reviewer_id, approval_hash]] = row.rows
      assert principal_type == to_string(type)
      assert reviewer_type == principal_type
      assert approver_id == "#{type}-approver"
      assert reviewer_id == approver_id
      assert approval_hash == Fount.Writing.Approval.fingerprint(approval)
    end)
  end

  test "forged authority and missing required checks cannot advance canon" do
    root = Screenplay.new()
    key = "authority-#{ID.v4()}"
    assert {:ok, _} = Persistence.create(Repo, key, root)

    semantic = %{"id" => "story-truth", "kind" => "semantic", "target" => %{"kind" => "screenplay", "id" => root.id},
      "spec" => %{"proposition" => "The reveal reads clearly", "expected" => true}, "severity" => "required"}
    assert {:ok, session} = Persistence.save_session(Repo, %{
      screenplay_id: root.id, base_revision_id: root.revision.id, workflow: "pass",
      request: %{"constraints" => [semantic], "approval" => %{"overridable_constraint_ids" => ["story-truth"]}}, status: "open"
    })
    op = %{"kind" => "insert_scene", "value" => %{"after_scene_id" => nil, "scene" => %{
      "local_id" => "new:scene", "heading" => "INT. ROOM - DAY",
      "elements" => [%{"local_id" => "new:action", "type" => "action", "text" => "Mara waits.", "attrs" => %{}}]
    }}}
    assert {:ok, draft, _} = Screenplay.apply(root, [op], [])

    assert {:error, :missing_required_check} =
             Persistence.save_candidate(Repo, session.id, %{screenplay: draft, provenance: %{"constraints" => [semantic], "checks" => []}})
    assert {:error, :not_found} = Persistence.load_revision(Repo, root.id, draft.revision.id)

    check = %{"constraint_id" => "story-truth", "kind" => "semantic", "severity" => "required",
      "evaluation" => "semantic", "status" => "unknown"}
    advisory_substitution = %{check | "severity" => "advisory", "status" => "pass"}
    assert {:error, :missing_required_check} =
             Persistence.save_candidate(Repo, session.id, %{
               screenplay: draft,
               provenance: %{"constraints" => [semantic], "checks" => [advisory_substitution]}
             })

    passing = %{check | "status" => "pass"}
    failing_application = %{check | "status" => "fail"}
    assert {:error, :conflicting_check_results} =
             Persistence.save_candidate(Repo, session.id, %{
               screenplay: draft,
               provenance: %{
                 "constraints" => [semantic],
                 "checks" => [passing],
                 "application_checks" => [failing_application]
               }
             })

    assert {:ok, candidate} = Persistence.save_candidate(Repo, session.id, %{
      screenplay: draft, provenance: %{"constraints" => [semantic], "checks" => [check], "report_ids" => []}
    })

    {agent_approval, agent_authority} = direct_approval(candidate.id, :agent, "editor-agent")
    assert {:error, {:review_blockers, [_]}} =
             Persistence.accept_candidate(Repo, candidate.id, approval: agent_approval, authority: agent_authority)

    {agent_override, agent_override_authority} = direct_approval(candidate.id, :agent, "override-agent",
      overrides: [%{"constraint_id" => "story-truth", "reason" => "Agent tried to override"}])
    assert {:error, :automated_override_forbidden} =
             Persistence.accept_candidate(Repo, candidate.id, approval: agent_override, authority: agent_override_authority)

    {approval, authority} = direct_approval(candidate.id, :human, "owner",
      overrides: [%{"constraint_id" => "story-truth", "reason" => "Writer reviewed the ambiguity"}])

    forged_review = %{approval.review | check_set_fingerprint: String.duplicate("0", 64)}
    assert {:error, :review_check_set_mismatch} =
             Persistence.accept_candidate(Repo, candidate.id, approval: %{approval | review: forged_review}, authority: authority)

    forged_reports = %{approval.review | report_ids: [ID.v4()]}
    assert {:error, :review_reports_mismatch} =
             Persistence.accept_candidate(Repo, candidate.id, approval: %{approval | review: forged_reports}, authority: authority)

    assert {:error, :approval_candidate_mismatch} =
             Persistence.accept_candidate(Repo, candidate.id, approval: %{approval | candidate_id: ID.v4()}, authority: authority)

    assert {:error, :approval_base_mismatch} =
             Persistence.accept_candidate(Repo, candidate.id, approval: %{approval | base_revision_id: ID.v4()}, authority: authority)

    {:ok, intruder} = Principal.new(:human, "intruder")
    {:ok, forged_authority} = Authority.new(intruder, root.id, [:approve])
    assert {:error, :authority_principal_mismatch} =
             Persistence.accept_candidate(Repo, candidate.id, approval: approval, authority: forged_authority)
    assert {:ok, unchanged} = Persistence.load(Repo, key)
    assert unchanged.revision.id == root.revision.id
    audit_before = Ecto.Adapters.SQL.query!(Repo, "SELECT count(*) FROM acceptances WHERE screenplay_id=$1::text::uuid", [root.id], log: false)
    assert [[1]] = audit_before.rows

    assert {:ok, accepted} = Persistence.accept_candidate(Repo, candidate.id, approval: approval, authority: authority)
    assert accepted.revision.id == draft.revision.id
  end

end
