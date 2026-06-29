-- SpatialVerify PostGIS Schema
-- Enable extensions
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Enums
CREATE TYPE user_role AS ENUM ('admin', 'supervisor', 'field_worker');
CREATE TYPE asset_status AS ENUM ('not_surveyed', 'pending', 'verified', 'rejected');
CREATE TYPE geometry_type AS ENUM ('point', 'line', 'polygon');
CREATE TYPE sync_status AS ENUM ('pending', 'uploading', 'synced', 'failed', 'conflict');
CREATE TYPE human_decision AS ENUM ('confirmed', 'rejected', 'edited');
CREATE TYPE reconstruction_phase AS ENUM ('capture', 'sparse_point_cloud', 'mesh', 'gltf_export', 'completed', 'failed');
CREATE TYPE notification_type AS ENUM ('conflict', 'approval', 'sync', 'assignment', 'system');
CREATE TYPE audit_action AS ENUM ('create', 'update', 'delete', 'login', 'logout', 'sync', 'verify', 'reject', 'resolve_conflict');

-- Users
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    role user_role NOT NULL DEFAULT 'field_worker',
    is_active BOOLEAN NOT NULL DEFAULT true,
    device_id VARCHAR(255),
    last_login_at TIMESTAMPTZ,
    password_reset_token VARCHAR(255),
    password_reset_expires TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_device_id ON users(device_id);

-- Refresh tokens
CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    device_id VARCHAR(255) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_token_hash ON refresh_tokens(token_hash);

-- Projects
CREATE TABLE projects (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    boundary GEOMETRY(Polygon, 4326),
    survey_rules JSONB NOT NULL DEFAULT '{}',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_projects_boundary ON projects USING GIST(boundary);
CREATE INDEX idx_projects_active ON projects(is_active);

-- Asset categories
CREATE TABLE asset_categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    detection_labels JSONB NOT NULL DEFAULT '[]',
    icon VARCHAR(50),
    color VARCHAR(7),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(project_id, name)
);

CREATE INDEX idx_asset_categories_project ON asset_categories(project_id);

-- Teams
CREATE TABLE teams (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(project_id, name)
);

CREATE TABLE team_members (
    team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (team_id, user_id)
);

CREATE INDEX idx_team_members_user ON team_members(user_id);

-- Assets
CREATE TABLE assets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    category_id UUID REFERENCES asset_categories(id),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    status asset_status NOT NULL DEFAULT 'not_surveyed',
    geometry_type geometry_type NOT NULL DEFAULT 'point',
    location GEOMETRY(Geometry, 4326) NOT NULL,
    altitude DOUBLE PRECISION,
    heading DOUBLE PRECISION,
    metadata JSONB NOT NULL DEFAULT '{}',
    created_by UUID REFERENCES users(id),
    verified_by UUID REFERENCES users(id),
    verified_at TIMESTAMPTZ,
    client_id VARCHAR(255),
    version INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_assets_location ON assets USING GIST(location);
CREATE INDEX idx_assets_project ON assets(project_id);
CREATE INDEX idx_assets_status ON assets(status);
CREATE INDEX idx_assets_category ON assets(category_id);
CREATE INDEX idx_assets_client_id ON assets(client_id);

-- Detections
CREATE TABLE detections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    asset_id UUID REFERENCES assets(id) ON DELETE SET NULL,
    session_id UUID,
    category_label VARCHAR(100) NOT NULL,
    confidence DOUBLE PRECISION NOT NULL,
    bounding_box JSONB NOT NULL,
    location GEOMETRY(Point, 4326),
    altitude DOUBLE PRECISION,
    heading DOUBLE PRECISION,
    image_id UUID,
    ai_model VARCHAR(100) NOT NULL DEFAULT 'yolov8',
    client_id VARCHAR(255),
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_detections_location ON detections USING GIST(location);
CREATE INDEX idx_detections_project ON detections(project_id);
CREATE INDEX idx_detections_asset ON detections(asset_id);
CREATE INDEX idx_detections_session ON detections(session_id);

-- Verifications
CREATE TABLE verifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    detection_id UUID NOT NULL REFERENCES detections(id) ON DELETE CASCADE,
    asset_id UUID REFERENCES assets(id) ON DELETE SET NULL,
    ai_prediction VARCHAR(100) NOT NULL,
    confidence DOUBLE PRECISION NOT NULL,
    human_decision human_decision NOT NULL,
    edited_category VARCHAR(100),
    edited_location GEOMETRY(Point, 4326),
    notes TEXT,
    verified_by UUID NOT NULL REFERENCES users(id),
    verified_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    client_id VARCHAR(255)
);

CREATE INDEX idx_verifications_detection ON verifications(detection_id);
CREATE INDEX idx_verifications_asset ON verifications(asset_id);
CREATE INDEX idx_verifications_verified_by ON verifications(verified_by);

-- Spatial anchors
CREATE TABLE anchors (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    asset_id UUID REFERENCES assets(id) ON DELETE CASCADE,
    anchor_id VARCHAR(255) NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    altitude DOUBLE PRECISION,
    heading DOUBLE PRECISION,
    camera_orientation JSONB,
    anchor_data JSONB NOT NULL DEFAULT '{}',
    is_relocated BOOLEAN NOT NULL DEFAULT false,
    created_by UUID REFERENCES users(id),
    client_id VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_anchors_project ON anchors(project_id);
CREATE INDEX idx_anchors_asset ON anchors(asset_id);
CREATE INDEX idx_anchors_location ON anchors USING GIST(
    ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)
);

