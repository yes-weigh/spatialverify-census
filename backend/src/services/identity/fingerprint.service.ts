import { observationRepository } from '../../repositories/observation.repository.js';
import {
  categorySimilarityScore,
  computeFinalConfidence,
  effectiveGpsScore,
  embeddingSimilarityScore,
  headingProfileScore,
  computeVisualDrift,
  interpretDrift,
} from './similarity.js';
import type {
  AssetFingerprint,
  GpsCluster,
  IdentityCandidate,
  TemporalDriftResult,
  ViewScore,
  ViewType,
} from '../../types/identity.js';

interface ObservationRow {
  observation_id: string;
  asset_id: string;
  asset_name: string;
  category_label: string | null;
  view_type: ViewType;
  heading: number | null;
  captured_at: string;
  accuracy: number | null;
  cosine_distance: number;
  distance_meters: number;
  distance_to_centroid_m: number | null;
  gps_variance_m2: number | null;
  gps_radius_m: number | null;
  observation_count: number | null;
  heading_mean: number | null;
  heading_variance: number | null;
  visual_drift_score: number | null;
  last_observation_at: string | null;
}

export class FingerprintService {
  /**
   * V2: Group top observations by asset, take best embedding score per asset.
   */
  buildCandidatesFromObservations(
    rows: ObservationRow[],
    queryCategory: string,
    queryHeading: number | undefined,
    queryAccuracy: number | undefined,
    categoryGroups: string[][]
  ): IdentityCandidate[] {
    const byAsset = new Map<string, {
      asset_name: string;
      category_label: string | null;
      view_scores: ViewScore[];
      best_embedding: number;
      best_view: ViewType | null;
      gps_cluster: GpsCluster | null;
      distance_to_centroid_m: number | null;
      heading_mean: number | null;
      heading_variance: number | null;
      visual_drift: number | null;
      last_seen_at: string | null;
      min_distance_m: number;
    }>();

    for (const row of rows) {
      const embScore = embeddingSimilarityScore(parseFloat(String(row.cosine_distance)));
      const assetId = row.asset_id as string;

      const viewScore: ViewScore = {
        view_type: row.view_type as ViewType,
        embedding_score: embScore,
        observation_id: row.observation_id as string,
        captured_at: row.captured_at as string,
      };

      const cluster: GpsCluster | null = row.gps_radius_m != null ? {
        centroid_lat: 0,
        centroid_lng: 0,
        variance_m2: parseFloat(String(row.gps_variance_m2 ?? 0)),
        radius_m: parseFloat(String(row.gps_radius_m ?? 0)),
        observation_count: (row.observation_count as number) ?? 0,
      } : null;

      const existing = byAsset.get(assetId);
      if (!existing) {
        byAsset.set(assetId, {
          asset_name: row.asset_name as string,
          category_label: row.category_label as string | null,
          view_scores: [viewScore],
          best_embedding: embScore,
          best_view: row.view_type as ViewType,
          gps_cluster: cluster,
          distance_to_centroid_m: row.distance_to_centroid_m != null
            ? parseFloat(String(row.distance_to_centroid_m))
            : parseFloat(String(row.distance_meters)),
          heading_mean: row.heading_mean != null ? parseFloat(String(row.heading_mean)) : null,
          heading_variance: row.heading_variance != null ? parseFloat(String(row.heading_variance)) : null,
          visual_drift: row.visual_drift_score != null ? parseFloat(String(row.visual_drift_score)) : null,
          last_seen_at: row.last_observation_at as string | null,
          min_distance_m: parseFloat(String(row.distance_meters)),
        });
      } else {
        existing.view_scores.push(viewScore);
        if (embScore > existing.best_embedding) {
          existing.best_embedding = embScore;
          existing.best_view = row.view_type as ViewType;
        }
        existing.min_distance_m = Math.min(existing.min_distance_m, parseFloat(String(row.distance_meters)));
      }
    }

    const candidates: IdentityCandidate[] = [];

    for (const [assetId, data] of byAsset) {
      const catScore = categorySimilarityScore(queryCategory, data.category_label, categoryGroups);
      const headScore = headingProfileScore(queryHeading, data.heading_mean, data.heading_variance);

      const gpsResult = effectiveGpsScore(
        data.min_distance_m,
        queryAccuracy,
        data.gps_cluster,
        data.distance_to_centroid_m ?? data.min_distance_m
      );

      const scores = {
        gps: gpsResult.score,
        embedding: data.best_embedding,
        category: catScore,
        heading: headScore,
      };

      candidates.push({
        asset_id: assetId,
        asset_name: data.asset_name,
        category_label: data.category_label,
        gps_score: scores.gps,
        embedding_score: scores.embedding,
        category_score: scores.category,
        heading_score: scores.heading,
        final_confidence: computeFinalConfidence(scores),
        distance_meters: data.distance_to_centroid_m ?? data.min_distance_m,
        view_scores: data.view_scores.sort((a, b) => b.embedding_score - a.embedding_score),
        best_view_type: data.best_view,
        gps_cluster: data.gps_cluster,
        inside_cluster: gpsResult.insideCluster,
        visual_drift: data.visual_drift,
        last_seen_at: data.last_seen_at,
      });
    }

    return candidates.sort((a, b) => b.final_confidence - a.final_confidence);
  }

