defmodule FountWorkshop.Store do
  @moduledoc "Caller-owned PostgreSQL boundary. A substituted module is an explicit test seam, not an application storage mode."
  @enforce_keys [:repo]
  defstruct [:repo, :guard, module: Fount.Persistence]

  def new(repo, opts \\ []) when is_list(opts),
    do: %__MODULE__{repo: repo, guard: Keyword.get(opts, :guard)}

  @actions [
    :save_session,
    :session,
    :session_by_operation,
    :save_candidate,
    :candidate,
    :candidate_by_operation,
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

  def call(%__MODULE__{repo: repo, module: module, guard: guard}, :save_session, [session])
      when not is_nil(guard) do
    normalize_result(apply(module, :save_session, [repo, session, [guard: guard]]))
  end

  def call(%__MODULE__{repo: repo, module: module, guard: guard}, :save_candidate, [session, candidate])
      when not is_nil(guard) do
    normalize_result(apply(module, :save_candidate, [repo, session, candidate, [guard: guard]]))
  end

  def call(%__MODULE__{repo: repo, module: module}, action, args) when action in @actions do
    normalize_result(apply(module, action, [repo | args]))
  end

  def call(_, _, _), do: {:error, :missing_store}
  def normalize(%Fount.Screenplay{} = model), do: model

  def normalize(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  def clients(services), do: FountWorkshop.Services.analysis(services)
  def reader(services), do: fn sid, rid -> call(services[:store], :load_revision, [sid, rid]) end

  defp normalize_result({:ok, value}) when is_map(value), do: {:ok, normalize(value)}
  defp normalize_result(other), do: other
end
