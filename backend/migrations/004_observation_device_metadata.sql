-- V2.1: Device capture metadata for embedding bias compensation
ALTER TABLE asset_observations ADD COLUMN IF NOT EXISTS device_model VARCHAR(100);
ALTER TABLE asset_observations ADD COLUMN IF NOT EXISTS camera_fov DOUBLE PRECISION;
ALTER TABLE asset_observations ADD COLUMN IF NOT EXISTS camera_resolution VARCHAR(20);

CREATE INDEX IF NOT EXISTS idx_asset_observations_device ON asset_observations(device_model);

-- Scale recommendation: LIST partition by project_id once table exceeds ~5M rows.
-- Keep project_id B-tree + location GIST as separate indexes (already present).

COMMENT ON COLUMN asset_observations.device_model IS 'Capture device model e.g. Samsung SM-A546B';
COMMENT ON COLUMN asset_observations.camera_fov IS 'Horizontal field of view in degrees at capture time';
COMMENT ON COLUMN asset_observations.camera_resolution IS 'Preview/capture resolution e.g. 1920x1080';
