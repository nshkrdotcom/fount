# Changelog

## 0.1.0 - 2026-09-24

Initial release of Fount Probe — screenplay-specific inspection, comparison, and investigation engine for the Fount framework:

- Closed screenplay tool catalog with 16 deterministic and scoped investigation tools (`inventory`, `extract_story`, `search`, `check_constraints`, `knowledge_trace`, `locate_boundary`, `dependencies`, `continuity`, `scene_mechanics`, `dialogue`, `voice`, `action`, `compare`, `scene_lift`, `ablate`, `strategy_contrast`)
- Strict read-only guarantee (`writes_screenplay: false`) with zero screenplay mutations
- Full source identity and provenance retention anchored to revision IDs, scene IDs, element IDs, and byte spans
- Investigation lifecycle orchestration (`plan/4`, `run/5`, `execute/4`, `explain/5`)
- Comparative analysis and counterfactual ablation (`compare/5`, `scene_lift`, `ablate`)
- CLI command runners (`mix fount.probe` and `mix fount.search`)
- Live script execution and test suite coverage
