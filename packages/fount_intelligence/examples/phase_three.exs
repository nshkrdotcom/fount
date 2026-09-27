alias Fount.Intelligence.StoryWorld
alias Fount.Observe.{Distribution, EvidenceRef, MeasurementResult, Observation, TargetRef}
alias Fount.Screenplay

screenplay =
  Screenplay.new(
    scenes: [
      %{
        heading: "INT. SERVICE CORRIDOR - NIGHT",
        elements: [%{type: :action, text: "Mara pockets the brass key."}]
      },
      %{
        heading: "INT. SERVICE CORRIDOR - YEARS EARLIER",
        elements: [%{type: :action, text: "The key hangs behind glass."}]
      },
      %{
        heading: "EXT. LOADING DOCK - DAWN",
        elements: [%{type: :action, text: "Mara leaves the key beside Dan."}]
      }
    ]
  )

[first_scene, flashback_scene, later_scene] = screenplay.ir.scenes
first_action = Enum.find(screenplay.ir.elements, &(&1.type == :action))

target = %TargetRef{
  screenplay_id: screenplay.id,
  revision_id: screenplay.revision.id,
  kind: "element",
  id: first_action.id
}

evidence = %EvidenceRef{
  id: "demo-evidence-1",
  screenplay_id: screenplay.id,
  revision_id: screenplay.revision.id,
  target: target,
  excerpt: first_action.text,
  excerpt_sha256: Fount.ID.hash(first_action.text),
  role: "input_context"
}

measurement = %MeasurementResult{
  id: "demo-measurement-1",
  value: %{"visible" => true},
  distribution: %Distribution{kind: :noul, values: [{"true", 0.9}, {"false", 0.1}]},
  output_contract_id: "demo.visibility",
  output_contract_sha256: "demo-contract",
  measurement_spec_sha256: "demo-spec",
  input_sha256: "demo-input",
  provider_fingerprint: %{"provider" => "fixture", "model" => "frozen"},
  semantic_execution_sha256: "demo-execution"
}

observation = %Observation{
  id: "demo-observation-1",
  kind: "demo.visibility",
  target: target,
  result: measurement,
  sensor_id: "fixture",
  evidence: [evidence]
}

evidence_at = fn scene ->
  element_id = Enum.at(scene.element_ids, 1)
  [%{"element_id" => element_id}]
end

first_event = "scene:" <> first_scene.id
flashback_event = "scene:" <> flashback_scene.id
later_event = "scene:" <> later_scene.id

records = [
  %{
    "record_type" => "story_time_constraint",
    "id" => "flashback-before-first",
    "left" => flashback_event,
    "right" => first_event,
    "relations" => ["before"],
    "evidence" => evidence_at.(flashback_scene)
  },
  %{
    "record_type" => "story_time_constraint",
    "id" => "first-before-later",
    "left" => first_event,
    "right" => later_event,
    "relations" => ["before"],
    "evidence" => evidence_at.(first_scene)
  },
  %{
    "record_type" => "state_transition",
    "id" => "key-taken",
    "subject" => "brass-key",
    "attribute" => "possessor",
    "to" => "Mara",
    "event_id" => first_event,
    "evidence" => evidence_at.(first_scene)
  },
  %{
    "record_type" => "causal_relation",
    "id" => "key-enables-dock",
    "causal_type" => "enables",
    "from" => first_event,
    "to" => later_event,
    "evidence" => evidence_at.(later_scene)
  }
]

{:ok, world} = StoryWorld.compile(screenplay, [observation], records: records)

IO.puts(
  "flashback key possession: #{inspect(StoryWorld.state_at(world, "brass-key", "possessor", flashback_event))}"
)

IO.puts(
  "later key possession: #{inspect(StoryWorld.state_at(world, "brass-key", "possessor", later_event))}"
)

IO.puts("causal descendants: #{inspect(StoryWorld.causal_descendants(world, first_event))}")

IO.puts(
  "\n" <>
    StoryWorld.render_markdown(world,
      question: "What is established about the key across the non-linear sequence?"
    )
)
