-- Satellite image registration fields (officer map overlay alignment).

ALTER TABLE layout_georef_sessions
  ADD COLUMN IF NOT EXISTS alignment_mode VARCHAR(30) DEFAULT 'satellite_registration',
  ADD COLUMN IF NOT EXISTS image_bounds JSONB,
  ADD COLUMN IF NOT EXISTS image_transform JSONB,
  ADD COLUMN IF NOT EXISTS potential_structures JSONB NOT NULL DEFAULT '[]',
  ADD COLUMN IF NOT EXISTS gps_boundary JSONB NOT NULL DEFAULT '[]';
