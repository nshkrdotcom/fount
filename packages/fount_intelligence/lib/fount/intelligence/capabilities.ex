defmodule Fount.Intelligence.Capabilities do
  @moduledoc "Pure dispatch for all twelve installed screenplay capability families through Phase 8."

  alias Fount.Intelligence.StoryWorld

  alias Fount.Intelligence.Capabilities.{
    AgencyCausality,
    AudienceReaderExperience,
    CharacterTrajectory,
    DialogueInteraction,
    EmotionalValueMovement,
    GenreLensPacks,
    RelationshipDynamics,
    Result,
    RevisionIntelligence,
    SceneEngine,
    SequenceMovement,
    SetupPayoffMotifs,
    ThemeMeaning
  }

  @families ~w(scene_engine agency_causality character_trajectory relationship_dynamics audience_reader_experience sequence_movement dialogue_interaction setup_payoff_motifs emotional_value_movement theme_meaning genre_lens_packs revision_intelligence)

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

  def analyze("emotional_value_movement", world, subject, entries, opts),
    do: {:ok, EmotionalValueMovement.analyze(world, subject, entries, opts)}

  def analyze("theme_meaning", world, subject, entries, opts),
    do: {:ok, ThemeMeaning.analyze(world, subject, entries, opts)}

  def analyze("genre_lens_packs", world, subject, entries, opts),
    do: {:ok, GenreLensPacks.analyze(world, subject, entries, opts)}

  def analyze("revision_intelligence", world, subject, entries, opts),
    do: {:ok, RevisionIntelligence.analyze(world, subject, entries, opts)}

  def analyze(_, _, _, _, _), do: {:error, :unknown_capability_family}

  @spec compare_revision(StoryWorld.t(), StoryWorld.t(), term(), list(), list(), keyword()) ::
          {:ok, Result.t()}
  def compare_revision(
        before_world,
        after_world,
        subject,
        before_entries,
        after_entries,
        opts \\ []
      ),
      do:
        {:ok,
         RevisionIntelligence.compare(
           before_world,
           after_world,
           subject,
           before_entries,
           after_entries,
           opts
         )}
end
