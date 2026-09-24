defmodule Fount.Persistence.Schema.Screenplay do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "screenplays" do
    field(:key, :string)
    field(:current_revision_id, Ecto.UUID)
    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Fount.Persistence.Schema.Revision do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "revisions" do
    field(:screenplay_id, Ecto.UUID)
    field(:parent_id, Ecto.UUID)
    field(:model, :map)
    field(:model_sha256, :string)
    field(:actor, :string)
    field(:message, :string)
    timestamps(updated_at: false, type: :utc_datetime_usec)
  end
end

defmodule Fount.Persistence.Schema.TitleEntry do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "title_entries" do
    field(:screenplay_id, Ecto.UUID)
    field(:ordinal, :integer)
    field(:key, :string)
    field(:values, {:array, :string})
  end
end

defmodule Fount.Persistence.Schema.Scene do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "scenes" do
    field(:screenplay_id, Ecto.UUID)
    field(:ordinal, :integer)
    field(:heading_element_id, Ecto.UUID)
    field(:scene_number, :string)
    field(:omitted, :boolean)
    field(:location_head, :string)
    field(:location_parts, {:array, :string})
    field(:time_of_day, :string)
  end
end

defmodule Fount.Persistence.Schema.DialogueTurn do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "dialogue_turns" do
    field(:screenplay_id, Ecto.UUID)
    field(:scene_id, Ecto.UUID)
    field(:cue_element_id, Ecto.UUID)
    field(:ordinal, :integer)
    field(:dual_with_id, Ecto.UUID)
  end
end

defmodule Fount.Persistence.Schema.Element do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "elements" do
    field(:screenplay_id, Ecto.UUID)
    field(:scene_id, Ecto.UUID)
    field(:turn_id, Ecto.UUID)
    field(:ordinal, :integer)
    field(:type, :string)
    field(:text, :string)
    field(:attrs, :map)
  end
end

defmodule Fount.Persistence.Schema.Character do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "characters" do
    field(:screenplay_id, Ecto.UUID)
    field(:display_name, :string)
    field(:notes, :string)
    field(:attributes, :map)
  end
end

defmodule Fount.Persistence.Schema.CharacterAlias do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "character_aliases" do
    field(:screenplay_id, Ecto.UUID)
    field(:character_id, Ecto.UUID)
    field(:alias, :string)
    field(:normalized_alias, :string)
    field(:kind, :string)
  end
end

defmodule Fount.Persistence.Schema.Mention do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "mentions" do
    field(:screenplay_id, Ecto.UUID)
    field(:element_id, Ecto.UUID)
    field(:character_id, Ecto.UUID)
    field(:role, :string)
    field(:status, :string)
    field(:surface, :string)
    field(:byte_start, :integer)
    field(:byte_end, :integer)
    field(:model_revision_id, Ecto.UUID)
    field(:producer, :string)
    field(:confidence, :float)
  end
end

defmodule Fount.Persistence.Schema.MentionCandidate do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "mention_candidates" do
    field(:screenplay_id, Ecto.UUID)
    field(:mention_id, Ecto.UUID)
    field(:character_id, Ecto.UUID)
  end
end

defmodule Fount.Persistence.Schema.Assertion do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "assertions" do
    field(:screenplay_id, Ecto.UUID)
    field(:namespace, :string)
    field(:kind, :string)
    field(:target_kind, :string)
    field(:target_id, Ecto.UUID)
    field(:value, :map)
    field(:model_revision_id, Ecto.UUID)
    field(:producer, :string)
    field(:confidence, :float)
    field(:dependencies, {:array, Ecto.UUID})
    field(:authored, :boolean)
  end
end

defmodule Fount.Persistence.Schema.ImportArtifact do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "import_artifacts" do
    field(:screenplay_id, Ecto.UUID)
    field(:format, :string)
    field(:original_bytes, :binary)
    field(:bytes_sha256, :string)
    field(:imported_model_revision_id, Ecto.UUID)
    field(:fidelity, :map)
    timestamps(updated_at: false, type: :utc_datetime_usec)
  end
end

defmodule Fount.Persistence.Schema.Acceptance do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "acceptances" do
    field(:screenplay_id, Ecto.UUID)
    field(:resulting_revision_id, Ecto.UUID)
    field(:base_revision_id, Ecto.UUID)
    field(:actor, :string)
    field(:provider, :string)
    field(:model, :string)
    field(:operations, {:array, :map})
    timestamps(updated_at: false, type: :utc_datetime_usec)
  end
end
