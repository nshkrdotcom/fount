alias Fount.Intelligence
alias Fount.Intelligence.Acquisition.CapabilityMeasurements
alias Fount.Observe.Sandbox
alias Fount.Screenplay

before =
  Screenplay.new(
    scenes: [
      %{
        heading: "INT. SERVICE OFFICE - NIGHT",
        elements: [
          %{
            type: :action,
            text: "Mara turns Dan's cracked watch over beside the sealed audit ledger."
          },
          %{type: :character, text: "DAN"},
          %{type: :dialogue, text: "Keep one thing."},
          %{type: :character, text: "MARA"},
          %{type: :dialogue, text: "Not this."}
        ]
      }
    ]
  )

[base_scene] = before.ir.scenes

{:ok, candidate} =
  Screenplay.apply(
    before,
    Fount.Edit.insert_scene_after(
      base_scene.id,
      "EXT. LOADING DOCK - PRE-DAWN",
      [
        %{
          type: :action,
          text:
            "Mara slides the ledger to the waiting investigator but closes her hand around the watch."
        },
        %{type: :character, text: "DAN"},
        %{type: :dialogue, text: "You kept it."},
        %{type: :character, text: "MARA"},
        %{type: :dialogue, text: "I kept the part that was mine."}
      ]
    )
  )

candidate_scene = List.last(candidate.ir.scenes)
spec = CapabilityMeasurements.revision_intelligence()

before_answers =
  Map.new(spec["questions"], fn {key, _question} ->
    value =
      if key in [:intended_effect_present, :protected_strength_preserved], do: 0.1, else: 0.1

    {to_string(key), value}
  end)

after_answers =
  Map.new(spec["questions"], fn {key, _question} ->
    value =
      cond do
        key in [:intended_effect_present, :protected_strength_preserved] ->
          0.9

        key in [
          :continuity_risk,
          :knowledge_risk,
          :causal_risk,
          :voice_drift,
          :action_readability_risk,
          :setup_payoff_break,
          :reader_state_regression
        ] ->
          0.1

        true ->
          0.1
      end

    {to_string(key), value}
  end)

provider =
  Sandbox.new!(%{
    "capability:revision_intelligence:scene:#{base_scene.id}" => before_answers,
    "capability:revision_intelligence:scene:#{candidate_scene.id}" => after_answers
  })

{:ok, packet} =
  Intelligence.run_revision_playbook(
    before,
    candidate,
    %{
      "before_selection" => %{"targets" => [%{"kind" => "scene", "id" => base_scene.id}]},
      "after_selection" => %{"targets" => [%{"kind" => "scene", "id" => candidate_scene.id}]},
      "intended_effect" =>
        "Give Mara a more active final choice without erasing the private history carried by the watch.",
      "protected_strengths" => ["The watch remains emotionally meaningful"],
      "concern" =>
        "Does the new ending gain agency without turning the watch into a discarded plot coupon?"
    },
    %{observe: provider}
  )

{:ok, markdown} = Intelligence.render_packet(packet, :markdown)
IO.puts(markdown)
