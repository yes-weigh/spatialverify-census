import { pool } from '../src/db/pool.js';
import { observationRepository } from '../src/repositories/observation.repository.js';
import { EMBEDDING_DIMENSION, IDENTITY_THRESHOLDS } from '../src/types/identity.js';
import { encodeGeohash, geohashSearchCells } from '../src/utils/geohash.js';
import { writeFileSync, mkdirSync } from 'fs';
import { resolve } from 'path';

const RUNS = parseInt(process.env.BENCH_RUNS ?? '20', 10);
const CENTER_LAT = parseFloat(process.env.CENTER_LAT ?? '10.14520');
const CENTER_LNG = parseFloat(process.env.CENTER_LNG ?? '76.32110');
const OUTPUT_DIR = process.env.BENCH_OUTPUT ?? resolve(process.cwd(), 'benchmark-results');

interface BenchReport {
  timestamp: string;
  observationCount: number;
  assetCount: number;
  storage: Record<string, unknown>;
  latencyMs: { runs: number; p50: number; p95: number; p99: number; max: number };
  candidateStats: {
    geoInRadius: { min: number; max: number; avg: number; p95: number };
    geoCandidatesUsed: { min: number; max: number; avg: number };
    vectorCandidatesReturned: { min: number; max: number; avg: number };
  };
  explainPlan: string[];
  explainFlags: string[];
}

function randomEmbedding(): number[] {
  const v = Array.from({ length: EMBEDDING_DIMENSION }, () => Math.random() * 2 - 1);
  const norm = Math.sqrt(v.reduce((sum, x) => sum + x * x, 0)) || 1;
  return v.map((x) => x / norm);
}

function formatVector(embedding: number[]): string {
  return `[${embedding.join(',')}]`;
}

function percentile(values: number[], p: number): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const idx = Math.ceil((p / 100) * sorted.length) - 1;
  return sorted[Math.max(0, idx)];
}

function avg(values: number[]): number {
  return values.length ? values.reduce((a, b) => a + b, 0) / values.length : 0;
}

async function getLoadTestProjectId(): Promise<string | null> {
  const { rows } = await pool.query(
    `SELECT id FROM projects WHERE name = 'Load Test Project' LIMIT 1`
  );
  return (rows[0]?.id as string) ?? null;
}

async function countGeoInRadius(
  projectId: string,
  lat: number,
  lng: number,
  geohashCells: string[]
): Promise<number> {
  const { rows } = await pool.query<{ count: string }>(
    `SELECT COUNT(*)::text AS count
     FROM asset_observations ao
     WHERE ao.project_id = $1
       AND ao.asset_id IS NOT NULL
       AND ao.geohash = ANY($2::text[])
       AND ST_DWithin(
         ao.location::geography,
         ST_SetSRID(ST_MakePoint($4, $3), 4326)::geography,
         $5
       )`,
    [projectId, geohashCells, lat, lng, IDENTITY_THRESHOLDS.searchRadiusMeters]
  );
  return parseInt(rows[0].count, 10);
}

