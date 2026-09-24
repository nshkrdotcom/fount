-- Reference fresh PostgreSQL schema. Translate to Ecto migrations.
-- All timestamps are UTC; UUIDs are assigned by the application.
CREATE TABLE screenplays (
  id uuid PRIMARY KEY,
  key text NOT NULL UNIQUE,
  head_revision_id uuid,
  inserted_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE import_artifacts (
  id uuid PRIMARY KEY,
  screenplay_id uuid NOT NULL REFERENCES screenplays(id),
  format text NOT NULL CHECK (format IN ('fountain','fdx','json')),
  original_bytes bytea NOT NULL,
  bytes_sha256 text NOT NULL,
  render_hash text NOT NULL,
  fidelity jsonb NOT NULL DEFAULT '{}',
  inserted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (screenplay_id,id)
);
CREATE TABLE revisions (
  id uuid PRIMARY KEY,
  screenplay_id uuid NOT NULL REFERENCES screenplays(id),
  parent_id uuid,
  artifact_id uuid,
  content_hash text NOT NULL,
  render_hash text NOT NULL,
  actor text,
  message text,
  format_version integer NOT NULL DEFAULT 2 CHECK (format_version = 2),
  inserted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (screenplay_id,id),
  CHECK (parent_id IS NULL OR parent_id <> id),
  FOREIGN KEY (screenplay_id,parent_id) REFERENCES revisions(screenplay_id,id),
  FOREIGN KEY (screenplay_id,artifact_id) REFERENCES import_artifacts(screenplay_id,id)
);
ALTER TABLE screenplays ADD CONSTRAINT screenplay_head_fk
  FOREIGN KEY (id,head_revision_id) REFERENCES revisions(screenplay_id,id)
  DEFERRABLE INITIALLY DEFERRED;
CREATE INDEX revision_history ON revisions(screenplay_id,inserted_at,id);
CREATE TABLE title_entries (
  screenplay_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  id uuid NOT NULL,
  ordinal integer NOT NULL CHECK (ordinal >= 0),
  key text NOT NULL,
  values text[] NOT NULL,
  PRIMARY KEY (screenplay_id,revision_id,id),
  UNIQUE (screenplay_id,revision_id,ordinal),
  FOREIGN KEY (screenplay_id,revision_id) REFERENCES revisions(screenplay_id,id)
);
CREATE TABLE scenes (
  screenplay_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  id uuid NOT NULL,
  ordinal integer NOT NULL CHECK (ordinal >= 0),
  heading_element_id uuid NOT NULL,
  scene_number text,
  omitted boolean NOT NULL DEFAULT false,
  location_parts text[] NOT NULL DEFAULT '{}',
  time_of_day text,
  PRIMARY KEY (screenplay_id,revision_id,id),
  UNIQUE (screenplay_id,revision_id,ordinal),
  FOREIGN KEY (screenplay_id,revision_id) REFERENCES revisions(screenplay_id,id)
);
CREATE TABLE dialogue_blocks (
  screenplay_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  id uuid NOT NULL,
  ordinal integer NOT NULL CHECK (ordinal >= 0),
  scene_id uuid,
  cue_element_id uuid NOT NULL,
  dual_with_id uuid,
  side text CHECK (side IN ('left','right')),
  PRIMARY KEY (screenplay_id,revision_id,id),
  UNIQUE (screenplay_id,revision_id,ordinal),
  CHECK (dual_with_id IS NULL OR dual_with_id <> id),
  CHECK ((dual_with_id IS NULL) = (side IS NULL)),
  FOREIGN KEY (screenplay_id,revision_id) REFERENCES revisions(screenplay_id,id),
  FOREIGN KEY (screenplay_id,revision_id,scene_id) REFERENCES scenes(screenplay_id,revision_id,id),
  FOREIGN KEY (screenplay_id,revision_id,dual_with_id) REFERENCES dialogue_blocks(screenplay_id,revision_id,id)
    DEFERRABLE INITIALLY DEFERRED
);
CREATE TABLE elements (
  screenplay_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  id uuid NOT NULL,
  ordinal integer NOT NULL CHECK (ordinal >= 0),
  scene_id uuid,
  dialogue_block_id uuid,
  type text NOT NULL CHECK (type IN ('scene_heading','action','character','dialogue',
    'parenthetical','transition','centered','lyric','section','synopsis','page_break',
    'note','boneyard','blank','unknown')),
  text text NOT NULL,
  raw_text text,
  inline jsonb NOT NULL DEFAULT '[]',
  attrs jsonb NOT NULL DEFAULT '{}',
  source_reference jsonb,
  origin text,
  PRIMARY KEY (screenplay_id,revision_id,id),
  UNIQUE (screenplay_id,revision_id,ordinal),
  FOREIGN KEY (screenplay_id,revision_id) REFERENCES revisions(screenplay_id,id),
  FOREIGN KEY (screenplay_id,revision_id,scene_id) REFERENCES scenes(screenplay_id,revision_id,id),
  FOREIGN KEY (screenplay_id,revision_id,dialogue_block_id) REFERENCES dialogue_blocks(screenplay_id,revision_id,id)
    DEFERRABLE INITIALLY DEFERRED
);
ALTER TABLE scenes ADD CONSTRAINT scene_heading_fk
  FOREIGN KEY (screenplay_id,revision_id,heading_element_id) REFERENCES elements(screenplay_id,revision_id,id)
  DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE dialogue_blocks ADD CONSTRAINT dialogue_cue_fk
  FOREIGN KEY (screenplay_id,revision_id,cue_element_id) REFERENCES elements(screenplay_id,revision_id,id)
  DEFERRABLE INITIALLY DEFERRED;
CREATE INDEX element_scene_order ON elements(screenplay_id,revision_id,scene_id,ordinal);
CREATE INDEX element_type_order ON elements(screenplay_id,revision_id,type,ordinal);
CREATE INDEX element_search ON elements USING gin(to_tsvector('simple',text));
CREATE TABLE characters (
  screenplay_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  id uuid NOT NULL,
  display_name text NOT NULL,
  notes text,
  attributes jsonb NOT NULL DEFAULT '{}',
  PRIMARY KEY (screenplay_id,revision_id,id),
  FOREIGN KEY (screenplay_id,revision_id) REFERENCES revisions(screenplay_id,id)
);
CREATE TABLE character_aliases (
  screenplay_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  character_id uuid NOT NULL,
  alias text NOT NULL,
  normalized_alias text NOT NULL,
  kind text NOT NULL,
  PRIMARY KEY (screenplay_id,revision_id,character_id,normalized_alias,kind),
  FOREIGN KEY (screenplay_id,revision_id,character_id) REFERENCES characters(screenplay_id,revision_id,id)
);
CREATE INDEX alias_lookup ON character_aliases(screenplay_id,revision_id,normalized_alias);
CREATE TABLE mentions (
  screenplay_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  id uuid NOT NULL,
  element_id uuid NOT NULL,
  character_id uuid,
  role text NOT NULL,
  status text NOT NULL CHECK (status IN ('confirmed','suggested','ambiguous','rejected')),
  surface text NOT NULL,
  byte_start integer NOT NULL CHECK (byte_start >= 0),
  byte_end integer NOT NULL CHECK (byte_end > byte_start),
  producer text NOT NULL,
  confidence double precision CHECK (confidence >= 0 AND confidence <= 1),
  PRIMARY KEY (screenplay_id,revision_id,id),
  FOREIGN KEY (screenplay_id,revision_id,element_id) REFERENCES elements(screenplay_id,revision_id,id),
  FOREIGN KEY (screenplay_id,revision_id,character_id) REFERENCES characters(screenplay_id,revision_id,id)
);
CREATE INDEX mentions_for_character ON mentions(screenplay_id,revision_id,character_id,role);
CREATE TABLE mention_candidates (
  screenplay_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  mention_id uuid NOT NULL,
  character_id uuid NOT NULL,
  PRIMARY KEY (screenplay_id,revision_id,mention_id,character_id),
  FOREIGN KEY (screenplay_id,revision_id,mention_id) REFERENCES mentions(screenplay_id,revision_id,id),
  FOREIGN KEY (screenplay_id,revision_id,character_id) REFERENCES characters(screenplay_id,revision_id,id)
);
CREATE TABLE authored_items (
  screenplay_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  id uuid NOT NULL,
  namespace text NOT NULL,
  kind text NOT NULL,
  target jsonb NOT NULL,
  value jsonb NOT NULL,
  dependencies jsonb NOT NULL DEFAULT '[]',
  status text NOT NULL CHECK (status IN ('active','unresolved','resolved')),
  provenance jsonb NOT NULL DEFAULT '{}',
  PRIMARY KEY (screenplay_id,revision_id,id),
  FOREIGN KEY (screenplay_id,revision_id) REFERENCES revisions(screenplay_id,id)
);
CREATE INDEX authored_kind ON authored_items(screenplay_id,revision_id,namespace,kind,status);
CREATE TABLE writing_sessions (
  id uuid PRIMARY KEY,
  screenplay_id uuid NOT NULL,
  base_revision_id uuid NOT NULL,
  workflow text NOT NULL CHECK (workflow IN ('develop','alternatives','propagate','sequence',
    'character','notes','pass','recover','investigate')),
  status text NOT NULL CHECK (status IN ('open','running','ready','partial','failed','closed')),
  request jsonb NOT NULL,
  strategies jsonb NOT NULL DEFAULT '[]',
  progress jsonb NOT NULL DEFAULT '{}',
  provenance jsonb NOT NULL DEFAULT '{}',
  lock_version integer NOT NULL DEFAULT 1,
  inserted_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (screenplay_id,id),
  FOREIGN KEY (screenplay_id,base_revision_id) REFERENCES revisions(screenplay_id,id)
);
CREATE TABLE writing_candidates (
  id uuid PRIMARY KEY,
  screenplay_id uuid NOT NULL,
  session_id uuid NOT NULL,
  base_revision_id uuid NOT NULL,
  result_revision_id uuid NOT NULL,
  parent_candidate_id uuid,
  label text NOT NULL,
  strategy jsonb NOT NULL DEFAULT '{}',
  change_groups jsonb NOT NULL,
  lineage jsonb NOT NULL DEFAULT '[]',
  provenance jsonb NOT NULL,
  decision text NOT NULL DEFAULT 'proposed' CHECK (decision IN ('proposed','accepted','rejected')),
  decision_actor text,
  decided_at timestamptz,
  inserted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (screenplay_id,id),
  UNIQUE (screenplay_id,result_revision_id),
  FOREIGN KEY (screenplay_id,session_id) REFERENCES writing_sessions(screenplay_id,id),
  FOREIGN KEY (screenplay_id,base_revision_id) REFERENCES revisions(screenplay_id,id),
  FOREIGN KEY (screenplay_id,result_revision_id) REFERENCES revisions(screenplay_id,id),
  FOREIGN KEY (screenplay_id,parent_candidate_id) REFERENCES writing_candidates(screenplay_id,id)
);
CREATE INDEX candidates_for_session ON writing_candidates(session_id,inserted_at,id);
CREATE TABLE analysis_reports (
  id uuid PRIMARY KEY,
  screenplay_id uuid NOT NULL REFERENCES screenplays(id),
  primary_revision_id uuid NOT NULL,
  session_id uuid,
  tool text NOT NULL,
  status text NOT NULL CHECK (status IN ('complete','partial','failed')),
  fingerprint text NOT NULL,
  payload jsonb NOT NULL,
  inserted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (screenplay_id,id),
  FOREIGN KEY (screenplay_id,primary_revision_id) REFERENCES revisions(screenplay_id,id),
  FOREIGN KEY (screenplay_id,session_id) REFERENCES writing_sessions(screenplay_id,id)
);
CREATE INDEX reports_for_revision ON analysis_reports(screenplay_id,primary_revision_id,tool,inserted_at);
CREATE TABLE analysis_report_sources (
  screenplay_id uuid NOT NULL,
  report_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  PRIMARY KEY (screenplay_id,report_id,revision_id),
  FOREIGN KEY (screenplay_id,report_id) REFERENCES analysis_reports(screenplay_id,id),
  FOREIGN KEY (screenplay_id,revision_id) REFERENCES revisions(screenplay_id,id)
);
CREATE TABLE acceptances (
  id uuid PRIMARY KEY,
  screenplay_id uuid NOT NULL,
  base_revision_id uuid,
  result_revision_id uuid NOT NULL,
  candidate_id uuid,
  actor text NOT NULL,
  origin text NOT NULL CHECK (origin IN ('writer_edit','imported_text','generated_text','generated_structural_edit','mixed')),
  operations jsonb NOT NULL,
  provenance jsonb NOT NULL,
  review jsonb NOT NULL,
  inserted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (screenplay_id,result_revision_id),
  FOREIGN KEY (screenplay_id,base_revision_id) REFERENCES revisions(screenplay_id,id),
  FOREIGN KEY (screenplay_id,result_revision_id) REFERENCES revisions(screenplay_id,id),
  FOREIGN KEY (screenplay_id,candidate_id) REFERENCES writing_candidates(screenplay_id,id)
);
