# Comparison and Counterfactual Ablation

Fount Probe offers tools for delta inspection and counterfactual impact assessment across screenplay revisions.

## Revision Comparison

Comparing two revisions of a screenplay verifies whether proposed changes satisfy constraints:

```elixir
constraints = [
  %{"type" => "character_voice", "character" => "MARA", "max_drift" => 0.15},
  %{"type" => "scene_length", "scene_id" => scene_id, "max_delta_eighths" => 2}
]

{:ok, comparison_report} = FountProbe.compare(base_model, revised_model, constraints, clients)
```

## Scene Lift Analysis

Before cutting or moving a scene, evaluate the narrative collateral damage:

```elixir
{:ok, lift_report} = FountProbe.run(model, "scene_lift", %{
  "scene_ids" => [climax_setup_scene_id],
  "constraints" => ["preserve_climax_payoff", "track_keycard_possession"]
})
```

`scene_lift` checks downstream dependencies, character introductions, and prop arrivals that break if the selected scenes are removed.

## Counterfactual Ablation

Test whether an insight or plot revelation is dependent on a specific prior event:

```elixir
{:ok, ablate_report} = FountProbe.run(model, "ablate", %{
  "groups" => ["scene-3-crypt-discovery"],
  "proposition" => "Mara realizes Dan hid the vault key",
  "point" => "scene-8",
  "projection" => "knowledge"
})
```
