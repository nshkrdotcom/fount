defmodule Fount.Repo.Migrations.CreateMentionCandidates do
  use Ecto.Migration

  def change do
    create unique_index(:mentions, [:screenplay_id, :id])

    create table(:mention_candidates, primary_key: false) do
      add :screenplay_id, references(:screenplays, type: :binary_id, on_delete: :delete_all), null: false

      add :mention_id,
          references(:mentions,
            type: :binary_id,
            with: [screenplay_id: :screenplay_id],
            on_delete: :delete_all
          ),
          null: false

      add :character_id,
          references(:characters,
            type: :binary_id,
            with: [screenplay_id: :screenplay_id],
            on_delete: :delete_all
          ),
          null: false
    end

    create unique_index(:mention_candidates, [:screenplay_id, :mention_id, :character_id])
    create index(:mention_candidates, [:screenplay_id, :character_id, :mention_id])

    execute(
      "INSERT INTO mention_candidates (screenplay_id, mention_id, character_id) SELECT screenplay_id, id, character_id FROM mentions WHERE status = 'suggested' AND character_id IS NOT NULL",
      "DELETE FROM mention_candidates WHERE mention_id IN (SELECT id FROM mentions WHERE status = 'suggested' AND character_id IS NOT NULL)"
    )
  end
end
