-- Sprint 1: Geohash coarse filter for two-phase identity resolve
ALTER TABLE asset_observations ADD COLUMN IF NOT EXISTS geohash VARCHAR(12);

CREATE INDEX IF NOT EXISTS idx_asset_observations_project_geohash
  ON asset_observations(project_id, geohash);

COMMENT ON COLUMN asset_observations.geohash IS 'Geohash precision-7 bucket for coarse geo pre-filter before ST_DWithin';
