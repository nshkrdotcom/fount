defmodule Fount.Revision do
  @moduledoc "Content revision identity."

  @enforce_keys [:id]
  defstruct [:id, :parent_id, :created_at, :actor, :message, :content_hash, :render_hash]

  @type t :: %__MODULE__{
          id: String.t(),
          parent_id: String.t() | nil,
          created_at: DateTime.t() | nil,
          actor: String.t() | nil,
          message: String.t() | nil
        }

  @spec from_source(binary(), keyword()) :: t()
  def from_source(raw, opts \\ []) when is_binary(raw) do
    %__MODULE__{
      id: Fount.ID.hash(raw),
      parent_id: Keyword.get(opts, :parent_id),
      created_at: Keyword.get(opts, :created_at, DateTime.utc_now()),
      actor: Keyword.get(opts, :actor),
      message: Keyword.get(opts, :message)
    }
  end
end
