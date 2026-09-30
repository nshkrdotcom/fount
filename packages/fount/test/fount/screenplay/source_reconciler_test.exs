defmodule Fount.Screenplay.SourceReconcilerTest do
  use ExUnit.Case, async: true

  alias Fount.Screenplay
  alias Fount.Screenplay.SourceReconciler

  @source """
  Title: Draft Fidelity

  INT. LAB - NIGHT

  A monitor blinks.

  MARA
  Keep the raw source.

  INT. HALL - NIGHT

  The door stays shut.
  """

  test "reconciles source onto the existing screenplay and preserves unaffected identities" do
    {:ok, document} = Fount.parse(@source, document_id: Fount.ID.v4())
    base = Screenplay.from_document(document, cast_resolution: :literal_cues)
    action = Enum.find(base.ir.elements, &(&1.type == :action and &1.text == "The door stays shut."))
    cue = Enum.find(base.ir.elements, &(&1.type == :character))
    cast_ids = Map.keys(base.cast)

    edited = String.replace(@source, "A monitor blinks.", "A monitor blinks twice.")

    assert {:ok, result} = SourceReconciler.reconcile(base, edited)
    assert result.screenplay.id == base.id
    assert result.screenplay.revision.parent_id == base.revision.id
    assert Enum.any?(result.screenplay.ir.elements, &(&1.id == action.id))
    assert Enum.any?(result.screenplay.ir.elements, &(&1.id == cue.id))
    assert Enum.all?(cast_ids, &Map.has_key?(result.screenplay.cast, &1))
    assert result.fidelity["exact_source_round_trip"]
    assert Screenplay.to_fountain(result.screenplay) == edited
  end

  test "persisted identity anchors keep draft-created node IDs stable after later source shifts" do
    {:ok, document} = Fount.parse(@source, document_id: Fount.ID.v4())
    base = Screenplay.from_document(document, cast_resolution: :literal_cues)

    first_raw = String.replace(@source, "A monitor blinks.", "A monitor blinks.\n\nA new cable sparks.")
    assert {:ok, first} = SourceReconciler.reconcile(base, first_raw)
    created = Enum.find(first.screenplay.ir.elements, &(&1.type == :action and &1.text == "A new cable sparks."))
    assert created

    second_raw = String.replace(first_raw, "A monitor blinks.", "A status light pulses.\n\nA monitor blinks.")

    assert {:ok, second} =
             SourceReconciler.reconcile(base, second_raw,
               prior_source: first_raw,
               identity_anchors: first.identity_anchors
             )

    retained = Enum.find(second.screenplay.ir.elements, &(&1.type == :action and &1.text == "A new cable sparks."))
    assert retained.id == created.id
    assert created.id in second.fidelity["preserved_element_ids"]
  end

  test "reports blocking intermediate Fountain without discarding raw input" do
    {:ok, document} = Fount.parse(@source, document_id: Fount.ID.v4())
    base = Screenplay.from_document(document, cast_resolution: :literal_cues)
    raw = @source <> "\n[[unfinished"

    assert {:error, {:invalid_source, blockers, _all}} =
             SourceReconciler.reconcile(base, raw)

    assert Enum.any?(blockers, &(&1.code == :unclosed_note))
    assert Screenplay.to_fountain(base) == @source
  end

  test "uses a caller-supplied deterministic candidate revision identity" do
    {:ok, document} = Fount.parse(@source, document_id: Fount.ID.v4())
    base = Screenplay.from_document(document, cast_resolution: :literal_cues)
    revision_id = Fount.ID.v5(base.id, "phase05-test")
    edited = String.replace(@source, "Keep the raw source.", "Keep every raw source byte.")

    assert {:ok, result} =
             SourceReconciler.reconcile(base, edited, revision_id: revision_id)

    assert result.screenplay.revision.id == revision_id
    assert result.screenplay.revision.parent_id == base.revision.id
    assert result.fidelity["source_sha256"] == Fount.ID.hash(edited)
  end

  test "bounds raw source before parsing" do
    base = Screenplay.new()
    assert {:error, {:source_too_large, 4}} = SourceReconciler.reconcile(base, "12345", max_bytes: 4)
  end
end
