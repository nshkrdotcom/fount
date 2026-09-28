defmodule Fount.Persistence.Schema.Screenplay do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "screenplays" do
    field(:id, Ecto.UUID, primary_key: true)
    field(:key, :string)
    field(:head_revision_id, Ecto.UUID)
    field(:inserted_at, :utc_datetime_usec)
    field(:updated_at, :utc_datetime_usec)
  end
end

defmodule Fount.Persistence.Schema.Revision do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "revisions" do
    field(:id, Ecto.UUID, primary_key: true)
    field(:screenplay_id, Ecto.UUID)
    field(:parent_id, Ecto.UUID)
    field(:artifact_id, Ecto.UUID)
    field(:content_hash, :string)
    field(:render_hash, :string)
    field(:model, :map)
    field(:actor, :string)
    field(:message, :string)
    field(:format_version, :integer)
    field(:inserted_at, :utc_datetime_usec)
  end
end

defmodule Fount.Persistence.Schema.TitleEntry do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "title_entries" do
    field(:id, Ecto.UUID, primary_key: true)
    field(:screenplay_id, Ecto.UUID, primary_key: true)
    field(:revision_id, Ecto.UUID, primary_key: true)
    field(:ordinal, :integer)
    field(:key, :string)
    field(:values, {:array, :string})
  end
end

defmodule Fount.Persistence.Schema.Scene do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "scenes" do
    field(:id, Ecto.UUID, primary_key: true)
    field(:screenplay_id, Ecto.UUID, primary_key: true)
    field(:revision_id, Ecto.UUID, primary_key: true)
    field(:ordinal, :integer)
    field(:heading_element_id, Ecto.UUID)
    field(:scene_number, :string)
    field(:omitted, :boolean)
    field(:location_parts, {:array, :string})
    field(:time_of_day, :string)
  end
end

defmodule Fount.Persistence.Schema.DialogueBlock do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "dialogue_blocks" do
    field(:id, Ecto.UUID, primary_key: true)
    field(:screenplay_id, Ecto.UUID, primary_key: true)
    field(:revision_id, Ecto.UUID, primary_key: true)
    field(:ordinal, :integer)
    field(:scene_id, Ecto.UUID)
    field(:cue_element_id, Ecto.UUID)
    field(:dual_with_id, Ecto.UUID)
    field(:side, :string)
  end
end

defmodule Fount.Persistence.Schema.Element do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "elements" do
    field(:id, Ecto.UUID, primary_key: true)
    field(:screenplay_id, Ecto.UUID, primary_key: true)
    field(:revision_id, Ecto.UUID, primary_key: true)
    field(:ordinal, :integer)
    field(:scene_id, Ecto.UUID)
    field(:dialogue_block_id, Ecto.UUID)
    field(:type, :string)
    field(:text, :string)
    field(:raw_text, :string)
    field(:inline, Fount.Persistence.JSONValue)
    field(:attrs, :map)
    field(:source_reference, :map)
    field(:origin, :string)
  end
end

defmodule Fount.Persistence.Schema.Character do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "characters" do
    field(:id, Ecto.UUID, primary_key: true)
    field(:screenplay_id, Ecto.UUID, primary_key: true)
    field(:revision_id, Ecto.UUID, primary_key: true)
    field(:display_name, :string)
    field(:notes, :string)
    field(:attributes, :map)
  end
end

defmodule Fount.Persistence.Schema.Mention do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "mentions" do
    field(:id, Ecto.UUID, primary_key: true)
    field(:screenplay_id, Ecto.UUID, primary_key: true)
    field(:revision_id, Ecto.UUID, primary_key: true)
    field(:element_id, Ecto.UUID)
    field(:character_id, Ecto.UUID)
    field(:role, :string)
    field(:status, :string)
    field(:surface, :string)
    field(:byte_start, :integer)
    field(:byte_end, :integer)
    field(:producer, :string)
    field(:confidence, :float)
  end
end

