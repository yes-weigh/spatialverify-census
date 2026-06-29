-- Census layout map georeferencing — sketch → GPS boundary alignment audit trail.

CREATE TABLE IF NOT EXISTS layout_georef_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  eb_id UUID NOT NULL UNIQUE REFERENCES enumeration_blocks(id) ON DELETE CASCADE,
  uploaded_map_key VARCHAR(512) NOT NULL,
  preview_map_key VARCHAR(512),
  mime_type VARCHAR(100) NOT NULL,
  status VARCHAR(30) NOT NULL DEFAULT 'uploaded',
  ai_suggestions JSONB DEFAULT '{}',
  control_points JSONB NOT NULL DEFAULT '[]',
  sketch_boundary JSONB NOT NULL DEFAULT '[]',
  affine_matrix DOUBLE PRECISION[],
  boundary_polygon JSONB,
  landmarks JSONB NOT NULL DEFAULT '[]',
  roads JSONB NOT NULL DEFAULT '[]',
  water_bodies JSONB NOT NULL DEFAULT '[]',
  alignment_score VARCHAR(20),
  rms_error_meters DOUBLE PRECISION,
  polygon_area_sq_meters DOUBLE PRECISION,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finalized_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_layout_georef_eb ON layout_georef_sessions (eb_id);
