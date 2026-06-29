-- Two-phase identity resolve EXPLAIN (Sprint 1)
-- Usage: psql $DATABASE_URL -f scripts/explain-identity-resolve.sql
-- Replace placeholders before running against load test data.

\set project_id '00000000-0000-0000-0000-000000000001'
\set query_lat 10.14520
\set query_lng 76.32110
\set geo_limit 500
\set vector_limit 30
\set radius_m 50

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
WITH geo_candidates AS (
  SELECT
    ao.id,
    ao.asset_id,
    ao.embedding,
    ST_Distance(
      ao.location::geography,
      ST_SetSRID(ST_MakePoint(:query_lng, :query_lat), 4326)::geography
    )::float AS distance_meters
  FROM asset_observations ao
  WHERE ao.project_id = :'project_id'
    AND ao.asset_id IS NOT NULL
    AND ao.geohash IS NOT NULL
    AND ST_DWithin(
      ao.location::geography,
      ST_SetSRID(ST_MakePoint(:query_lng, :query_lat), 4326)::geography,
      :radius_m
    )
  ORDER BY distance_meters ASC
  LIMIT :geo_limit
),
ranked AS (
  SELECT
    gc.*,
    (gc.embedding <=> (SELECT embedding FROM asset_observations WHERE asset_id IS NOT NULL LIMIT 1))::float AS cosine_distance
  FROM geo_candidates gc
  ORDER BY gc.embedding <=> (SELECT embedding FROM asset_observations WHERE asset_id IS NOT NULL LIMIT 1)
  LIMIT :vector_limit
)
SELECT COUNT(*) FROM ranked;

SELECT
  pg_size_pretty(pg_total_relation_size('asset_observations')) AS observations_total,
  pg_size_pretty(pg_indexes_size('asset_observations')) AS observations_indexes,
  (SELECT COUNT(*) FROM asset_observations) AS observation_count;