defmodule Fount.Persistence.Schema.AuthoredItem do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "authored_items" do
    field(:id, Ecto.UUID, primary_key: true)
    field(:screenplay_id, Ecto.UUID, primary_key: true)
    field(:revision_id, Ecto.UUID, primary_key: true)
    field(:namespace, :string)
    field(:kind, :string)
    field(:target, :map)
    field(:value, :map)
    field(:dependencies, Fount.Persistence.JSONValue)
    field(:status, :string)
    field(:provenance, :map)
  end
end

defmodule Fount.Persistence.Schema.ImportArtifact do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "import_artifacts" do
    field(:id, Ecto.UUID, primary_key: true)
    field(:screenplay_id, Ecto.UUID)
    field(:format, :string)
    field(:original_bytes, :binary)
    field(:bytes_sha256, :string)
    field(:render_hash, :string)
    field(:fidelity, :map)
    field(:inserted_at, :utc_datetime_usec)
  end
end

defmodule Fount.Persistence.Schema.WritingSession do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "writing_sessions" do
    field(:id, Ecto.UUID, primary_key: true)
    field(:screenplay_id, Ecto.UUID)
    field(:base_revision_id, Ecto.UUID)
    field(:workflow, :string)
    field(:status, :string)
    field(:request, :map)
    field(:strategies, Fount.Persistence.JSONValue)
    field(:progress, :map)
    field(:provenance, :map)
    field(:lock_version, :integer)
  end
end

defmodule Fount.Persistence.Schema.WritingCandidate do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "writing_candidates" do
    field(:id, Ecto.UUID, primary_key: true)
    field(:screenplay_id, Ecto.UUID)
    field(:session_id, Ecto.UUID)
    field(:base_revision_id, Ecto.UUID)
    field(:result_revision_id, Ecto.UUID)
    field(:parent_candidate_id, Ecto.UUID)
    field(:label, :string)
    field(:strategy, :map)
    field(:change_groups, Fount.Persistence.JSONValue)
    field(:lineage, Fount.Persistence.JSONValue)
    field(:provenance, :map)
    field(:decision, :string)
    field(:decision_actor, :string)
    field(:payload_hash, :string)
    field(:review_hash, :string)
    field(:required_checks, Fount.Persistence.JSONValue)
    field(:check_set_fingerprint, :string)
    field(:approval_id, Ecto.UUID)
  end
end

defmodule Fount.Persistence.Schema.AnalysisReport do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "analysis_reports" do
    field(:id, Ecto.UUID, primary_key: true)
    field(:screenplay_id, Ecto.UUID)
    field(:primary_revision_id, Ecto.UUID)
    field(:session_id, Ecto.UUID)
    field(:tool, :string)
    field(:status, :string)
    field(:fingerprint, :string)
    field(:payload, :map)
  end
end

defmodule Fount.Persistence.Schema.Acceptance do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "acceptances" do
    field(:id, Ecto.UUID, primary_key: true)
    field(:screenplay_id, Ecto.UUID)
    field(:base_revision_id, Ecto.UUID)
    field(:result_revision_id, Ecto.UUID)
    field(:candidate_id, Ecto.UUID)
    field(:actor, :string)
    field(:origin, :string)
    field(:operations, Fount.Persistence.JSONValue)
    field(:provenance, :map)
    field(:review, :map)
    field(:acceptance_kind, :string)
    field(:approval_id, Ecto.UUID)
    field(:approval_hash, :string)
    field(:approval, :map)
    field(:approver_type, :string)
    field(:approver_id, :string)
    field(:reviewer_type, :string)
    field(:reviewer_id, :string)
    field(:review_hash, :string)
    field(:check_set_fingerprint, :string)
    field(:report_ids, Fount.Persistence.JSONValue)
    field(:run_id, Ecto.UUID)
    field(:run_policy_version, :integer)
    field(:run_policy_fingerprint, :string)
    field(:inserted_at, :utc_datetime_usec)
  end
end

