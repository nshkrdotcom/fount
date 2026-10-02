defmodule FountRun.Repo.Migrations.ProviderValidationAudit do
  use Ecto.Migration

  def change do
    alter table(:fount_run_provider_requests) do
      add(:validation_result, :map)
    end
  end
end
