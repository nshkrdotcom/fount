defmodule Fount.Slice do
  @moduledoc "Ordered, revision-specific screenplay selections."
  defstruct [
    :screenplay_id,
    :revision_id,
    :selector,
    :fingerprint,
    elements: [],
    scene_ids: [],
    block_ids: [],
    cast: []
  ]

  def scene(model, id, opts \\ []) do
    with {:ok, elements} <- Fount.Query.scene_elements(model, id), do: build(model, elements, %{scene_id: id}, opts)
  end

  def scene_range(model, first, last, opts \\ []) do
    with {:ok, scenes} <- Fount.Query.scenes_between(model, first, last) do
      ids = Enum.flat_map(scenes, & &1.element_ids)
      build(model, Enum.filter(model.ir.elements, &(&1.id in ids)), %{scene_range: [first, last]}, opts)
    end
  end

  def scene_prefix(model, id, through, opts \\ []) do
    with {:ok, elements} <- Fount.Query.scene_elements(model, id) do
      index = if is_nil(through), do: 0, else: Enum.find_index(elements, &(&1.id == through))
      block = Fount.Query.block_for(model, through)
      joint_last = if block && block.dual_with do
        partner = Fount.Query.dialogue_block(model, block.dual_with)
        ids = block.body_ids ++ partner.body_ids
        elements |> Enum.filter(&(&1.id in ids)) |> List.last() |> Map.fetch!(:id)
      end

      cond do
        is_nil(index) ->
          {:error, :invalid_cutoff}

        block && block.dual_with && through != joint_last ->
          {:error, :split_simultaneous_group}

        block && is_nil(block.dual_with) && through != List.last(block.body_ids) ->
          {:error, :split_dialogue_block}

        true ->
          build(model, Enum.take(elements, index + 1), %{scene_id: id, through: through}, opts)
      end
    end
  end

  def dialogue_block(model, id, opts \\ []) do
    case Fount.Query.dialogue_block(model, id) do
      nil -> {:error, :unknown_block}
      b -> build(model, Enum.map([b.cue_id | b.body_ids], &Fount.Query.node(model, &1)), %{block_id: id}, opts)
    end
  end

  def character(model, id, opts \\ []) do
    ids = Fount.Query.character_dialogue(model, id) |> Enum.flat_map(&[&1.cue_id | &1.body_ids])
    build(model, Enum.filter(model.ir.elements, &(&1.id in ids)), %{character_id: id}, opts)
  end

  def selected(model, targets, opts \\ []) do
    results =
      Enum.map(targets, fn target ->
        case Fount.Target.resolve(model, target) do
          {:ok, %Fount.IR.Scene{} = s} -> {:ok, s.element_ids}
          {:ok, %Fount.IR.DialogueBlock{} = b} -> {:ok, [b.cue_id | b.body_ids]}
          {:ok, %Fount.IR.Element{} = e} -> {:ok, [e.id]}
          {:ok, %Fount.Screenplay{}} -> {:ok, Enum.map(model.ir.elements, & &1.id)}
          {:ok, _} -> {:error, :unsupported_slice_target}
          error -> error
        end
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        ids = Enum.flat_map(results, &elem(&1, 1))
        build(model, Enum.filter(model.ir.elements, &(&1.id in ids)), %{targets: targets}, opts)

      error ->
        error
    end
  end

  def to_map(slice), do: slice |> Map.from_struct() |> Fount.Screenplay.Model.plain()

  defp build(model, elements, selector, opts) do
    omitted = for s <- model.ir.scenes, s.omitted?, id <- s.element_ids, do: id

    elements =
      Enum.filter(elements, fn e ->
        (Keyword.get(opts, :include_omitted, false) or e.id not in omitted) and
          (Keyword.get(opts, :include_notes, false) or e.type != :note) and
          (Keyword.get(opts, :include_boneyards, false) or e.type != :boneyard)
      end)

    slice = %__MODULE__{
      screenplay_id: model.id,
      revision_id: model.revision.id,
      selector: selector,
      elements: elements,
      scene_ids:
        Enum.flat_map(elements, fn e ->
          case Fount.Query.scene_for(model, e.id) do
            nil -> []
            s -> [s.id]
          end
        end)
        |> Enum.uniq(),
      block_ids:
        Enum.flat_map(elements, fn e ->
          case Fount.Query.block_for(model, e.id) do
            nil -> []
            b -> [b.id]
          end
        end)
        |> Enum.uniq(),
      cast: Fount.Query.characters(model)
    }

    {:ok, %{slice | fingerprint: Fount.Writing.CanonicalJSON.hash(to_map(slice))}}
  end
end