  async getAssetFingerprint(assetId: string): Promise<AssetFingerprint | null> {
    const { query } = await import('../../db/pool.js');
    const { rows } = await query(
      `SELECT id, name, category_id, observation_count, visual_drift_score, last_observation_at,
              ST_Y(gps_centroid::geometry) as centroid_lat,
              ST_X(gps_centroid::geometry) as centroid_lng,
              gps_variance_m2, gps_radius_m, heading_mean, heading_variance
       FROM assets WHERE id = $1`,
      [assetId]
    );
    if (!rows[0]) return null;

    const asset = rows[0];
    const observations = await observationRepository.findByAsset(assetId);

    const viewScores: ViewScore[] = observations.map((obs: Record<string, unknown>) => ({
      view_type: obs.view_type as ViewType,
      embedding_score: 1,
      observation_id: obs.id as string,
      captured_at: obs.captured_at as string,
    }));

    const gpsCluster: GpsCluster | null = asset.centroid_lat != null ? {
      centroid_lat: parseFloat(String(asset.centroid_lat)),
      centroid_lng: parseFloat(String(asset.centroid_lng)),
      variance_m2: parseFloat(String(asset.gps_variance_m2 ?? 0)),
      radius_m: parseFloat(String(asset.gps_radius_m ?? 0)),
      observation_count: asset.observation_count as number,
    } : null;

    return {
      asset_id: assetId,
      asset_name: asset.name as string,
      category_label: null,
      gps_cluster: gpsCluster,
      heading_profile: {
        mean: asset.heading_mean != null ? parseFloat(String(asset.heading_mean)) : null,
        variance: asset.heading_variance != null ? parseFloat(String(asset.heading_variance)) : null,
      },
      view_scores: viewScores,
      best_embedding_score: 0,
      best_view_type: null,
      observation_count: asset.observation_count as number,
      last_observation_at: asset.last_observation_at as string | null,
      visual_drift_score: asset.visual_drift_score != null
        ? parseFloat(String(asset.visual_drift_score))
        : null,
    };
  }

  async computeTemporalDrift(assetId: string): Promise<TemporalDriftResult | null> {
    const embeddings = await observationRepository.getEmbeddingsByAsset(assetId);
    if (embeddings.length < 2) return null;

    const observations = await observationRepository.findByAsset(assetId);
    const driftScore = computeVisualDrift(embeddings);
    await observationRepository.updateVisualDrift(assetId, driftScore);

    return {
      asset_id: assetId,
      drift_score: driftScore,
      earliest_observation: observations[observations.length - 1].captured_at as string,
      latest_observation: observations[0].captured_at as string,
      observation_pairs: (embeddings.length * (embeddings.length - 1)) / 2,
      interpretation: interpretDrift(driftScore),
    };
  }

  async refreshAssetFingerprint(assetId: string) {
    await observationRepository.updateAssetFingerprint(assetId);
    return this.computeTemporalDrift(assetId);
  }
}

export const fingerprintService = new FingerprintService();
