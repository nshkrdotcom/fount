defmodule Fount.Index do
  @moduledoc "Fast derived indexes over immutable screenplay IR."
  alias Fount.IR.Script

  defstruct by_id: %{},
            by_type: %{},
            scenes_by_id: %{},
            dialogue_blocks_by_id: %{},
            scene_for_element: %{},
            character_cues: %{}

  @type t :: %__MODULE__{}

  @spec build(Script.t()) :: t()
  def build(%Script{} = script) do
    by_id = Map.new(script.elements, &{&1.id, &1})
    by_type = Enum.group_by(script.elements, & &1.type)
    scenes_by_id = Map.new(script.scenes, &{&1.id, &1})
    dialogue_blocks_by_id = Map.new(script.dialogue_blocks, &{&1.id, &1})

    scene_for_element =
      Enum.reduce(script.scenes, %{}, fn scene, acc ->
        Enum.reduce(scene.element_ids, acc, &Map.put(&2, &1, scene.id))
      end)

    character_cues =
      script.elements
      |> Enum.filter(&(&1.type == :character))
      |> Enum.group_by(&normalize_character(&1.text), & &1.id)

    %__MODULE__{
      by_id: by_id,
      by_type: by_type,
      scenes_by_id: scenes_by_id,
      dialogue_blocks_by_id: dialogue_blocks_by_id,
      scene_for_element: scene_for_element,
      character_cues: character_cues
    }
  end

  @spec normalize_character(binary()) :: binary()
  def normalize_character(name) do
    if String.valid?(name), do: name |> String.trim() |> String.upcase(), else: name
  end
end
