-- Coverage gap investigation audit trail (zero-exclusion proof)
CREATE TABLE IF NOT EXISTS mission_coverage_gap_resolutions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  eb_id UUID NOT NULL REFERENCES enumeration_blocks(id) ON DELETE CASCADE,
  gap_fingerprint TEXT NOT NULL,
  gap_type TEXT NOT NULL,
  gap_reason TEXT NOT NULL,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  resolution TEXT NOT NULL CHECK (resolution IN (
    'building_found', 'no_building', 'not_accessible', 'investigated'
  )),
  notes TEXT,
  resolved_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_by UUID REFERENCES users(id),
  resolved_latitude DOUBLE PRECISION,
  resolved_longitude DOUBLE PRECISION,
  UNIQUE (eb_id, gap_fingerprint)
);

CREATE INDEX IF NOT EXISTS idx_gap_resolutions_eb ON mission_coverage_gap_resolutions(eb_id);
