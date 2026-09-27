# Investigations and exact evidence

Investigations ask a specific writing question, gather selected evidence, and keep competing interpretations separate from accepted pages. Planning and explanation use a host-owned proposal service; no native completion client belongs in Intelligence.

```elixir
concern = "Does the audience learn about the spare key before Mara can plausibly discover it?"
{:ok, plan} = Fount.Intelligence.plan(model, concern, services)
requests = Enum.map(plan.data["requests"], &Map.take(&1, ["id", "playbook", "params"]))
{:ok, reports} = Fount.Intelligence.execute(model, requests, services)
{:ok, explanation} = Fount.Intelligence.explain(model, concern, reports, services)
```

`services` is constructed as described in `usage.md`. Inspect each report's status and errors before treating its findings as available. A successful batch return is not a claim that every acquisition succeeded. Hypothesis reasons are explanation, not executable authority; only the three request fields above enter `Playbooks.Request`.

Planning admits at most six requests and six hypotheses from the installed registry. Explanation can return evidence-linked hypotheses, uncertainties and strategies. It cannot apply screenplay edits. A strategy is not a candidate; actual writing remains a Workshop operation followed by explicit review.

Evidence IDs resolve to the exact inspected source, including revision, scene, element and element-relative UTF-8 span. Source-evidence validation rejects an invented ID, changed excerpt, invalid byte boundary or unsupported historical revision. Comparison reports carry their actual before/after models while being validated; those transient models are not serialized as provider metadata. Persisted report lookup requires its logical contract, shape digest and declared source coverage to match.

Do not translate missing acquisition into a negative answer, or model probabilities into established reader reactions. Candidate interpretation, accepted source and human feedback remain different things.
