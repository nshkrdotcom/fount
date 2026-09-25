# Question profiles

These are finite question assets, not executable workflows. Public SDK constructors
compile them. Question types may not change an existing tool's question type.
Runtime candidate criteria and rubric levels remain owned by the specific tool.
Every evaluated request records the effective question definitions and their hash,
the asset hash, and the separate SDK Prepared fingerprint. The shared policy
threshold values describe the current fixed policy; changing these asset threshold
values alone does **not** change interpretation. Threshold override dispatch and
profiles for the remaining dynamic tools are follow-on work, not implemented here.
