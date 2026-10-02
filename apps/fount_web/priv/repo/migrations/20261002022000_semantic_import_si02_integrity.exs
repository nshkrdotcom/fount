defmodule FountWeb.Migrations.SemanticImportSI02Integrity do
  use Ecto.Migration

  def up do
    execute("""
    CREATE FUNCTION fount_web_guard_semantic_assessment() RETURNS trigger AS $$
    BEGIN
      IF ROW(NEW.id,NEW.owner_id,NEW.project_id,NEW.screenplay_id,NEW.revision_id,
             NEW.source_artifact_id,NEW.source_sha256,NEW.render_sha256,NEW.request_fingerprint,
             NEW.schema_version,NEW.prompt_version,NEW.parser_version,NEW.model,NEW.reasoning_effort,
             NEW.provider_family,NEW.origin,NEW.limits,NEW.command_id,NEW.supersedes_assessment_id,NEW.inserted_at)
         IS DISTINCT FROM
         ROW(OLD.id,OLD.owner_id,OLD.project_id,OLD.screenplay_id,OLD.revision_id,
             OLD.source_artifact_id,OLD.source_sha256,OLD.render_sha256,OLD.request_fingerprint,
             OLD.schema_version,OLD.prompt_version,OLD.parser_version,OLD.model,OLD.reasoning_effort,
             OLD.provider_family,OLD.origin,OLD.limits,OLD.command_id,OLD.supersedes_assessment_id,OLD.inserted_at)
         OR (OLD.run_id IS NOT NULL AND NEW.run_id IS DISTINCT FROM OLD.run_id) THEN
        RAISE EXCEPTION 'semantic assessment identity is immutable';
      END IF;
      IF OLD.status IN ('ready','partial','failed','cancelled') AND
         ROW(NEW.status,NEW.run_id,NEW.coverage,NEW.result,NEW.usage,NEW.provenance,
             NEW.provider_returned_model,NEW.error,NEW.completed_at)
         IS DISTINCT FROM
         ROW(OLD.status,OLD.run_id,OLD.coverage,OLD.result,OLD.usage,OLD.provenance,
             OLD.provider_returned_model,OLD.error,OLD.completed_at) THEN
        RAISE EXCEPTION 'terminal semantic assessment is immutable';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    execute("""
    CREATE TRIGGER zz_semantic_assessment_immutable
    AFTER UPDATE ON fount_web_semantic_assessments
    FOR EACH ROW EXECUTE FUNCTION fount_web_guard_semantic_assessment()
    """)

    execute("""
    CREATE FUNCTION fount_web_guard_semantic_review_history() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'semantic review history is append-only';
    END;
    $$ LANGUAGE plpgsql
    """)

    execute("""
    CREATE TRIGGER semantic_review_history_immutable
    BEFORE UPDATE ON fount_web_semantic_review_events
    FOR EACH ROW EXECUTE FUNCTION fount_web_guard_semantic_review_history()
    """)
  end

  def down do
    execute(
      "DROP TRIGGER IF EXISTS semantic_review_history_immutable ON fount_web_semantic_review_events"
    )

    execute("DROP FUNCTION IF EXISTS fount_web_guard_semantic_review_history()")

    execute(
      "DROP TRIGGER IF EXISTS zz_semantic_assessment_immutable ON fount_web_semantic_assessments"
    )

    execute("DROP FUNCTION IF EXISTS fount_web_guard_semantic_assessment()")
  end
end
