defmodule Fount.Writer do
  @moduledoc "Pure writer-facing projections over a canonical screenplay."
  alias Fount.Screenplay

  @doc "Groups visible scenes by the first parsed location component, preserving scene order."
  @spec location_groups(Screenplay.t(), keyword()) :: %{optional(String.t()) => [String.t()]}
  def location_groups(%Screenplay{} = model, opts \\ []) do
    model
    |> visible_scenes(opts)
    |> Enum.group_by(
      fn scene ->
        scene
        |> then(&Screenplay.node(model, &1.heading_id))
        |> then(&Fount.SceneHeading.parse(&1.text))
        |> Map.fetch!(:locations)
        |> List.first()
      end,
      & &1.id
    )
  end

  @doc "Ordered scene labels authored as storyline annotations, grouped by thread."
  @spec swimlanes(Screenplay.t(), keyword()) :: %{optional(String.t()) => [map()]}
  def swimlanes(%Screenplay{} = model, opts \\ []) do
    labels =
      model.annotations
      |> Map.values()
      |> Enum.filter(&(&1.namespace == "writer" and &1.kind in [:storyline, "storyline"]))
      |> Enum.group_by(& &1.target.node_id)

    model
    |> visible_scenes(opts)
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {scene, ordinal} ->
      for label <- Map.get(labels, scene.id, []),
          thread = label.value["thread"],
          is_binary(thread),
          do: {thread, %{scene_id: scene.id, beat: label.value["beat"], ordinal: ordinal}}
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc "Computes display numbers in visible order and reports collisions with locked literal numbers."
  @spec scene_numbers(Screenplay.t(), keyword()) :: {:ok, map()} | {:error, {:scene_number_conflict, String.t()}}
  def scene_numbers(%Screenplay{} = model, opts \\ []) do
    scenes = visible_scenes(model, opts)

    scenes
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, %{}, MapSet.new(), nil}, fn {scene, ordinal}, {:ok, numbers, used, previous} ->
      next_locked = scenes |> Enum.drop(ordinal) |> Enum.find_value(& &1.number)
      number = scene.number || next_display_number(previous, next_locked, ordinal)

      if MapSet.member?(used, number) do
        {:halt, {:error, {:scene_number_conflict, number}}}
      else
        {:cont, {:ok, Map.put(numbers, scene.id, number), MapSet.put(used, number), number}}
      end
    end)
    |> case do
      {:ok, numbers, _used, _previous} -> {:ok, numbers}
      error -> error
    end
  end

  defp next_display_number(nil, _next_locked, ordinal), do: Integer.to_string(ordinal)

  defp next_display_number(previous, next_locked, ordinal) do
    case Regex.run(~r/^(\d+)([A-Z]*)$/, previous, capture: :all_but_first) do
      [digits, suffix] ->
        base = String.to_integer(digits)

        if next_locked == Integer.to_string(base + 1),
          do: digits <> next_suffix(suffix),
          else: Integer.to_string(base + 1)

      _ ->
        Integer.to_string(ordinal)
    end
  end

  defp next_suffix(suffix) do
    value = suffix |> String.to_charlist() |> Enum.reduce(0, fn letter, acc -> acc * 26 + letter - ?A + 1 end)
    encode_suffix(value + 1)
  end

  defp encode_suffix(0), do: ""

  defp encode_suffix(value),
    do: encode_suffix(div(value - 1, 26)) <> <<?A + rem(value - 1, 26)>>

  defp visible_scenes(model, opts) do
    if Keyword.get(opts, :include_omitted, false),
      do: model.ir.scenes,
      else: Enum.reject(model.ir.scenes, & &1.omitted?)
  end

  @doc "Exact whitespace-delimited action and dialogue word counts for one scene."
  @spec word_counts(Screenplay.t(), String.t(), keyword()) ::
          {:ok, %{action: non_neg_integer(), dialogue: non_neg_integer()}} | {:error, {:unknown_scene, String.t()}}
  def word_counts(%Screenplay{} = model, scene_id, opts \\ []) do
    case Screenplay.scene(model, scene_id) do
      nil ->
        {:error, {:unknown_scene, scene_id}}

      %{omitted?: true} = scene ->
        if Keyword.get(opts, :include_omitted, false), do: {:ok, count_words(model, scene)}, else: {:ok, zero_counts()}

      scene ->
        {:ok, count_words(model, scene)}
    end
  end

  defp count_words(model, scene) do
    scene.element_ids
    |> Enum.map(&Screenplay.node(model, &1))
    |> Enum.reduce(zero_counts(), fn element, counts ->
      if element.type in [:action, :dialogue] do
        Map.update!(counts, element.type, &(&1 + length(String.split(element.text, ~r/\s+/u, trim: true))))
      else
        counts
      end
    end)
  end

  defp zero_counts, do: %{action: 0, dialogue: 0}

  @doc "Ordered rehearsal turns, with explicit cast identity and literal cue text kept separate."
  @spec table_read(Screenplay.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, {:unknown_scene, String.t()}}
  def table_read(%Screenplay{} = model, scene_id, opts \\ []) do
    case Screenplay.scene(model, scene_id) do
      nil ->
        {:error, {:unknown_scene, scene_id}}

      %{omitted?: true} = scene ->
        if Keyword.get(opts, :include_omitted, false), do: {:ok, turns(model, scene)}, else: {:ok, []}

      scene ->
        {:ok, turns(model, scene)}
    end
  end

  defp turns(model, scene) do
    members = MapSet.new(scene.element_ids)

    model.ir.dialogue_blocks
    |> Enum.filter(&MapSet.member?(members, &1.cue_id))
    |> Enum.map(fn block ->
      cue = Screenplay.node(model, block.cue_id)
      body = Enum.map(block.body_ids, &Screenplay.node(model, &1))

      %{
        id: block.id,
        scene_id: scene.id,
        cue: cue.text,
        character_id: confirmed_speaker(model, cue.id),
        dialogue: body |> Enum.filter(&(&1.type == :dialogue)) |> Enum.map_join("\n", & &1.text),
        parentheticals: body |> Enum.filter(&(&1.type == :parenthetical)) |> Enum.map(& &1.text),
        dual_with: block.dual_with,
        side: block.side
      }
    end)
  end

  defp confirmed_speaker(model, cue_id) do
    model.mentions
    |> Map.values()
    |> Enum.find(fn mention ->
      mention.element_id == cue_id and mention.role == :speaker_cue and mention.status == :confirmed
    end)
    |> case do
      nil -> nil
      mention -> mention.character_id
    end
  end
end
