-- Digital twin storage on georef session.

ALTER TABLE layout_georef_sessions
  ADD COLUMN IF NOT EXISTS digital_twin JSONB;
