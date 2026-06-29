import { describe, it, expect } from 'vitest';
import {
  gpsSimilarityScore,
  gpsAccuracyConfidence,
  gpsClusterScore,
  effectiveGpsScore,
  headingSimilarityScore,
  headingProfileScore,
  categorySimilarityScore,
  embeddingSimilarityScore,
  computeFinalConfidence,
  determineVerdict,
  cosineSimilarity,
  computeVisualDrift,
  interpretDrift,
  buildExplanationSummary,
} from '../services/identity/similarity.js';
import { FingerprintService } from '../services/identity/fingerprint.service.js';

describe('Spatial Identity similarity engine', () => {
  it('gpsSimilarityScore is 1 at zero distance', () => {
    expect(gpsSimilarityScore(0)).toBe(1);
  });

  it('gpsSimilarityScore uses inverse decay curve', () => {
    expect(gpsSimilarityScore(5)).toBeCloseTo(1 / (1 + 5 / 10), 5);
    expect(gpsSimilarityScore(10)).toBeCloseTo(0.5, 5);
    expect(gpsSimilarityScore(20)).toBeCloseTo(1 / 3, 5);
  });

  it('gpsSimilarityScore decays with distance', () => {
    expect(gpsSimilarityScore(15)).toBeLessThan(gpsSimilarityScore(5));
    expect(gpsSimilarityScore(100)).toBe(0);
  });

  it('gpsSimilarityScore supports field-realistic SAME_ASSET distances', () => {
    expect(gpsSimilarityScore(5)).toBeGreaterThan(0.55);
    expect(gpsSimilarityScore(8)).toBeGreaterThan(0.40);
  });

  it('gpsAccuracyConfidence weights high-accuracy fixes higher', () => {
    expect(gpsAccuracyConfidence(3)).toBe(1.0);
    expect(gpsAccuracyConfidence(18)).toBeLessThan(gpsAccuracyConfidence(3));
    expect(gpsAccuracyConfidence(null)).toBe(0.75);
  });

  it('gpsClusterScore returns high score inside cluster', () => {
    const cluster = { centroid_lat: 10, centroid_lng: 76, variance_m2: 4, radius_m: 6.4, observation_count: 4 };
    const result = gpsClusterScore(2, cluster, 3);
    expect(result.insideCluster).toBe(true);
    expect(result.score).toBeGreaterThan(0.8);
  });

  it('effectiveGpsScore uses cluster when available', () => {
    const cluster = { centroid_lat: 10, centroid_lng: 76, variance_m2: 4, radius_m: 6.4, observation_count: 4 };
    const result = effectiveGpsScore(20, 3, cluster, 2);
    expect(result.insideCluster).toBe(true);
    expect(result.score).toBeGreaterThan(0.7);
  });

  it('headingSimilarityScore handles opposite headings', () => {
    expect(headingSimilarityScore(0, 180)).toBe(0);
    expect(headingSimilarityScore(90, 90)).toBe(1);
  });

  it('headingProfileScore uses profile mean', () => {
    expect(headingProfileScore(90, 90, 10)).toBeCloseTo(1, 1);
    expect(headingProfileScore(0, 90, 10)).toBeLessThanOrEqual(0.5);
  });

  it('headingSimilarityScore returns neutral when missing', () => {
    expect(headingSimilarityScore(null, 90)).toBe(0.5);
  });

  it('categorySimilarityScore exact match', () => {
    expect(categorySimilarityScore('fire_hydrant', 'fire_hydrant')).toBe(1);
  });

  it('categorySimilarityScore grouped labels', () => {
    const groups = [['pole', 'utility_pole']];
    expect(categorySimilarityScore('pole', 'utility_pole', groups)).toBe(0.8);
  });

  it('embeddingSimilarityScore from cosine distance', () => {
    expect(embeddingSimilarityScore(0)).toBe(1);
    expect(embeddingSimilarityScore(1)).toBe(0);
  });

  it('computeFinalConfidence weighted sum', () => {
    const score = computeFinalConfidence({
      gps: 1,
      embedding: 1,
      category: 1,
      heading: 1,
    });
    expect(score).toBeCloseTo(1);
  });

  it('determineVerdict SAME_ASSET threshold', () => {
    const verdict = determineVerdict(
      { gps: 0.9, embedding: 0.85, category: 1, heading: 0.8 },
      0.9
    );
    expect(verdict).toBe('same_asset');
  });

  it('determineVerdict POSSIBLE_MATCH threshold', () => {
    const verdict = determineVerdict(
      { gps: 0.6, embedding: 0.7, category: 0.8, heading: 0.5 },
      0.65
    );
    expect(verdict).toBe('possible_match');
  });

  it('determineVerdict NEW_ASSET fallback', () => {
    const verdict = determineVerdict(
      { gps: 0.1, embedding: 0.2, category: 0, heading: 0.5 },
      0.2
    );
    expect(verdict).toBe('new_asset');
  });

  it('cosineSimilarity identical vectors', () => {
    const v = Array.from({ length: 1280 }, (_, i) => Math.sin(i));
    expect(cosineSimilarity(v, v)).toBeCloseTo(1, 5);
  });

  it('computeVisualDrift is zero for identical embeddings', () => {
    const emb = [1, 0, 0, 0];
    expect(computeVisualDrift([emb, emb])).toBe(0);
  });

  it('interpretDrift classifies drift levels', () => {
    expect(interpretDrift(0.05)).toBe('stable');
    expect(interpretDrift(0.25)).toBe('moderate_change');
    expect(interpretDrift(0.5)).toBe('significant_change');
  });

  it('buildExplanationSummary includes cluster and view info', () => {
    const summary = buildExplanationSummary(
      { gps: 0.9, embedding: 0.85, category: 1, heading: 0.8 },
      { insideCluster: true, bestView: 'front' }
    );
    expect(summary).toContain('strong visual match');
    expect(summary).toContain('inside GPS cluster');
    expect(summary).toContain('front');
  });
});

