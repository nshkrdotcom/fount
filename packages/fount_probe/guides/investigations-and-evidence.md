# Investigations and Evidence

Fount Probe structures analytical workflows into verifiable investigations that avoid ungrounded model hallucinations.

## Investigation Protocol

When diagnosing an editorial question—such as *"Does Sarah discover Marcus's betrayal too early?"*—an agent follows three steps:

### 1. Planning

```elixir
concern = %{
  "question" => "Does Sarah discover Marcus's betrayal too early?",
  "subjects" => ["Sarah", "Marcus"],
  "scope" => %{"type" => "act", "number" => 2}
}

{:ok, plan} = FountProbe.plan(model, concern, clients)
```

The planner selects specific probes from the closed catalog (e.g. `knowledge_trace`, `dependencies`, `continuity`), generating deterministic request specs.

### 2. Execution

Run individual probes or a batch with guaranteed request ID deduplication:

```elixir
{:ok, reports} = FountProbe.execute(model, plan.requests, clients)
```

Each report includes the evidence items pointing to the precise lines, elements, and scenes that justify the observation.

### 3. Explanation

```elixir
{:ok, finding} = FountProbe.explain(model, concern, reports, clients)
```

The explanation synthesis synthesizes the reports into human-readable dramaturgical feedback while citing the explicit report and evidence IDs.
