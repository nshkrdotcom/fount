defmodule Fount.Intelligence.StoryWorld.NarrativeScope do
  @moduledoc "Qualified reality/storyline scope. Base story is never silently merged with recollection, dream, hypothetical, alternate, or contested material."
  @enforce_keys [:id, :kind]
  defstruct [:id, :kind, :parent_id, :claim_status, evidence: [], metadata: %{}]
  @type t :: %__MODULE__{}

  @kinds ~w(base recollection dream hypothetical alternate contested)
  def kinds, do: @kinds
  def base, do: %__MODULE__{id: "base", kind: "base", claim_status: "established"}
end

defmodule Fount.Intelligence.StoryWorld.PresentationPoint do
  @moduledoc "Stable source-order coordinate. It describes presentation only and never implies diegetic chronology."
  @enforce_keys [:scene_ordinal]
  defstruct [:scene_id, :scene_ordinal, :element_id, :element_ordinal, boundary: "at"]
  @type t :: %__MODULE__{}
end

defmodule Fount.Intelligence.StoryWorld.Entity do
  @moduledoc "Interpreted story entity grounded in canonical or observation evidence."
  @enforce_keys [:id, :kind, :name]
  defstruct [
    :id,
    :kind,
    :name,
    :canonical_ref,
    aliases: [],
    mentions: [],
    evidence: [],
    confidence: nil,
    alternatives: [],
    dependencies: [],
    metadata: %{}
  ]
  @type t :: %__MODULE__{}
end

defmodule Fount.Intelligence.StoryWorld.Mention do
  @moduledoc "Source-backed occurrence of an interpreted story entity."
  @enforce_keys [:id, :entity_id, :target, :surface]
  defstruct [:id, :entity_id, :target, :surface, :role, :status, evidence: [], dependencies: []]
  @type t :: %__MODULE__{}
end

defmodule Fount.Intelligence.StoryWorld.Event do
  @moduledoc "Qualified story event or structural scene event. Presentation points, story time, and causal relations stay separate."
  @enforce_keys [:id, :kind, :scope_id]
  defstruct [
    :id,
    :kind,
    :label,
    :scope_id,
    :story_time_node_id,
    participants: %{},
    presentation_points: [],
    evidence: [],
    preconditions: [],
    postconditions: [],
    certainty: nil,
    alternatives: [],
    dependencies: [],
    metadata: %{}
  ]
  @type t :: %__MODULE__{}
end

defmodule Fount.Intelligence.StoryWorld.Interaction do
  @moduledoc "Character interaction whose local objectives, tactics, information, status, trust, obligation, or leverage may change."
  @enforce_keys [:id, :scope_id]
  defstruct [
    :id,
    :scope_id,
    :event_id,
    participants: [],
    objectives: [],
    tactics: [],
    changes: %{},
    presentation_points: [],
    evidence: [],
    confidence: nil,
    alternatives: [],
    dependencies: [],
    metadata: %{}
  ]
  @type t :: %__MODULE__{}
end

defmodule Fount.Intelligence.StoryWorld.Assertion do
  @moduledoc "Qualified proposition. Assertions are derived interpretation, not authored screenplay truth."
  @enforce_keys [:id, :predicate, :scope_id]
  defstruct [
    :id,
    :subject,
    :predicate,
    :object,
    :stance,
    :epistemic_owner,
    :scope_id,
    :lifecycle,
    story_time_refs: [],
    presentation_points: [],
    evidence: [],
    confidence: nil,
    alternatives: [],
    dependencies: [],
    metadata: %{}
  ]
  @type t :: %__MODULE__{}
end

defmodule Fount.Intelligence.StoryWorld.Goal do
  @moduledoc "Long-horizon, sequence, scene, or conversational pursuit with explicit evidence and uncertainty."
  @enforce_keys [:id, :owner, :description, :scope_id]
  defstruct [
    :id,
    :owner,
    :description,
    :scope_id,
    :level,
    :status,
    :active_at,
    evidence: [],
    confidence: nil,
    alternatives: [],
    dependencies: [],
    metadata: %{}
  ]
  @type t :: %__MODULE__{}
