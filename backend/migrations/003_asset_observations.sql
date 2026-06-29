-- V2: Multi-view asset fingerprints via observations
CREATE TYPE view_type AS ENUM ('front', 'left', 'right', 'rear', 'far', 'unknown');

-- Observations are the atomic unit of spatial identity (not single embeddings)
CREATE TABLE asset_observations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    asset_id UUID REFERENCES assets(id) ON DELETE CASCADE,
    detection_id UUID REFERENCES detections(id) ON DELETE SET NULL,
    image_id UUID REFERENCES images(id) ON DELETE SET NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    altitude DOUBLE PRECISION,
    accuracy DOUBLE PRECISION,
    vertical_accuracy DOUBLE PRECISION,
    heading DOUBLE PRECISION,
    bearing_accuracy DOUBLE PRECISION,
    embedding vector(1280) NOT NULL,
    view_type view_type NOT NULL DEFAULT 'unknown',
    category_label VARCHAR(100),
    weather VARCHAR(50),
    lighting VARCHAR(50),
    model_name VARCHAR(50) NOT NULL DEFAULT 'mobilenet_v2',
    location GEOMETRY(Point, 4326) NOT NULL,
    captured_by UUID REFERENCES users(id),
    captured_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    client_id VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_asset_observations_project ON asset_observations(project_id);
CREATE INDEX idx_asset_observations_asset ON asset_observations(asset_id);
CREATE INDEX idx_asset_observations_captured ON asset_observations(captured_at);
CREATE INDEX idx_asset_observations_view ON asset_observations(view_type);
CREATE INDEX idx_asset_observations_location ON asset_observations USING GIST(location);
CREATE INDEX idx_asset_observations_vector ON asset_observations
    USING hnsw (embedding vector_cosine_ops);

-- GPS cluster + heading profile cached on asset fingerprint
ALTER TABLE assets ADD COLUMN IF NOT EXISTS gps_centroid GEOMETRY(Point, 4326);
ALTER TABLE assets ADD COLUMN IF NOT EXISTS gps_variance_m2 DOUBLE PRECISION;
ALTER TABLE assets ADD COLUMN IF NOT EXISTS gps_radius_m DOUBLE PRECISION;
ALTER TABLE assets ADD COLUMN IF NOT EXISTS observation_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE assets ADD COLUMN IF NOT EXISTS heading_mean DOUBLE PRECISION;
ALTER TABLE assets ADD COLUMN IF NOT EXISTS heading_variance DOUBLE PRECISION;
ALTER TABLE assets ADD COLUMN IF NOT EXISTS last_observation_at TIMESTAMPTZ;
ALTER TABLE assets ADD COLUMN IF NOT EXISTS visual_drift_score DOUBLE PRECISION;

CREATE INDEX IF NOT EXISTS idx_assets_gps_centroid ON assets USING GIST(gps_centroid);

-- Migrate existing embeddings into observations
INSERT INTO asset_observations (
    project_id, asset_id, detection_id, image_id,
    latitude, longitude, altitude, heading, embedding,
    view_type, category_label, model_name, location,
    captured_by, captured_at, client_id
)
SELECT
    ae.project_id, ae.asset_id, ae.detection_id, ae.image_id,
    ST_Y(ae.location::geometry), ST_X(ae.location::geometry),
    NULL, ae.heading, ae.embedding,
    'unknown'::view_type, ae.category_label, ae.model_name, ae.location,
    ae.captured_by, ae.created_at, ae.client_id
FROM asset_embeddings ae
WHERE ae.location IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM asset_observations ao
    WHERE ao.asset_id = ae.asset_id AND ao.captured_at = ae.created_at
  );

-- Enrich identity_resolutions with V2 explanation fields
ALTER TABLE identity_resolutions ADD COLUMN IF NOT EXISTS view_scores JSONB NOT NULL DEFAULT '{}';
ALTER TABLE identity_resolutions ADD COLUMN IF NOT EXISTS gps_accuracy DOUBLE PRECISION;
ALTER TABLE identity_resolutions ADD COLUMN IF NOT EXISTS explanation JSONB NOT NULL DEFAULT '{}';
ALTER TABLE identity_resolutions ADD COLUMN IF NOT EXISTS matched_view_type view_type;
ALTER TABLE identity_resolutions ADD COLUMN IF NOT EXISTS visual_drift DOUBLE PRECISION;
ALTER TABLE identity_resolutions ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;
