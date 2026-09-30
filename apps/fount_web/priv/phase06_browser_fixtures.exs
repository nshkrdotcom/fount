# Test-only stored evidence; never starts a worker or calls a provider.
if Mix.env() != :test, do: raise("Phase 06 fixtures require MIX_ENV=test")
owner = System.fetch_env!("FOUNT_OWNER_ID")

{:ok, %{run: run, access: access}} =
  FountWeb.Launch.create(owner, %{
    "title" => "Stored Phase 06 evidence",
    "key" => "phase06-stored-#{Fount.ID.v4()}",
    "journey" => "opening",
    "source" => FountWeb.Journeys.fixture_fountain(),
    "filename" => "stored.fountain"
  })

{:ok, base} = Fount.Persistence.load(Fount.Repo, access["key"])

fixture = fn status, suffix, opts ->
  FountWeb.AnalysisFixtures.persist_packet(base, status, suffix, opts).id
end

ids = Map.new(~w(complete partial failed running), &{&1, fixture.(&1, &1, [])})
empty = fixture.("complete", "empty", story_world_records: [])
legacy = fixture.("complete", "legacy", legacy: true, observation: false)
left = fixture.("complete", "compare-a", observed: 2, evidence_id: "shared")
right = fixture.("complete", "compare-b", observed: 5, evidence_id: "shared")

other =
  fixture.("complete", "compare-other",
    observed: 8,
    evidence_id: "shared",
    provider: %{"provider" => "different", "model" => "fixture"}
  )

records =
  for n <- 1..70,
      do: %{
        "id" => "event-#{n}",
        "record_type" => "event",
        "label" => "Recorded event #{n}",
        "subjects" => ["NORA-#{n}"],
        "evidence_ids" => ["evidence-oversized"],
        "uncertainty" => "stored unknown"
      }

oversized = fixture.("complete", "oversized", story_world_records: records)
FountWeb.AnalysisFixtures.insert_usage(run, "reserved", "tokens", 120, nil, "unknown", "reserved")
FountWeb.AnalysisFixtures.insert_usage(run, "settled", "tokens", 80, 60, "known", "settled")

FountWeb.AnalysisFixtures.insert_usage(run, "unknown", "tokens", 30, 0, "unknown", "unknown")
{:ok, %{run: stale_run, access: stale_access}} =
  FountWeb.Launch.create(owner, %{
    "title" => "Stale stored evidence",
    "key" => "phase06-stale-#{Fount.ID.v4()}",
    "journey" => "opening",
    "source" => FountWeb.Journeys.fixture_fountain(),
    "filename" => "stale.fountain"
  })

{:ok, stale_base} = Fount.Persistence.load(Fount.Repo, stale_access["key"])
stale = FountWeb.AnalysisFixtures.persist_packet(stale_base, "complete", "stale")
[action | _] = Fount.Query.elements(stale_base, :action)

{:ok, changed} =
  Fount.Screenplay.apply(stale_base, Fount.Edit.replace_text(action.id, "Changed candidate."))

{:ok, candidate} = Fount.Persistence.save_edit_candidate(Fount.Repo, stale_access["key"], changed)

Ecto.Adapters.SQL.query!(
  Fount.Repo,
  "UPDATE fount_runs SET selected_candidate_id=$2::text::uuid WHERE id=$1::text::uuid",
  [stale_run["id"], candidate.id]
)

output =
  Map.merge(ids, %{
    "run_id" => run["id"],
    "revision_id" => base.revision.id,
    "empty" => empty,
    "legacy" => legacy,
    "left" => left,
    "right" => right,
    "other" => other,
    "oversized" => oversized,
    "stale_run_id" => stale_run["id"],
    "stale" => stale.id
  })

File.write!(
  Path.join(System.fetch_env!("FOUNT_ARTIFACT_ROOT"), "phase06-fixtures.json"),
  Jason.encode!(output)
)