describe('V2 view-aware fingerprint matching', () => {
  const service = new FingerprintService();

  it('groups observations by asset and picks best embedding score', () => {
    const rows = [
      {
        observation_id: 'obs-1',
        asset_id: 'asset-a',
        asset_name: 'House A',
        category_label: 'house',
        view_type: 'front' as const,
        heading: 90,
        captured_at: '2027-01-01T00:00:00Z',
        accuracy: 3,
        cosine_distance: 0.08,
        distance_meters: 2,
        distance_to_centroid_m: 2,
        gps_variance_m2: 4,
        gps_radius_m: 6,
        observation_count: 3,
        heading_mean: 90,
        heading_variance: 0,
        visual_drift_score: null,
        last_observation_at: '2027-01-01T00:00:00Z',
      },
      {
        observation_id: 'obs-2',
        asset_id: 'asset-a',
        asset_name: 'House A',
        category_label: 'house',
        view_type: 'left' as const,
        heading: 90,
        captured_at: '2027-01-02T00:00:00Z',
        accuracy: 3,
        cosine_distance: 0.19,
        distance_meters: 3,
        distance_to_centroid_m: 3,
        gps_variance_m2: 4,
        gps_radius_m: 6,
        observation_count: 3,
        heading_mean: 90,
        heading_variance: null,
        visual_drift_score: null,
        last_observation_at: '2027-01-02T00:00:00Z',
      },
      {
        observation_id: 'obs-3',
        asset_id: 'asset-b',
        asset_name: 'House B',
        category_label: 'house',
        view_type: 'front' as const,
        heading: 90,
        captured_at: '2027-01-01T00:00:00Z',
        accuracy: 3,
        cosine_distance: 0.29,
        distance_meters: 4,
        distance_to_centroid_m: 4,
        gps_variance_m2: 4,
        gps_radius_m: 6,
        observation_count: 2,
        heading_mean: 90,
        heading_variance: null,
        visual_drift_score: null,
        last_observation_at: '2027-01-01T00:00:00Z',
      },
    ];

    const candidates = service.buildCandidatesFromObservations(
      rows,
      'house',
      90,
      3,
      []
    );

    expect(candidates).toHaveLength(2);
    expect(candidates[0].asset_id).toBe('asset-a');
    expect(candidates[0].embedding_score).toBeCloseTo(0.92, 2);
    expect(candidates[0].view_scores).toHaveLength(2);
    expect(candidates[0].best_view_type).toBe('front');
    expect(candidates[0].final_confidence).toBeGreaterThan(candidates[1].final_confidence);
  });
});
