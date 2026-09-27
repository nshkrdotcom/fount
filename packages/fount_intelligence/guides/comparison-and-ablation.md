# Compare revisions before adopting a change

Use actual immutable model values, not descriptions of what a generator says it changed:

```elixir
{:ok, report} = Fount.Intelligence.compare(before, candidate, [], services)
comparison = Fount.Intelligence.Reporting.Report.to_map(report)
```

An empty constraint list requests structural/source comparison without extra semantic checks. Supply validated writing constraints for protected text, knowledge, voice or layout checks. Constraint shapes are the current writing contracts, not arbitrary English strings. The result distinguishes differences, failed checks and unavailable measurements. PDF page savings are not guessed from text length.

## Lift a scene experimentally

```elixir
{:ok, lift} = Fount.Intelligence.run(model, "scene_lift",
  %{"scene_ids" => [scene_id], "constraints" => []}, services)
```

The experiment deletes the selected scenes in an in-memory model and compares that model with the original. Add appropriate constraints to investigate a specific setup, reveal or continuity concern; an unconstrained comparison does not automatically establish every downstream consequence. Canonical storage remains unchanged.

## Remove a support and re-measure

```elixir
{:ok, experiment} = Fount.Intelligence.run(model, "ablate", %{
  "groups" => [%{"id" => "without-key-clue", "targets" => [%{"kind" => "element", "id" => clue_id}]}],
  "proposition" => "Dan kept the spare key",
  "point" => %{"scene_id" => later_scene_id, "through_element_id" => later_element_id},
  "projection" => "page_reader"
}, services)
```

The checkpoint must survive the removal. Inspect the current registry and `Acquisition.Views.points/2` for valid checkpoint references. `page_reader`, `audience_estimate` and `character_access` are distinct projections; character access also requires the character ID. Missing checkpoints, invalid targets and failed acquisitions stay explicit errors. An observed probability change is not causal proof or evidence of actual audience response.

After reviewing an experiment, use Workshop to generate/revise a candidate. Only explicit Workshop acceptance changes the stored draft.
