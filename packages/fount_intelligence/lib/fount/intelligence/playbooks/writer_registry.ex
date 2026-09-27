defmodule Fount.Intelligence.Playbooks.WriterRegistry do
  @moduledoc "Closed writer playbook catalog. Definitions and installed capability-family mappings are data; callers cannot inject executable modules."

  @definitions [
    %{
      "id" => "scene_doctor",
      "label" => "Scene Doctor",
      "purpose" =>
        "Diagnose why a selected scene is not producing the intended dramatic effect before proposing a rewrite.",
      "foundational_tools" => ~w(scene_mechanics dependencies continuity),
      "future_capability_families" => ~w(scene_engine agency_causality),
      "phase_6_capability_families" => ~w(scene_engine),
      "writer_questions" => [
        "What is the scene trying to make the reader expect, fear, understand, or want?",
        "Which competing explanations fit the evidence?"
      ]
    },
    %{
      "id" => "dialogue_pass",
      "label" => "Dialogue Pass",
      "purpose" =>
        "Diagnose exchange-level problems while preserving character intent, subtext, and useful asymmetry.",
      "foundational_tools" => ~w(dialogue voice knowledge_trace),
      "future_capability_families" => ~w(dialogue_interaction relationship_dynamics),
      "phase_7_capability_families" => ~w(dialogue_interaction relationship_dynamics),
      "writer_questions" => [
        "Where does an exchange stop changing tactic, leverage, knowledge, or status?",
        "Which apparent repetition is intentional rhythm rather than a defect?"
      ]
    },
    %{
      "id" => "character_trajectory",
      "label" => "Character Trajectory",
      "purpose" =>
        "Track a character's goals, commitments, decisions, consequences, and adaptation without forcing a universal arc shape.",
      "foundational_tools" => ~w(extract_story dependencies knowledge_trace),
      "future_capability_families" => ~w(character_trajectory agency_causality),
      "phase_6_capability_families" => ~w(character_trajectory agency_causality),
      "phase_8_capability_families" => ~w(emotional_value_movement),
      "writer_questions" => [
        "What changes because this character chooses or refuses to choose?",
        "What evidence supports an apparent trajectory break?"
      ]
    },
    %{
      "id" => "relationship_pass",
      "label" => "Relationship Pass",
      "purpose" =>
        "Diagnose changes in trust, leverage, intimacy, allegiance, concealment, and dependency across the selected relationship.",
      "foundational_tools" => ~w(extract_story continuity dependencies),
      "future_capability_families" => ~w(relationship_dynamics),
      "phase_6_capability_families" => ~w(relationship_dynamics),
      "writer_questions" => [
        "What changes between the characters at each consequential encounter?",
        "Does presentation order obscure or sharpen the relationship movement?"
      ]
    },
    %{
      "id" => "suspense_audit",
      "label" => "Suspense Audit",
      "purpose" =>
        "Inspect what the reader knows, expects, fears, and waits for without treating surprise or suspense as universally desirable.",
      "foundational_tools" => ~w(knowledge_trace locate_boundary),
      "future_capability_families" => ~w(audience_reader_experience),
      "phase_7_capability_families" => ~w(audience_reader_experience),
      "writer_questions" => [
        "Which open question or threat carries forward at each checkpoint?",
        "Where is uncertainty intentional versus accidentally collapsed?"
      ]
    },
    %{
      "id" => "sequence_momentum",
      "label" => "Sequence Momentum",
      "purpose" =>
        "Diagnose repeated dramatic function, stalled strategy, and weak handoffs across a sequence while preserving intentional stillness.",
      "foundational_tools" => ~w(scene_mechanics dependencies continuity),
      "future_capability_families" => ~w(sequence_movement),
      "phase_7_capability_families" => ~w(sequence_movement),
      "writer_questions" => [
        "What changes at each scene exit?",
        "Where do cost, strategy, information, or consequence fail to change?"
      ]
    },
    %{
      "id" => "setup_payoff",
      "label" => "Setup / Payoff",
      "purpose" =>
        "Inspect explicit setup, reinforcement, transformation, payoff, subversion, or abandonment without requiring every setup to pay conventionally.",
      "foundational_tools" => ~w(dependencies continuity),
      "future_capability_families" => ~w(setup_payoff_motifs),
      "phase_7_capability_families" => ~w(setup_payoff_motifs),
      "writer_questions" => [
        "What promise does the screenplay create and when can a first-time reader carry it?",
        "Is the later use a payoff, transformation, subversion, or deliberate abandonment?"
      ]
    },
    %{
      "id" => "notes_diagnosis",
      "label" => "Notes Diagnosis",
      "purpose" =>
        "Separate a note's reported reaction from possible causes and possible fixes, then test competing explanations against source evidence.",
      "foundational_tools" => ~w(search scene_mechanics dialogue),
      "future_capability_families" => ~w(revision_intelligence),
      "writer_questions" => [
        "What reader reaction is the note actually reporting?",
        "Which different causes could produce the same reaction?"
      ]
    },
    %{
      "id" => "submission_read",
      "label" => "Submission Read",
      "purpose" =>
        "Assemble a source-grounded read of major clarity, momentum, character, dialogue, and reader-experience concerns without issuing a universal quality score.",
      "foundational_tools" => ~w(inventory extract_story scene_mechanics dialogue voice),
      "future_capability_families" =>
        ~w(audience_reader_experience sequence_movement dialogue_interaction revision_intelligence),
      "phase_8_capability_families" => ~w(theme_meaning genre_lens_packs),
      "writer_questions" => [
        "Which concerns are strongly evidenced versus speculative?",
        "What strengths should survive any revision response?"
      ]
    },
    %{
      "id" => "revision_regression",
      "label" => "Revision Regression",
      "purpose" =>
        "Compare intended gains and collateral effects across revisions while keeping reader effects separate from diegetic continuity and causal changes.",
      "foundational_tools" => ~w(compare strategy_contrast),
      "future_capability_families" => ~w(revision_intelligence),
      "phase_8_capability_families" => ~w(revision_intelligence),
      "writer_questions" => [
        "Did the intended effect change?",
        "Which protected strengths or downstream dependencies regressed?"
      ]
    }
  ]

  @ids Enum.map(@definitions, & &1["id"])

  def list, do: @definitions
  def ids, do: @ids
  def member?(id), do: id in @ids

  def fetch(id) when is_binary(id) do
    case Enum.find(@definitions, &(&1["id"] == id)) do
      nil -> {:error, :unknown_writer_playbook}
      definition -> {:ok, definition}
    end
  end

  def fetch(_), do: {:error, :unknown_writer_playbook}
end
