# Adapters and Fidelity

Foreign formats are boundaries around the canonical model. An adapter must report what it cannot preserve rather than silently pretending conversions are lossless.

## JSON projection

`Fount.Adapter.JSON` emits a versioned `fount.projection.v1` representation containing screenplay structure, identities, spans, revisions, annotations, and optionally source. It is a projection for APIs/indexing/debugging, not the architecture of the in-memory model.
Canonical `Fount.Screenplay` projections also include authored cast and occurrence evidence.

## FDX

`Fount.Adapter.FDX` provides practical spec-script interchange:

- scene headings and scene numbers
- action
- character cues and extensions
- dialogue and parentheticals
- dual dialogue
- transitions
- lyrics/shots where representable
- selected inline bold/italic/underline import

The adapter reports losses for production-specific or currently unsupported information such as locked-page state, FDX revision metadata, production tags, script notes, title-page positioning, and styling without a faithful Fountain equivalent.

`Fount.Screenplay.from_fdx/2` returns a canonical model and import losses. `Fount.Screenplay.to_fdx/1` returns exact original XML for an untouched FDX import; after a model edit it regenerates FDX and carries the import losses forward. XML text is escaped on regenerated export.

FDX is deliberately not allowed to shape Fount's domain model. A valid FDX document can contain production/application state irrelevant to ordinary spec-script authoring and analysis.

## Future adapters

An adapter should return data plus diagnostics/loss information. Fountain and FDX imports map into `Fount.Screenplay`; original bytes are retained for unchanged export, while the Fountain CST remains available in the parsed `Fount.Document` and can be reconstructed from those bytes. `Fount.Screenplay.export_fountain/2` reports when canonical editing may change lexical trivia. Either route must preserve the distinction between canonical screenplay facts and foreign-format application metadata.