-- Images
CREATE TABLE images (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    asset_id UUID REFERENCES assets(id) ON DELETE SET NULL,
    detection_id UUID REFERENCES detections(id) ON DELETE SET NULL,
    s3_key VARCHAR(500) NOT NULL,
    s3_bucket VARCHAR(100) NOT NULL,
    mime_type VARCHAR(50) NOT NULL,
    file_size BIGINT NOT NULL,
    width INTEGER,
    height INTEGER,
    location GEOMETRY(Point, 4326),
    heading DOUBLE PRECISION,
    encryption_key_id VARCHAR(100),
    captured_by UUID REFERENCES users(id),
    captured_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    client_id VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_images_project ON images(project_id);
CREATE INDEX idx_images_asset ON images(asset_id);

-- Point clouds
CREATE TABLE point_clouds (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    asset_id UUID REFERENCES assets(id) ON DELETE SET NULL,
    session_id UUID,
    phase reconstruction_phase NOT NULL DEFAULT 'capture',
    s3_key VARCHAR(500),
    point_count INTEGER,
    bounds GEOMETRY(Polygon, 4326),
    metadata JSONB NOT NULL DEFAULT '{}',
    created_by UUID REFERENCES users(id),
    client_id VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_point_clouds_project ON point_clouds(project_id);

-- Meshes
CREATE TABLE meshes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    point_cloud_id UUID NOT NULL REFERENCES point_clouds(id) ON DELETE CASCADE,
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    phase reconstruction_phase NOT NULL DEFAULT 'mesh',
    s3_key VARCHAR(500),
    vertex_count INTEGER,
    face_count INTEGER,
    gltf_s3_key VARCHAR(500),
    metadata JSONB NOT NULL DEFAULT '{}',
    created_by UUID REFERENCES users(id),
    client_id VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_meshes_project ON meshes(project_id);
CREATE INDEX idx_meshes_point_cloud ON meshes(point_cloud_id);

-- Survey sessions
CREATE TABLE survey_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id),
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    coverage_percentage DOUBLE PRECISION NOT NULL DEFAULT 0,
    path GEOMETRY(MultiLineString, 4326),
    visited_area GEOMETRY(MultiPolygon, 4326),
    metadata JSONB NOT NULL DEFAULT '{}',
    client_id VARCHAR(255),
    sync_status sync_status NOT NULL DEFAULT 'pending'
);

CREATE INDEX idx_survey_sessions_project ON survey_sessions(project_id);
CREATE INDEX idx_survey_sessions_user ON survey_sessions(user_id);
CREATE INDEX idx_survey_sessions_path ON survey_sessions USING GIST(path);

-- Coverage maps
CREATE TABLE coverage_maps (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    session_id UUID REFERENCES survey_sessions(id) ON DELETE CASCADE,
    grid_resolution DOUBLE PRECISION NOT NULL DEFAULT 10,
    heatmap_data JSONB NOT NULL DEFAULT '{}',
    coverage_geometry GEOMETRY(MultiPolygon, 4326),
    coverage_percentage DOUBLE PRECISION NOT NULL DEFAULT 0,
    generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_coverage_maps_project ON coverage_maps(project_id);
CREATE INDEX idx_coverage_maps_geometry ON coverage_maps USING GIST(coverage_geometry);

-- Conflicts
CREATE TABLE conflicts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    asset_id UUID REFERENCES assets(id) ON DELETE CASCADE,
    entity_type VARCHAR(50) NOT NULL,
    entity_id UUID NOT NULL,
    submission_a JSONB NOT NULL,
    submission_b JSONB NOT NULL,
    submitted_by_a UUID NOT NULL REFERENCES users(id),
    submitted_by_b UUID NOT NULL REFERENCES users(id),
    resolution JSONB,
    resolved_by UUID REFERENCES users(id),
    resolved_at TIMESTAMPTZ,
    status VARCHAR(20) NOT NULL DEFAULT 'open',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_conflicts_project ON conflicts(project_id);
CREATE INDEX idx_conflicts_status ON conflicts(status);

-- Sync queue
CREATE TABLE sync_queue (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id),
    device_id VARCHAR(255) NOT NULL,
    entity_type VARCHAR(50) NOT NULL,
    entity_id UUID NOT NULL,
    client_id VARCHAR(255) NOT NULL,
    operation VARCHAR(10) NOT NULL,
    payload JSONB NOT NULL,
    status sync_status NOT NULL DEFAULT 'pending',
    retry_count INTEGER NOT NULL DEFAULT 0,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    synced_at TIMESTAMPTZ
);

CREATE INDEX idx_sync_queue_user ON sync_queue(user_id);
CREATE INDEX idx_sync_queue_status ON sync_queue(status);
CREATE INDEX idx_sync_queue_client_id ON sync_queue(client_id);

-- Notifications
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type notification_type NOT NULL,
    title VARCHAR(255) NOT NULL,
    body TEXT NOT NULL,
    data JSONB NOT NULL DEFAULT '{}',
    is_read BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notifications_user ON notifications(user_id);
CREATE INDEX idx_notifications_unread ON notifications(user_id, is_read) WHERE is_read = false;

-- Audit logs
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    action audit_action NOT NULL,
    entity_type VARCHAR(50),
    entity_id UUID,
    details JSONB NOT NULL DEFAULT '{}',
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_logs_user ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);
CREATE INDEX idx_audit_logs_created ON audit_logs(created_at);

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_users_updated BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER tr_projects_updated BEFORE UPDATE ON projects FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER tr_assets_updated BEFORE UPDATE ON assets FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER tr_anchors_updated BEFORE UPDATE ON anchors FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER tr_point_clouds_updated BEFORE UPDATE ON point_clouds FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER tr_meshes_updated BEFORE UPDATE ON meshes FOR EACH ROW EXECUTE FUNCTION update_updated_at();