defmodule Fount.Persistence.Schema.CharacterAlias do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "character_aliases" do
    field(:screenplay_id, Ecto.UUID, primary_key: true)
    field(:revision_id, Ecto.UUID, primary_key: true)
    field(:character_id, Ecto.UUID, primary_key: true)
    field(:normalized_alias, :string, primary_key: true)
    field(:kind, :string, primary_key: true)
    field(:alias, :string)
  end
end

defmodule Fount.Persistence.Schema.MentionCandidate do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "mention_candidates" do
    field(:screenplay_id, Ecto.UUID, primary_key: true)
    field(:revision_id, Ecto.UUID, primary_key: true)
    field(:mention_id, Ecto.UUID, primary_key: true)
    field(:character_id, Ecto.UUID, primary_key: true)
  end
end

defmodule Fount.Persistence.Schema.AnalysisAsset do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "analysis_assets" do
    field(:id, Ecto.UUID, primary_key: true)
    field(:screenplay_id, Ecto.UUID)
    field(:scope_id, :string)
    field(:kind, :string)
    field(:logical_id, :string)
    field(:trust, :string)
    field(:source, :map)
    field(:content, :map)
    field(:sha256, :string)
    field(:parent_id, Ecto.UUID)
    field(:enabled, :boolean)
    field(:inserted_at, :utc_datetime_usec)
  end
end

defmodule Fount.Persistence.Schema.AnalysisRun do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "analysis_runs" do
    field(:id, Ecto.UUID, primary_key: true)
    field(:screenplay_id, Ecto.UUID)
    field(:revision_id, Ecto.UUID)
    field(:revision_content_sha256, :string)
    field(:session_id, Ecto.UUID)
    field(:candidate_id, Ecto.UUID)
    field(:playbook, :string)
    field(:playbook_sha256, :string)
    field(:status, :string)
    field(:concern, :map)
    field(:intent, :map)
    field(:scope, :map)
    field(:privacy_namespace, :string)
    field(:output_contract_id, :string)
    field(:output_contract_sha256, :string)
    field(:preflight, :map)
    field(:resource_usage, :map)
    field(:summary, :map)
    field(:result, :map)
    field(:metadata, :map)
    field(:started_at, :utc_datetime_usec)
    field(:finished_at, :utc_datetime_usec)
    field(:inserted_at, :utc_datetime_usec)
  end
end

defmodule Fount.Persistence.Schema.AnalysisMeasurementResult do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "analysis_measurement_results" do
    field(:cache_key, :string, primary_key: true)
    field(:ordinal, :integer, primary_key: true)
    field(:result_id, :string)
    field(:privacy_namespace, :string)
    field(:measurement_spec_sha256, :string)
    field(:input_sha256, :string)
    field(:semantic_execution_sha256, :string)
    field(:output_contract_id, :string)
    field(:output_contract_sha256, :string)
    field(:provider_fingerprint, :map)
    field(:payload, :map)
    field(:inserted_at, :utc_datetime_usec)
    field(:last_accessed_at, :utc_datetime_usec)
    field(:access_count, :integer)
  end
end

defmodule Fount.Persistence.Schema.AnalysisObservation do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "analysis_observations" do
    field(:id, :string, primary_key: true)
    field(:analysis_run_id, Ecto.UUID)
    field(:screenplay_id, Ecto.UUID)
    field(:revision_id, Ecto.UUID)
    field(:request_id, :string)
    field(:result_id, :string)
    field(:kind, :string)
    field(:target, :map)
    field(:evidence, Fount.Persistence.JSONValue)
    field(:dependencies, Fount.Persistence.JSONValue)
    field(:payload, :map)
    field(:inserted_at, :utc_datetime_usec)
  end
end

defmodule Fount.Persistence.Schema.AnalysisDependency do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "analysis_dependencies" do
    field(:id, Ecto.UUID, primary_key: true)
    field(:screenplay_id, Ecto.UUID)
    field(:subject_kind, :string)
    field(:subject_id, :string)
    field(:dependency_key, :string)
    field(:analysis_run_id, Ecto.UUID)
    field(:inserted_at, :utc_datetime_usec)
  end
end