end

defmodule Fount.Intelligence.StoryWorld.Commitment do
  @moduledoc "Promise, bargain, threat, order, duty, plan, deadline, debt, vow, or obligation with a lifecycle."
  @enforce_keys [:id, :kind, :scope_id]
  defstruct [
    :id,
    :kind,
    :scope_id,
    :from,
    :to,
    :terms,
    :status,
    :deadline,
    conditions: [],
    active_at: [],
    evidence: [],
    confidence: nil,
    alternatives: [],
    dependencies: [],
    metadata: %{}
  ]
  @type t :: %__MODULE__{}
end

defmodule Fount.Intelligence.StoryWorld.StateTransition do
  @moduledoc "Event-qualified state transition used for possession, injury/death, knowledge, plan, access, resource, and relationship continuity."
  @enforce_keys [:id, :subject, :attribute, :event_id, :scope_id]
  defstruct [
    :id,
    :subject,
    :attribute,
    :from,
    :to,
    :event_id,
    :scope_id,
    preconditions: [],
    postconditions: [],
    evidence: [],
    certainty: nil,
    alternatives: [],
    dependencies: [],
    metadata: %{}
  ]
  @type t :: %__MODULE__{}
end

defmodule Fount.Intelligence.StoryWorld.Beat do
  @moduledoc "Derived source-range beat interpretation. Competing segmentations are legal."
  @enforce_keys [:id, :scope_id]
  defstruct [
    :id,
    :scope_id,
    :scene_id,
    :summary,
    :objective,
    :tactic,
    :information_change,
    :relationship_delta,
    :value_delta,
    :outcome,
    :transition_reason,
    element_ids: [],
    presentation_points: [],
    evidence: [],
    confidence: nil,
    alternatives: [],
    dependencies: [],
    metadata: %{}
  ]
  @type t :: %__MODULE__{}
end

defmodule Fount.Intelligence.StoryWorld.Motif do
  @moduledoc "Recurring story-world image, object, phrase, behavior, sound, place, gesture, or concept."
  @enforce_keys [:id, :label]
  defstruct [:id, :label, :kind, occurrences: [], evidence: [], confidence: nil, dependencies: [], metadata: %{}]
  @type t :: %__MODULE__{}
end

defmodule Fount.Intelligence.StoryWorld.StoryTimeNode do
  @moduledoc "Event or interval node in a partial diegetic time graph."
  @enforce_keys [:id, :scope_id]
  defstruct [:id, :scope_id, :event_id, :kind, :exact, :anchor, :duration, evidence: [], dependencies: [], metadata: %{}]
  @type t :: %__MODULE__{}
end

defmodule Fount.Intelligence.StoryWorld.StoryTimeConstraint do
  @moduledoc "Evidence-backed qualitative relation set between two story-time nodes. Multiple allowed relations preserve ambiguity."
  @enforce_keys [:id, :left, :right, :relations]
  defstruct [
    :id,
    :left,
    :right,
    relations: [],
    evidence: [],
    confidence: nil,
    alternatives: [],
    dependencies: [],
    metadata: %{}
  ]
  @type t :: %__MODULE__{}
end

defmodule Fount.Intelligence.StoryWorld.CausalRelation do
  @moduledoc "Typed causal relation, deliberately independent from presentation and story-time ordering."
  @enforce_keys [:id, :type, :from, :to]
  defstruct [:id, :type, :from, :to, evidence: [], confidence: nil, alternatives: [], dependencies: [], metadata: %{}]
  @type t :: %__MODULE__{}
end

defmodule Fount.Intelligence.StoryWorld.Conflict do
  @moduledoc "Source-grounded local inconsistency or unsupported transition. Ambiguity is not itself a conflict."
  @enforce_keys [:id, :kind, :message]
  defstruct [:id, :kind, :message, severity: "warning", involved_ids: [], evidence: [], dependencies: [], metadata: %{}]
  @type t :: %__MODULE__{}
end
