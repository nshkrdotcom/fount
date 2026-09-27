alias Fount.Intelligence
alias Fount.Intelligence.Acquisition.CapabilityMeasurements
alias Fount.Intelligence.StoryWorld.Evidence
alias Fount.Observe.Sandbox
alias Fount.Screenplay

screenplay =
  Screenplay.new(
    scenes: [
      %{
        heading: "INT. SERVICE OFFICE - NIGHT",
        elements: [
          %{type: :action, text: "Mara turns a cracked watch over. The initials D.R. are cut into the back."}
        ]
      },
      %{
        heading: "EXT. SERVICE ROAD - YEARS EARLIER",
        elements: [
          %{type: :action, text: "Years earlier, Dan presses the uncracked watch into Mara's palm."}
        ]
      }
    ]
  )

[first, second] = Enum.filter(screenplay.ir.elements, &(&1.type == :action))
[first_scene, second_scene] = screenplay.ir.scenes

reader_events = [
  %{
    "id" => "watch-question",
    "kind" => "question",
    "action" => "open",
    "point" => first.id,
    "key" => "watch-origin",
    "claim_class" => "deterministic_derived_narrative_state",
    "data" => %{"text" => "Why does Mara have Dan's D.R. watch?"},
    "evidence" => [Evidence.canonical_element(screenplay, first)]
  },
  %{
    "id" => "watch-origin-reveal",
    "kind" => "reveal",
    "action" => "explicit",
    "point" => second.id,
    "key" => "watch-origin-reveal",
    "claim_class" => "deterministic_derived_narrative_state",
    "data" => %{"proposition" => "Dan gave Mara the watch years earlier."},
    "evidence" => [Evidence.canonical_element(screenplay, second)]
  },
  %{
    "id" => "watch-question-resolve",
    "kind" => "question",
    "action" => "resolve",
    "point" => second.id,
    "key" => "watch-origin",
    "claim_class" => "deterministic_derived_narrative_state",
    "data" => %{"answer" => "Dan gave it to Mara before she left."},
    "evidence" => [Evidence.canonical_element(screenplay, second)]
  }
]

spec = CapabilityMeasurements.audience_reader_experience()
answers = Map.new(spec["questions"], fn {key, _question} -> {to_string(key), 0.9} end)

provider =
  Sandbox.new!(%{
    "capability:audience_reader_experience:scene:#{first_scene.id}" => answers,
    "capability:audience_reader_experience:scene:#{second_scene.id}" => answers
  })

{:ok, packet} =
  Intelligence.run_capability_playbook(
    screenplay,
    "suspense_audit",
    %{
      "selection" => %{
        "targets" => [
          %{"kind" => "scene", "id" => first_scene.id},
          %{"kind" => "scene", "id" => second_scene.id}
        ]
      },
      "reader_events" => reader_events,
      "concern" => "Does the watch create a first-exposure question that the later flashback answers?"
    },
    %{observe: provider}
  )

{:ok, markdown} = Intelligence.render_packet(packet, :markdown)
IO.puts(markdown)
