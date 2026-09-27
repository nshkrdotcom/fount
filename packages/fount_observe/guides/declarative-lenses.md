# Constrained declarative lenses

Phase 8 exposes a data-only authoring path for project/studio measurements that fit Fount Observe's existing generic question machinery. It is intentionally **not** a plugin/module loader.

A declaration can choose only:

- one generic question kind: `noul`, `choice`, or `score`;
- a registered projection;
- the registered `observe.answer_set` output contract;
- a closed typed context contract;
- standard interpretation thresholds;
- an Observe resource-policy request;
- trust/source/calibration metadata.

It cannot name an Elixir module/function/MFA, shell command, file path, provider endpoint, URL, credentials/API key/token/headers, HTTP/database query, recursive callback, custom decoder/adapter, or tool.

## Validate and preview first

```elixir
{:ok, validated} = Fount.Observe.validate_declarative_lens(declaration)
{:ok, preview} = Fount.Observe.preview_declarative_lens(declaration)
```

The preview includes the canonical hash, generic question specification, exact caller-supplied lens asset, trust/source metadata, and `enabled: false`.

## Installation and enablement are separate

```elixir
catalog = Fount.Observe.new_declarative_lens_catalog()
{:ok, catalog} = Fount.Observe.install_declarative_lens(catalog, declaration)
{:ok, catalog} = Fount.Observe.enable_declarative_lens(catalog, declaration["id"])
```

The catalog is immutable caller-owned data. Phase 8 does not persist it across sessions. Durable project/studio asset storage is a later persistence phase.

## Execute through ordinary Observe

```elixir
{:ok, questions, lens, execution_opts} = Fount.Observe.compile_declarative_lens(declaration)
opts = Keyword.put(execution_opts, :lens, lens)

Fount.Observe.preflight(requests, questions, opts)
Fount.Observe.evaluate(provider, requests, questions, opts)
```

`Fount.Observe.Lens.validate/1`, `Question.validate_many/1`, normal request/context validation, provider budgeting, and output-contract handling still apply. The declaration does not get a new execution surface.

Genre/craft packs in `fount_intelligence` may reference an explicitly enabled custom lens catalog during pack validation. That reference only establishes a safe declared primitive; it does not grant the pack code execution authority.
