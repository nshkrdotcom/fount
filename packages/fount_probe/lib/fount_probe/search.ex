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

      scene_ids != nil and
          (not is_list(scene_ids) or Enum.any?(scene_ids, &(not MapSet.member?(known, &1)))) ->
        {:error, :unknown_scene}

      element_types != nil and
          (not is_list(element_types) or Enum.any?(element_types, &(not is_atom(&1)))) ->
        {:error, :invalid_element_types}

      not is_integer(limit) or limit < 1 ->
        {:error, :invalid_limit}

      true ->
        omitted =
          model.ir.scenes
          |> Enum.filter(& &1.omitted?)
          |> Enum.flat_map(& &1.element_ids)
          |> MapSet.new()

        eligible =
          model.ir.elements
          |> Enum.filter(fn element ->
            scene = Query.scene_for(model, element.id)

            (Keyword.get(opts, :include_omitted, false) or
               not MapSet.member?(omitted, element.id)) and
              (Keyword.get(opts, :include_notes, false) or element.type != :note) and
              (Keyword.get(opts, :include_boneyards, false) or element.type != :boneyard) and
              (scene_ids == nil or (scene && scene.id in scene_ids)) and
              (element_types == nil or element.type in element_types)
          end)

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
  end

  def find(_, _, _), do: {:error, :invalid_query}
end
