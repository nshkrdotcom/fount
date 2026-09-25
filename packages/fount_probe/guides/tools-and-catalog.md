# Tools and Catalog Reference

`FountProbe.Catalog` defines the closed schema of inspection capabilities available to analysts and language models.

## Catalog Summary

| Tool | Required Parameters | Optional Parameters | Purpose |
| :--- | :--- | :--- | :--- |
| `inventory` | `selection` | `include_summaries` | Hierarchical summary of scenes, characters, headings, and counts |
| `extract_story` | `selection`, `kinds` | `question`, `adjacent_scenes` | Extracts beats, events, dialog, or scene chunks |
| `search` | `query` | `selection`, `filters`, `revision_ids`, `mode`, `limit`, `exact_phrase` | Lexical, semantic, and exact-phrase retrieval across script spans |
| `check_constraints` | `constraints` | `selection` | Validates dramaturgy, pacing limits, cast rules, and custom constraints |
| `knowledge_trace` | `proposition`, `subjects`, `points` | `access_mode`, `suspicion`, `behavior_element_ids`, `intended_reveal_point` | Verifies whether characters know or suspect specific propositions |
| `locate_boundary` | `scene_id`, `proposition`, `projection` | `character_id`, `threshold`, `include_prior_context` | Pinpoints the exact scene or element boundary where knowledge shifts |
| `dependencies` | `targets`, `selection` | `record_report_ids`, `include_alternative_support`, `inspect_setup_purpose` | Analyzes narrative setups, payoffs, props, and causal chains |
| `continuity` | `selection` | `subjects`, `changed_targets`, `record_report_ids` | Verifies temporal, character, prop, and spatial consistency |
| `scene_mechanics` | `selection` | `character_id`, `objective`, `concern`, `include_tactics` | Evaluates dramatic objectives, obstacles, tactics, and beats in scenes |
| `dialogue` | `selection`, `lenses` | `character_ids` | Deep dialogue examination through subtext, cadence, and exposition lenses |
| `voice` | `character_ids`, `selection` | `training_targets`, `profiles`, `comparison_groups` | Character dialogue fingerprinting and vocabulary distinctiveness |
| `action` | `selection` | `direction`, `layout_report_id` | Assesses visual pacing, line density, readability, and blocking clarity |
| `compare` | `before_revision_id`, `after_revision_id`, `constraints` | `profile_id` | Forensic delta analysis between two screenplay revisions |
| `scene_lift` | `scene_ids`, `constraints` | `consequence_scope` | Assesses dramatic and causal consequences of cutting or moving scenes |
| `ablate` | `groups`, `proposition`, `point`, `projection` | `character_id` | Counterfactual ablation removing specific scenes, facts, or beats |
| `strategy_contrast` | `brief`, `strategies` | — | Evaluates multiple proposed creative rewrite strategies against criteria |

## Schema Validation

Every tool invocation is strictly checked against the parameter types (`lists`, `booleans`, `strings`, `integers`, `numbers`) in `FountProbe.Catalog.validate/3`. Unrecognized parameters or malformed selections are rejected prior to execution.
