defmodule Fount.Intelligence.Capabilities do
  @moduledoc "Pure dispatch for installed screenplay capability families through Phase 7."

  alias Fount.Intelligence.Capabilities.{
    AgencyCausality,
    AudienceReaderExperience,
    CharacterTrajectory,
    DialogueInteraction,
    RelationshipDynamics,
    Result,
    SceneEngine,
    SequenceMovement,
    SetupPayoffMotifs
  }

  @families ~w(scene_engine agency_causality character_trajectory relationship_dynamics audience_reader_experience sequence_movement dialogue_interaction setup_payoff_motifs)

  def families, do: @families
  def member?(family), do: family in @families

  @spec analyze(String.t(), Fount.Intelligence.StoryWorld.t(), term(), list(), keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def analyze("scene_engine", world, subject, entries, opts),
    do: {:ok, SceneEngine.analyze(world, subject, entries, opts)}

  def analyze("agency_causality", world, subject, entries, opts),
    do: {:ok, AgencyCausality.analyze(world, subject, entries, opts)}

  def analyze("character_trajectory", world, subject, entries, opts),
    do: {:ok, CharacterTrajectory.analyze(world, subject, entries, opts)}

  def analyze("relationship_dynamics", world, subject, entries, opts),
    do: {:ok, RelationshipDynamics.analyze(world, subject, entries, opts)}

  def analyze("audience_reader_experience", world, subject, entries, opts),
    do: {:ok, AudienceReaderExperience.analyze(world, subject, entries, opts)}

  def analyze("sequence_movement", world, subject, entries, opts),
    do: {:ok, SequenceMovement.analyze(world, subject, entries, opts)}

  def analyze("dialogue_interaction", world, subject, entries, opts),
    do: {:ok, DialogueInteraction.analyze(world, subject, entries, opts)}

  def analyze("setup_payoff_motifs", world, subject, entries, opts),
    do: {:ok, SetupPayoffMotifs.analyze(world, subject, entries, opts)}

  def analyze(_, _, _, _, _), do: {:error, :unknown_capability_family}
end
