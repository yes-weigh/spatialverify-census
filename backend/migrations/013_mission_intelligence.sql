-- Mission Intelligence — auto-aligned hypotheses from officer satellite map.

ALTER TABLE layout_georef_sessions
  ADD COLUMN IF NOT EXISTS mission_intelligence JSONB,
  ADD COLUMN IF NOT EXISTS alignment_quality_percent INTEGER;
