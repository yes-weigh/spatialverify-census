-- Evidence stream (append-only, hash-chained) + canonical knowledge graph + world projection cache

CREATE TABLE IF NOT EXISTS evidence_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  mission_id UUID NOT NULL REFERENCES enumeration_blocks(id) ON DELETE CASCADE,
  aggregate_id TEXT NOT NULL,
  aggregate_type TEXT NOT NULL,
  evidence_type TEXT NOT NULL,
  schema_version TEXT NOT NULL DEFAULT '1',
  payload JSONB NOT NULL DEFAULT '{}',
  occurred_at TIMESTAMPTZ NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  actor_id UUID REFERENCES users(id),
  device_id TEXT,
  record_hash TEXT NOT NULL,
  previous_hash TEXT,
  sequence_num BIGINT NOT NULL,
  CONSTRAINT evidence_mission_sequence_unique UNIQUE (mission_id, sequence_num)
);

CREATE INDEX IF NOT EXISTS idx_evidence_events_mission_seq
  ON evidence_events (mission_id, sequence_num ASC);

CREATE INDEX IF NOT EXISTS idx_evidence_events_mission_type
  ON evidence_events (mission_id, evidence_type);

-- Canonical derived state (rebuildable from evidence)
CREATE TABLE IF NOT EXISTS knowledge_graph_snapshots (
  mission_id UUID PRIMARY KEY REFERENCES enumeration_blocks(id) ON DELETE CASCADE,
  graph JSONB NOT NULL,
  fact_engine_version TEXT NOT NULL,
  reasoning_engine_version TEXT NOT NULL,
  last_evidence_sequence BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Disposable projection cache (WorldProjection builder v1)
CREATE TABLE IF NOT EXISTS world_projection_cache (
  mission_id UUID PRIMARY KEY REFERENCES enumeration_blocks(id) ON DELETE CASCADE,
  projection JSONB NOT NULL,
  builder_version TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
