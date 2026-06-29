-- Census Mission Engine Phase 1: Layout Map → Enumerator Mission Plan

CREATE TYPE mission_building_type AS ENUM (
  'pucca_residential',
  'non_residential_pucca',
  'kutcha_residential',
  'kutcha_non_residential'
);

CREATE TYPE mission_building_status AS ENUM (
  'not_visited',
  'visited',
  'completed',
  'revisit_required'
);

CREATE TYPE eb_status AS ENUM ('draft', 'published', 'archived');

CREATE TYPE landmark_type AS ENUM (
  'school', 'temple', 'mosque', 'church', 'hospital',
  'panchayat_office', 'park', 'pond', 'river', 'other'
);

-- Enumeration Block (EB) with uploaded layout map
CREATE TABLE enumeration_blocks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  eb_code VARCHAR(20) NOT NULL,
  name VARCHAR(255),
  status eb_status NOT NULL DEFAULT 'draft',
  layout_image_key VARCHAR(512),
  layout_image_mime VARCHAR(100),
  -- Normalized map coords (0-1) for human-drawn boundary on layout image
  boundary_map JSONB NOT NULL DEFAULT '[]',
  -- Real-world boundary after GPS alignment (optional Phase 1)
  boundary GEOMETRY(Polygon, 4326),
  north_bearing DOUBLE PRECISION DEFAULT 0,
  route_building_ids UUID[] NOT NULL DEFAULT '{}',
  assigned_enumerator_id UUID REFERENCES users(id),
  created_by UUID REFERENCES users(id),
  published_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(project_id, eb_code)
);

CREATE INDEX idx_enumeration_blocks_project ON enumeration_blocks(project_id);
CREATE INDEX idx_enumeration_blocks_status ON enumeration_blocks(status);
CREATE INDEX idx_enumeration_blocks_assigned ON enumeration_blocks(assigned_enumerator_id);
CREATE INDEX idx_enumeration_blocks_boundary ON enumeration_blocks USING GIST(boundary);

-- Buildings on layout map
CREATE TABLE mission_buildings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  eb_id UUID NOT NULL REFERENCES enumeration_blocks(id) ON DELETE CASCADE,
  building_number INTEGER NOT NULL,
  census_house_count INTEGER NOT NULL DEFAULT 1,
  building_type mission_building_type NOT NULL DEFAULT 'pucca_residential',
  map_x DOUBLE PRECISION NOT NULL,
  map_y DOUBLE PRECISION NOT NULL,
  location GEOMETRY(Point, 4326),
  route_sequence INTEGER,
  status mission_building_status NOT NULL DEFAULT 'not_visited',
  notes TEXT,
  asset_id UUID REFERENCES assets(id) ON DELETE SET NULL,
  visited_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  completed_by UUID REFERENCES users(id),
  client_id VARCHAR(255),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(eb_id, building_number)
);

CREATE INDEX idx_mission_buildings_eb ON mission_buildings(eb_id);
CREATE INDEX idx_mission_buildings_status ON mission_buildings(status);
CREATE INDEX idx_mission_buildings_location ON mission_buildings USING GIST(location);

-- Landmarks on layout map
CREATE TABLE mission_landmarks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  eb_id UUID NOT NULL REFERENCES enumeration_blocks(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  landmark_type landmark_type NOT NULL DEFAULT 'other',
  map_x DOUBLE PRECISION NOT NULL,
  map_y DOUBLE PRECISION NOT NULL,
  location GEOMETRY(Point, 4326),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_mission_landmarks_eb ON mission_landmarks(eb_id);

-- GPS breadcrumb trail for coverage analysis
CREATE TABLE mission_gps_breadcrumbs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  eb_id UUID NOT NULL REFERENCES enumeration_blocks(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  location GEOMETRY(Point, 4326) NOT NULL,
  accuracy DOUBLE PRECISION,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_mission_breadcrumbs_eb ON mission_gps_breadcrumbs(eb_id);
CREATE INDEX idx_mission_breadcrumbs_user ON mission_gps_breadcrumbs(user_id);
CREATE INDEX idx_mission_breadcrumbs_location ON mission_gps_breadcrumbs USING GIST(location);
CREATE INDEX idx_mission_breadcrumbs_recorded ON mission_gps_breadcrumbs(recorded_at);
