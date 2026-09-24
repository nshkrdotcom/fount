defmodule Fount.Screenplay do
  @moduledoc """
  Format-independent screenplay being authored by the writer.

  `Fount.Document` remains an exact imported Fountain document. This value owns
  literal screenplay structure and authored cast identity; an import artifact
  is retained only for exact, unchanged export. No Fountain text is required
  to create or edit a screenplay.
  """

  alias Fount.Adapter.{ExportResult, FDX}
  alias Fount.Cast.{Character, Mention}
  alias Fount.Fountain.Serializer
  alias Fount.ID
  alias Fount.IR.{DialogueBlock, Element, Scene, Script, TitlePage}
  alias Fount.Revision

  @enforce_keys [:id, :revision, :ir]
  defstruct [:id, :revision, :ir, :import, cast: %{}, mentions: %{}, annotations: %{}]

  @type t :: %__MODULE__{
          id: String.t(),
          revision: Revision.t(),
          ir: Script.t(),
          import: map() | nil,
          cast: map(),
          mentions: map(),
          annotations: map()
        }

  @doc "Creates a typed screenplay; scenes contain heading text and typed elements."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    id = Keyword.get(opts, :id, ID.v4())
    title_page = title_page(Keyword.get(opts, :title, []))

    {scenes, elements, turns} =
      case Keyword.fetch(opts, :body) do
        {:ok, body} -> build_body(body)
        :error -> build_scenes(Keyword.get(opts, :scenes, []))
      end

    ir =
      %Script{
        document_id: id,
        title_page: title_page,
        elements: elements,
        scenes: scenes,
        dialogue_blocks: turns,
        outline: [],
        metadata: %{}
      }
      |> refresh_outline()

    %__MODULE__{id: id, revision: revision(nil), ir: ir}
  end

  @doc "Adopts a parsed Fountain document without making its source the edit authority."
  @spec from_document(Fount.Document.t()) :: t()
  def from_document(doc) do
    %__MODULE__{
      id: doc.id,
      revision: revision(nil),
      ir: doc.ir,
      annotations: doc.annotations,
      import: %{format: :fountain, bytes: doc.source.raw, revision_id: nil}
    }
    |> bind_import_revision()
  end

  @doc "Imports practical FDX content into the canonical model and returns fidelity losses."
  @spec from_fdx(binary(), keyword()) :: {:ok, t(), [String.t()]} | {:error, term()}
  def from_fdx(xml, opts \\ []) do
    with {:ok, result} <- FDX.decode(xml, opts) do
      model = from_document(result.document)
      import = %{format: :fdx, bytes: xml, revision_id: model.revision.id, losses: result.losses}
      {:ok, %{model | import: import}, result.losses}
    end
  end

  @doc "Exports the current canonical screenplay as FDX with adapter fidelity losses."
  @spec to_fdx(t()) :: {:ok, ExportResult.t()} | {:error, term()}

  def to_fdx(%__MODULE__{import: %{format: :fdx, bytes: bytes, revision_id: revision}} = model)
      when revision == model.revision.id,
      do: {:ok, %ExportResult{data: bytes}}

  def to_fdx(%__MODULE__{} = model) do
    with {:ok, document} <- Fount.parse(to_fountain(model)),
         {:ok, result} <- FDX.export(document) do
      import_losses = if model.import, do: model.import[:losses] || [], else: []
      {:ok, %{result | losses: Enum.uniq(result.losses ++ import_losses)}}
    end
  end

  @doc "Returns original Fountain bytes for an unchanged import; otherwise serializes the model."
  @spec to_fountain(t(), keyword()) :: binary()
  def to_fountain(screenplay, opts \\ [])

  def to_fountain(%__MODULE__{import: %{format: :fountain, bytes: bytes, revision_id: revision}} = screenplay, _opts)
      when revision == screenplay.revision.id,
      do: bytes

  def to_fountain(%__MODULE__{ir: ir}, opts),
    do: Serializer.serialize(ir, Keyword.put(opts, :canonical_spacing, true))

  @doc "Returns Fountain bytes with an explicit fidelity report for regenerated imports."
  @spec export_fountain(t(), keyword()) :: {:ok, ExportResult.t()}
  def export_fountain(%__MODULE__{} = model, opts \\ []) do
    losses =
      case model.import do
        %{format: :fountain, revision_id: revision} when revision == model.revision.id -> []
        %{format: :fountain} -> ["Original Fountain spacing and trivia may change after canonical editing"]
        %{format: :fdx, losses: import_losses} -> import_losses
        _ -> []
      end

    {:ok, %ExportResult{data: to_fountain(model, opts), losses: losses}}
  end

  @doc "Applies typed operations to the model and advances its revision once."
  @spec apply(t(), Fount.Edit.Op.t() | [Fount.Edit.Op.t()]) :: {:ok, t()} | {:error, term()}
  def apply(%__MODULE__{} = screenplay, operations) do
    operations = List.wrap(operations)

    with {:ok, updated} <- Enum.reduce_while(operations, {:ok, screenplay}, &apply_step/2) do
      next_revision = revision(screenplay.revision.id)
      mentions = rebind_mentions(updated, next_revision.id)
      affected = affected_ids(screenplay, updated)
      annotations = invalidate_annotations(updated, affected)
      {:ok, %{updated | revision: next_revision, mentions: mentions, annotations: annotations}}
    end
  end

  @doc "Creates a new head with a prior model's content and identities."
  @spec undo(t(), t()) :: {:ok, t()} | {:error, :different_screenplay}
  def undo(current, prior), do: restore_model(current, prior, "undo")

  @doc "Creates a new head with a subsequent model's content and identities."
  @spec redo(t(), t()) :: {:ok, t()} | {:error, :different_screenplay}
  def redo(current, subsequent), do: restore_model(current, subsequent, "redo")

  @doc "ID-based semantic changes between two revisions of one screenplay."
  @spec diff(t(), t()) :: map()
  def diff(%__MODULE__{} = before, %__MODULE__{} = after_model) do
    scene_changes = changes(before.ir.scenes, after_model.ir.scenes, &scene_content/1)

    %{
      elements: changes(before.ir.elements, after_model.ir.elements, &element_content/1),
      scenes: Map.put(scene_changes, :moved, moved_ids(before.ir.scenes, after_model.ir.scenes)),
      cast: changes(Map.values(before.cast), Map.values(after_model.cast), & &1)
    }
  end

  defp changes(before, after_items, content) do
    old = Map.new(before, &{&1.id, content.(&1)})
    new = Map.new(after_items, &{&1.id, content.(&1)})
    old_ids = MapSet.new(Map.keys(old))
    new_ids = MapSet.new(Map.keys(new))

    %{
      added: Enum.filter(Enum.map(after_items, & &1.id), &(!MapSet.member?(old_ids, &1))),
      removed: Enum.filter(Enum.map(before, & &1.id), &(!MapSet.member?(new_ids, &1))),
      changed: Enum.filter(Enum.map(after_items, & &1.id), &(Map.has_key?(old, &1) and old[&1] != new[&1]))
    }
  end

  defp moved_ids(before, after_items) do
    positions = before |> Enum.with_index() |> Map.new(fn {scene, index} -> {scene.id, index} end)

    after_items
    |> Enum.with_index()
    |> Enum.flat_map(fn {scene, index} ->
      if Map.has_key?(positions, scene.id) and positions[scene.id] != index, do: [scene.id], else: []
    end)
  end

  defp scene_content(scene), do: {scene.heading_id, scene.element_ids, scene.number, scene.omitted?}
  defp element_content(element), do: {element.type, element.text, element.attrs}

  defp restore_model(%__MODULE__{id: id} = current, %__MODULE__{id: id} = target, message) do
    next_revision = %{revision(current.revision.id) | message: message}
    {:ok, %{target | revision: next_revision, mentions: rebind_mentions(target, next_revision.id)}}
  end

  defp restore_model(%__MODULE__{}, %__MODULE__{}, _message), do: {:error, :different_screenplay}

  defp affected_ids(before, after_model) do
    before_nodes = Map.new(before.ir.elements ++ before.ir.scenes, &{&1.id, &1})
    after_nodes = Map.new(after_model.ir.elements ++ after_model.ir.scenes, &{&1.id, &1})

    before_nodes
    |> Enum.filter(fn {id, node} -> Map.get(after_nodes, id) != node end)
    |> MapSet.new(&elem(&1, 0))
  end

  defp invalidate_annotations(screenplay, affected) do
    live =
      MapSet.new([screenplay.id | Enum.map(screenplay.ir.scenes, & &1.id) ++ Enum.map(screenplay.ir.elements, & &1.id)])

    Map.reject(screenplay.annotations, fn {_id, annotation} ->
      targets = [annotation.target.node_id | annotation.dependencies || []]

      Enum.any?(targets, &(not MapSet.member?(live, &1))) or
        (annotation.provenance.producer != "writer" and Enum.any?(targets, &MapSet.member?(affected, &1)))
    end)
  end

  @doc "Adds a writer-authored cast entry. Aliases are allowed to overlap across characters."
  @spec add_character(t(), String.t(), keyword()) :: {t(), Character.t()}
  def add_character(%__MODULE__{} = screenplay, name, opts \\ []) when is_binary(name) do
    character = %Character{
      id: Keyword.get(opts, :id, ID.v4()),
      display_name: name,
      notes: Keyword.get(opts, :notes),
      aliases: Enum.map(Keyword.get(opts, :aliases, []), &alias_entry/1),
      attributes: Keyword.get(opts, :attributes, %{})
    }

    updated = %{screenplay | cast: Map.put(screenplay.cast, character.id, character)}
    next_revision = revision(screenplay.revision.id)
    {%{updated | revision: next_revision, mentions: rebind_mentions(updated, next_revision.id)}, character}
  end

  @doc "Confirms that one literal character cue refers to an authored cast entry."
  @spec link_cue(t(), String.t(), String.t()) :: {:ok, t()} | {:error, term()}
  def link_cue(%__MODULE__{} = screenplay, cue_id, character_id) do
    with %Character{} <- Map.get(screenplay.cast, character_id),
         %Element{type: :character} = cue <- node(screenplay, cue_id) do
      next_revision = revision(screenplay.revision.id)

      mention = %Mention{
        id: ID.v5(screenplay.id, ["cue:", cue_id]),
        element_id: cue_id,
        character_id: character_id,
        role: :speaker_cue,
        status: :confirmed,
        surface: cue.text,
        byte_start: 0,
        byte_end: byte_size(cue.text),
        model_revision_id: next_revision.id,
        producer: "writer",
        confidence: 1.0
      }

      mentions =
        screenplay.mentions
        |> Map.reject(fn {_id, item} -> item.element_id == cue_id and item.role == :speaker_cue end)
        |> Map.put(mention.id, mention)

      {:ok, %{screenplay | mentions: mentions, revision: next_revision}}
    else
      nil -> {:error, {:unknown_character_or_cue, character_id, cue_id}}
      _ -> {:error, {:not_a_character_cue, cue_id}}
    end
  end

  @doc "Suggests exact named occurrences; ambiguous aliases remain unresolved."
  @spec suggest_mentions(t()) :: [Mention.t()]
  def suggest_mentions(%__MODULE__{} = screenplay) do
    aliases =
      screenplay.cast
      |> Map.values()
      |> Enum.flat_map(fn character ->
        [
          %{alias: character.display_name, character_id: character.id}
          | Enum.map(character.aliases, &Map.put(&1, :character_id, character.id))
        ]
      end)

    screenplay.ir.elements
    |> Enum.filter(&(&1.type in [:action, :dialogue, :parenthetical]))
    |> Enum.flat_map(&element_suggestions(screenplay, &1, aliases))
  end

  @spec mentions_for(t(), String.t()) :: [Mention.t()]
  def mentions_for(%__MODULE__{} = screenplay, character_id) do
    screenplay.mentions
    |> Map.values()
    |> Enum.filter(&(&1.character_id == character_id))
    |> Enum.sort_by(&{element_ordinal(screenplay, &1.element_id), &1.byte_start})
  end

  @doc "Plans a cast rename: confirmed cues are mechanical; prose references require review."
  @spec plan_character_rename(t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def plan_character_rename(%__MODULE__{} = screenplay, character_id, new_name)
      when is_binary(new_name) and new_name != "" do
    case Map.get(screenplay.cast, character_id) do
      nil ->
        {:error, {:unknown_character, character_id}}

      _character ->
        cues =
          screenplay
          |> mentions_for(character_id)
          |> Enum.filter(&(&1.role == :speaker_cue and &1.status == :confirmed))
          |> Enum.map(&Fount.Edit.set_character_cue(&1.element_id, new_name))

        review = Enum.filter(suggest_mentions(screenplay), &(character_id in &1.candidate_ids))

        {:ok,
         %{
           base_revision: screenplay.revision.id,
           character_id: character_id,
           new_name: new_name,
           cue_operations: cues,
           review: review
         }}
    end
  end

  @doc "Accepts only the mechanical cue and cast-name part of a reviewed rename plan."
  @spec accept_character_rename(t(), map()) :: {:ok, t()} | {:error, term()}
  def accept_character_rename(%__MODULE__{} = screenplay, %{base_revision: base} = plan) do
    if screenplay.revision.id == base do
      with {:ok, renamed} <- __MODULE__.apply(screenplay, plan.cue_operations),
           %Character{} = character <- Map.get(renamed.cast, plan.character_id) do
        cast = Map.put(renamed.cast, character.id, %{character | display_name: plan.new_name})
        {:ok, %{renamed | cast: cast}}
      else
        nil -> {:error, {:unknown_character, plan.character_id}}
        error -> error
      end
    else
      {:error, {:stale_rename_plan, screenplay.revision.id}}
    end
  end

  defp element_suggestions(screenplay, element, aliases) do
    aliases
    |> Enum.flat_map(fn %{alias: alias_text, character_id: character_id} ->
      pattern = ~r/(?<![\p{L}\p{N}_])#{Regex.escape(alias_text)}(?![\p{L}\p{N}_])/iu

      Regex.scan(pattern, element.text, return: :index)
      |> Enum.map(fn [{start, length}] -> {{start, start + length}, character_id} end)
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {{start, stop}, candidates} ->
      ids = Enum.uniq(candidates)
      surface = binary_part(element.text, start, stop - start)

      %Mention{
        id:
          ID.v5(screenplay.id, ["suggestion:", element.id, ":", Integer.to_string(start), ":", Integer.to_string(stop)]),
        element_id: element.id,
        character_id: if(length(ids) == 1, do: hd(ids), else: nil),
        candidate_ids: ids,
        role: mention_role(element.type),
        status: if(length(ids) == 1, do: :suggested, else: :ambiguous),
        surface: surface,
        byte_start: start,
        byte_end: stop,
        model_revision_id: screenplay.revision.id,
        producer: "fount.exact_name"
      }
    end)
    |> Enum.sort_by(& &1.byte_start)
  end

  defp mention_role(:action), do: :action
  defp mention_role(:dialogue), do: :dialogue_reference
  defp mention_role(:parenthetical), do: :parenthetical

  defp alias_entry(%{alias: alias_text, kind: kind, character_id: character_id}),
    do: %{alias: alias_text, kind: kind, character_id: character_id}

  defp alias_entry({alias_text, kind}), do: %{alias: alias_text, kind: kind}
  defp alias_entry(alias_text) when is_binary(alias_text), do: %{alias: alias_text, kind: :name}

  defp element_ordinal(screenplay, id) do
    Enum.find_index(screenplay.ir.elements, &(&1.id == id)) || -1
  end

  defp rebind_mentions(screenplay, revision_id) do
    Map.new(screenplay.mentions, fn {id, mention} ->
      element = node(screenplay, mention.element_id)

      if element && mention.byte_end <= byte_size(element.text) &&
           binary_part(element.text, mention.byte_start, mention.byte_end - mention.byte_start) == mention.surface do
        {id, %{mention | model_revision_id: revision_id}}
      else
        {id, nil}
      end
    end)
    |> Map.reject(fn {_id, mention} -> is_nil(mention) end)
  end

  @spec node(t(), String.t()) :: Element.t() | nil
  def node(%__MODULE__{ir: ir}, id), do: Enum.find(ir.elements, &(&1.id == id))

  @spec scene(t(), String.t()) :: Scene.t() | nil
  def scene(%__MODULE__{ir: ir}, id), do: Enum.find(ir.scenes, &(&1.id == id))

  defp apply_step(op, {:ok, screenplay}) do
    case apply_one(screenplay, op) do
      {:ok, updated} -> {:cont, {:ok, updated}}
      error -> {:halt, error}
    end
  end

  defp apply_one(screenplay, %Fount.Edit.Op{kind: :replace_text, target: id, value: text})
       when is_binary(text) do
    update_element(screenplay, id, fn element ->
      %{element | text: text, raw_text: nil, source_span: nil, content_span: nil}
    end)
  end

  defp apply_one(screenplay, %Fount.Edit.Op{kind: :set_character_cue, target: id, value: name})
       when is_binary(name) and name != "" do
    case node(screenplay, id) do
      %Element{type: :character} ->
        {:ok, updated} =
          update_element(screenplay, id, fn element ->
            attrs = Map.put(element.attrs || %{}, :forced?, name != String.upcase(name))
            %{element | text: name, raw_text: nil, source_span: nil, content_span: nil, attrs: attrs}
          end)

        mentions = Map.new(updated.mentions, &rename_cue_mention(&1, id, name))

        {:ok, %{updated | mentions: mentions}}

      nil ->
        {:error, {:unknown_element, id}}

      _ ->
        {:error, {:not_a_character_cue, id}}
    end
  end

  defp apply_one(screenplay, %Fount.Edit.Op{kind: :set_scene_heading, target: id, value: heading})
       when is_binary(heading) do
    case scene(screenplay, id) do
      nil ->
        {:error, {:unknown_scene, id}}

      scene ->
        update_element(screenplay, scene.heading_id, fn element ->
          %{
            element
            | text: heading,
              raw_text: nil,
              source_span: nil,
              content_span: nil,
              attrs: Map.put(element.attrs || %{}, :forced?, not Fount.SceneHeading.standard_fountain?(heading))
          }
        end)
    end
  end

  defp apply_one(screenplay, %Fount.Edit.Op{kind: :omit_scene, target: id, value: omit?})
       when is_boolean(omit?) do
    if scene(screenplay, id) do
      scenes = Enum.map(screenplay.ir.scenes, &set_omission(&1, id, omit?))

      {:ok, %{screenplay | ir: %{screenplay.ir | scenes: scenes}}}
    else
      {:error, {:unknown_scene, id}}
    end
  end

  defp apply_one(screenplay, %Fount.Edit.Op{kind: :set_scene_number, target: id, value: number})
       when is_nil(number) or (is_binary(number) and number != "") do
    case scene(screenplay, id) do
      nil ->
        {:error, {:unknown_scene, id}}

      current ->
        {:ok, update_scene_number(screenplay, current, number)}
    end
  end

  defp apply_one(screenplay, %Fount.Edit.Op{kind: :move_scene, target: id, value: after_id}) do
    cond do
      is_nil(scene(screenplay, id)) -> {:error, {:unknown_scene, id}}
      is_nil(scene(screenplay, after_id)) -> {:error, {:unknown_scene, after_id}}
      id == after_id -> {:ok, screenplay}
      true -> {:ok, move_scene_after(screenplay, id, after_id)}
    end
  end

  defp apply_one(screenplay, %Fount.Edit.Op{kind: :insert_scene_after, target: id, value: value}) do
    case scene(screenplay, id) do
      nil ->
        {:error, {:unknown_scene, id}}

      preceding ->
        spec = %{heading: value.heading, elements: value.content}
        {[created], new_elements, new_turns} = build_scenes([spec])
        after_element = List.last(preceding.element_ids)
        index = Enum.find_index(screenplay.ir.elements, &(&1.id == after_element))
        elements = List.insert_at(screenplay.ir.elements, index + 1, new_elements) |> List.flatten()
        scene_index = Enum.find_index(screenplay.ir.scenes, &(&1.id == id))
        scenes = List.insert_at(screenplay.ir.scenes, scene_index + 1, created)
        ordinal = elements |> Enum.with_index() |> Map.new(fn {element, position} -> {element.id, position} end)
        turns = Enum.sort_by(screenplay.ir.dialogue_blocks ++ new_turns, &Map.fetch!(ordinal, &1.cue_id))
        ir = %{screenplay.ir | elements: elements, scenes: scenes, dialogue_blocks: turns}
        {:ok, %{screenplay | ir: refresh_outline(ir)}}
    end
  end

  defp apply_one(screenplay, %Fount.Edit.Op{kind: :delete_scene, target: id}) do
    case scene(screenplay, id) do
      nil ->
        {:error, {:unknown_scene, id}}

      removed ->
        element_ids = MapSet.new(removed.element_ids)
        elements = Enum.reject(screenplay.ir.elements, &MapSet.member?(element_ids, &1.id))
        turns = Enum.reject(screenplay.ir.dialogue_blocks, &MapSet.member?(element_ids, &1.cue_id))
        scenes = Enum.reject(screenplay.ir.scenes, &(&1.id == id))
        ir = %{screenplay.ir | elements: elements, scenes: scenes, dialogue_blocks: turns}
        {:ok, %{screenplay | ir: refresh_outline(ir)}}
    end
  end

  defp apply_one(_screenplay, op), do: {:error, {:unsupported_model_operation, op.kind}}

  defp rename_cue_mention({id, %{element_id: cue_id, role: :speaker_cue} = mention}, cue_id, name),
    do: {id, %{mention | surface: name, byte_start: 0, byte_end: byte_size(name)}}

  defp rename_cue_mention(entry, _cue_id, _name), do: entry

  defp update_scene_number(screenplay, current, number) do
    scenes = Enum.map(screenplay.ir.scenes, &number_scene(&1, current.id, number))
    elements = Enum.map(screenplay.ir.elements, &number_heading(&1, current.heading_id, number))
    %{screenplay | ir: %{screenplay.ir | scenes: scenes, elements: elements}}
  end

  defp number_scene(%{id: id} = scene, id, number), do: %{scene | number: number}
  defp number_scene(scene, _id, _number), do: scene

  defp number_heading(%{id: id} = element, id, nil),
    do: %{element | attrs: Map.delete(element.attrs || %{}, :number)}

  defp number_heading(%{id: id} = element, id, number),
    do: %{element | attrs: Map.put(element.attrs || %{}, :number, number)}

  defp number_heading(element, _id, _number), do: element

  defp move_scene_after(screenplay, id, after_id) do
    scene_for = Map.new(for scene <- screenplay.ir.scenes, element_id <- scene.element_ids, do: {element_id, scene.id})

    chunks =
      screenplay.ir.elements
      |> Enum.chunk_by(&Map.get(scene_for, &1.id))
      |> Enum.map(fn elements -> {Map.get(scene_for, hd(elements).id), elements} end)

    {moving, remaining} = List.pop_at(chunks, Enum.find_index(chunks, &(elem(&1, 0) == id)))
    destination = Enum.find_index(remaining, &(elem(&1, 0) == after_id))
    chunks = List.insert_at(remaining, destination + 1, moving)
    elements = Enum.flat_map(chunks, &elem(&1, 1))
    scene_by_id = Map.new(screenplay.ir.scenes, &{&1.id, &1})
    scenes = for {scene_id, _} <- chunks, scene_id != nil, do: Map.fetch!(scene_by_id, scene_id)
    ordinal = elements |> Enum.with_index() |> Map.new(fn {element, index} -> {element.id, index} end)
    turns = Enum.sort_by(screenplay.ir.dialogue_blocks, &Map.fetch!(ordinal, &1.cue_id))
    ir = %{screenplay.ir | elements: elements, scenes: scenes, dialogue_blocks: turns}
    %{screenplay | ir: refresh_outline(ir)}
  end

  defp refresh_outline(ir) do
    Fount.IR.restore_views(ir)
  end

  defp update_element(screenplay, id, fun) do
    if node(screenplay, id) do
      elements = Enum.map(screenplay.ir.elements, &update_if_target(&1, id, fun))

      {:ok, %{screenplay | ir: %{screenplay.ir | elements: elements}}}
    else
      {:error, {:unknown_element, id}}
    end
  end

  defp build_scenes(specs) do
    Enum.reduce(specs, {[], [], []}, fn spec, {scenes, elements, turns} ->
      scene_id = ID.v4()
      heading_text = Map.fetch!(spec, :heading)

      number = Map.get(spec, :number)

      heading = %Element{
        id: ID.v4(),
        type: :scene_heading,
        text: heading_text,
        attrs: %{forced?: not Fount.SceneHeading.standard_fountain?(heading_text), number: number}
      }

      body = Enum.map(Map.get(spec, :elements, []), &build_element/1)
      scene_elements = [heading | body]

      scene = %Scene{
        id: scene_id,
        heading_id: heading.id,
        element_ids: Enum.map(scene_elements, & &1.id),
        omitted?: false,
        number: number
      }

      scene_turns = build_turns(scene_elements)
      {scenes ++ [scene], elements ++ scene_elements, turns ++ scene_turns}
    end)
  end

  defp build_body(specs) do
    Enum.reduce(specs, {[], [], []}, fn
      %{type: :scene} = spec, {scenes, elements, turns} ->
        {new_scenes, new_elements, new_turns} = build_scenes([spec])
        {scenes ++ new_scenes, elements ++ new_elements, turns ++ new_turns}

      spec, {scenes, elements, turns} ->
        {scenes, elements ++ [build_element(spec)], turns}
    end)
  end

  defp build_element(%{type: type, text: text} = spec) do
    attrs = Map.get(spec, :attrs, %{})
    attrs = if type == :character and text != String.upcase(text), do: Map.put(attrs, :forced?, true), else: attrs
    %Element{id: ID.v4(), type: type, text: text, attrs: attrs}
  end

  defp build_turns(elements) do
    {turns, pending} =
      Enum.reduce(elements, {[], nil}, fn element, {turns, pending} ->
        cond do
          element.type == :character ->
            turns = close_turn(turns, pending)
            {turns, %DialogueBlock{id: ID.v4(), cue_id: element.id, body_ids: []}}

          pending && element.type in [:dialogue, :parenthetical] ->
            {turns, %{pending | body_ids: pending.body_ids ++ [element.id]}}

          true ->
            {close_turn(turns, pending), nil}
        end
      end)

    if pending, do: Enum.reverse([pending | turns]), else: Enum.reverse(turns)
  end

  defp close_turn(turns, nil), do: turns
  defp close_turn(turns, pending), do: [pending | turns]

  defp update_if_target(element, id, fun) do
    if element.id == id, do: fun.(element), else: element
  end

  defp set_omission(scene, id, omit?) do
    if scene.id == id, do: %{scene | omitted?: omit?}, else: scene
  end

  defp title_page([]), do: nil

  defp title_page(entries) do
    %TitlePage{
      entries:
        Enum.map(entries, fn {key, values} ->
          %TitlePage.Entry{id: ID.v4(), key: key, values: List.wrap(values)}
        end)
    }
  end

  defp bind_import_revision(%__MODULE__{import: import} = screenplay),
    do: %{screenplay | import: %{import | revision_id: screenplay.revision.id}}

  defp revision(parent), do: %Revision{id: ID.v4(), parent_id: parent, created_at: DateTime.utc_now()}
end
