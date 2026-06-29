-- HLB discovery: boundary walk vertices from GPS (ground-truth mapping)

CREATE TABLE mission_boundary_vertices (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  eb_id UUID NOT NULL REFERENCES enumeration_blocks(id) ON DELETE CASCADE,
  sequence INTEGER NOT NULL,
  location GEOMETRY(Point, 4326) NOT NULL,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_boundary_vertices_eb ON mission_boundary_vertices(eb_id);
