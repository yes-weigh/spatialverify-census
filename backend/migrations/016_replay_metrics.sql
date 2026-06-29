-- Replay projection cache + flow metrics (disposable / analytics)

CREATE TABLE IF NOT EXISTS replay_projection_cache (
  mission_id UUID PRIMARY KEY REFERENCES enumeration_blocks(id) ON DELETE CASCADE,
  projection JSONB NOT NULL,
  builder_version TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS mission_flow_metrics (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  mission_id UUID NOT NULL REFERENCES enumeration_blocks(id) ON DELETE CASCADE,
  metric_type TEXT NOT NULL,
  aggregate_id TEXT,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ NOT NULL,
  duration_ms INT,
  payload JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mission_flow_metrics_mission
  ON mission_flow_metrics (mission_id, metric_type, completed_at);
