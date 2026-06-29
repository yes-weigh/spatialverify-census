import { pool } from '../src/db/pool.js';
import { observationRepository } from '../src/repositories/observation.repository.js';
import { EMBEDDING_DIMENSION, IDENTITY_THRESHOLDS } from '../src/types/identity.js';
import { encodeGeohash } from '../src/utils/geohash.js';

const OBS_COUNT = parseInt(process.env.OBS_COUNT ?? '1000000', 10);
const ASSET_COUNT = parseInt(process.env.ASSET_COUNT ?? '50000', 10);
const BATCH_SIZE = parseInt(process.env.BATCH_SIZE ?? '200', 10);
const CENTER_LAT = parseFloat(process.env.CENTER_LAT ?? '10.14520');
const CENTER_LNG = parseFloat(process.env.CENTER_LNG ?? '76.32110');

function randomEmbedding(): number[] {
  const v = Array.from({ length: EMBEDDING_DIMENSION }, () => Math.random() * 2 - 1);
  const norm = Math.sqrt(v.reduce((sum, x) => sum + x * x, 0)) || 1;
  return v.map((x) => x / norm);
}

function formatVector(embedding: number[]): string {
  return `[${embedding.join(',')}]`;
}

async function ensureLoadTestProject(): Promise<string> {
  const { rows: existing } = await pool.query(
    `SELECT id FROM projects WHERE name = 'Load Test Project' LIMIT 1`
  );
  if (existing[0]) return existing[0].id as string;

  const { rows: admin } = await pool.query(
    `SELECT id FROM users WHERE role = 'admin' LIMIT 1`
  );
  if (!admin[0]) throw new Error('No admin user found — run npm run seed first');

  const { rows } = await pool.query(
    `INSERT INTO projects (name, description, survey_rules, created_by)
     VALUES ('Load Test Project', 'Synthetic observations for identity resolve benchmarking',
             '{"min_confidence": 0.6}'::jsonb, $1)
     RETURNING id`,
    [admin[0].id]
  );
  return rows[0].id as string;
}

async function ensureAssets(projectId: string, count: number): Promise<string[]> {
  const { rows: existing } = await pool.query<{ id: string }>(
    `SELECT id FROM assets WHERE project_id = $1 AND name LIKE 'loadtest-asset-%'`,
    [projectId]
  );
  if (existing.length >= count) {
    return existing.slice(0, count).map((r) => r.id);
  }

  const assetIds: string[] = existing.map((r) => r.id);
  const toCreate = count - assetIds.length;
  const gridSize = Math.ceil(Math.sqrt(count));

  for (let i = 0; i < toCreate; i += BATCH_SIZE) {
    const batchEnd = Math.min(i + BATCH_SIZE, toCreate);
    const values: unknown[] = [];
    const placeholders: string[] = [];
    let param = 1;

    for (let j = i; j < batchEnd; j++) {
      const idx = assetIds.length + j;
      const row = Math.floor(idx / gridSize);
      const col = idx % gridSize;
      const lat = CENTER_LAT + (row - gridSize / 2) * 0.0003;
      const lng = CENTER_LNG + (col - gridSize / 2) * 0.0003;

      const base = param;
      placeholders.push(
        `($${base}, $${base + 1}, 'verified', ST_SetSRID(ST_MakePoint($${base + 3}, $${base + 2}), 4326), $${base + 4}, $${base + 5})`
      );
      values.push(projectId, `loadtest-asset-${idx}`, lat, lng, `loadtest-${idx}`, 1);
      param += 6;
    }

    const { rows } = await pool.query(
      `INSERT INTO assets (project_id, name, status, location, client_id, version)
       VALUES ${placeholders.join(', ')}
       RETURNING id`,
      values
    );
    assetIds.push(...rows.map((r: { id: string }) => r.id));
    process.stdout.write(`\rAssets created: ${assetIds.length}/${count}`);
  }

  console.log('');
  return assetIds;
}

