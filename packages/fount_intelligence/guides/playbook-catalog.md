# Closed playbook catalog

`Fount.Intelligence.playbooks/0` returns installed names, required/optional fields, input schemas, output-contract identity and `writes_screenplay: false`. `Playbooks.Registry.validate/3` checks the current model, schema and target restrictions before dispatch. A request cannot select executable code or a persistence route.

| Playbook | Writing question or task |
|---|---|
| `inventory` | What scenes, characters and material are present? Optional summaries require the proposal service. |
| `extract_story` | Extract only requested story-record kinds with exact supporting evidence. |
| `search` | Find lexical, exact-phrase or semantically evaluated passages within an explicit source scope. |
| `check_constraints` | Check declared writing requirements without editing the draft. |
| `knowledge_trace` | What does a reader, estimated audience or selected character have evidence to know at each checkpoint? |
| `locate_boundary` | At which inspected checkpoint does a proposition cross the chosen threshold? |
| `dependencies` | Examine supported setups, uses and alternative support for selected targets. |
| `continuity` | Inspect selected story state and changes without making uncertainty disappear. |
| `scene_mechanics` | Examine objectives, obstacles, tactics and selected scene movement. |
| `dialogue` | Apply explicitly chosen dialogue lenses to actual passages. |
| `voice` | Compare character attribution and dialogue evidence, keeping training material separate from held-out turns. |
| `action` | Inspect visual action and optionally use a host-supplied measured-layout service. |
| `compare` | Compare concrete revisions and evaluate requested constraints. |
| `scene_lift` | Try removing scenes in memory, then compare without accepting the experiment. |
| `ablate` | Remove selected supporting material and re-measure a surviving checkpoint. |
| `strategy_contrast` | Compare named dramatic approaches to a specific brief without pretending they are screenplay pages. |

Use the executable catalog for exact field names and schemas. The examples in `usage.md`, `investigations-and-evidence.md` and `comparison-and-ablation.md` show the orchestration surfaces. Provider-free inventory needs `include_summaries: false` in the string-keyed request map. Other playbooks require the services their work actually uses; they do not silently substitute invented answers when a service is missing.

The first-phase catalog preserves existing inspection behavior. It is not a claim that all future twelve-family capabilities, temporal reducers or human-calibrated diagnostics are implemented.
