# Read-only screenplay inspections

```elixir
request = %{"id" => "inventory", "playbook" => "inventory",
  "params" => %{"selection" => %{"whole_screenplay" => true}, "include_summaries" => false}}
{:ok, results} = Fount.Intelligence.execute(model, [request], %{})
```

Requests use the closed `Playbooks.Request` contract. Duplicate IDs, unknown playbooks, unknown fields and invalid targets fail before execution. Inspect each returned result; a batch can contain individual failures. Model output cannot choose a module, shell command or persistence route.

## Supply only the services needed

In a Workshop host:

```elixir
{:ok, observe} = Fount.Intelligence.Acquisition.Configuration.provider(
  api_key: key, model: measurement_model)
services = FountWorkshop.Services.analysis(%{observe: observe, inference: completion_client})
{:ok, report} = Fount.Intelligence.run(model, "scene_mechanics",
  %{"selection" => %{"whole_screenplay" => true}}, services)
```

`completion_client` is an actual `Inference.Client` constructed by the host. Intelligence receives the Workshop-owned `propose` callback, not the native client. A host outside Workshop may provide a trusted four-argument function `(prompt, schema, validator, opts)` returning `{:ok, map, traces}` or `{:error, reason, traces}`. The local schema/evidence validator is still mandatory. These functions are explicit host code, never selected by request data.

`Configuration.sandbox(fixtures)` supplies deterministic measurement fixtures. Missing fixture answers remain acquisition errors. Shell tests can combine it with a small fixture proposal callback; this does not make the fixture a human/model evaluation.

## Compare concrete revisions

```elixir
{:ok, comparison} = Fount.Intelligence.compare(before, candidate, constraints, services)
payload = Fount.Intelligence.Reporting.Report.to_map(comparison)
```

The result contains source/structural changes and constraint checks. Evidence is validated against both actual revisions. A scene-lift/ablation experiment creates an in-memory alternative; it does not update the accepted draft. Historical sources require explicit model values or a trusted history reader. Saved analytical reports must match their logical contract/digest and revision coverage; there is no reader for superseded report generations.

## Inspectability

Use `Reporting.Report.to_map/1` for JSON-friendly output and `Reporting.Report.persistence/2` for Fount's existing report storage boundary. Reports retain request/definition identities, coverage, findings, exact evidence, provenance and explicit errors. Measurements retain their raw distributions and actual acquisition status. No universal quality score, automatic deletions or calibrated claim about audience response is produced.

For actual generation/revision, see `packages/fount_workshop/examples/phase_one.exs` and the existing Workshop workflows.
