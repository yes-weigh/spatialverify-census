-- Official HLB boundaries from HLO / Census sources — authoritative mission perimeter.

CREATE TABLE IF NOT EXISTS hlb_boundaries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  eb_id UUID NOT NULL UNIQUE REFERENCES enumeration_blocks(id) ON DELETE CASCADE,
  hlb_code VARCHAR(20) NOT NULL,
  name VARCHAR(255),
  boundary GEOMETRY(Polygon, 4326) NOT NULL,
  area_sq_meters DOUBLE PRECISION NOT NULL DEFAULT 0,
  north_description TEXT,
  south_description TEXT,
  east_description TEXT,
  west_description TEXT,
  source VARCHAR(20) NOT NULL DEFAULT 'official',
  start_lat DOUBLE PRECISION,
  start_lng DOUBLE PRECISION,
  imported_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_hlb_boundaries_boundary ON hlb_boundaries USING GIST (boundary);
CREATE INDEX IF NOT EXISTS idx_hlb_boundaries_hlb_code ON hlb_boundaries (hlb_code);

CREATE TABLE IF NOT EXISTS mission_boundary_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  eb_id UUID NOT NULL UNIQUE REFERENCES enumeration_blocks(id) ON DELETE CASCADE,
  enumerator_id UUID REFERENCES users(id),
  entered_boundary_at TIMESTAMPTZ,
  left_boundary_at TIMESTAMPTZ,
  start_point_reached_at TIMESTAMPTZ,
  discovery_started_at TIMESTAMPTZ,
  outside_boundary_discoveries JSONB NOT NULL DEFAULT '[]',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mission_boundary_audit_eb ON mission_boundary_audit (eb_id);
