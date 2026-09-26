defmodule Fount.Screenplay do
  import Kernel, except: [apply: 2, apply: 3]

  @moduledoc """
  Format-independent screenplay being authored by the writer.

  `Fount.Document` remains an exact imported Fountain document. This value owns
  literal screenplay structure and authored cast identity; an import artifact
  is retained only for exact, unchanged export. No Fountain text is required
  to create or edit a screenplay.
  """
  alias Fount.Adapter.ExportResult
  alias Fount.Adapter.FDX
  alias Fount.Cast.Character
  alias Fount.Cast.Mention
  alias Fount.Fountain.Serializer
  alias Fount.ID
  alias Fount.IR.DialogueBlock
  alias Fount.IR.Element
  alias Fount.IR.Scene
  alias Fount.IR.Script
  alias Fount.IR.TitlePage
  alias Fount.Revision
  alias Fount.Screenplay.Editor
  alias Fount.Screenplay.Model

  @enforce_keys [:id, :revision, :ir]
  defstruct [:id, :revision, :ir, :import, cast: %{}, mentions: %{}, annotations: %{}, authored_items: %{}, index: nil]

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

    %__MODULE__{
      id: id,
      revision: revision(nil),
      ir: ir,
      cast: Keyword.get(opts, :cast, %{}),
      authored_items: Keyword.get(opts, :authored_items, %{})
    }
    |> Model.refresh()
  end

  @doc "Adopts a parsed Fountain document without making its source the edit authority."
  @spec from_document(Fount.Document.t()) :: t()
  def from_document(doc, opts \\ []) do
    %__MODULE__{
      id: doc.id,
      revision: revision(nil),
      ir: doc.ir,
      annotations: doc.annotations,
      import: %{format: :fountain, bytes: doc.source.raw, revision_id: nil}
    }
    |> Model.resolve_cast(Keyword.get(opts, :cast_resolution, :manual))
    |> Model.refresh()
    |> bind_import_revision()
  end

  @doc "Imports practical FDX content into the canonical model and returns fidelity losses."
  @spec from_fdx(binary(), keyword()) :: {:ok, t(), [String.t()]} | {:error, term()}
  def from_fdx(xml, opts \\ []) do
    with {:ok, result} <- FDX.decode(xml, opts) do
      model = from_document(result.document)

      import = %{
        format: :fdx,
        bytes: xml,
        revision_id: model.revision.id,
        render_hash: model.revision.render_hash,
        id: ID.v4(),
        losses: result.losses
      }

      {:ok, %{model | import: import}, result.losses}
    end
  end

  @doc "Exports the current canonical screenplay as FDX with adapter fidelity losses."
  @spec to_fdx(t()) :: {:ok, ExportResult.t()} | {:error, term()}

  def to_fdx(%__MODULE__{import: %{format: :fdx, bytes: bytes, render_hash: hash}} = model) do
    if hash == Model.refresh(model).revision.render_hash,
      do: {:ok, %ExportResult{data: bytes}},
      else: regenerate_fdx(model)
  end

  def to_fdx(%__MODULE__{} = model), do: regenerate_fdx(model)

  defp regenerate_fdx(model) do
    with {:ok, document} <- Fount.parse(to_fountain(model)),
         {:ok, result} <- FDX.export(document) do
      import_losses = if model.import, do: model.import[:losses] || [], else: []
      {:ok, %{result | losses: Enum.uniq(result.losses ++ import_losses)}}
    end
  end

  @doc "Returns original Fountain bytes for an unchanged import; otherwise serializes the model."
  @spec to_fountain(t(), keyword()) :: binary()
  def to_fountain(screenplay, opts \\ [])

  def to_fountain(%__MODULE__{} = model, opts) do
    if model.import && model.import[:format] == :fountain &&
         model.import[:render_hash] == Model.refresh(model).revision.render_hash &&
         Keyword.get(opts, :mode, :archival) == :archival do
      model.import.bytes
    else
      ir = if Keyword.get(opts, :mode) == :spec, do: Editor.spec_ir(model), else: model.ir
      Serializer.serialize(ir, Keyword.put(opts, :canonical_spacing, true))
    end
  end

  @doc "Returns Fountain bytes with an explicit fidelity report for regenerated imports."
  @spec export_fountain(t(), keyword()) :: {:ok, ExportResult.t()}
  def export_fountain(%__MODULE__{} = model, opts \\ []) do
    current_render_hash = Model.refresh(model).revision.render_hash

    losses =
      case model.import do
        %{format: :fountain, render_hash: ^current_render_hash} -> []
        %{format: :fountain} -> ["Original Fountain spacing and trivia may change after canonical editing"]
        %{format: :fdx, losses: import_losses} -> import_losses
        _ -> []
      end

    {:ok, %ExportResult{data: to_fountain(model, opts), losses: losses}}
  end

  @doc "Applies typed operations to the model and advances its revision once."
  @spec apply(t(), Fount.Edit.Op.t() | map() | [Fount.Edit.Op.t() | map()]) ::
          {:ok, t()} | {:ok, t(), Fount.Edit.ChangeSet.t()} | {:error, term()}
  def apply(%__MODULE__{} = screenplay, operations) do
    case apply(screenplay, List.wrap(operations), []) do
      {:ok, model, _changes} = result ->
        if Enum.all?(List.wrap(operations), &is_struct(&1, Fount.Edit.Op)), do: {:ok, model}, else: result

      error ->
        error
    end
  end

  def apply(%__MODULE__{} = screenplay, operations, opts),
    do: Editor.apply(screenplay, operations, opts)

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

    {:ok,
     %{target | revision: next_revision, mentions: rebind_mentions(target, next_revision.id)}
     |> Model.refresh()}
  end

  defp restore_model(%__MODULE__{}, %__MODULE__{}, _message), do: {:error, :different_screenplay}

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

    {%{updated | revision: next_revision, mentions: rebind_mentions(updated, next_revision.id)}
     |> Model.refresh(), character}
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

      {:ok, %{screenplay | mentions: mentions, revision: next_revision} |> Model.refresh()}
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
        {:ok, %{renamed | cast: cast} |> Model.refresh()}
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
  def node(%__MODULE__{} = model, id), do: Fount.Query.node(model, id)

  @spec scene(t(), String.t()) :: Scene.t() | nil
  def scene(%__MODULE__{} = model, id), do: Fount.Query.scene(model, id)

  defp refresh_outline(ir), do: Fount.IR.restore_views(ir)

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
    do: %{
      screenplay
      | import:
          Map.merge(import, %{
            revision_id: screenplay.revision.id,
            render_hash: screenplay.revision.render_hash,
            id: ID.v4()
          })
    }

  defp revision(parent), do: %Revision{id: ID.v4(), parent_id: parent, created_at: DateTime.utc_now()}
end
