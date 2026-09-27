defmodule Fount.Intelligence.Acquisition.CapabilityMeasurements do
  @moduledoc "Closed Phase-6 measurement registry for Scene, Agency, Character, and Relationship capability families."

  alias Fount.Observe.Question

  @ids ~w(scene_engine agency_causality character_trajectory relationship_dynamics)
  def ids, do: @ids

  def fetch("scene_engine"), do: {:ok, scene_engine()}
  def fetch("agency_causality"), do: {:ok, agency_causality()}
  def fetch("character_trajectory"), do: {:ok, character_trajectory()}
  def fetch("relationship_dynamics"), do: {:ok, relationship_dynamics()}
  def fetch(_), do: {:error, :unknown_capability_family}

  def scene_engine do
    spec("scene_engine", "scene.engine",
      objective: noul("Is a concrete scene objective legible for a principal character?"),
      opposition: noul("Is meaningful opposition to the active objective present in this scene?"),
      stakes:
        noul("Does the scene make a cost, risk, loss, or meaningful value at stake legible?"),
      urgency:
        noul(
          "Does the scene establish why the objective matters now rather than indefinitely later?"
        ),
      tactic: noul("Is at least one purposeful tactic used to pursue an objective in the scene?"),
      tactic_shift:
        noul(
          "Does a tactic materially change in response to resistance, information, or failure?"
        ),
      reveal:
        noul(
          "Does the scene introduce information that changes what a character or reader can infer?"
        ),
      decision: noul("Does a character make or refuse a consequential choice in the scene?"),
      consequence:
        noul(
          "Does the scene establish a consequence that changes later options, state, or pressure?"
        ),
      value_delta:
        noul("Does a tracked value or practical state change from scene entry to exit?"),
      relationship_delta:
        noul("Does a relationship dimension materially change during the scene?"),
      preamble_candidate:
        noul("Could the performed scene plausibly begin later without losing required setup?"),
      linger_candidate:
        noul(
          "Could the performed scene plausibly end earlier without losing a required consequence or handoff?"
        )
    )
  end

  def agency_causality do
    spec("agency_causality", "agency.causality",
      initiating_choice:
        noul("Does the selected character initiate a choice that changes subsequent events?"),
      active_goal_pursuit:
        noul("Is the selected character actively pursuing an established goal here?"),
      causal_support:
        noul(
          "Is the apparent downstream consequence supported by a visible decision or action rather than convenience alone?"
        ),
      motive_support:
        noul(
          "Does available screenplay evidence support why the selected character takes the consequential action?"
        ),
      knowledge_support:
        noul(
          "Does available screenplay evidence support that the selected character knows or believes enough to take this action?"
        ),
      relationship_pressure_support:
        noul(
          "Does a relationship, obligation, threat, or pressure help support the selected character's action?"
        ),
      alternate_support:
        noul(
          "Could the same downstream event remain supported by a materially independent cause if this character action were removed?"
        ),
      reactive_only:
        noul(
          "In this scene, is the selected character primarily reacting without introducing a new goal-directed choice?"
        ),
      delayed_consequence:
        noul("Is an earlier choice receiving a delayed consequence in this scene?"),
      removal_impact:
        noul(
          "Would removing the selected character's action break a later causal or motivational link visible in the supplied material?"
        )
    )
  end

  def character_trajectory do
    questions = [
      active_goal: noul("Is a current goal of the selected character legible in this scene?"),
      belief_change:
        noul(
          "Does the selected character's belief or interpretation materially change in this scene?"
        ),
      knowledge_change:
        noul(
          "Does the selected character gain, lose, confirm, or revise consequential knowledge in this scene?"
        ),
      tactic_change:
        noul(
          "Does the selected character change tactic in response to resistance or new information?"
        ),
      commitment_change:
        noul(
          "Does the selected character make, break, revise, or fulfill a consequential commitment?"
        ),
      relationship_change:
        noul(
          "Does a consequential relationship involving the selected character change in this scene?"
        ),
      value_change:
        noul(
          "Does a value, allegiance, priority, resource, or practical state important to the character materially change?"
        ),
      adapts_after_failure:
        noul(
          "Where prior failure or resistance is available, does the selected character adapt rather than simply repeat the same response?"
        ),
      choice_reveals_character:
        noul(
          "Does a choice or refusal in this scene reveal a consequential preference, value, fear, or commitment?"
        ),
      repeated_defense:
        noul(
          "Does the selected character repeat a defensive pattern already visible in the supplied trajectory?"
        )
    ]

    arc =
      Question.choice(
        "Which trajectory description is best supported by the supplied material without requiring transformation?",
        steadfast: "the character is tested while a core position remains substantially stable",
        tragic: "choices and consequences support a self-defeating or destructive trajectory",
        corruption:
          "the character increasingly adopts a more damaging value, allegiance, or method",
        revelation:
          "the central movement is discovery or recognition rather than personality replacement",
        cyclical: "the trajectory meaningfully returns to an earlier state or pattern",
        ensemble:
          "movement is distributed across an ensemble rather than one dominant individual arc",
        deliberately_static: "relative stability appears intentional and dramatically functional",
        mixed_or_unclear:
          "the supplied evidence supports more than one shape or no clear single shape"
      )

    spec("character_trajectory", "character.trajectory", questions ++ [arc_pattern: arc])
  end

  def relationship_dynamics do
    spec("relationship_dynamics", "relationship.dynamics",
      trust_change:
        noul("Does trust between the selected parties materially change in this scene?"),
      intimacy_change:
        noul(
          "Does emotional or practical intimacy between the selected parties materially change?"
        ),
      allegiance_change:
        noul("Does allegiance or willingness to side with the other party materially change?"),
      leverage_change: noul("Does one party gain or lose meaningful leverage over another?"),
      status_change: noul("Does relative social or interactional status materially change?"),
      dependency_change: noul("Does practical or emotional dependency materially change?"),
      attraction_change:
        noul("Does attraction or romantic/sexual interest materially change where applicable?"),
      resentment_change: noul("Does resentment or hostility materially change?"),
      obligation_change:
        noul("Does a debt, promise, duty, or obligation between the parties materially change?"),
      concealment_change:
        noul(
          "Does openness, concealment, or withheld information between the parties materially change?"
        ),
      knowledge_asymmetry_change:
        noul("Does the difference in what the selected parties know materially change?"),
      interaction_changes_relationship:
        noul(
          "Does this interaction change the relationship rather than merely restate its current state?"
        ),
      repetitive_negotiation:
        noul(
          "Does this interaction repeat substantially the same negotiation or leverage pattern without a new consequence?"
        ),
      betrayal_or_payoff_prepared:
        noul(
          "If this scene contains a betrayal, reversal, fulfillment, or relationship payoff, is it supported by prior visible setup in the supplied material?"
        )
    )
  end

  defp spec(id, lens_id, questions),
    do: %{"id" => id, "lens_id" => lens_id, "questions" => questions}

  defp noul(text), do: Question.noul(text)
end