async function insertObservations(
  projectId: string,
  assetIds: string[],
  count: number
): Promise<void> {
  const { rows: countRows } = await pool.query<{ c: string }>(
    `SELECT COUNT(*)::text AS c FROM asset_observations WHERE project_id = $1`,
    [projectId]
  );
  let inserted = parseInt(countRows[0].c, 10);
  if (inserted >= count) {
    console.log(`Already have ${inserted} observations for project — skipping insert`);
    return;
  }

  const viewTypes = ['front', 'left', 'right', 'rear', 'far', 'unknown'];
  const start = Date.now();

  while (inserted < count) {
    const batchCount = Math.min(BATCH_SIZE, count - inserted);
    const values: unknown[] = [];
    const placeholders: string[] = [];
    let param = 1;

    for (let i = 0; i < batchCount; i++) {
      const assetId = assetIds[(inserted + i) % assetIds.length];
      const assetIdx = (inserted + i) % assetIds.length;
      const gridSize = Math.ceil(Math.sqrt(assetIds.length));
      const row = Math.floor(assetIdx / gridSize);
      const col = assetIdx % gridSize;
      const lat = CENTER_LAT + (row - gridSize / 2) * 0.0003 + (Math.random() - 0.5) * 0.00005;
      const lng = CENTER_LNG + (col - gridSize / 2) * 0.0003 + (Math.random() - 0.5) * 0.00005;
      const geohash = encodeGeohash(lat, lng, IDENTITY_THRESHOLDS.geohashPrecision);
      const embedding = formatVector(randomEmbedding());
      const viewType = viewTypes[i % viewTypes.length];

      const base = param;
      placeholders.push(
        `($${base}, $${base + 1}, $${base + 2}, $${base + 3}, $${base + 4}, $${base + 5}, $${base + 6}::vector,
          $${base + 7}::view_type, $${base + 8}, ST_SetSRID(ST_MakePoint($${base + 3}, $${base + 2}), 4326), $${base + 9})`
      );
      values.push(
        projectId, assetId, lat, lng, 5 + Math.random() * 10,
        90 + Math.random() * 20, embedding, viewType, 'house', geohash
      );
      param += 10;
    }

    await pool.query(
      `INSERT INTO asset_observations (
        project_id, asset_id, latitude, longitude, accuracy, heading, embedding,
        view_type, category_label, location, geohash
      ) VALUES ${placeholders.join(', ')}`,
      values
    );

    inserted += batchCount;
    const elapsed = ((Date.now() - start) / 1000).toFixed(1);
    const rate = (inserted / (Date.now() - start) * 1000).toFixed(0);
    process.stdout.write(`\rObservations: ${inserted}/${count} (${rate}/s, ${elapsed}s)`);
  }

  console.log('');
}

async function main() {
  console.log(`Load test config: ${OBS_COUNT} observations, ${ASSET_COUNT} assets, batch ${BATCH_SIZE}`);
  console.log(`Center: ${CENTER_LAT}, ${CENTER_LNG}`);

  const projectId = await ensureLoadTestProject();
  console.log(`Project: ${projectId}`);

  const assetIds = await ensureAssets(projectId, ASSET_COUNT);
  await insertObservations(projectId, assetIds, OBS_COUNT);

  console.log('Backfilling geohash for any rows missing it...');
  let backfilled = 0;
  do {
    backfilled = await observationRepository.backfillGeohash(10000);
    if (backfilled > 0) process.stdout.write(`\rGeohash backfill: ${backfilled} rows`);
  } while (backfilled > 0);
  console.log('');

  const total = await observationRepository.countObservations(projectId);
  console.log(`Done. Project observation count: ${total}`);
  console.log('Run: npm run bench:identity');

  await pool.end();
}

main().catch((err) => {
  console.error('Load test failed:', err);
  process.exit(1);
});
