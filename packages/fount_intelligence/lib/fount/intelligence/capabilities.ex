defmodule Fount.Intelligence.Capabilities do
  @moduledoc "Pure dispatch for the installed Phase-6 screenplay capability families."

  alias Fount.Intelligence.Capabilities.{
    AgencyCausality,
    CharacterTrajectory,
    RelationshipDynamics,
    Result,
    SceneEngine
  }

  @families ~w(scene_engine agency_causality character_trajectory relationship_dynamics)

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

  def analyze(_, _, _, _, _), do: {:error, :unknown_capability_family}
end
