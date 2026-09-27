alias Fount.Intelligence
alias Fount.Intelligence.Acquisition.CapabilityMeasurements
alias Fount.Observe.Sandbox
alias Fount.Screenplay

screenplay =
  Screenplay.new(
    scenes: [
      %{
        heading: "INT. SERVICE OFFICE - NIGHT",
        elements: [
          %{
            type: :action,
            text: "Mara asks Dan for the archive ledger before the morning audit."
          },
          %{type: :action, text: "Dan keeps the archive key in his palm instead of answering."}
        ]
      }
    ]
  )

scene = hd(screenplay.ir.scenes)
{:ok, spec} = CapabilityMeasurements.fetch("scene_engine")
answers = Map.new(spec["questions"], fn {key, _question} -> {to_string(key), 0.9} end)
provider = Sandbox.new!(%{"capability:scene_engine:scene:#{scene.id}" => answers})

request = %{
  "selection" => %{"targets" => [%{"kind" => "scene", "id" => scene.id}]},
  "subject" => %{"scene_id" => scene.id},
  "concern" => %{
    "summary" => "Does the office scene hand off enough pressure to justify the next scene?"
  },
  "intent" => %{"desired_effect" => "urgent bargaining"},
  "protected_strengths" => ["Dan's quiet control of the key"]
}

{:ok, packet} =
  Intelligence.run_capability_playbook(
    screenplay,
    "scene_doctor",
    request,
    %{observe: provider}
  )

{:ok, markdown} = Intelligence.render_packet(packet, :markdown)
IO.puts(markdown)