async function runExplain(projectId: string, vector: string): Promise<{ lines: string[]; flags: string[] }> {
  const geohashCells = geohashSearchCells(CENTER_LAT, CENTER_LNG, IDENTITY_THRESHOLDS.geohashPrecision);

  const { rows } = await pool.query(
    `EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
     WITH geo_candidates AS (
       SELECT
         ao.id,
         ao.asset_id,
         ao.embedding,
         ST_Distance(
           ao.location::geography,
           ST_SetSRID(ST_MakePoint($3, $4), 4326)::geography
         )::float AS distance_meters
       FROM asset_observations ao
       WHERE ao.project_id = $1
         AND ao.asset_id IS NOT NULL
         AND ao.geohash = ANY($5::text[])
         AND ST_DWithin(
           ao.location::geography,
           ST_SetSRID(ST_MakePoint($3, $4), 4326)::geography,
           $6
         )
       ORDER BY distance_meters ASC
       LIMIT $7
     ),
     ranked AS (
       SELECT gc.*, (gc.embedding <=> $2::vector)::float AS cosine_distance
       FROM geo_candidates gc
       ORDER BY gc.embedding <=> $2::vector
       LIMIT $8
     )
     SELECT COUNT(*) FROM ranked`,
    [
      projectId,
      vector,
      CENTER_LNG,
      CENTER_LAT,
      geohashCells,
      IDENTITY_THRESHOLDS.searchRadiusMeters,
      IDENTITY_THRESHOLDS.geoCandidateLimit,
      IDENTITY_THRESHOLDS.observationSearchLimit,
    ]
  );

  const lines = rows.map((row) => String(row['QUERY PLAN']));
  const joined = lines.join('\n');
  const flags: string[] = [];
  if (/Seq Scan/i.test(joined)) flags.push('SEQ_SCAN');
  if (/Bitmap Heap Scan/i.test(joined)) flags.push('BITMAP_HEAP_SCAN');
  if (/Sort/i.test(joined) && !/Index Scan/i.test(joined)) flags.push('SORT');
  if (/Materialize/i.test(joined)) flags.push('MATERIALIZE');
  if (/Nested Loop/i.test(joined)) flags.push('NESTED_LOOP');

  return { lines, flags };
}

async function runTimedSearch(projectId: string) {
  const latencies: number[] = [];
  const geoInRadiusCounts: number[] = [];
  const geoUsedCounts: number[] = [];
  const vectorReturnedCounts: number[] = [];

  for (let i = 0; i < RUNS; i++) {
    const lat = CENTER_LAT + (Math.random() - 0.5) * 0.001;
    const lng = CENTER_LNG + (Math.random() - 0.5) * 0.001;
    const geohashCells = geohashSearchCells(lat, lng, IDENTITY_THRESHOLDS.geohashPrecision);
    const embedding = randomEmbedding();

    const geoInRadius = await countGeoInRadius(projectId, lat, lng, geohashCells);
    geoInRadiusCounts.push(geoInRadius);

    const start = performance.now();
    const results = await observationRepository.searchObservations(
      projectId,
      embedding,
      IDENTITY_THRESHOLDS.observationSearchLimit,
      IDENTITY_THRESHOLDS.searchRadiusMeters,
      lat,
      lng
    );
    latencies.push(performance.now() - start);

    const geoUsed = Math.min(geoInRadius, IDENTITY_THRESHOLDS.geoCandidateLimit);
    geoUsedCounts.push(geoUsed);
    vectorReturnedCounts.push(results.length);
  }

  return {
    latencies,
    geoInRadiusCounts,
    geoUsedCounts,
    vectorReturnedCounts,
  };
}

async function printStorageStats() {
  const { rows } = await pool.query(`
    SELECT
      pg_size_pretty(pg_total_relation_size('asset_observations')) AS observations_total,
      pg_size_pretty(pg_relation_size('asset_observations')) AS observations_heap,
      pg_size_pretty(pg_indexes_size('asset_observations')) AS observations_indexes,
      pg_total_relation_size('asset_observations') AS observations_total_bytes,
      (SELECT COUNT(*)::bigint FROM asset_observations) AS observation_count,
      (SELECT COUNT(*)::bigint FROM assets) AS asset_count
  `);
  return rows[0];
}

