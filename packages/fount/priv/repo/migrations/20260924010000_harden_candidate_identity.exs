defmodule Fount.Repo.Migrations.HardenCandidateIdentity do
  use Ecto.Migration
  def up do
    alter table(:writing_candidates) do
      add :payload_hash, :text
      add :review_hash, :text
    end
    execute "CREATE UNIQUE INDEX acceptance_candidate_once ON acceptances(candidate_id) WHERE candidate_id IS NOT NULL"
    execute "ALTER TABLE writing_sessions ADD CONSTRAINT session_lock_positive CHECK(lock_version > 0)"
    execute ~S"""
    CREATE FUNCTION fount_check_projection() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF TG_TABLE_NAME = 'scenes' THEN
        IF NOT EXISTS (SELECT 1 FROM elements e WHERE e.screenplay_id=NEW.screenplay_id AND e.revision_id=NEW.revision_id AND e.id=NEW.heading_element_id AND e.scene_id=NEW.id AND e.type='scene_heading') THEN
          RAISE EXCEPTION 'scene heading type or membership mismatch';
        END IF;
      ELSE
        IF NOT EXISTS (SELECT 1 FROM elements e WHERE e.screenplay_id=NEW.screenplay_id AND e.revision_id=NEW.revision_id AND e.id=NEW.cue_element_id AND e.dialogue_block_id=NEW.id AND e.type='character' AND e.scene_id IS NOT DISTINCT FROM NEW.scene_id) THEN
          RAISE EXCEPTION 'dialogue cue type or membership mismatch';
        END IF;
        IF NEW.dual_with_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dialogue_blocks b WHERE b.screenplay_id=NEW.screenplay_id AND b.revision_id=NEW.revision_id AND b.id=NEW.dual_with_id AND b.dual_with_id=NEW.id AND b.side<>NEW.side AND b.scene_id IS NOT DISTINCT FROM NEW.scene_id) THEN
          RAISE EXCEPTION 'asymmetric or cross-scene dual dialogue';
        END IF;
      END IF;
      RETURN NEW;
    END $$
    """
    execute "CREATE CONSTRAINT TRIGGER scene_projection_valid AFTER INSERT OR UPDATE ON scenes DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION fount_check_projection()"
    execute "CREATE CONSTRAINT TRIGGER dialogue_projection_valid AFTER INSERT OR UPDATE ON dialogue_blocks DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION fount_check_projection()"
  end
  def down do
    execute "DROP TRIGGER dialogue_projection_valid ON dialogue_blocks"
    execute "DROP TRIGGER scene_projection_valid ON scenes"
    execute "DROP FUNCTION fount_check_projection()"
    execute "ALTER TABLE writing_sessions DROP CONSTRAINT session_lock_positive"
    execute "DROP INDEX acceptance_candidate_once"
    alter table(:writing_candidates) do
      remove :review_hash
      remove :payload_hash
    end
  end
end
