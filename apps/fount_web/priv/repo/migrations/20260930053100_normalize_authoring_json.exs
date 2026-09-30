defmodule FountWeb.Repo.Migrations.NormalizeAuthoringJson do
  use Ecto.Migration

  def up do
    # Repair recovery sidecars written by the initial offline JSONB adapter.
    execute(
      "UPDATE fount_web_drafts SET identity_anchors = (identity_anchors #>> '{}')::jsonb WHERE jsonb_typeof(identity_anchors) = 'string'"
    )

    execute(
      "UPDATE fount_web_drafts SET last_valid_fidelity = (last_valid_fidelity #>> '{}')::jsonb WHERE jsonb_typeof(last_valid_fidelity) = 'string'"
    )
  end

  def down, do: :ok
end
