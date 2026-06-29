-- Spatial Identity Engine: pgvector + embeddings + resolution audit
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TYPE identity_verdict AS ENUM ('same_asset', 'possible_match', 'new_asset');
CREATE TYPE identity_resolution_status AS ENUM ('pending', 'confirmed', 'rejected', 'auto_linked');

-- Per-image / per-asset visual embeddings (MobileNet v2 = 1280 dims)
CREATE TABLE asset_embeddings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
    image_id UUID REFERENCES images(id) ON DELETE SET NULL,
    detection_id UUID REFERENCES detections(id) ON DELETE SET NULL,
    model_name VARCHAR(50) NOT NULL DEFAULT 'mobilenet_v2',
    embedding vector(1280) NOT NULL,
    category_label VARCHAR(100),
    heading DOUBLE PRECISION,
    location GEOMETRY(Point, 4326),
    captured_by UUID REFERENCES users(id),
    client_id VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_asset_embeddings_project ON asset_embeddings(project_id);
CREATE INDEX idx_asset_embeddings_asset ON asset_embeddings(asset_id);
CREATE INDEX idx_asset_embeddings_location ON asset_embeddings USING GIST(location);
CREATE INDEX idx_asset_embeddings_vector ON asset_embeddings
    USING hnsw (embedding vector_cosine_ops);

-- Identity resolution audit trail
CREATE TABLE identity_resolutions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    detection_id UUID REFERENCES detections(id) ON DELETE SET NULL,
    query_category VARCHAR(100) NOT NULL,
    query_location GEOMETRY(Point, 4326) NOT NULL,
    query_heading DOUBLE PRECISION,
    query_embedding vector(1280),
    matched_asset_id UUID REFERENCES assets(id) ON DELETE SET NULL,
    verdict identity_verdict NOT NULL,
    gps_score DOUBLE PRECISION NOT NULL,
    embedding_score DOUBLE PRECISION NOT NULL,
    category_score DOUBLE PRECISION NOT NULL,
    heading_score DOUBLE PRECISION NOT NULL,
    final_confidence DOUBLE PRECISION NOT NULL,
    candidate_scores JSONB NOT NULL DEFAULT '[]',
    resolution_status identity_resolution_status NOT NULL DEFAULT 'pending',
    resolved_by UUID REFERENCES users(id),
    resolved_at TIMESTAMPTZ,
    conflict_id UUID REFERENCES conflicts(id) ON DELETE SET NULL,
    created_by UUID REFERENCES users(id),
    client_id VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_identity_resolutions_project ON identity_resolutions(project_id);
CREATE INDEX idx_identity_resolutions_verdict ON identity_resolutions(verdict);
CREATE INDEX idx_identity_resolutions_status ON identity_resolutions(resolution_status);
CREATE INDEX idx_identity_resolutions_matched_asset ON identity_resolutions(matched_asset_id);
CREATE INDEX idx_identity_resolutions_detection ON identity_resolutions(detection_id);

-- Link conflicts to identity engine
ALTER TABLE conflicts ADD COLUMN IF NOT EXISTS identity_resolution_id UUID REFERENCES identity_resolutions(id);
