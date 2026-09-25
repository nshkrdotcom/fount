defmodule Fount.Writing.LocalReferences do
  @moduledoc "Allocates canonical local identities once and rewrites typed references, never prose."
  @keys ~w(id keep anchor_id after_scene_id before_scene_id scene_id heading_id character_id dialogue_block_id element_id target_id source_id destination_id partner_id replaces dual_with_cue)
  @lists ~w(ids scene_ids element_ids mention_ids)
  @label ~r/\Anew:[a-z][a-z0-9_-]*\z/
  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  def compile(value, opts \\ []) do
    try do
      declarations = declarations(value)
      labels = Enum.map(declarations, & &1["local_id"])
      duplicates = labels -- Enum.uniq(labels)
      if duplicates != [], do: fail({:duplicate_local_ids, Enum.uniq(duplicates)})
      given = Keyword.get(opts, :reference_map, %{})
      generator = Keyword.get(opts, :uuid_generator, Keyword.get(opts, :uuid, &Fount.ID.v4/0))
      ids = Map.new(labels, fn label -> {label, Map.get_lazy(given, label, generator)} end)

      if Enum.any?(ids, fn {_, id} -> not is_binary(id) or not Regex.match?(@uuid, id) end),
        do: fail(:invalid_allocated_uuid)

      if length(Enum.uniq(Map.values(ids))) != map_size(ids), do: fail(:duplicate_allocated_uuid)

      ids =
        Enum.reduce(declarations, ids, fn d, acc ->
          if d["type"] == "character" and Keyword.get(opts, :screenplay_id) do
            "new:" <> label = d["local_id"]
            block = "new:block-" <> label
            if Map.has_key?(acc, block), do: fail(:reserved_block_local_id)
            Map.put(acc, block, Fount.ID.v5(opts[:screenplay_id], ["dialogue-block:", acc[d["local_id"]]]))
          else
            acc
          end
        end)

      {:ok, rewrite(value, ids), ids}
    catch
      {:local_reference, reason} -> {:error, reason}
    end
  end

  @doc "Renames local declarations/references for combining independent proposals."
  def namespace(value, prefix) when is_binary(prefix) do
    names =
      value
      |> declarations()
      |> Map.new(fn d ->
        "new:" <> label = d["local_id"]
        {d["local_id"], "new:" <> prefix <> "-" <> label}
      end)

    names =
      Enum.reduce(names, names, fn {"new:" <> label, "new:" <> renamed}, acc ->
        Map.put(acc, "new:block-" <> label, "new:block-" <> renamed)
      end)

    rename(value, names)
  end

  @doc "Maps concrete IDs back to local references when appending writer edits."
  def localize(value, ids), do: rename_refs(value, Map.new(ids, fn {local, id} -> {id, local} end))

  defp declarations(map) when is_map(map) do
    own =
      if Map.has_key?(map, "local_id") do
        local = map["local_id"]

        if not is_binary(local) or not Regex.match?(@label, local) or Map.has_key?(map, "id"),
          do: fail(:invalid_local_id)

        [map]
      else
        []
      end

    own ++ Enum.flat_map(Map.values(map), &declarations/1)
  end

  defp declarations(list) when is_list(list), do: Enum.flat_map(list, &declarations/1)
  defp declarations(_), do: []

  defp rewrite(map, ids) when is_map(map) do
    Map.new(map, fn
      {"local_id", local} -> {"id", Map.fetch!(ids, local)}
      {key, value} when key in @keys -> {key, reference(value, ids)}
      {key, value} when key in @lists and is_list(value) -> {key, Enum.map(value, &reference(&1, ids))}
      {key, value} -> {key, rewrite(value, ids)}
    end)
  end

  defp rewrite(list, ids) when is_list(list), do: Enum.map(list, &rewrite(&1, ids))
  defp rewrite(value, _), do: value
  defp reference("new:" <> _ = value, ids), do: Map.get(ids, value) || fail({:undeclared_local_reference, value})
  defp reference(value, ids) when is_map(value) or is_list(value), do: rewrite(value, ids)
  defp reference(value, _), do: value

  defp rename(map, ids) when is_map(map) do
    Map.new(map, fn
      {"local_id", value} -> {"local_id", Map.get(ids, value, value)}
      {key, value} when key in @keys -> {key, rename_ref(value, ids)}
      {key, value} when key in @lists and is_list(value) -> {key, Enum.map(value, &rename_ref(&1, ids))}
      {key, value} -> {key, rename(value, ids)}
    end)
  end

  defp rename(list, ids) when is_list(list), do: Enum.map(list, &rename(&1, ids))
  defp rename(value, _), do: value
  defp rename_ref(value, ids) when is_binary(value), do: Map.get(ids, value, value)
  defp rename_ref(value, ids), do: rename(value, ids)
  defp rename_refs(value, ids), do: rename(value, ids)
  defp fail(reason), do: throw({:local_reference, reason})
end
