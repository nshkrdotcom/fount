Code.require_file("../support/scripted_completion.ex", __DIR__)

defmodule FountWorkshop.PhaseTenResumeHistoryTest do
  use ExUnit.Case, async: false

  alias Fount.{ID, Persistence, Repo, Screenplay}
  alias Fount.Persistence.Analysis
  alias Fount.Writing.CanonicalJSON
  alias FountWorkshop.{Candidate, Review, Session, Store}
  alias FountWorkshop.TestSupport.ScriptedCompletion

  setup_all do
    start_supervised!({Repo, url: System.fetch_env!("FOUNT_DATABASE_URL"), pool_size: 2})
    :ok
  end

  test "resume preserves a rejected branch, an unchosen branch, and durable analysis history" do
    base =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. SERVICE OFFICE - NIGHT",
            elements: [%{type: :action, text: "Mara keeps the sealed ledger under her coat."}]
          }
        ]
      )

    key = "phase-ten-resume-#{ID.v4()}"
    assert {:ok, _} = Persistence.create(Repo, key, base)
    action = List.last(base.ir.elements)

    request = %{
      "version" => 1,
      "workflow" => "alternatives",
      "mode" => "revise",
      "base_revision_id" => base.revision.id,
      "instruction" => "Make the choice visible without deciding for the writer.",
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "alternatives" => 2,
      "options" => %{}
    }

    strategies = [
      strategy("a", "Break the seal", "Mara breaks the seal and exposes the ledger."),
      strategy("b", "Hide the ledger", "Mara slips the ledger into the radiator housing.")
    ]

    session_id = ID.v4()
    store = Store.new(Repo)
    namespace = "phase-ten:#{base.id}"

    assert {:ok, session} =
             Store.call(store, :save_session, [
               %{
                 "id" => session_id,
                 "screenplay_id" => base.id,
                 "base_revision_id" => base.revision.id,
                 "workflow" => request["workflow"],
                 "request" => request,
                 "status" => "open",
                 "strategies" => strategies,
                 "progress" => %{
                   "branches" => %{},
                   "report_ids" => [],
                   "spent" => %{},
                   "preparation" => cached_preparation(base)
                 },
                 "provenance" => %{
                   "limits" => %{
                     "durable_analysis" => true,
                     "analysis_privacy_namespace" => namespace
                   },
                   "phase9_preflight" => %{"changes_canon" => false}
                 }
               }
             ])

    assert {:ok, first} =
             base
             |> Candidate.compile(proposal(base, action.id, "a", strategies |> hd() |> Map.fetch!("summary")))
             |> save_candidate(store, session_id)

    assert {:ok, second} =
             base
             |> Candidate.compile(
               proposal(base, action.id, "b", strategies |> List.last() |> Map.fetch!("summary"))
             )
             |> save_candidate(store, session_id)

    branches = %{
      "a" => %{"status" => "saved", "candidate_id" => first["id"], "needs_writer_review" => true},
      "b" => %{"status" => "saved", "candidate_id" => second["id"], "needs_writer_review" => true}
    }

    assert {:ok, _} =
             Store.call(store, :save_session, [
               session
               |> put_in(["progress", "branches"], branches)
               |> Map.put("status", "review_ready")
             ])

    assert {:ok, rejected} = Review.reject(Repo, first["id"], "fixture-writer")
    assert rejected["decision"] == "rejected"

    assert {:ok, run} =
             Analysis.start_run(Repo, %{
               "id" => ID.v4(),
               "screenplay_id" => base.id,
               "revision_id" => first["screenplay"].revision.id,
               "revision_content_sha256" => first["screenplay"].revision.content_hash,
               "session_id" => session_id,
               "candidate_id" => first["id"],
               "playbook" => "scene_doctor",
               "playbook_sha256" => CanonicalJSON.hash(%{"id" => "scene_doctor"}),
               "status" => "running",
               "concern" => %{"text" => "Keep the rejected advice auditable, not active."},
               "intent" => %{"workflow" => "alternatives"},
               "scope" => %{"candidate_id" => first["id"]},
               "privacy_namespace" => namespace,
               "preflight" => %{"changes_canon" => false},
               "metadata" => %{"fixture" => "phase_ten_resume_history"}
             })

    assert {:ok, _} =
             Analysis.finish_run(Repo, run["id"] || run[:id], %{
               "status" => "complete",
               "resource_usage" => %{"provider_requests" => 1},
               "summary" => %{"advice" => "Break the seal."},
               "result" => %{"status" => "complete", "candidate_id" => first["id"]},
               "metadata" => %{"decision" => "rejected_later_by_writer"}
             })

    before_runs = Analysis.runs_for_session(Repo, base.id, session_id)
    assert length(before_runs) == 1

    {:ok, script} = Agent.start_link(fn -> [] end)
    inference = Inference.Client.new!(adapter: ScriptedCompletion, adapter_opts: [script: script])
    services = %{store: store, inference: inference}

    assert {:ok, resumed} = Session.resume(session_id, services)
    assert resumed["status"] == "review_ready"
    assert Agent.get(script, & &1) == []

    assert {:ok, loaded} = Session.get(session_id, services)
    assert length(loaded["candidates"]) == 2

    decisions = Map.new(loaded["candidates"], &{&1["id"], &1["decision"]})
    assert decisions[first["id"]] == "rejected"
    assert is_nil(decisions[second["id"]])

    after_runs = Analysis.runs_for_session(Repo, base.id, session_id)
    assert Enum.map(after_runs, & &1["id"]) == Enum.map(before_runs, & &1["id"])
    assert hd(after_runs)["candidate_id"] == first["id"]
    assert hd(after_runs)["status"] == "complete"

    assert {:ok, head} = Persistence.load(Repo, key)
    assert head.revision.id == base.revision.id
  end

  defp save_candidate({:ok, candidate}, store, session_id),
    do: Store.call(store, :save_candidate, [session_id, candidate])

  defp save_candidate(error, _store, _session_id), do: error

  defp cached_preparation(base) do
    data = %{
      "writer_intelligence" => %{"status" => "not_run", "reason" => "resume_fixture"},
      "note_triage" => []
    }

    %{
      "status" => "complete",
      "context_sha256" => CanonicalJSON.hash(data),
      "context" => %{
        "data" => data,
        "evidence" => [],
        "selection" => %{"whole_screenplay" => true},
        "source_revision_ids" => [base.revision.id],
        "historical_revisions" => [],
        "historical" => false,
        "investigation_strategies" => nil
      }
    }
  end

  defp strategy(id, title, summary),
    do: %{
      "id" => id,
      "title" => title,
      "summary" => summary,
      "premise_of_change" => summary,
      "dramatic_mechanism" => title,
      "entry_state" => "Guarded",
      "exit_state" => "Exposed",
      "beats" => [summary],
      "preserves" => ["Writer decides which branch, if any, becomes canon."],
      "changes" => [title],
      "inventions" => [],
      "consequences" => [],
      "evidence_ids" => [],
      "open_questions" => []
    }

  defp proposal(base, action_id, strategy_id, text),
    do: %{
      "version" => 1,
      "base_revision_id" => base.revision.id,
      "strategy_id" => strategy_id,
      "summary" => text,
      "inventions" => [],
      "unresolved_questions" => [],
      "groups" => [
        %{
          "id" => "choice",
          "title" => "Visible choice",
          "reason" => "Keep two real alternatives available to the writer.",
          "depends_on" => [],
          "addresses_notes" => [],
          "evidence_ids" => [],
          "origin" => "generated_text",
          "operations" => [
            %{
              "kind" => "replace_text",
              "target" => %{"kind" => "element", "id" => action_id},
              "value" => text
            }
          ]
        }
      ]
    }
end
