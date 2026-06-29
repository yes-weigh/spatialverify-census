/**
 * Identity accuracy evaluation harness.
 *
 * Creates controlled asset pairs (hard negatives) and measures:
 *   - SAME_ASSET recall/precision
 *   - POSSIBLE_MATCH precision
 *   - NEW_ASSET precision
 *   - False match rate
 *
 * Usage:
 *   npm run eval:identity-accuracy
 *
 * Env:
 *   EVAL_ASSET_PAIRS=50        pairs of similar nearby assets
 *   EVAL_VARIANTS_PER_ASSET=4  angle/lighting/distance/device variants
 */

import { pool } from '../src/db/pool.js';
import { spatialIdentityService } from '../src/services/identity/spatial-identity.service.js';
import { EMBEDDING_DIMENSION, type IdentityVerdict } from '../src/types/identity.js';
import { writeFileSync, mkdirSync } from 'fs';
import { resolve } from 'path';

const PAIR_COUNT = parseInt(process.env.EVAL_ASSET_PAIRS ?? '50', 10);
const CENTER_LAT = parseFloat(process.env.CENTER_LAT ?? '10.14520');
const CENTER_LNG = parseFloat(process.env.CENTER_LNG ?? '76.32110');
const OUTPUT_DIR = process.env.BENCH_OUTPUT ?? resolve(process.cwd(), 'benchmark-results');

interface EvalCase {
  label: string;
  expected: IdentityVerdict;
  assetId?: string;
  embedding: number[];
  lat: number;
  lng: number;
}

interface EvalMetrics {
  timestamp: string;
  totalCases: number;
  byVerdict: Record<string, { tp: number; fp: number; fn: number; precision: number; recall: number }>;
  falseMatchRate: number;
  cases: Array<{ label: string; expected: string; actual: string; confidence: number; correct: boolean }>;
}

function baseEmbedding(seed: number): number[] {
  const v = Array.from({ length: EMBEDDING_DIMENSION }, (_, i) => Math.sin(seed * 1000 + i * 0.01));
  const norm = Math.sqrt(v.reduce((s, x) => s + x * x, 0)) || 1;
  return v.map((x) => x / norm);
}

function perturbEmbedding(base: number[], noise = 0.05): number[] {
  const v = base.map((x) => x + (Math.random() - 0.5) * noise);
  const norm = Math.sqrt(v.reduce((s, x) => s + x * x, 0)) || 1;
  return v.map((x) => x / norm);
}

function unrelatedEmbedding(seed: number): number[] {
  return baseEmbedding(seed + 9999);
}

async function ensureEvalProject(): Promise<string> {
  const { rows: existing } = await pool.query(
    `SELECT id FROM projects WHERE name = 'Identity Eval Project' LIMIT 1`
  );
  if (existing[0]) return existing[0].id as string;

  const { rows: admin } = await pool.query(`SELECT id FROM users WHERE role = 'admin' LIMIT 1`);
  if (!admin[0]) throw new Error('Run npm run seed first');

  const { rows } = await pool.query(
    `INSERT INTO projects (name, description, survey_rules, created_by)
     VALUES ('Identity Eval Project', 'Controlled accuracy evaluation dataset',
             '{"min_confidence": 0.6}'::jsonb, $1) RETURNING id`,
    [admin[0].id]
  );
  return rows[0].id as string;
}

async function createHardNegativePairs(projectId: string): Promise<EvalCase[]> {
  const cases: EvalCase[] = [];
  const storedEmbeddings: Map<string, number[]> = new Map();

  for (let i = 0; i < PAIR_COUNT; i++) {
    const baseLat = CENTER_LAT + i * 0.002;
    const baseLng = CENTER_LNG;

    // Asset A
    const embA = baseEmbedding(i * 2);
    const { rows: assetA } = await pool.query(
      `INSERT INTO assets (project_id, name, status, location)
       VALUES ($1, $2, 'verified', ST_SetSRID(ST_MakePoint($4, $3), 4326))
       RETURNING id`,
      [projectId, `eval-house-a-${i}`, baseLat, baseLng]
    );
    const assetAId = assetA[0].id as string;
    storedEmbeddings.set(assetAId, embA);

    await spatialIdentityService.storeObservation({
      projectId,
      assetId: assetAId,
      embedding: embA,
      latitude: baseLat,
      longitude: baseLng,
      categoryLabel: 'house',
      viewType: 'front',
      accuracy: 3,
    });

    // Asset B — hard negative, 10m north
    const embB = baseEmbedding(i * 2 + 1);
    const latB = baseLat + 0.00009;
    const { rows: assetB } = await pool.query(
      `INSERT INTO assets (project_id, name, status, location)
       VALUES ($1, $2, 'verified', ST_SetSRID(ST_MakePoint($4, $3), 4326))
       RETURNING id`,
      [projectId, `eval-house-b-${i}`, latB, baseLng]
    );
    const assetBId = assetB[0].id as string;

    await spatialIdentityService.storeObservation({
      projectId,
      assetId: assetBId,
      embedding: embB,
      latitude: latB,
      longitude: baseLng,
      categoryLabel: 'house',
      viewType: 'front',
      accuracy: 3,
    });

    // Positive variants for asset A
    cases.push({
      label: `pair-${i}-same-angle`,
      expected: 'same_asset',
      assetId: assetAId,
      embedding: perturbEmbedding(embA, 0.02),
      lat: baseLat,
      lng: baseLng,
    });
    cases.push({
      label: `pair-${i}-same-different-angle`,
      expected: 'same_asset',
      assetId: assetAId,
      embedding: perturbEmbedding(embA, 0.08),
      lat: baseLat + 0.00001,
      lng: baseLng + 0.00001,
    });
    cases.push({
      label: `pair-${i}-same-different-lighting`,
      expected: 'same_asset',
      assetId: assetAId,
      embedding: perturbEmbedding(embA, 0.12),
      lat: baseLat,
      lng: baseLng,
    });

    // Hard negative — query near B should NOT match A
    cases.push({
      label: `pair-${i}-negative-near-b`,
      expected: 'new_asset',
      embedding: perturbEmbedding(embB, 0.03),
      lat: latB,
      lng: baseLng,
    });

    // Unrelated asset far away
    cases.push({
      label: `pair-${i}-unrelated`,
      expected: 'new_asset',
      embedding: unrelatedEmbedding(i),
      lat: baseLat + 0.01,
      lng: baseLng + 0.01,
    });
  }

  // Wait briefly for async fingerprint jobs if worker running
  await new Promise((r) => setTimeout(r, 2000));

  return cases;
}

