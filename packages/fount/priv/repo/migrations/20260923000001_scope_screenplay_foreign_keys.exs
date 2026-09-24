defmodule Fount.Repo.Migrations.ScopeScreenplayForeignKeys do
  use Ecto.Migration

  def change do
    for table <- [:revisions, :scenes, :dialogue_turns, :elements, :characters, :title_entries] do
      create unique_index(table, [:screenplay_id, :id])
    end

    foreign_key(:screenplays, :screenplay_head_scope_fk, [:id, :current_revision_id], :revisions, [:screenplay_id, :id])
    foreign_key(:revisions, :revision_parent_scope_fk, [:screenplay_id, :parent_id], :revisions, [:screenplay_id, :id])
    foreign_key(:scenes, :scene_heading_scope_fk, [:screenplay_id, :heading_element_id], :elements, [:screenplay_id, :id])
    foreign_key(:dialogue_turns, :turn_scene_scope_fk, [:screenplay_id, :scene_id], :scenes, [:screenplay_id, :id])
    foreign_key(:dialogue_turns, :turn_cue_scope_fk, [:screenplay_id, :cue_element_id], :elements, [:screenplay_id, :id])
    foreign_key(:dialogue_turns, :turn_dual_scope_fk, [:screenplay_id, :dual_with_id], :dialogue_turns, [:screenplay_id, :id])
    foreign_key(:elements, :element_scene_scope_fk, [:screenplay_id, :scene_id], :scenes, [:screenplay_id, :id])
    foreign_key(:elements, :element_turn_scope_fk, [:screenplay_id, :turn_id], :dialogue_turns, [:screenplay_id, :id])
    foreign_key(:character_aliases, :alias_character_scope_fk, [:screenplay_id, :character_id], :characters, [:screenplay_id, :id])
    foreign_key(:mentions, :mention_element_scope_fk, [:screenplay_id, :element_id], :elements, [:screenplay_id, :id])
    foreign_key(:mentions, :mention_character_scope_fk, [:screenplay_id, :character_id], :characters, [:screenplay_id, :id])
    foreign_key(:mentions, :mention_revision_scope_fk, [:screenplay_id, :model_revision_id], :revisions, [:screenplay_id, :id])
    foreign_key(:assertions, :assertion_revision_scope_fk, [:screenplay_id, :model_revision_id], :revisions, [:screenplay_id, :id])
    foreign_key(:import_artifacts, :artifact_revision_scope_fk, [:screenplay_id, :imported_model_revision_id], :revisions, [:screenplay_id, :id])
    foreign_key(:acceptances, :acceptance_result_scope_fk, [:screenplay_id, :resulting_revision_id], :revisions, [:screenplay_id, :id])
    foreign_key(:acceptances, :acceptance_base_scope_fk, [:screenplay_id, :base_revision_id], :revisions, [:screenplay_id, :id])
  end

  defp foreign_key(table, name, columns, parent, targets) do
    local = Enum.map_join(columns, ",", &to_string/1)
    remote = Enum.map_join(targets, ",", &to_string/1)

    execute(
      "ALTER TABLE #{table} ADD CONSTRAINT #{name} FOREIGN KEY (#{local}) REFERENCES #{parent}(#{remote}) DEFERRABLE INITIALLY DEFERRED",
      "ALTER TABLE #{table} DROP CONSTRAINT #{name}"
    )
  end
end
