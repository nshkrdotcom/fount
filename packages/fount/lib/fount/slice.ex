defmodule Fount.Slice do
  @moduledoc "Ordered, revision-specific screenplay selections."
  alias Fount.Screenplay.Model
  alias Fount.Writing.CanonicalJSON

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

      case prefix_cutoff(model, elements, block, through, index) do
        :ok -> build(model, Enum.take(elements, index + 1), %{scene_id: id, through: through}, opts)
        error -> error
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

  def to_map(slice), do: slice |> Map.from_struct() |> Model.plain()

  defp build(model, elements, selector, opts) do
    omitted = for s <- model.ir.scenes, s.omitted?, id <- s.element_ids, do: id

    elements = Enum.filter(elements, &include_element?(&1, omitted, opts))

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

    {:ok, %{slice | fingerprint: CanonicalJSON.hash(to_map(slice))}}
  end

  defp prefix_cutoff(_, _, _, _, nil), do: {:error, :invalid_cutoff}
  defp prefix_cutoff(_, _, nil, _, _), do: :ok

  defp prefix_cutoff(model, elements, %{dual_with: partner_id} = block, through, _) when not is_nil(partner_id) do
    partner = Fount.Query.dialogue_block(model, partner_id)
    ids = block.body_ids ++ partner.body_ids
    last = elements |> Enum.filter(&(&1.id in ids)) |> List.last() |> Map.fetch!(:id)
    if through == last, do: :ok, else: {:error, :split_simultaneous_group}
  end

  defp prefix_cutoff(_, _, block, through, _) do
    if through == List.last(block.body_ids), do: :ok, else: {:error, :split_dialogue_block}
  end

  defp include_element?(element, omitted, opts) do
    (Keyword.get(opts, :include_omitted, false) or element.id not in omitted) and
      (Keyword.get(opts, :include_notes, false) or element.type != :note) and
      (Keyword.get(opts, :include_boneyards, false) or element.type != :boneyard)
  end
end
