defmodule Fount.Intelligence.ReaderForwardTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.Reader
  alias Fount.Intelligence.TestSupport.PhaseFourFixture, as: Fixture

  setup do
    screenplay = Fixture.screenplay()
    events = Fixture.reader_events(screenplay)
    {:ok, reader} = Reader.reduce(screenplay, events)
    {:ok, screenplay: screenplay, events: events, reader: reader}
  end

  test "private notes are not Reader checkpoints or reader-visible events", %{
    screenplay: screenplay,
    reader: reader
  } do
    note = Fixture.note(screenplay)

    refute Enum.any?(reader.points, &(&1["element_id"] == note.id))
    assert reader.ignored_private_event_ids == ["private-note"]
    refute "private-note" in reader.event_ids
  end

  test "question lifecycle opens then resolves without altering the earlier snapshot", %{
    screenplay: screenplay,
    reader: reader
  } do
    [action_1, action_2 | _] = Fixture.actions(screenplay)

    assert {:ok, first} = Reader.snapshot_at(reader, action_1.id)
    assert [%{"id" => "what-does-key-open", "status" => "open"}] = Reader.open_questions(first)

    assert {:ok, second} = Reader.snapshot_at(reader, action_2.id)
    assert Reader.open_questions(second) == []
    assert second.state.open_questions["what-does-key-open"]["status"] == "resolved"

    assert first.state.open_questions["what-does-key-open"]["status"] == "open"
  end

  test "future evidence is rejected instead of leaking backward", %{screenplay: screenplay} do
    [action_1, action_2 | _] = Fixture.actions(screenplay)

    bad =
      Fixture.event("future-leak", "reveal", "explicit", action_2, screenplay,
        key: "future-leak",
        data: %{"proposition" => "future"}
      )
      |> Map.put(:point, action_1.id)

    assert {:error, {:future_reader_evidence, "future-leak", _evidence_id, _source, _target}} =
             Reader.reduce(screenplay, [bad])
  end

  test "a future presentation mutation cannot alter an earlier Reader snapshot", %{
    screenplay: screenplay,
    events: events,
    reader: reader
  } do
    [action_1, action_2, _action_3, action_4] = Fixture.actions(screenplay)

    changed_suffix =
      Enum.map(events, fn
        %{id: "promise-fulfilled"} = event ->
          %{event | data: %{"outcome" => "Mara withholds the ledger after all."}, evidence: [Fixture.evidence(screenplay, action_4)]}

        event ->
          event
      end)

    assert {:ok, revised} = Reader.reduce(screenplay, changed_suffix)
    assert Reader.snapshot_at(reader, action_1.id) == Reader.snapshot_at(revised, action_1.id)
    assert Reader.snapshot_at(reader, action_2.id) == Reader.snapshot_at(revised, action_2.id)
  end

  test "deterministic replay produces identical snapshots", %{screenplay: screenplay, events: events, reader: reader} do
    assert {:ok, replay} = Reader.reduce(screenplay, events)
    assert replay.points == reader.points
    assert replay.snapshots == reader.snapshots
    assert Reader.inspection_packet(replay) == Reader.inspection_packet(reader)
  end

  test "moving a reveal earlier changes only snapshots at and after the new presentation point", %{
    screenplay: screenplay,
    events: events,
    reader: later_reader
  } do
    [action_1, action_2 | _] = Fixture.actions(screenplay)

    earlier_events =
      Enum.map(events, fn
        %{id: "reveal-explicit"} = event ->
          %{event | point: action_1.id, evidence: [Fixture.evidence(screenplay, action_1)]}

        event ->
          event
      end)

    assert {:ok, earlier_reader} = Reader.reduce(screenplay, earlier_events)
    assert {:ok, later_first} = Reader.snapshot_at(later_reader, action_1.id)
    assert {:ok, earlier_first} = Reader.snapshot_at(earlier_reader, action_1.id)

    refute Map.has_key?(later_first.state.reveals, "archive-key-reveal")
    assert earlier_first.state.reveals["archive-key-reveal"]["status"] == "explicit"

    assert {:ok, later_second} = Reader.snapshot_at(later_reader, action_2.id)
    assert {:ok, earlier_second} = Reader.snapshot_at(earlier_reader, action_2.id)
    assert later_second.state.reveals["archive-key-reveal"]["status"] == "explicit"
    assert earlier_second.state.reveals["archive-key-reveal"]["status"] == "explicit"
  end

  test "presentation suffix recomputation starts at the earliest affected event", %{reader: reader} do
    boundary = Reader.recomputation_boundary(reader, ["reader:key-reveal"])

    assert boundary["semantics"] == "presentation_suffix"
    assert boundary["from_ordinal"] > 0
    assert "reveal-explicit" in boundary["event_ids"]

    assert Enum.all?(boundary["snapshot_ids"], fn id ->
             point = Enum.find(reader.points, &(&1["id"] == id))
             point["ordinal"] >= boundary["from_ordinal"]
           end)

    assert Reader.recomputation_boundary(reader, ["reader:unrelated"]) == :unaffected
  end


  test "question reinforce and abandon remain explicit lifecycle events", %{screenplay: screenplay} do
    [action_1, action_2 | _] = Fixture.actions(screenplay)

    events = [
      Fixture.event("q-open", "question", "open", action_1, screenplay,
        key: "q",
        data: %{"text" => "Will Mara trust Dan?"}
      ),
      Fixture.event("q-reinforce", "question", "reinforce", action_2, screenplay,
        key: "q",
        data: %{"text" => "Dan presses for an answer."}
      ),
      Fixture.event("q-abandon", "question", "abandon", action_2, screenplay,
        key: "q",
        data: %{"reason" => "The screenplay deliberately leaves it open-ended."}
      )
    ]

    assert {:ok, reader} = Reader.reduce(screenplay, events)
    assert {:ok, second} = Reader.snapshot_at(reader, action_2.id)
    question = second.state.open_questions["q"]
    assert question["status"] == "abandoned"
    assert Enum.map(question["history"], & &1["action"]) == ["open", "reinforce", "abandon"]
    assert Reader.open_questions(second) == []
  end

  test "a later-presented flashback can update Reader state while remaining diegetically earlier", %{
    screenplay: screenplay,
    reader: reader
  } do
    [_action_1, action_2, action_3 | _] = Fixture.actions(screenplay)

    assert {:ok, before_flashback} = Reader.snapshot_at(reader, action_2.id)
    refute Map.has_key?(before_flashback.state.reveals, "key-origin-reveal")

    assert {:ok, after_flashback} = Reader.snapshot_at(reader, action_3.id)
    assert after_flashback.state.reveals["key-origin-reveal"]["status"] == "explicit"
  end

  test "trajectory rejects unknown tracks without raising", %{reader: reader} do
    assert {:error, {:unknown_reader_track, "not_a_track"}} =
             Reader.trajectory(reader, "not_a_track", "anything")
  end

  test "suspense remains inspectable components rather than one universal score", %{reader: reader} do
    suspense = reader.snapshots |> List.last() |> then(& &1.state.suspense["corridor-pressure"])

    assert suspense["data"]["components"]["threat"] == "Dan may stop her"
    refute Map.has_key?(suspense["data"], "score")
    assert suspense["claim_class"] == "model_estimated_reader_interpretation"
  end
end
