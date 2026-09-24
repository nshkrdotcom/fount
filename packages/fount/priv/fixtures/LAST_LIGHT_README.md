# Live demonstration material

`last_light.fountain` is original material written for this handoff, usable and modifiable in implementation, tests and examples. It is deliberately a short draft with opportunities for creative revision, not a professional-quality claim or a set of predetermined model answers. Do not use public copyrighted screenplay text as a test fixture without permission.

Import the file through the real parser. Bind scene/character/note selectors to the imported UUIDs and write `fixture_bindings.json` into the example output. Never bake parser-generated UUIDs into the examples. Assert each heading and selected text matches exactly once before resolving it.

| Label | Unique selector / purpose |
| --- | --- |
| scene_1 | `INT. MARINA OFFICE - DUSK`: establishes the accounting discrepancy and original across the water |
| scene_2 | `EXT. EQUIPMENT SHED - DUSK`: visible key transfer |
| scene_3 | `INT. RECORDS ROOM - NIGHT`: explicit confession; baseline reveal |
| scene_4 | `EXT. BOAT RAMP - NIGHT`: accusation dependent on that confession |
| scene_5 | `INT. TICKET HUT - NIGHT`: route obstacle and key reminder |
| scene_6 | `EXT. FERRY QUEUE - NIGHT`: destination for delayed confession |
| scene_7 | `EXT. SERVICE GATE - NIGHT`: key payoff and Dan's choice to follow |
| scene_8 | `INT. FERRY SALOON - NIGHT`: shared consequence |
| dan / mara | Exact normalized character cue, confirmed speaker identity |
| pin_line | `We bill by the berth, not by altitude.` |
| key_transfer | `He puts the key in her hand. She pockets it.` |
| local_note | `Give Dan a response here that costs him something.` |
| untouched_note | `Keep the imbalance between helping him and resenting him.` |

The fixture has eight scenes; scenes 2–6 are the five-scene sequence for W04. Keep scene 7's access plausible after sequence surgery. The first line is a protected joke for one request, not a mandatory screenplay convention. Existing notes and the boneyard test export/perspective handling. A separate small synthetic format fixture in core tests covers dual dialogue, Unicode, inline comments, CRLF and forced syntax; the live core example also creates a real temporary format specimen through the public APIs and exports it.

## Requests to demonstrate

- Develop: “A marina bookkeeper must get her former partner onto the last ferry to face an accountant. They used to trust each other. Give me two different opening scenes, one built around a practical task and one around an attempted escape. Let behavior carry the resentment.” Start from an empty root with this brief; do not import finished pages as a substitute for generation.
- Alternatives: “Rewrite the office confrontation in three approaches: a bargain, a failed bluff, and a physical discovery. Preserve the invoice discrepancy and the accountant across the water.” Audition two, then select A's opening and B's ending, requesting a connective beat.
- Propagate: “Move Dan's confession from the records room to the ferry queue. Before then Mara can suspect fraud but cannot know Dan admitted it. Repair her boat-ramp accusation and preserve her motive to reach the accountant, the key transfer and the service-gate payoff.” Inspect exact scenes 3, 4, 6 and 7 before/after.
- Sequence: “Compress scenes 2–6 into three scenes. Give me two materially different routes, preserve the transfer of the key and the need to face the accountant, and keep the protected joke wherever its original scene survives.” Render both; report measured pages without promising a reduction on this short script.
- Character: “Dan uses jokes to avoid choosing. Give him a voice that starts evasive and becomes concrete by the ferry. Rewrite him across at least three scenes, including a changed response to Mara's resistance, while preserving the confession and destination.”
- Notes: use the existing local note plus an external sequence note: “The trip to the ferry feels too easy; make a decision cost them something.” Accept only the local response in the dedicated demo project and show the sequence note remains open.
- Pass: execute dialogue/subtext, action/visual and dry-comedy passes over scene 1 separately. Request actual alternative pages; do not reuse one completion for all profiles.
- Recover: save a writer revision that removes the key transfer, then search the previous revision, recover it and ask for an adaptation to scene 5. Check scene 7. The saved removal is an explicit demonstration writer edit; the generated restoration stays proposed until selected.
- Investigate: “The trip to the ferry feels like a string of easy answers. Investigate the scene choices, then give me three routes that create stronger resistance and write two of them.” Model conclusions are allowed to disagree with the premise; record their evidence and still offer labeled exploratory remedies.

These requests are inputs to real calls. Do not ship their supposed outputs as example responses. Live acceptance checks verify valid structure, real outputs, identities, coverage and stated constraints; artistic success is reviewed from actual candidate pages.
