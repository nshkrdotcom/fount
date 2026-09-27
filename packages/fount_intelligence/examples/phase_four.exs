alias Fount.Intelligence.{Reader, StoryWorld, Temporal}
alias Fount.Intelligence.Reader.Event
alias Fount.Intelligence.StoryWorld.Evidence
alias Fount.Screenplay

screenplay =
  Screenplay.new(
    scenes: [
      %{
        heading: "INT. SERVICE CORRIDOR - NIGHT",
        elements: [
          %{type: :action, text: "Mara pockets the brass key."},
          %{type: :note, text: "[[Writer note: the key opens the archive.]]"}
        ]
      },
      %{
        heading: "INT. ARCHIVE DOOR - LATER",
        elements: [%{type: :action, text: "The brass key opens the archive."}]
      },
      %{
        heading: "INT. SERVICE CORRIDOR - YEARS EARLIER",
        elements: [%{type: :action, text: "Young Mara sees the key behind glass."}]
      }
    ]
  )

actions = Enum.filter(screenplay.ir.elements, &(&1.type == :action))
[action_1, action_2, action_3] = actions
note = Enum.find(screenplay.ir.elements, &(&1.type == :note))
[scene_1, scene_2, scene_3] = Enum.map(screenplay.ir.scenes, &("scene:" <> &1.id))

evidence = fn element -> Evidence.canonical_element(screenplay, element) end
record = fn type, id, element, extra ->
  %{"record_type" => type, "id" => id, "evidence" => [%{"element_id" => element.id}]}
  |> Map.merge(extra)
end

records = [
  record.("state_transition", "key-possession", action_1, %{
    "subject" => "Mara",
    "attribute" => "possession.key",
    "from" => false,
    "to" => true,
    "event_id" => scene_1
  }),
  record.("assertion", "mara-remembers-key", action_3, %{
    "subject" => "key",
    "predicate" => "origin",
    "object" => "display case",
    "stance" => "knows",
    "epistemic_owner" => "Mara",
    "story_time_refs" => [scene_3]
  }),
  record.("story_time_constraint", "flashback-before-present", action_3, %{
    "left" => scene_3,
    "right" => scene_1,
    "relations" => ["before"]
  }),
  record.("story_time_constraint", "present-before-reveal", action_2, %{
    "left" => scene_1,
    "right" => scene_2,
    "relations" => ["before"]
  })
]

{:ok, world} = StoryWorld.compile(screenplay, [], records: records)

new_event = fn id, kind, action, element, key, data, visibility ->
  {:ok, event} =
    Event.new(%{
      "id" => id,
      "kind" => kind,
      "action" => action,
      "point" => element.id,
      "key" => key,
      "claim_class" => "deterministic_derived_narrative_state",
      "visibility" => visibility,
      "data" => data,
      "evidence" => [evidence.(element)],
      "dependencies" => ["demo:#{id}"]
    })

  event
end

reader_events = [
  new_event.(
    "question-open",
    "question",
    "open",
    action_1,
    "what-does-key-open",
    %{"text" => "What does the key open?"},
    "reader_visible"
  ),
  new_event.(
    "private-note",
    "reveal",
    "explicit",
    note,
    "private-note",
    %{"proposition" => "The key opens the archive."},
    "private"
  ),
  new_event.(
    "reveal",
    "reveal",
    "explicit",
    action_2,
    "archive-key",
    %{"proposition" => "The key opens the archive."},
    "reader_visible"
  ),
  new_event.(
    "question-resolve",
    "question",
    "resolve",
    action_2,
    "what-does-key-open",
    %{"answer" => "The archive."},
    "reader_visible"
  )
]

{:ok, reader} = Reader.reduce(screenplay, reader_events)

IO.puts("=== STORY TIME (flashback is diegetically earlier) ===")
IO.inspect(StoryWorld.story_time_relation(world, scene_3, scene_1))

IO.puts("\n=== PRESENTATION VIEW (flashback is shown later) ===")
IO.inspect(Temporal.sequence_view(world, [scene_1, scene_2, scene_3], ordering: :presentation))

IO.puts("\n=== READER AFTER FIRST ACTION ===")
{:ok, first} = Reader.snapshot_at(reader, action_1.id)
IO.inspect(Fount.Screenplay.Model.plain(first.state))

IO.puts("\n=== READER AFTER REVEAL ===")
{:ok, second} = Reader.snapshot_at(reader, action_2.id)
IO.inspect(Fount.Screenplay.Model.plain(second.state))

IO.puts("\n=== PRIVATE NOTE DOES NOT ENTER READER STATE ===")
IO.inspect(reader.ignored_private_event_ids)

IO.puts("\n=== TEMPORAL CHARACTER VIEW ===")
IO.inspect(Temporal.character_state(world, "Mara", scene_2))
