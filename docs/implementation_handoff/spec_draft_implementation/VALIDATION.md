# Docset validation

Validated on 2026-09-24. This is a specification and implementation handoff; no Fount implementation or live model run is claimed by this document.

## Checks performed

- Read all nine source notes listed in 02 and inspected relevant code, manifests, tests and guides in Fount, System One SDK and Inference. Checked the local optional completion runtime's manifest after the user's clarification.
- Checked every local Markdown link and code-fence pairing, every JSON file, all three JSON Schemas under draft 2020-12, and both example payloads against their schemas with UUID format checking. All passed.
- Checked the user's document wording restrictions and unfinished-work markers. No violations found.
- Verified the original Fountain fixture has eight unique scene headings and unique selectors for the protected line, key transfer and two notes.
- Executed the full reference DDL against PostgreSQL 18.6 in a temporary cluster on a separate port. All tables, foreign keys and indexes were created successfully. The temporary cluster was removed by the helper afterward.
- Reviewed all W01–W09 requirements against the Workshop design, build sequence, test matrix and live modes. Checked the three XML names and local repository paths appear in both delivery instructions and the implementation prompt.
- Ran Git whitespace checks before committing.

Successful SQL command from this docset's parent directory:

```bash
pg_virtualenv -c '-p 65439' psql -X -v ON_ERROR_STOP=1 -f spec_draft_implementation/contracts/schema.sql
```

The helper's initial default-port attempt collided with an existing listener before executing SQL; using a separate temporary port resolved that environment issue. No existing database was modified.

## What these checks establish

The document set is internally linked, its sample wire contracts validate, its reference SQL executes, and its required creative workflows have explicit implementation and verification paths. The implementation agent must still translate the schema into Ecto, implement the APIs/workflows, run all three offline suites, and execute real provider/database/PDF examples as instructed. Schema validation alone does not establish runtime behavior or the artistic quality of generated writing.
