-- Silent travel-time learning between buildings (ETA + route recovery)

CREATE TABLE mission_travel_segments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  eb_id UUID NOT NULL REFERENCES enumeration_blocks(id) ON DELETE CASCADE,
  from_building_id UUID REFERENCES mission_buildings(id) ON DELETE SET NULL,
  to_building_id UUID NOT NULL REFERENCES mission_buildings(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  travel_seconds INTEGER NOT NULL CHECK (travel_seconds >= 0),
  distance_meters DOUBLE PRECISION,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_travel_segments_eb ON mission_travel_segments(eb_id);
CREATE INDEX idx_travel_segments_recorded ON mission_travel_segments(recorded_at);
