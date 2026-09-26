defmodule FountWorkshop.Writing.ChangeGroups do
  @moduledoc """
  Validation, deterministic ordering and explicit selection of creative edits.

  Dependency completion is returned to the caller as a proposal; selecting a
  group never silently selects additional writing. No persistence or generation
  occurs in this module.
  """

  @spec order([map()]) :: {:ok, [map()]} | {:error, term()}
  def order(groups) when is_list(groups) and groups != [] do
    with :ok <- shapes(groups),
         :ok <- identities(groups),
         :ok <- references(groups) do
      topological(groups, [], %{})
    end
  end

  def order(_), do: {:error, :empty_change_groups}

  @spec select([map()], [String.t()]) ::
          {:ok, [map()]} | {:error, term()}
  def select(groups, requested) when is_list(requested) and requested != [] do
    with {:ok, ordered} <- order(groups),
         :ok <- requested_ids(ordered, requested) do
      by_id = Map.new(ordered, &{&1["id"], &1})
      selected = MapSet.new(requested)
      required = closure(selected, by_id)
      missing = MapSet.difference(required, selected)

      if MapSet.size(missing) == 0 do
        {:ok, Enum.filter(ordered, &MapSet.member?(selected, &1["id"]))}
      else
        {:error,
         {:missing_required_groups,
          %{
            "missing" => Enum.filter(Enum.map(ordered, & &1["id"]), &MapSet.member?(missing, &1)),
            "proposed_selection" =>
              Enum.filter(Enum.map(ordered, & &1["id"]), &MapSet.member?(required, &1))
          }}}
      end
    end
  end

  def select(_, _), do: {:error, :empty_group_selection}

  @spec operations([map()]) :: {:ok, [map()]} | {:error, term()}
  def operations(groups) do
    with {:ok, ordered} <- order(groups) do
      {:ok, Enum.flat_map(ordered, & &1["operations"])}
    end
  end

  @spec notes_addressed([map()]) :: [String.t()]
  def notes_addressed(groups) do
    groups |> Enum.flat_map(&Map.get(&1, "addresses_notes", [])) |> Enum.uniq()
  end

  defp shapes(groups) do
    case Enum.find(groups, &invalid_shape?/1) do
      nil -> :ok
      group -> {:error, {:invalid_change_group, group}}
    end
  end

  defp invalid_shape?(group) when not is_map(group), do: true

  defp invalid_shape?(group) do
    not is_binary(group["id"]) or group["id"] == "" or
      not is_list(group["operations"]) or group["operations"] == [] or
      not Enum.all?(group["operations"], &is_map/1) or
      not is_list(Map.get(group, "depends_on", [])) or
      not Enum.all?(Map.get(group, "depends_on", []), &is_binary/1) or
      not is_list(Map.get(group, "addresses_notes", []))
  end

  defp identities(groups) do
    ids = Enum.map(groups, & &1["id"])
    if length(ids) == length(Enum.uniq(ids)), do: :ok, else: {:error, :duplicate_group_ids}
  end

  defp references(groups) do
    ids = MapSet.new(groups, & &1["id"])

    missing =
      for group <- groups,
          dependency <- Map.get(group, "depends_on", []),
          not MapSet.member?(ids, dependency),
          do: %{"group_id" => group["id"], "missing_dependency" => dependency}

    if missing == [], do: :ok, else: {:error, {:unknown_group_dependencies, missing}}
  end

  defp topological([], ordered, _done), do: {:ok, Enum.reverse(ordered)}

  defp topological(pending, ordered, done) do
    case Enum.find(pending, fn group ->
           Enum.all?(Map.get(group, "depends_on", []), &Map.has_key?(done, &1))
         end) do
      nil ->
        {:error, {:cyclic_group_dependencies, Enum.map(pending, & &1["id"])}}

      next ->
        remaining = Enum.reject(pending, &(&1["id"] == next["id"]))
        topological(remaining, [next | ordered], Map.put(done, next["id"], true))
    end
  end

  defp requested_ids(groups, ids) do
    existing = MapSet.new(groups, & &1["id"])
    missing = Enum.reject(ids, &MapSet.member?(existing, &1))

    cond do
      length(Enum.uniq(ids)) != length(ids) -> {:error, :duplicate_selected_group}
      missing != [] -> {:error, {:unknown_selected_groups, missing}}
      true -> :ok
    end
  end

  defp closure(selected, by_id) do
    expanded =
      Enum.reduce(selected, selected, fn id, acc ->
        Enum.reduce(Map.get(Map.fetch!(by_id, id), "depends_on", []), acc, &MapSet.put(&2, &1))
      end)

    if MapSet.equal?(selected, expanded), do: expanded, else: closure(expanded, by_id)
  end
end