async function main() {
  const projectId = await getLoadTestProjectId();
  if (!projectId) {
    console.error('Load Test Project not found. Run: npm run loadtest:observations');
    process.exit(1);
  }

  const count = await observationRepository.countObservations(projectId);
  console.log(`\n=== Identity Resolve Benchmark ===`);
  console.log(`Observations: ${count.toLocaleString()}`);
  console.log(`Geo candidate cap: ${IDENTITY_THRESHOLDS.geoCandidateLimit}`);
  console.log(`Vector result limit: ${IDENTITY_THRESHOLDS.observationSearchLimit}`);
  console.log(`Search radius: ${IDENTITY_THRESHOLDS.searchRadiusMeters}m\n`);

  const storage = await printStorageStats();
  console.log('=== Storage ===');
  console.log(storage);

  const vector = formatVector(randomEmbedding());
  console.log('\n=== EXPLAIN ANALYZE (two-phase resolve) ===\n');
  const explain = await runExplain(projectId, vector);
  for (const line of explain.lines) console.log(line);
  if (explain.flags.length > 0) {
    console.log(`\n⚠ Plan flags: ${explain.flags.join(', ')}`);
  } else {
    console.log('\n✓ No red-flag scan patterns detected');
  }

  console.log('\n=== Timed resolve search ===');
  const timed = await runTimedSearch(projectId);

  const report: BenchReport = {
    timestamp: new Date().toISOString(),
    observationCount: count,
    assetCount: parseInt(String(storage.asset_count), 10),
    storage,
    latencyMs: {
      runs: RUNS,
      p50: percentile(timed.latencies, 50),
      p95: percentile(timed.latencies, 95),
      p99: percentile(timed.latencies, 99),
      max: Math.max(...timed.latencies),
    },
    candidateStats: {
      geoInRadius: {
        min: Math.min(...timed.geoInRadiusCounts),
        max: Math.max(...timed.geoInRadiusCounts),
        avg: avg(timed.geoInRadiusCounts),
        p95: percentile(timed.geoInRadiusCounts, 95),
      },
      geoCandidatesUsed: {
        min: Math.min(...timed.geoUsedCounts),
        max: Math.max(...timed.geoUsedCounts),
        avg: avg(timed.geoUsedCounts),
      },
      vectorCandidatesReturned: {
        min: Math.min(...timed.vectorReturnedCounts),
        max: Math.max(...timed.vectorReturnedCounts),
        avg: avg(timed.vectorReturnedCounts),
      },
    },
    explainPlan: explain.lines,
    explainFlags: explain.flags,
  };

  console.log(`Runs: ${RUNS}`);
  console.log(`p50:  ${report.latencyMs.p50.toFixed(1)} ms`);
  console.log(`p95:  ${report.latencyMs.p95.toFixed(1)} ms`);
  console.log(`p99:  ${report.latencyMs.p99.toFixed(1)} ms`);
  console.log(`max:  ${report.latencyMs.max.toFixed(1)} ms`);

  console.log('\n=== Candidate counts ===');
  console.log(`Geo in 50m radius (raw):  min=${report.candidateStats.geoInRadius.min} max=${report.candidateStats.geoInRadius.max} avg=${report.candidateStats.geoInRadius.avg.toFixed(1)} p95=${report.candidateStats.geoInRadius.p95}`);
  console.log(`Geo candidates used (capped): min=${report.candidateStats.geoCandidatesUsed.min} max=${report.candidateStats.geoCandidatesUsed.max} avg=${report.candidateStats.geoCandidatesUsed.avg.toFixed(1)}`);
  console.log(`Vector results returned:    min=${report.candidateStats.vectorCandidatesReturned.min} max=${report.candidateStats.vectorCandidatesReturned.max} avg=${report.candidateStats.vectorCandidatesReturned.avg.toFixed(1)}`);

  const cappedPct = timed.geoInRadiusCounts.filter((c) => c > IDENTITY_THRESHOLDS.geoCandidateLimit).length;
  if (cappedPct > 0) {
    console.log(`\n⚠ ${cappedPct}/${RUNS} queries hit geo cap (${IDENTITY_THRESHOLDS.geoCandidateLimit}) — adaptive budget may be needed in dense areas`);
  }

  mkdirSync(OUTPUT_DIR, { recursive: true });
  const outFile = resolve(OUTPUT_DIR, `bench-${count}-obs-${Date.now()}.json`);
  writeFileSync(outFile, JSON.stringify(report, null, 2));
  console.log(`\nReport saved: ${outFile}`);

  await pool.end();
}

main().catch((err) => {
  console.error('Benchmark failed:', err);
  process.exit(1);
});
