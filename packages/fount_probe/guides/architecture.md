# Fount Probe Architecture

Fount Probe provides a closed, deterministic inspection, comparison, and investigation engine for the [Fount](https://hexdocs.pm/fount) screenplay framework.

## Core Architectural Invariants

1. **Strict Read-Only Semantics (`writes_screenplay: false`)**:
   Every tool in the probe catalog guarantees zero mutation of the canonical screenplay, revision trees, or database records. Probes observe and report; they never edit.
2. **Exact Source Identity & Provenance**:
   All extracted facts, mentions, dialogue cues, and character knowledge states are anchored directly to:
   - Revision UUIDs (`revision_id`)
   - Scene UUIDs (`scene_id`)
   - Element UUIDs (`element_id`)
   - Byte-level CST spans (`start_byte`, `end_byte`)
3. **Closed Tool Catalog**:
   Probing operates through a finite, statically validated catalog of 16 tools defined in `FountProbe.Catalog`. AI models or automated workflows cannot execute arbitrary code or shell routes.
4. **Structured Investigation Lifecycle**:
   Investigations flow through a three-phase protocol:
   - **`plan/4`**: Determine which targeted probes are required to address a dramaturgical question or concern.
   - **`execute/4` or `run/5`**: Execute the planned probes against canonical models and gather structured `FountProbe.Report` records.
   - **`explain/5`**: Synthesize an evidence-backed dramaturgical finding, citing only the collected probe reports.

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                          CANONICAL SCREENPLAY                           │
│            (Scenes, Elements, CST Byte Spans, Revision Hash)            │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           FOUNT PROBE ENGINE                            │
│                                                                         │
│  ┌───────────────────┐   ┌───────────────────┐   ┌───────────────────┐  │
│  │  Closed Catalog   │   │    Projection     │   │ Budget Controller │  │
│  │ (16 Finite Tools) │   │ (Unit Selection)  │   │  (:atomics Quota) │  │
│  └───────────────────┘   └───────────────────┘   └───────────────────┘  │
│  ┌───────────────────┐   ┌───────────────────┐   ┌───────────────────┐  │
│  │  Knowledge Trace  │   │    Continuity     │   │  Scene Mechanics  │  │
│  │  (Audience/Cast)  │   │  (State & Props)  │   │ (7 Turn Dynamics) │  │
│  └───────────────────┘   └───────────────────┘   └───────────────────┘  │
│  ┌───────────────────┐   ┌───────────────────┐   ┌───────────────────┐  │
│  │   Dependencies    │   │  Dialogue & Voice │   │ Revision Compare  │  │
│  │  (Causal Ripple)  │   │ (Subtext/Attrib)  │   │ (Forensic Diffs)  │  │
│  └───────────────────┘   └───────────────────┘   └───────────────────┘  │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                       STRUCTURED EVIDENCE REPORT                        │
│   Grounded Findings, Probabilities, Element IDs, CST Byte Provenance    │
└─────────────────────────────────────────────────────────────────────────┘
```

## Report & Provenance Model

Every probe execution yields a `FountProbe.Report` struct:

- **`screenplay_id`**: The canonical screenplay identity.
- **`revision_id`**: The precise revision hash or UUID at the time of observation.
- **`tool`**: Name of the probe tool executed (e.g. `"knowledge_trace"`, `"voice"`).
- **`request`**: Parameters supplied to the probe.
- **`data`**: Structured results specific to the probe type.
- **`evidence`**: List of source-grounded references linking observations to scene and element IDs.
- **`provenance`**: Execution metadata including timestamp, request ID, and caller context.
