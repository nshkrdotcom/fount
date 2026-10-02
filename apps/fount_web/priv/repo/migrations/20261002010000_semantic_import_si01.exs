defmodule FountWeb.Migrations.SemanticImportSI01 do
  use Ecto.Migration

  def up do
    create table(:fount_web_semantic_assessments, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :owner_id, :text, null: false
      add :project_id, references(:fount_web_projects, type: :uuid, on_delete: :delete_all), null: false
      add :screenplay_id, references(:screenplays, type: :uuid, on_delete: :delete_all), null: false
      add :revision_id, :uuid, null: false
      add :source_artifact_id, :uuid
      add :source_sha256, :text, null: false
      add :render_sha256, :text, null: false
      add :request_fingerprint, :text, null: false
      add :schema_version, :text, null: false
      add :prompt_version, :text
      add :parser_version, :text, null: false
      add :model, :text
      add :reasoning_effort, :text
      add :provider_family, :text
      add :provider_returned_model, :text
      add :run_id, :uuid
      add :origin, :text, null: false
      add :status, :text, null: false
      add :coverage, :map, null: false, default: %{}
      add :result, :map, null: false, default: %{}
      add :usage, :map, null: false, default: %{}
      add :limits, :map, null: false, default: %{}
      add :provenance, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(
             :fount_web_semantic_assessments,
             [:owner_id, :project_id, :revision_id, :schema_version, :origin, :source_sha256],
             name: :semantic_assessment_source_identity
           )

    create index(
             :fount_web_semantic_assessments,
             [:owner_id, :project_id, :revision_id, :status, :inserted_at],
             name: :semantic_assessment_project_source_index
           )

    create constraint(:fount_web_semantic_assessments, :semantic_assessment_origin,
             check: "origin IN ('manual','model','deterministic_fixture','legacy_literal')"
           )

    create constraint(:fount_web_semantic_assessments, :semantic_assessment_schema_version,
             check: "schema_version IN ('source_inventory_v1','semantic_import_v1')"
           )

    create constraint(:fount_web_semantic_assessments, :semantic_assessment_status,
             check: "status IN ('queued','running','partial','ready','failed','cancelled')"
           )

    create constraint(:fount_web_semantic_assessments, :semantic_assessment_source_hash,
             check: "source_sha256 ~ '^[0-9a-f]{64}$' AND render_sha256 ~ '^[0-9a-f]{64}$'"
           )

    create table(:fount_web_semantic_entity_handles, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :owner_id, :text, null: false
      add :project_id, references(:fount_web_projects, type: :uuid, on_delete: :delete_all), null: false
      add :screenplay_id, references(:screenplays, type: :uuid, on_delete: :delete_all), null: false
      add :kind, :text, null: false
      add :created_origin, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(
             :fount_web_semantic_entity_handles,
             [:owner_id, :project_id, :id],
             name: :semantic_handle_owner_identity
           )

    create constraint(:fount_web_semantic_entity_handles, :semantic_handle_kind,
             check: "kind IN ('character','location','document_text','prop','organization','unknown')"
           )

    create table(:fount_web_semantic_assessment_entities, primary_key: false) do
      add :assessment_id,
          references(:fount_web_semantic_assessments, type: :uuid, on_delete: :delete_all),
          primary_key: true,
          null: false

      add :local_id, :text, primary_key: true, null: false
      add :handle_id, references(:fount_web_semantic_entity_handles, type: :uuid, on_delete: :nothing), null: false
      add :kind, :text, null: false
      add :label, :text, null: false
      add :payload, :map, null: false, default: %{}
      add :evidence, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:fount_web_semantic_assessment_entities, [:assessment_id, :handle_id],
             name: :semantic_assessment_handle_identity
           )

    create index(:fount_web_semantic_assessment_entities, [:handle_id, :kind],
             name: :semantic_entity_handle_kind_index
           )

    create constraint(:fount_web_semantic_assessment_entities, :semantic_assessment_entity_kind,
             check: "kind IN ('character','location','document_text','prop','organization','unknown')"
           )

    create table(:fount_web_semantic_review_events, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :owner_id, :text, null: false
      add :project_id, references(:fount_web_projects, type: :uuid, on_delete: :delete_all), null: false
      add :screenplay_id, references(:screenplays, type: :uuid, on_delete: :delete_all), null: false
      add :revision_id, :uuid, null: false
      add :assessment_id,
          references(:fount_web_semantic_assessments, type: :uuid, on_delete: :delete_all),
          null: false
      add :target_handle_id, references(:fount_web_semantic_entity_handles, type: :uuid, on_delete: :nothing)
      add :action, :text, null: false
      add :payload, :map, null: false, default: %{}
      add :expected_version, :bigint, null: false
      add :new_version, :bigint, null: false
      add :outcome, :text, null: false
      add :command_id, :text, null: false
      add :actor, :text, null: false
      add :provenance, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:fount_web_semantic_review_events, [:owner_id, :project_id, :command_id],
             name: :semantic_review_command_identity
           )

    create index(
             :fount_web_semantic_review_events,
             [:owner_id, :project_id, :assessment_id, :new_version, :inserted_at],
             name: :semantic_review_history_index
           )

    create constraint(:fount_web_semantic_review_events, :semantic_review_action,
             check:
               "action IN ('confirm','reject','change_type','merge','split','set_alias','resolve_occurrence','set_location_parent','set_time','undo')"
           )

    create constraint(:fount_web_semantic_review_events, :semantic_review_outcome,
             check: "outcome IN ('applied','conflict')"
           )

    create constraint(:fount_web_semantic_review_events, :semantic_review_versions,
             check: "expected_version >= 0 AND new_version >= 0"
           )

    execute(
      "ALTER TABLE fount_web_semantic_assessments ADD CONSTRAINT semantic_assessment_project_source_fk FOREIGN KEY (owner_id,project_id,screenplay_id) REFERENCES fount_web_projects(owner_id,id,screenplay_id)"
    )

    execute(
      "ALTER TABLE fount_web_semantic_assessments ADD CONSTRAINT semantic_assessment_revision_fk FOREIGN KEY (screenplay_id,revision_id) REFERENCES revisions(screenplay_id,id)"
    )

    execute(
      "ALTER TABLE fount_web_semantic_assessments ADD CONSTRAINT semantic_assessment_artifact_fk FOREIGN KEY (screenplay_id,source_artifact_id) REFERENCES import_artifacts(screenplay_id,id)"
    )

    execute(
      "ALTER TABLE fount_web_semantic_entity_handles ADD CONSTRAINT semantic_handle_project_source_fk FOREIGN KEY (owner_id,project_id,screenplay_id) REFERENCES fount_web_projects(owner_id,id,screenplay_id)"
    )

    execute(
      "ALTER TABLE fount_web_semantic_review_events ADD CONSTRAINT semantic_review_project_source_fk FOREIGN KEY (owner_id,project_id,screenplay_id) REFERENCES fount_web_projects(owner_id,id,screenplay_id)"
    )

    execute(
      "ALTER TABLE fount_web_semantic_review_events ADD CONSTRAINT semantic_review_revision_fk FOREIGN KEY (screenplay_id,revision_id) REFERENCES revisions(screenplay_id,id)"
    )
  end

  def down do
    drop table(:fount_web_semantic_review_events)
    drop table(:fount_web_semantic_assessment_entities)
    drop table(:fount_web_semantic_entity_handles)
    drop table(:fount_web_semantic_assessments)
  end
end