function computeMetrics(results: EvalMetrics['cases']): EvalMetrics {
  const byExpected: Record<string, { tp: number; fp: number; fn: number }> = {
    same_asset: { tp: 0, fp: 0, fn: 0 },
    possible_match: { tp: 0, fp: 0, fn: 0 },
    new_asset: { tp: 0, fp: 0, fn: 0 },
  };

  let falseMatches = 0;

  for (const r of results) {
    const expected = r.expected;
    const actual = r.actual;

    if (expected === 'same_asset') {
      if (actual === 'same_asset') byExpected.same_asset.tp++;
      else if (actual === 'possible_match') byExpected.same_asset.fn++;
      else byExpected.same_asset.fn++;
    }

    if (expected === 'new_asset') {
      if (actual === 'new_asset') byExpected.new_asset.tp++;
      else {
        byExpected.new_asset.fn++;
        falseMatches++;
      }
    }

    if (actual === 'same_asset' && expected !== 'same_asset') {
      byExpected.same_asset.fp++;
    }
  }

  const byVerdict: EvalMetrics['byVerdict'] = {};
  for (const [verdict, counts] of Object.entries(byExpected)) {
    const precision = counts.tp + counts.fp > 0 ? counts.tp / (counts.tp + counts.fp) : 0;
    const recall = counts.tp + counts.fn > 0 ? counts.tp / (counts.tp + counts.fn) : 0;
    byVerdict[verdict] = { ...counts, precision, recall };
  }

  const totalNegatives = results.filter((r) => r.expected === 'new_asset').length;
  const falseMatchRate = totalNegatives > 0 ? falseMatches / totalNegatives : 0;

  return {
    timestamp: new Date().toISOString(),
    totalCases: results.length,
    byVerdict,
    falseMatchRate,
    cases: results,
  };
}

async function main() {
  console.log('=== Identity Accuracy Evaluation ===\n');
  const projectId = await ensureEvalProject();
  console.log(`Creating ${PAIR_COUNT} hard-negative pairs...`);

  const cases = await createHardNegativePairs(projectId);
  const results: EvalMetrics['cases'] = [];

  for (const c of cases) {
    const result = await spatialIdentityService.resolveIdentity({
      projectId,
      categoryLabel: 'house',
      latitude: c.lat,
      longitude: c.lng,
      embedding: c.embedding,
      accuracy: 3,
      viewType: 'front',
    });

    const correct = result.verdict === c.expected ||
      (c.expected === 'same_asset' && result.verdict === 'possible_match' && result.matchedAssetId === c.assetId);

    results.push({
      label: c.label,
      expected: c.expected,
      actual: result.verdict,
      confidence: result.finalConfidence,
      correct,
    });
  }

  const metrics = computeMetrics(results);

  console.log('\n=== Results ===');
  console.log(`Total cases: ${metrics.totalCases}`);
  console.log(`SAME_ASSET    precision: ${(metrics.byVerdict.same_asset.precision * 100).toFixed(1)}%  recall: ${(metrics.byVerdict.same_asset.recall * 100).toFixed(1)}%`);
  console.log(`NEW_ASSET     precision: ${(metrics.byVerdict.new_asset.precision * 100).toFixed(1)}%  recall: ${(metrics.byVerdict.new_asset.recall * 100).toFixed(1)}%`);
  console.log(`False match rate: ${(metrics.falseMatchRate * 100).toFixed(1)}%`);

  const incorrect = results.filter((r) => !r.correct);
  if (incorrect.length > 0) {
    console.log(`\n⚠ ${incorrect.length} incorrect cases (first 10):`);
    for (const r of incorrect.slice(0, 10)) {
      console.log(`  ${r.label}: expected=${r.expected} actual=${r.actual} conf=${r.confidence.toFixed(2)}`);
    }
  }

  mkdirSync(OUTPUT_DIR, { recursive: true });
  const outFile = resolve(OUTPUT_DIR, `accuracy-eval-${Date.now()}.json`);
  writeFileSync(outFile, JSON.stringify(metrics, null, 2));
  console.log(`\nReport saved: ${outFile}`);

  await pool.end();
}

main().catch((err) => {
  console.error('Evaluation failed:', err);
  process.exit(1);
});
