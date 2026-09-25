defmodule FountWorkshop.Store do
  @moduledoc "Caller-owned PostgreSQL boundary. A substituted module is an explicit test seam, not an application storage mode."
  @enforce_keys [:repo]
  defstruct [:repo, module: Fount.Persistence]
  def new(repo), do: %__MODULE__{repo: repo}

  @actions [
    :save_session,
    :session,
    :save_candidate,
    :candidate,
    :candidates_for_session,
    :load_revision,
    :at_revision,
    :load,
    :create,
    :save_report,
    :report,
    :history,
    :accept_candidate,
    :reject_candidate
  ]
  def call(%__MODULE__{repo: repo, module: module}, action, args) when action in @actions do
    case apply(module, action, [repo | args]) do
      {:ok, value} when is_map(value) -> {:ok, normalize(value)}
      other -> other
    end
  end

  def call(_, _, _), do: {:error, :missing_store}
  def normalize(%Fount.Screenplay{} = model), do: model

  def normalize(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  def clients(services), do: %{system_one: services[:jev], inference: services[:inference]}
  def reader(services), do: fn sid, rid -> call(services[:store], :load_revision, [sid, rid]) end
end
