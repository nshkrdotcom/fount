defmodule Fount.Intelligence.Acquisition.CapabilityMeasurements do
  @moduledoc "Closed measurement registry for all twelve installed screenplay capability families through Phase 8."

  alias Fount.Observe.Question

  @ids ~w(scene_engine agency_causality character_trajectory relationship_dynamics audience_reader_experience sequence_movement dialogue_interaction setup_payoff_motifs emotional_value_movement theme_meaning genre_lens_packs revision_intelligence)
  def ids, do: @ids

  def fetch("scene_engine"), do: {:ok, scene_engine()}
  def fetch("agency_causality"), do: {:ok, agency_causality()}
  def fetch("character_trajectory"), do: {:ok, character_trajectory()}
  def fetch("relationship_dynamics"), do: {:ok, relationship_dynamics()}
  def fetch("audience_reader_experience"), do: {:ok, audience_reader_experience()}
  def fetch("sequence_movement"), do: {:ok, sequence_movement()}
  def fetch("dialogue_interaction"), do: {:ok, dialogue_interaction()}
  def fetch("setup_payoff_motifs"), do: {:ok, setup_payoff_motifs()}
  def fetch("emotional_value_movement"), do: {:ok, emotional_value_movement()}
  def fetch("theme_meaning"), do: {:ok, theme_meaning()}
  def fetch("genre_lens_packs"), do: {:ok, genre_lens_packs()}
  def fetch("revision_intelligence"), do: {:ok, revision_intelligence()}
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

  def audience_reader_experience do
    spec("audience_reader_experience", "audience.reader_experience",
      open_question:
        noul(
          "Does this material create or carry a specific question a first-time reader can hold at this point?"
        ),
      expectation:
        noul(
          "Does this material establish or materially revise a reader-facing expectation about what may happen next?"
        ),
      visible_threat:
        noul(
          "Is a concrete threat, opportunity, deadline, or risk legible to the reader in this material?"
        ),
      valued_uncertainty:
        noul(
          "Is an outcome both meaningfully uncertain and consequential enough to matter within the supplied material?"
        ),
      curiosity_gap:
        noul(
          "Does the material create a legible information gap that can motivate continued reading without requiring later-page knowledge?"
        ),
      surprise_candidate:
        noul(
          "Would the event or reveal plausibly revise an expectation established by material already supplied to this measurement?"
        ),
      comprehension_risk:
        noul(
          "Is there a concrete risk that the reader cannot connect required information, identity, goal, location, or causality at this point?"
        ),
      intentional_ambiguity:
        noul(
          "Does the supplied material support that an ambiguity or withheld answer is intentional rather than simply missing context?"
        ),
      reveal_changes_inference:
        noul(
          "Does a reveal change what a first-time reader can reasonably infer from already presented material?"
        ),
      forward_pull:
        noul(
          "Does the material create a concrete reason to continue into the next scene, beat, answer, threat, choice, or consequence?"
        )
    )
  end

  def sequence_movement do
    spec("sequence_movement", "sequence.movement",
      objective_active:
        noul("Is a legible sequence-level objective or dramatic task active in this scene?"),
      objective_progress:
        noul(
          "Does this scene materially advance, obstruct, transform, or resolve the active sequence objective?"
        ),
      constraint_escalation:
        noul(
          "Does a constraint become more restrictive, expensive, immediate, or difficult in this scene?"
        ),
      stakes_escalation:
        noul("Does the cost, risk, loss, or consequence materially change in this scene?"),
      knowledge_change:
        noul(
          "Does consequential knowledge change in a way that alters the sequence's available choices or interpretation?"
        ),
      relationship_change:
        noul(
          "Does a relationship change in a way that alters the sequence's available choices, pressure, or leverage?"
        ),
      choice_change:
        noul("Does a consequential choice or refusal change the path of the sequence?"),
      tactic_shift:
        noul(
          "Does the operative tactic or strategy materially change in response to resistance, failure, or new information?"
        ),
      reversal:
        noul(
          "Does this scene contain a reversal that changes direction, leverage, expectation, or apparent outcome?"
        ),
      local_outcome:
        noul(
          "Does this scene establish a concrete local outcome rather than only continuing the prior state?"
        ),
      repeated_function:
        noul(
          "Does this scene substantially repeat the previous dramatic function without a new cost, tactic, information change, relationship change, choice, or consequence?"
        ),
      handoff_pressure:
        noul(
          "Does the scene exit create a concrete unresolved consequence, choice, threat, question, or task that carries pressure into what follows?"
        )
    )
  end

  def dialogue_interaction do
    spec("dialogue_interaction", "dialogue.exchange",
      responds:
        noul(
          "Does the later turn materially respond to the immediately preceding turn, including refusal, deflection, or strategic silence?"
        ),
      evades:
        noul(
          "Does the later turn avoid the prior turn's direct demand, question, accusation, or implication?"
        ),
      redirects:
        noul(
          "Does the later turn redirect the exchange toward a different subject, demand, frame, or tactical objective?"
        ),
      attacks:
        noul(
          "Does the later turn increase pressure through accusation, threat, insult, challenge, exposure, or another attack tactic?"
        ),
      bargains:
        noul("Does the exchange make or revise a trade, condition, concession, debt, or bargain?"),
      reveals:
        noul(
          "Does the exchange reveal consequential information, intention, belief, or leverage to another participant or the reader?"
        ),
      conceals:
        noul(
          "Does the exchange actively conceal, withhold, disguise, or misdirect consequential information?"
        ),
      subtext:
        noul(
          "Does the exchange support a playable intention or pressure that differs materially from the literal surface wording?"
        ),
      exposition:
        noul(
          "Does the exchange communicate story information the audience needs to understand events, relationships, or stakes?"
        ),
      exposition_dramatic_work:
        noul(
          "Where exposition is present, is it also doing dramatic work through conflict, tactic, status, concealment, choice, or relationship pressure?"
        ),
      tactic_shift: noul("Does a participant materially change tactic across the exchange?"),
      status_shift:
        noul(
          "Does relative status, leverage, control, or conversational advantage materially change across the exchange?"
        ),
      knowledge_asymmetry:
        noul(
          "Does the exchange depend on or change a meaningful difference in what participants know or believe?"
        ),
      repetition:
        noul(
          "Does the exchange repeat substantially the same information, tactic, or demand without a new dramatic purpose or consequence?"
        ),
      exchange_changes_state:
        noul(
          "Does the exchange change knowledge, goal, relationship, status, leverage, pressure, commitment, or available action?"
        ),
      voice_distinction:
        noul(
          "Do wording, syntax, rhythm, tactic, reference frame, or conversational behavior provide evidence that the participating voices are meaningfully distinguishable here?"
        )
    )
  end

  def setup_payoff_motifs do
    spec("setup_payoff_motifs", "setup_payoff.motifs",
      setup_signal:
        noul(
          "Does this material plant an object, fact, promise, image, phrase, behavior, rule, threat, or question that can carry forward as a setup?"
        ),
      reinforcement:
        noul(
          "Does this material reinforce an already established setup, promise, motif, or expectation rather than merely repeat it?"
        ),
      transformation:
        noul(
          "Does a later use materially transform the meaning, function, context, or emotional/story significance of an earlier setup or motif?"
        ),
      payoff:
        noul(
          "Does this material fulfill or resolve an earlier setup, promise, commitment, question, rule, image, object, or phrase in a materially connected way?"
        ),
      subversion:
        noul(
          "Does this material deliberately redirect or invert an earlier setup or expected payoff while preserving a legible connection?"
        ),
      abandonment:
        noul(
          "Does the supplied material support that an earlier setup or promise is deliberately abandoned or denied rather than accidentally forgotten?"
        ),
      unsupported_payoff:
        noul(
          "Does an apparent payoff depend on a setup or dependency that is not visible in the supplied material?"
        ),
      orphaned_setup:
        noul(
          "Does an established setup remain unresolved without visible transformation, payoff, subversion, or deliberate abandonment in the supplied scope?"
        ),
      motif_callback:
        noul(
          "Does an image, object, phrase, sound, place, gesture, behavior, or concept recur in a way that invites connection to an earlier occurrence?"
        ),
      motif_function_change:
        noul(
          "Does a recurring motif materially change story, character, relationship, or thematic function across occurrences?"
        ),
      over_signaled:
        noul(
          "Is a setup or motif reinforced so repeatedly or explicitly that the later use may be strongly predicted from the supplied material?"
        ),
      revision_break_candidate:
        noul(
          "Does the supplied material show a setup/payoff or motif chain whose dependency appears broken, contradictory, or disconnected after revision?"
        )
    )
  end


  def emotional_value_movement do
    direction = fn dimension ->
      Question.choice(
        "Relative to scene entry, what change in #{dimension} is best supported for the selected character?",
        improves: "the condition materially improves or becomes more available",
        worsens: "the condition materially worsens or becomes less available",
        mixed: "gains and losses coexist or the direction materially conflicts",
        unchanged: "the supplied material supports no material change",
        other_or_unclear: "the dimension is not applicable or the direction is not clear from the supplied evidence"
      )
    end

    spec("emotional_value_movement", "emotional.value_movement",
      practical_direction: direction.("the character's practical situation or available options"),
      hope_direction: direction.("hope or anticipated possibility"),
      fear_direction: direction.("fear, threat exposure, or anticipated loss"),
      security_direction: direction.("security versus danger or instability"),
      belonging_direction: direction.("belonging versus exclusion or isolation"),
      trust_direction: direction.("trust versus distrust"),
      status_direction: direction.("status, dignity, or social standing"),
      control_direction: direction.("control, agency, or powerlessness"),
      certainty_direction: direction.("certainty versus uncertainty about consequential facts, choices, or outcomes"),
      moral_confidence_direction: direction.("moral confidence versus conflict about what the character believes they should do"),
      anticipated_gain: noul("Does the selected character visibly anticipate a meaningful gain in this scene?"),
      anticipated_loss: noul("Does the selected character visibly anticipate a meaningful loss in this scene?"),
      major_event: noul("Does this scene contain a major event for the selected character that plausibly calls for later emotional or behavioral consequence?"),
      reaction_consequence: noul("Does the selected character show a visible reaction or changed emotional condition that is connected to a consequential event in the supplied material?"),
      behavioral_consequence: noul("Does a consequential event change the selected character's later choice, tactic, avoidance, commitment, or other behavior in the supplied material?"),
      reversal: noul("Does the selected character undergo a material reversal in a tracked practical/emotional/value condition in this scene?"),
      reversal_prepared: noul("Where a reversal occurs, does earlier supplied material visibly prepare pressure, contradiction, choice, or information that can support it?"),
      declared_feeling_without_behavioral_change: noul("Does dialogue or narration name a feeling while the supplied material shows no corresponding change in behavior, choice, tactic, relationship, or consequence?"),
      value_action_inconsistency: noul("Does the selected character take an action that appears inconsistent with an established value or commitment without visible pressure, conflict, self-deception, or revision of that value?"))
  end

  def theme_meaning do
    axis =
      Question.choice(
        "If a recurring value conflict is legible in this scene, which broad axis is best supported? Use other_or_unclear rather than forcing the material into the installed vocabulary.",
        loyalty_vs_truth: "loyalty, allegiance, or protection conflicts with truth, disclosure, or honesty",
        belonging_vs_autonomy: "belonging, family, community, or acceptance conflicts with autonomy or individuation",
        control_vs_acceptance: "control, mastery, or certainty conflicts with acceptance, surrender, or uncertainty",
        justice_vs_mercy: "justice, accountability, or punishment conflicts with mercy, forgiveness, or compassion",
        security_vs_freedom: "security, safety, or stability conflicts with freedom, risk, or self-determination",
        intimacy_vs_self_protection: "intimacy or vulnerability conflicts with concealment, distance, or self-protection",
        duty_vs_desire: "duty, obligation, role, or responsibility conflicts with personal desire",
        identity_vs_role: "self-conception or identity conflicts with an imposed or chosen social role",
        other_or_unclear: "a different value conflict is present or the installed axes do not fit clearly"
      )

    spec("theme_meaning", "theme.meaning",
      value_conflict: noul("Does this scene materially stage a conflict between values, obligations, identities, loyalties, or meanings rather than only a practical obstacle?"),
      conflict_axis: axis,
      choice_embodies_conflict: noul("Does a consequential character choice or refusal embody the value conflict rather than merely state it?"),
      consequence_complicates_conflict: noul("Does the consequence of a choice complicate, reverse, or deepen the apparent value conflict rather than simply reward one side?"),
      motif_reinforces_question: noul("Does a recurring image, object, phrase, place, behavior, or contrast connect materially to the value conflict in the supplied material?"),
      contrast_reinforces_question: noul("Does a character, scene, outcome, or repeated contrast provide a materially different answer to the same value question?"),
      ending_recontextualizes_question: noul("If this material is at or near the ending, does it revisit, complicate, answer, or deliberately leave open a value question established earlier?"),
      writer_intent_alignment: noul("Where writer thematic intent is supplied, does the scene materially support or productively complicate that declared intent?"),
      contradictory_signal: noul("Does this scene provide material counterevidence to an otherwise recurring thematic hypothesis or value-conflict reading?"))
  end

  def genre_lens_packs do
    spec("genre_lens_packs", "genre.lens_pack",
      expectation_present: noul("Given the supplied optional genre/craft pack, is one of its specialized expectations or pressures materially present in this scene?"),
      expectation_satisfied: noul("Where a pack expectation is present, does the scene visibly fulfill or advance it in a way consistent with the writer's declared intent?"),
      expectation_subverted: noul("Where a pack expectation is present, does the scene visibly subvert, invert, refuse, or redirect it rather than simply omit it?"),
      intentional_subversion_visible: noul("Does the supplied material support that a pack expectation is being intentionally subverted or de-emphasized, consistent with declared subversion/anti-genre intent?"),
      specialized_pressure: noul("Does the pack contribute a specialized analytical pressure or question here that is not already exhausted by generic scene/character/reader analysis?"),
      conflict_with_writer_intent: noul("Would applying the pack expectation as a defect rule conflict with the writer's declared intent, opt-out guidance, or intentional subversion?"))
  end

  def revision_intelligence do
    spec("revision_intelligence", "revision.intelligence",
      intended_effect_present: noul("Relative to the supplied revision contract, is the intended dramatic or reader-facing effect visibly present in this revision's selected material?"),
      protected_strength_preserved: noul("Does the selected material preserve the declared protected strengths or constraints relevant to this revision?"),
      continuity_risk: noul("Does this revision create a plausible continuity contradiction or unsupported state transition in the selected material?"),
      knowledge_risk: noul("Does this revision create a plausible character-knowledge/access inconsistency or require knowledge that is no longer established?"),
      causal_risk: noul("Does this revision create a plausible causal or motivational gap where a later event, choice, or consequence loses visible support?"),
      voice_drift: noul("Does this revision create a plausible character-voice drift relative to the supplied local/trajectory evidence and writer intent?"),
      action_readability_risk: noul("Does this revision make physical action, spatial relation, objective, or cause/effect materially harder to follow in the selected material?"),
      setup_payoff_break: noul("Does this revision plausibly break, contradict, orphan, or unsupportedly preserve a setup/payoff/motif dependency in the supplied scope?"),
      reader_state_regression: noul("Does this revision plausibly create an unintended first-exposure reader-state regression such as premature inference, missing setup, comprehension loss, or collapsed uncertainty?"))
  end

  defp spec(id, lens_id, questions),
    do: %{"id" => id, "lens_id" => lens_id, "questions" => questions}

  defp noul(text), do: Question.noul(text)
end