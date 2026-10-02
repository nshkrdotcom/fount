defmodule FountRun.Repo.Migrations.ProviderRequestAudit do
  use Ecto.Migration

  def change do
    alter table(:fount_run_provider_requests) do
      add(:request_snapshot, :map, null: false, default: %{})
    end

    execute(
      "CREATE INDEX fount_run_provider_purpose ON fount_run_provider_requests ((request_snapshot->>'purpose'),intended_at)",
      "DROP INDEX fount_run_provider_purpose"
    )
  end
end
