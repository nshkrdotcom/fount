defmodule Fount.Persistence do
  @moduledoc """
  Transactional PostgreSQL boundary around Fount's immutable screenplay model.

  Fount owns the tables and queries. Callers start/configure `Fount.Repo`; pure
  model construction, edits and adapter operations do not require it.
  """

  import Ecto.Query

  alias Fount.Annotation
  alias Fount.Annotation.{Provenance, Target}
  alias Fount.Cast.{Character, Mention}
  alias Fount.ID
  alias Fount.IR.{DialogueBlock, Element, Scene, Script, TitlePage}
  alias Fount.Persistence.Codec
  alias Fount.Persistence.Schema
  alias Fount.Revision
  alias Fount.Screenplay
  alias Fount.Store.SQLite

  @tables [
    Schema.MentionCandidate,
    Schema.Mention,
    Schema.Assertion,
    Schema.Element,
    Schema.DialogueTurn,
    Schema.Scene,
    Schema.TitleEntry,
    Schema.CharacterAlias,
    Schema.Character
  ]

  @doc "Path to Fount-owned Ecto migrations."
  @spec migrations_path() :: Path.t()
  def migrations_path, do: Application.app_dir(:fount, "priv/repo/migrations")

  @doc "Saves a validated model as one new head, rejecting a stale expected revision."
  @spec save(module(), String.t(), Screenplay.t(), keyword()) :: :ok | {:error, term()}
  def save(repo, key, %Screenplay{} = model, opts \\ []) do
    with :ok <- validate(model),
         {:ok, :ok} <- repo.transaction(fn -> save_transaction(repo, key, model, opts) end) do
      :ok
    end
  end

  @doc "Loads current typed rows into an immutable screenplay value."
  @spec load(module(), String.t()) :: {:ok, Screenplay.t()} | {:error, :not_found}
  def load(repo, key) do
    {:ok, result} =
      repo.transaction(fn ->
        case repo.one(from(s in Schema.Screenplay, where: s.key == ^key, lock: "FOR SHARE")) do
          nil -> {:error, :not_found}
          row -> {:ok, load_rows(repo, row)}
        end
      end)

    result
  end

  @doc "Returns immutable historical revision identifiers in creation order."
  @spec history(module(), String.t()) :: [Revision.t()]
  def history(repo, key) do
    case repo.get_by(Schema.Screenplay, key: key) do
      nil ->
        []

      row ->
        repo.all(from(r in Schema.Revision, where: r.screenplay_id == ^row.id, order_by: [r.inserted_at, r.id]))
        |> Enum.map(&revision_from_row/1)
    end
  end

  @doc "Reconstructs an immutable old model snapshot for history or undo."
  @spec at_revision(module(), String.t()) :: {:ok, Screenplay.t()} | {:error, :not_found}
  def at_revision(repo, id) do
    case repo.get(Schema.Revision, id) do
      nil ->
        {:error, :not_found}

      row ->
        model = Codec.decode(row.model)
        artifact = repo.get_by(Schema.ImportArtifact, screenplay_id: row.screenplay_id, imported_model_revision_id: id)
        {:ok, attach_import(model, artifact)}
    end
  end

  @doc "Imports all revisions of one v1 SQLite Fountain document into this Repo atomically."
  @spec import_legacy(module(), SQLite.t(), String.t(), String.t()) ::
          {:ok, Screenplay.t()} | {:error, term()}
  def import_legacy(repo, legacy, source_key, target_key) do
    with {:ok, history} <- SQLite.history(legacy, source_key),
         {:ok, documents} <- legacy_documents(legacy, source_key, history) do
      repo.transaction(fn -> save_legacy_documents(repo, target_key, documents) end)
    end
  end

  defp legacy_documents(legacy, key, history) do
    Enum.reduce_while(history, {:ok, []}, fn item, {:ok, acc} ->
      case SQLite.load_revision(legacy, key, item.revision_id) do
        {:ok, doc} -> {:cont, {:ok, [doc | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, []} -> {:error, :not_found}
      {:ok, docs} -> {:ok, Enum.reverse(docs)}
      error -> error
    end
  end

  defp save_legacy_documents(repo, key, docs) do
    docs
    |> Enum.with_index()
    |> Enum.reduce(nil, fn {doc, index}, previous ->
      revision_id = ID.v5(doc.id, ["legacy:", doc.revision.id])
      model = Screenplay.from_document(doc)

      model = %{
        model
        | revision: %{model.revision | id: revision_id},
          import: %{model.import | revision_id: revision_id}
      }

      expected = if index == 0, do: :new, else: previous.revision.id

      case save(repo, key, model, expected_revision: expected) do
        :ok -> model
        {:error, reason} -> repo.rollback(reason)
      end
    end)
  end

  defp attach_import(model, nil), do: model

  defp attach_import(model, artifact) do
    %{
      model
      | import: %{
          format: String.to_existing_atom(artifact.format),
          bytes: artifact.original_bytes,
          revision_id: artifact.imported_model_revision_id,
          losses: artifact.fidelity["losses"] || []
        }
    }
  end

  defp save_transaction(repo, key, model, opts) do
    current = repo.one(from(s in Schema.Screenplay, where: s.key == ^key, lock: "FOR UPDATE"))
    expected = Keyword.get(opts, :expected_revision, :new)
    actual = if current, do: current.current_revision_id, else: nil

    cond do
      current && current.id != model.id -> repo.rollback(:screenplay_identity_conflict)
      not expected?(actual, expected) -> repo.rollback({:conflict, actual || :missing})
      true -> persist(repo, current, key, model, actual, opts)
    end
  end

  defp expected?(nil, :new), do: true
  defp expected?(actual, actual) when is_binary(actual), do: true
  defp expected?(_actual, _expected), do: false

  defp persist(repo, current, key, model, parent, opts) do
    now = DateTime.utc_now()
    model = %{model | revision: %{model.revision | parent_id: parent}}

    if is_nil(current) do
      repo.insert!(%Schema.Screenplay{id: model.id, key: key, inserted_at: now, updated_at: now})
    end

    snapshot = Codec.encode(model)

    repo.insert!(%Schema.Revision{
      id: model.revision.id,
      screenplay_id: model.id,
      parent_id: parent,
      model: snapshot,
      model_sha256: ID.hash(Jason.encode!(snapshot)),
      actor: model.revision.actor,
      message: model.revision.message,
      inserted_at: now
    })

    clear_projection(repo, model.id)
    insert_projection(repo, model)
    insert_import(repo, model, now)
    insert_acceptance(repo, model, parent, opts, now)

    repo.update_all(from(s in Schema.Screenplay, where: s.id == ^model.id),
      set: [current_revision_id: model.revision.id, updated_at: now]
    )

    :ok
  end

  defp clear_projection(repo, id) do
    Enum.each(@tables, fn table -> repo.delete_all(from(row in table, where: row.screenplay_id == ^id)) end)
  end

  defp insert_projection(repo, model) do
    id = model.id
    elements = Map.new(model.ir.elements, &{&1.id, &1})
    scene_for = Map.new(for scene <- model.ir.scenes, element_id <- scene.element_ids, do: {element_id, scene.id})

    turn_for =
      Map.new(
        for turn <- model.ir.dialogue_blocks, element_id <- [turn.cue_id | turn.body_ids], do: {element_id, turn.id}
      )

    if model.ir.title_page do
      model.ir.title_page.entries
      |> Enum.with_index()
      |> Enum.each(fn {entry, ordinal} ->
        repo.insert!(%Schema.TitleEntry{
          id: entry.id,
          screenplay_id: id,
          ordinal: ordinal,
          key: entry.key,
          values: entry.values
        })
      end)
    end

    model.ir.scenes
    |> Enum.with_index()
    |> Enum.each(fn {scene, ordinal} ->
      parts = Fount.SceneHeading.parse(Map.fetch!(elements, scene.heading_id).text)

      repo.insert!(%Schema.Scene{
        id: scene.id,
        screenplay_id: id,
        ordinal: ordinal,
        heading_element_id: scene.heading_id,
        scene_number: scene.number,
        omitted: scene.omitted?,
        location_head: List.first(parts.locations),
        location_parts: parts.locations,
        time_of_day: parts.time
      })
    end)

    model.ir.dialogue_blocks
    |> Enum.with_index()
    |> Enum.each(fn {turn, ordinal} ->
      repo.insert!(%Schema.DialogueTurn{
        id: turn.id,
        screenplay_id: id,
        scene_id: Map.fetch!(scene_for, turn.cue_id),
        cue_element_id: turn.cue_id,
        ordinal: ordinal,
        dual_with_id: turn.dual_with
      })
    end)

    model.ir.elements
    |> Enum.with_index()
    |> Enum.each(fn {element, ordinal} ->
      repo.insert!(%Schema.Element{
        id: element.id,
        screenplay_id: id,
        scene_id: Map.get(scene_for, element.id),
        turn_id: Map.get(turn_for, element.id),
        ordinal: ordinal,
        type: Atom.to_string(element.type),
        text: element.text,
        attrs: json_map(element.attrs || %{})
      })
    end)

    Enum.each(model.cast, fn {_id, character} -> insert_character(repo, id, character) end)

    Enum.each(model.mentions, fn {_id, mention} ->
      insert_mention(repo, id, model.revision.id, mention)

      Enum.each(mention.candidate_ids, fn character_id ->
        repo.insert!(%Schema.MentionCandidate{
          screenplay_id: id,
          mention_id: mention.id,
          character_id: character_id
        })
      end)
    end)

    Enum.each(model.annotations, fn {_id, annotation} ->
      insert_assertion(repo, id, model.revision.id, annotation)
    end)
  end

  defp insert_assertion(repo, screenplay_id, revision_id, annotation) do
    value = %{
      "data" => json_value(annotation.value),
      "provenance" => json_value(Map.from_struct(annotation.provenance)),
      "span" => json_value(annotation.target.span)
    }

    repo.insert!(%Schema.Assertion{
      id: annotation.id,
      screenplay_id: screenplay_id,
      namespace: annotation.namespace,
      kind: to_string(annotation.kind),
      target_kind: "node",
      target_id: annotation.target.node_id,
      value: value,
      model_revision_id: revision_id,
      producer: annotation.provenance.producer,
      confidence: annotation.confidence,
      dependencies: annotation.dependencies || [],
      authored: annotation.provenance.producer == "writer"
    })
  end

  defp insert_character(repo, screenplay_id, character) do
    repo.insert!(%Schema.Character{
      id: character.id,
      screenplay_id: screenplay_id,
      display_name: character.display_name,
      notes: character.notes,
      attributes: json_map(character.attributes)
    })

    aliases = [%{alias: character.display_name, kind: :name} | character.aliases]

    aliases
    |> Enum.uniq_by(&{Fount.Index.normalize_character(&1.alias), &1.kind})
    |> Enum.each(fn item ->
      normalized = Fount.Index.normalize_character(item.alias)
      alias_id = ID.v5(character.id, [normalized, ":", to_string(item.kind)])

      repo.insert!(%Schema.CharacterAlias{
        id: alias_id,
        screenplay_id: screenplay_id,
        character_id: character.id,
        alias: item.alias,
        normalized_alias: normalized,
        kind: to_string(item.kind)
      })
    end)
  end

  defp insert_mention(repo, screenplay_id, revision_id, mention) do
    repo.insert!(%Schema.Mention{
      id: mention.id,
      screenplay_id: screenplay_id,
      element_id: mention.element_id,
      character_id: mention.character_id,
      role: to_string(mention.role),
      status: to_string(mention.status),
      surface: mention.surface,
      byte_start: mention.byte_start,
      byte_end: mention.byte_end,
      model_revision_id: revision_id,
      producer: mention.producer || "unknown",
      confidence: mention.confidence
    })
  end

  defp insert_import(_repo, %Screenplay{import: nil}, _now), do: :ok

  defp insert_import(repo, model, now) do
    import = model.import
    hash = ID.hash(import.bytes)
    artifact_id = ID.v5(model.id, [to_string(import.format), ":", import.revision_id, ":", hash])

    if is_nil(repo.get(Schema.ImportArtifact, artifact_id)) do
      repo.insert!(%Schema.ImportArtifact{
        id: artifact_id,
        screenplay_id: model.id,
        format: to_string(import.format),
        original_bytes: import.bytes,
        bytes_sha256: hash,
        imported_model_revision_id: import.revision_id,
        fidelity: %{"losses" => import[:losses] || []},
        inserted_at: now
      })
    end
  end

  defp insert_acceptance(repo, model, parent, opts, now) do
    if acceptance = opts[:acceptance] do
      inference = acceptance.inference || %{}

      repo.insert!(%Schema.Acceptance{
        id: ID.v4(),
        screenplay_id: model.id,
        resulting_revision_id: model.revision.id,
        base_revision_id: parent,
        actor: opts[:actor],
        provider: to_string(inference[:provider]),
        model: inference[:model],
        operations: Enum.map(acceptance.operations, &json_map(Map.take(&1, [:kind, :target]))),
        inserted_at: now
      })
    end
  end

  defp validate(model) do
    element_ids = MapSet.new(model.ir.elements, & &1.id)
    scene_ids = MapSet.new(model.ir.scenes, & &1.id)
    cast_ids = MapSet.new(Map.keys(model.cast))
    title_ids = if model.ir.title_page, do: Enum.map(model.ir.title_page.entries, & &1.id), else: []
    target_ids = MapSet.new([model.id | MapSet.to_list(element_ids) ++ MapSet.to_list(scene_ids) ++ title_ids])

    cond do
      MapSet.size(element_ids) != length(model.ir.elements) ->
        {:error, :duplicate_element_id}

      MapSet.size(scene_ids) != length(model.ir.scenes) ->
        {:error, :duplicate_scene_id}

      Enum.any?(model.ir.scenes, &invalid_scene?(&1, element_ids)) ->
        {:error, :invalid_scene_reference}

      Enum.any?(model.ir.dialogue_blocks, &invalid_turn?(&1, element_ids)) ->
        {:error, :invalid_dialogue_reference}

      Enum.any?(model.mentions, fn {_id, item} -> invalid_mention?(model, item, element_ids, cast_ids) end) ->
        {:error, :invalid_mention_evidence}

      Enum.any?(model.annotations, fn {_id, item} -> invalid_annotation?(item, target_ids) end) ->
        {:error, :invalid_annotation_target}

      true ->
        :ok
    end
  end

  defp invalid_scene?(scene, element_ids) do
    not MapSet.member?(element_ids, scene.heading_id) or
      Enum.any?(scene.element_ids, &(not MapSet.member?(element_ids, &1)))
  end

  defp invalid_turn?(turn, element_ids) do
    not MapSet.member?(element_ids, turn.cue_id) or
      Enum.any?(turn.body_ids, &(not MapSet.member?(element_ids, &1)))
  end

  defp invalid_annotation?(annotation, target_ids) do
    not MapSet.member?(target_ids, annotation.target.node_id) or
      Enum.any?(annotation.dependencies || [], &(not MapSet.member?(target_ids, &1)))
  end

  defp invalid_mention?(model, mention, element_ids, cast_ids) do
    element = Screenplay.node(model, mention.element_id)

    not MapSet.member?(element_ids, mention.element_id) or is_nil(element) or
      invalid_mention_candidates?(mention, cast_ids) or invalid_mention_span?(mention, element.text)
  end

  defp invalid_mention_candidates?(%Mention{candidate_ids: candidates} = mention, cast_ids)
       when is_list(candidates) do
    (not is_nil(mention.character_id) and not MapSet.member?(cast_ids, mention.character_id)) or
      Enum.any?(candidates, &(not MapSet.member?(cast_ids, &1))) or
      length(candidates) != length(Enum.uniq(candidates)) or
      invalid_candidate_resolution?(mention, candidates)
  end

  defp invalid_mention_candidates?(_mention, _cast_ids), do: true

  defp invalid_candidate_resolution?(mention, candidates) do
    selected = mention.character_id

    (mention.status == :ambiguous and (not is_nil(selected) or length(candidates) < 2)) or
      (not is_nil(selected) and candidates != [] and selected not in candidates)
  end

  defp invalid_mention_span?(mention, text) do
    mention.byte_start < 0 or mention.byte_end <= mention.byte_start or
      mention.byte_end > byte_size(text) or
      binary_part(text, mention.byte_start, mention.byte_end - mention.byte_start) != mention.surface
  end

  defp load_rows(repo, head) do
    id = head.id
    revision = repo.get!(Schema.Revision, head.current_revision_id)
    titles = repo.all(from(x in Schema.TitleEntry, where: x.screenplay_id == ^id, order_by: x.ordinal))
    scenes = repo.all(from(x in Schema.Scene, where: x.screenplay_id == ^id, order_by: x.ordinal))
    turns = repo.all(from(x in Schema.DialogueTurn, where: x.screenplay_id == ^id, order_by: x.ordinal))
    elements = repo.all(from(x in Schema.Element, where: x.screenplay_id == ^id, order_by: x.ordinal))
    characters = repo.all(from(x in Schema.Character, where: x.screenplay_id == ^id))
    aliases = repo.all(from(x in Schema.CharacterAlias, where: x.screenplay_id == ^id))
    mentions = repo.all(from(x in Schema.Mention, where: x.screenplay_id == ^id))
    candidates = repo.all(from(x in Schema.MentionCandidate, where: x.screenplay_id == ^id))
    assertions = repo.all(from(x in Schema.Assertion, where: x.screenplay_id == ^id))
    candidates_by_mention = Enum.group_by(candidates, & &1.mention_id, & &1.character_id)

    ir =
      %Script{
        document_id: id,
        title_page: title_from_rows(titles),
        scenes: Enum.map(scenes, &scene_from_row(&1, elements)),
        dialogue_blocks: Enum.map(turns, &turn_from_row(&1, elements)),
        elements: Enum.map(elements, &element_from_row/1),
        outline: [],
        metadata: %{}
      }
      |> Fount.IR.restore_views()

    model = %Screenplay{
      id: id,
      revision: revision_from_row(revision),
      ir: ir,
      cast: Map.new(characters, &{&1.id, character_from_row(&1, aliases)}),
      mentions: Map.new(mentions, &{&1.id, mention_from_row(&1, Map.get(candidates_by_mention, &1.id, []))}),
      annotations: Map.new(assertions, &{&1.id, annotation_from_row(&1)})
    }

    case repo.one(
           from(x in Schema.ImportArtifact, where: x.screenplay_id == ^id, order_by: [desc: x.inserted_at], limit: 1)
         ) do
      nil ->
        model

      artifact ->
        %{
          model
          | import: %{
              format: String.to_existing_atom(artifact.format),
              bytes: artifact.original_bytes,
              revision_id: artifact.imported_model_revision_id,
              losses: artifact.fidelity["losses"] || []
            }
        }
    end
  end

  defp title_from_rows([]), do: nil

  defp title_from_rows(rows),
    do: %TitlePage{entries: Enum.map(rows, &%TitlePage.Entry{id: &1.id, key: &1.key, values: &1.values})}

  defp scene_from_row(row, elements) do
    %Scene{
      id: row.id,
      heading_id: row.heading_element_id,
      element_ids: for(element <- elements, element.scene_id == row.id, do: element.id),
      number: row.scene_number,
      omitted?: row.omitted
    }
  end

  defp turn_from_row(row, elements) do
    %DialogueBlock{
      id: row.id,
      cue_id: row.cue_element_id,
      body_ids:
        for(element <- elements, element.turn_id == row.id and element.id != row.cue_element_id, do: element.id),
      dual_with: row.dual_with_id
    }
  end

  defp element_from_row(row) do
    attrs =
      Map.new(row.attrs || %{}, fn {key, value} ->
        if key in ["forced?", "number", "extension", "dual?", "level", "intentional_blank?"],
          do: {String.to_existing_atom(key), value},
          else: {key, value}
      end)

    %Element{id: row.id, type: String.to_existing_atom(row.type), text: row.text, attrs: attrs}
  end

  defp character_from_row(row, aliases) do
    entries =
      for alias_row <- aliases,
          alias_row.character_id == row.id,
          do: %{alias: alias_row.alias, kind: String.to_existing_atom(alias_row.kind)}

    %Character{
      id: row.id,
      display_name: row.display_name,
      notes: row.notes,
      attributes: row.attributes,
      aliases: entries
    }
  end

  defp mention_from_row(row, candidates) do
    %Mention{
      id: row.id,
      element_id: row.element_id,
      character_id: row.character_id,
      role: String.to_existing_atom(row.role),
      status: String.to_existing_atom(row.status),
      surface: row.surface,
      byte_start: row.byte_start,
      byte_end: row.byte_end,
      model_revision_id: row.model_revision_id,
      producer: row.producer,
      confidence: row.confidence,
      candidate_ids: Enum.sort(candidates)
    }
  end

  defp annotation_from_row(row) do
    source = row.value["provenance"] || %{}

    created_at =
      case source["created_at"] do
        nil -> nil
        text -> elem(DateTime.from_iso8601(text), 1)
      end

    provenance = %Provenance{
      producer: row.producer,
      producer_version: source["producer_version"],
      model: source["model"],
      source_revision: source["source_revision"],
      created_at: created_at,
      metadata: source["metadata"]
    }

    %Annotation{
      id: row.id,
      namespace: row.namespace,
      kind: row.kind,
      target: %Target{node_id: row.target_id, span: row.value["span"]},
      value: row.value["data"],
      provenance: provenance,
      confidence: row.confidence,
      dependencies: row.dependencies
    }
  end

  defp revision_from_row(row) do
    %Revision{
      id: row.id,
      parent_id: row.parent_id,
      actor: row.actor,
      message: row.message,
      created_at: row.inserted_at
    }
  end

  defp json_map(value), do: value |> Jason.encode!() |> Jason.decode!()
  defp json_value(value), do: value |> Jason.encode!() |> Jason.decode!()
end
