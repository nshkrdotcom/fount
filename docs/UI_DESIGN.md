# Screenplay workspace presentation

Fount is presented as a compact screenplay development workspace. Project titles,
writer-supplied synopses and screenplay pages carry the hierarchy. Small fonts and
tight spacing remain intentional: this is a working tool, not a promotional site.

## Research and design decisions

- [Frame.io's redesign](https://blog.frame.io/2024/05/21/frame-io-v4-web-app-beta-feature-focus-new-design-smooth-navigation/)
  emphasizes navigation and flexible workspaces around creative material.
- [StudioBinder's production boards](https://www.studiobinder.com/film-project-management-software/)
  organize project information into readable cards for production teams.
- [Sundance's producer discussion of pitch decks](https://collab.sundance.org/catalog/Advisor-Studio-Series-How-to-Create-a-Pitch-Deck-with-Jess-Devaney-and-Mallory-Schwartz)
  connects presentation to a project's look, feel and artistic intent.

These sources inform a story-first hierarchy, rather than establish a universal
Hollywood executive preference. Fount's implementation uses warm charcoal, paper,
restrained brass links, editorial project headings and plain surfaces. It adds no
stock imagery, borrowed interface assets, external fonts or decorative animation.
The screenplay keeps its original paper color, Courier typography and formatting.

Remove neon gradients, glowing status dots, ambient grids, decorative panel stripes
and slogan grids. Status labels remain readable without color; warnings, conflicts,
selected material and keyboard focus remain distinguishable.

## Language

Describe the user's work and the consequences of actions. Use “saved analysis,”
“screenplay version,” “approved screenplay,” “proposed changes” and “Run settings.”
Do not put phase numbers, database architecture, internal authority names or storage
claims in introductory copy. Candidate terminology remains where it distinguishes
saved proposals from approved changes. Technical version identities and recorded
results remain available for inspection; changing labels does not change contracts.

Saving a draft or candidate must never imply approval. Missing analysis must never
imply a pass. Cost estimates remain distinct from actual charges. Demo responses
remain labeled simulated, and the interface makes no screenplay-quality claim.

## Verification

Run the entire browser directory, including desktop/tablet/phone at 200% zoom,
keyboard focus, reduced motion, reconnect, lost acknowledgements, two-tab recovery,
imports, analysis and separate approval. Browser expectations use the new wording
without dropping behavioral checks. Run the complete runtime inventory on committed
source with logs outside the repository:

```sh
python3 scripts/run_runtime_qc.py --phase 8 --output /absolute/new/external/directory
```

Historical Phase 08 certification lives in the separate program docset. This is a
subsequent presentation refactor, not another program phase.
