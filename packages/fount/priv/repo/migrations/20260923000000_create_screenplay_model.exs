defmodule Fount.Repo.Migrations.CreateScreenplayModel do
  use Ecto.Migration

  def change do
    create table(:screenplays, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :text, null: false
      add :current_revision_id, :binary_id
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:screenplays, [:key])

    create table(:revisions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :screenplay_id, references(:screenplays, type: :binary_id, on_delete: :delete_all), null: false
      add :parent_id, references(:revisions, type: :binary_id)
      add :model, :map, null: false
      add :model_sha256, :text, null: false
      add :actor, :text
      add :message, :text
      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create index(:revisions, [:screenplay_id, :inserted_at])

    create table(:title_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :screenplay_id, references(:screenplays, type: :binary_id, on_delete: :delete_all), null: false
      add :ordinal, :integer, null: false
      add :key, :text, null: false
      add :values, {:array, :text}, null: false
    end

    create unique_index(:title_entries, [:screenplay_id, :ordinal])

    create table(:scenes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :screenplay_id, references(:screenplays, type: :binary_id, on_delete: :delete_all), null: false
      add :ordinal, :integer, null: false
      add :heading_element_id, :binary_id, null: false
      add :scene_number, :text
      add :omitted, :boolean, null: false, default: false
      add :location_head, :text
      add :location_parts, {:array, :text}, null: false, default: []
      add :time_of_day, :text
    end

    create unique_index(:scenes, [:screenplay_id, :ordinal])
    create index(:scenes, [:screenplay_id, :location_head])

    create table(:dialogue_turns, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :screenplay_id, references(:screenplays, type: :binary_id, on_delete: :delete_all), null: false
      add :scene_id, references(:scenes, type: :binary_id, on_delete: :delete_all), null: false
      add :cue_element_id, :binary_id, null: false
      add :ordinal, :integer, null: false
      add :dual_with_id, :binary_id
    end

    create unique_index(:dialogue_turns, [:screenplay_id, :ordinal])

    create table(:elements, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :screenplay_id, references(:screenplays, type: :binary_id, on_delete: :delete_all), null: false
      add :scene_id, references(:scenes, type: :binary_id, on_delete: :delete_all)
      add :turn_id, :binary_id
      add :ordinal, :integer, null: false
      add :type, :text, null: false
      add :text, :text, null: false
      add :attrs, :map, null: false, default: %{}
    end

    create unique_index(:elements, [:screenplay_id, :ordinal])
    create index(:elements, [:screenplay_id, :scene_id, :ordinal])
    create index(:elements, [:screenplay_id, :type, :ordinal])

    create table(:characters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :screenplay_id, references(:screenplays, type: :binary_id, on_delete: :delete_all), null: false
      add :display_name, :text, null: false
      add :notes, :text
      add :attributes, :map, null: false, default: %{}
    end

    create table(:character_aliases, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :screenplay_id, references(:screenplays, type: :binary_id, on_delete: :delete_all), null: false
      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all), null: false
      add :alias, :text, null: false
      add :normalized_alias, :text, null: false
      add :kind, :text, null: false
    end

    create unique_index(:character_aliases, [:character_id, :normalized_alias, :kind])
    create index(:character_aliases, [:screenplay_id, :normalized_alias])

    create table(:mentions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :screenplay_id, references(:screenplays, type: :binary_id, on_delete: :delete_all), null: false
      add :element_id, references(:elements, type: :binary_id, on_delete: :delete_all), null: false
      add :character_id, references(:characters, type: :binary_id, on_delete: :nilify_all)
      add :role, :text, null: false
      add :status, :text, null: false
      add :surface, :text, null: false
      add :byte_start, :integer, null: false
      add :byte_end, :integer, null: false
      add :model_revision_id, references(:revisions, type: :binary_id), null: false
      add :producer, :text, null: false
      add :confidence, :float
    end

    create index(:mentions, [:screenplay_id, :character_id, :role, :status])
    create index(:mentions, [:screenplay_id, :element_id, :byte_start])
    create constraint(:mentions, :valid_byte_span, check: "byte_start >= 0 AND byte_end > byte_start")
    create constraint(:mentions, :valid_confidence, check: "confidence IS NULL OR (confidence >= 0 AND confidence <= 1)")

    create table(:assertions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :screenplay_id, references(:screenplays, type: :binary_id, on_delete: :delete_all), null: false
      add :namespace, :text, null: false
      add :kind, :text, null: false
      add :target_kind, :text, null: false
      add :target_id, :binary_id, null: false
      add :value, :map, null: false
      add :model_revision_id, references(:revisions, type: :binary_id), null: false
      add :producer, :text, null: false
      add :confidence, :float
      add :dependencies, {:array, :binary_id}, null: false, default: []
      add :authored, :boolean, null: false, default: false
    end

    create index(:assertions, [:screenplay_id, :target_kind, :target_id, :namespace, :kind])
    create index(:assertions, [:screenplay_id, :namespace, :kind])

    create table(:import_artifacts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :screenplay_id, references(:screenplays, type: :binary_id, on_delete: :delete_all), null: false
      add :format, :text, null: false
      add :original_bytes, :binary, null: false
      add :bytes_sha256, :text, null: false
      add :imported_model_revision_id, references(:revisions, type: :binary_id), null: false
      add :fidelity, :map, null: false, default: %{}
      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create unique_index(:import_artifacts, [:screenplay_id, :bytes_sha256, :format])

    create table(:acceptances, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :screenplay_id, references(:screenplays, type: :binary_id, on_delete: :delete_all), null: false
      add :resulting_revision_id, references(:revisions, type: :binary_id), null: false
      add :base_revision_id, references(:revisions, type: :binary_id), null: false
      add :actor, :text
      add :provider, :text
      add :model, :text
      add :operations, {:array, :map}, null: false, default: []
      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create unique_index(:acceptances, [:screenplay_id, :resulting_revision_id])

    execute("ALTER TABLE screenplays ADD CONSTRAINT screenplay_head_fk FOREIGN KEY (current_revision_id) REFERENCES revisions(id) DEFERRABLE INITIALLY DEFERRED", "ALTER TABLE screenplays DROP CONSTRAINT screenplay_head_fk")
    execute("ALTER TABLE scenes ADD CONSTRAINT scene_heading_fk FOREIGN KEY (heading_element_id) REFERENCES elements(id) DEFERRABLE INITIALLY DEFERRED", "ALTER TABLE scenes DROP CONSTRAINT scene_heading_fk")
    execute("ALTER TABLE dialogue_turns ADD CONSTRAINT dialogue_cue_fk FOREIGN KEY (cue_element_id) REFERENCES elements(id) DEFERRABLE INITIALLY DEFERRED", "ALTER TABLE dialogue_turns DROP CONSTRAINT dialogue_cue_fk")
    execute("ALTER TABLE elements ADD CONSTRAINT element_turn_fk FOREIGN KEY (turn_id) REFERENCES dialogue_turns(id) DEFERRABLE INITIALLY DEFERRED", "ALTER TABLE elements DROP CONSTRAINT element_turn_fk")
  end
end
