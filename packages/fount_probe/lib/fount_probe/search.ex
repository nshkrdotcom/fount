defmodule FountProbe.Search do
  @moduledoc "Source-grounded text retrieval over a specified screenplay revision."
  alias Fount.Query

  @doc "Returns exact hits and the number of eligible elements inspected."
  def find(model, query, opts \\ [])

  def find(model, query, opts) when is_binary(query) do
    phrase = String.trim(query)
    scene_ids = Keyword.get(opts, :scene_ids)
    element_types = Keyword.get(opts, :element_types)
    limit = Keyword.get(opts, :limit, 50)
    known = MapSet.new(Enum.map(model.ir.scenes, & &1.id))

    cond do
      phrase == "" ->
        {:error, :empty_query}

      invalid_scene_ids?(scene_ids, known) ->
        {:error, :unknown_scene}

      invalid_element_types?(element_types) ->
        {:error, :invalid_element_types}

      invalid_limit?(limit) ->
        {:error, :invalid_limit}

      true ->
        search(model, phrase, opts, scene_ids, element_types, limit)
    end
  end

  def find(_, _, _), do: {:error, :invalid_query}

  defp invalid_scene_ids?(nil, _known), do: false

  defp invalid_scene_ids?(ids, known),
    do: not is_list(ids) or Enum.any?(ids, &(not MapSet.member?(known, &1)))

  defp invalid_element_types?(nil), do: false

  defp invalid_element_types?(types),
    do: not is_list(types) or Enum.any?(types, &(not is_atom(&1)))

  defp invalid_limit?(limit), do: not is_integer(limit) or limit < 1

  defp search(model, phrase, opts, scene_ids, element_types, limit) do
    omitted =
      model.ir.scenes
      |> Enum.filter(& &1.omitted?)
      |> Enum.flat_map(& &1.element_ids)
      |> MapSet.new()

    eligible =
      model.ir.elements
      |> Enum.filter(&eligible?(&1, model, opts, omitted, scene_ids, element_types))

    needle = String.downcase(phrase)

    hits =
      eligible
      |> Enum.filter(&String.contains?(String.downcase(&1.text), needle))
      |> Enum.take(limit)
      |> Enum.map(fn element ->
        scene = Query.scene_for(model, element.id)

        %{
          scene_id: scene && scene.id,
          element_id: element.id,
          type: element.type,
          excerpt: element.text
        }
      end)

    {:ok,
     %{
       screenplay_id: model.id,
       revision_id: model.revision.id,
       query: phrase,
       mode: :literal_phrase,
       inspected_element_count: length(eligible),
       returned_hit_count: length(hits),
       truncated?:
         Enum.count(eligible, &String.contains?(String.downcase(&1.text), needle)) > limit,
       hits: hits
     }}
  end

  defp eligible?(element, model, opts, omitted, scene_ids, element_types) do
    scene = Query.scene_for(model, element.id)

    included?(opts, :include_omitted, not MapSet.member?(omitted, element.id)) and
      included?(opts, :include_notes, element.type != :note) and
      included?(opts, :include_boneyards, element.type != :boneyard) and
      matches_scene?(scene, scene_ids) and matches_type?(element, element_types)
  end

  defp included?(opts, key, default), do: Keyword.get(opts, key, false) or default
  defp matches_scene?(_scene, nil), do: true
  defp matches_scene?(scene, ids), do: scene && scene.id in ids
  defp matches_type?(_element, nil), do: true
  defp matches_type?(element, types), do: element.type in types
end
