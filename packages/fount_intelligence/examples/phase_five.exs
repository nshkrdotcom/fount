alias Fount.Intelligence.Acquisition.Planner
alias Fount.Intelligence.Reporting.WriterPacket
alias Fount.Observe.Sandbox

model =
  Fount.Screenplay.new(
    scenes: [
      %{
        heading: "INT. INTERROGATION ROOM - NIGHT",
        elements: [
          %{type: :action, text: "Mara closes the file and waits."},
          %{type: :character, text: "DAN"},
          %{type: :dialogue, text: "You already know what I came to say."},
          %{type: :character, text: "MARA"},
          %{type: :dialogue, text: "Then say something I don't know."}
        ]
      }
    ]
  )

request = %{
  "concern" => %{
    "statement" => "The interrogation loses pressure after the first exchange.",
    "desired_effect" => "sustained entrapment without making Mara overtly aggressive",
    "protected_strengths" => ["Mara remains restrained"]
  },
  "hypotheses" => [
    %{
      "id" => "repeated-tactic",
      "code" => "repeated_tactic",
      "hypothesis" => "The exchange stops changing tactic or leverage.",
      "alternatives" => ["The stillness may be intentional entrapment."],
      "context" => %{}
    }
  ]
}

{:ok, plan} = Planner.plan(model, request)

base_fixtures =
  Map.new(plan["base_inputs"], fn input ->
    {input["id"], %{"relevant" => 0.9}}
  end)

contextual_fixtures = %{
  "hypothesis:repeated-tactic" => %{
    "support" => 0.9,
    "counterevidence" => 0.1
  }
}

provider = Sandbox.new!(Map.merge(base_fixtures, contextual_fixtures))

{:ok, preflight} = Fount.Intelligence.preflight_playbook(model, "scene_doctor", request)
IO.puts("preflight targets=#{preflight["estimate"]["targets"]}")
IO.puts("preflight hosted_cost=#{inspect(preflight["estimate"]["hosted_cost"])}")

{:ok, packet} =
  Fount.Intelligence.run_playbook(
    model,
    "scene_doctor",
    request,
    %{observe: provider},
    run_id: "phase-five-example"
  )

true = WriterPacket.compatible?(packet)
{:ok, markdown} = Fount.Intelligence.render_packet(packet, :markdown)
IO.puts(markdown)
