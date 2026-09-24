# Wishlist and upstream requests

This list is separate from the required release in 01/01a. Do not move the nine writing workflows here to reduce implementation effort. Current required workflows can be built using the inspected public System One and Inference APIs; no proven System One blocker was found.

## Provider request: Antigravity

The user explicitly chose Codex for this implementation and asked that Antigravity remain a wishlist item. Inference's inspected ASM adapter refuses Antigravity because the provider does not currently prove the adapter's required completion-only contract. Do not add Antigravity configuration, direct calls, alternate CLI wrappers or examples to Fount. A later upstream change needs a real completion-only capability declaration and implementation, structured-output capability reporting, error handling and an offline adapter test before a Fount live example is appropriate. Reassess the then-current Inference/ASM sources rather than assuming the present restriction is permanent.

## Possible System One improvements to request after evidence

| Desired future use | Current public support / remaining question | Upstream request if needed |
| --- | --- | --- |
| Predicting whether a long screenplay evidence packet fits before dispatch | Fount can measure bytes and split exact scene context; this does not establish a model's token/context limit | If absent in the then-current model metadata, expose documented input limits and an estimation interface. Do not invent a local tokenizer compatibility layer. |
| Comparing a saved screenplay check after a moving model alias changes | Fount records returned model metadata, prepared fingerprint and profile version; an alias may still resolve differently | If the API offers immutable model revisions not exposed by the SDK, expose that identifier/selection. No fixed-result claims from `jev-latest`. |
| Explaining which exact phrase caused an evaluation | Current question answers provide probabilities/choices/scores, not trustworthy generated supporting spans | If the service adds attribution or token-span evidence, expose it with documented semantics. Until then Fount's candidate-evidence testing remains an interpretation, not model attribution. |
| Provider-side cancellation/usage detail beyond currently reported values | Fount records what the public SDK returns and stops scheduling new work | Request an upstream API only if a real use case requires unavailable cancellation or accounting. Do not guess charges or emulate transport internals. |

These are conditional future requests, not assertions that a present public API is defective. File a concrete request only after naming the missing symbol/behavior in the supplied source, the writer workflow blocked, a minimal request/response example, and the desired SDK-level change. Required release features must not depend on these future improvements.

## Future writing features

- A graphical editor showing alternative passages inline, keyboard auditioning and visual sequence cards over the same implemented APIs.
- Collaborative review, permissions and multi-writer conflict resolution. Current head conflicts and three-way candidate rebase serve a local writing workflow; do not build a collaboration platform now.
- Richer FDX production metadata, production revision colors and shooting-script workflows when actual writer needs demand them. Preserve/report current unsupported import fidelity.
- Professional multi-voice performance synthesis with deliberate casting and simultaneous dual playback. The release already supplies table-read data and optional real local speech.
- Longer-lived character/series bibles spanning multiple screenplay projects, with explicit canon adoption and cross-project identities.
- More genre-specific creative profiles after using the initial dialogue/visual/comedy/tension workflows on real drafts. Profiles must earn their place through useful writing outcomes.
- More advanced dependency discovery or retrieval after ordinary full-text/structured search and exact-source inspection show a practical limit. No graph/vector service is required for the specified screenplay scale.

A future feature proposal should begin with a writer request and an example of the pages or decision it improves, then explain necessary tools/schema changes. A new metric alone is not sufficient product justification.
