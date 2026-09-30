defmodule FountWeb.AnalysisFixtures do
  @moduledoc false
  alias Ecto.Adapters.SQL
  alias Fount.Persistence.Analysis

  def persist_packet(screenplay, status, suffix, opts \\ []) do
    run_id = Fount.ID.v4()
    spec_sha = String.duplicate("b", 64)
    contract_sha = String.duplicate("c", 64)
    evidence_sha = String.duplicate("d", 64)
    provider = Keyword.get(opts, :provider, %{"provider" => "sandbox", "model" => "fixture"})
    evidence_id = Keyword.get(opts, :evidence_id, "evidence-#{suffix}")

    target = %{
      "kind" => "scene",
      "id" => screenplay.ir.scenes |> hd() |> Map.fetch!(:id),
      "screenplay_id" => screenplay.id,
      "revision_id" => screenplay.revision.id
    }

    {:ok, _} =
      Analysis.start_run(Fount.Repo, %{
        id: run_id,
        screenplay_id: screenplay.id,
        revision_id: screenplay.revision.id,
        revision_content_sha256: screenplay.revision.content_hash,
        playbook: "phase06-fixture",
        playbook_sha256: String.duplicate("a", 64),
        status: "running",
        concern: %{"kind" => "phase06"},
        intent: %{"inspect" => true},
        scope: %{"scene_ids" => [target["id"]]},
        privacy_namespace: "phase06:#{screenplay.id}",
        preflight: %{},
        metadata: %{"fixture" => true}
      })

    if Keyword.get(opts, :observation, true) do
      records =
        Keyword.get(opts, :story_world_records, [
          %{
            "id" => "event-#{suffix}",
            "record_type" => "event",
            "label" => "Stored event #{suffix}",
            "subjects" => ["NORA"],
            "evidence_ids" => [evidence_id]
          }
        ])

      observation = %{
        id: "observation-#{suffix}-#{Fount.ID.v4()}",
        kind: "story_world",
        target: target,
        evidence: [
          %{
            "evidence_id" => evidence_id,
            "screenplay_id" => screenplay.id,
            "revision_id" => screenplay.revision.id,
            "target" => target
          }
        ],
        dependencies: [],
        provenance: %{"request_id" => "request-#{suffix}"},
        result: %{
          "id" => "result-#{suffix}",
          "provider_fingerprint" => provider,
          "measurement_spec_sha256" => spec_sha,
          "value" => %{"story_world_records" => records}
        },
        metadata: %{}
      }

      {:ok, _} =
        Analysis.save_observations(Fount.Repo, run_id, screenplay.id, screenplay.revision.id, [
          observation
        ])
    end

    if status != "running" do
      legacy = Keyword.get(opts, :legacy, false)

      packet = %{
        "id" => "packet-#{suffix}",
        "playbook" => "phase06-fixture",
        "source_revision" => screenplay.revision.id,
        "status" => status,
        "finding" => "Stored finding #{suffix}",
        "evidence" => [
          %{
            "evidence_id" => evidence_id,
            "target" => target,
            "revision_id" => screenplay.revision.id,
            "excerpt" => "Persisted evidence excerpt.",
            "excerpt_sha256" => evidence_sha
          }
        ],
        "diagnoses" => [
          %{
            "id" => "diagnosis-#{suffix}",
            "hypothesis" => "Stored hypothesis",
            "uncertainty" => "bounded"
          }
        ],
        "uncertainty" => ["Stored uncertainty"],
        "missing_evidence" => [],
        "coverage" => %{"observed" => Keyword.get(opts, :observed, 2), "possible" => 10},
        "provenance" => %{"measurement_spec_sha256" => spec_sha},
        "resource_usage" => %{}
      }

      attrs = %{
        status: status,
        resource_usage: %{},
        summary: %{"finding" => packet["finding"]},
        result: if(legacy, do: %{}, else: packet),
        metadata: %{"fixture" => true}
      }

      attrs =
        if legacy do
          attrs
        else
          Map.merge(attrs, %{
            output_contract_id: "writer-packet.v1",
            output_contract_sha256: contract_sha
          })
        end

      {:ok, _} = Analysis.finish_run(Fount.Repo, run_id, attrs)
    end

    %{id: run_id, revision_id: screenplay.revision.id}
  end

  def insert_usage(run, operation_id, resource, reserved, settled, knowledge, reconciliation) do
    settled_at = if reconciliation == "reserved", do: nil, else: DateTime.utc_now()

    SQL.query!(
      Fount.Repo,
      "INSERT INTO fount_run_usage(id,operation_id,run_id,screenplay_id,resource,reserved_quantity,settled_quantity,knowledge_state,reconciliation_state,settled_at,currency) VALUES($1::text::uuid,$2,$3::text::uuid,$4::text::uuid,$5,$6,$7,$8,$9,$10,$11)",
      [
        Fount.ID.v4(),
        operation_id <> "-" <> run["id"],
        run["id"],
        run["screenplay_id"],
        resource,
        reserved,
        settled,
        knowledge,
        reconciliation,
        settled_at,
        "USD"
      ]
    )
  end
end
