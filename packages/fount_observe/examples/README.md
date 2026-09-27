# Observe examples

Run `mix run examples/sandbox.exs` from `packages/fount_observe` after dependency setup. It prints a real Observe batch from fixed synthetic fixture answers, including source references and measurement/observation identities. It needs no credentials, database or live service. Execution is pending runtime QC.

For a live measurement use the same request/question and replace Sandbox with `Fount.Observe.provider/1` as shown in [usage](../guides/usage.md). Do not send a private screenplay without its owner's authorization.
