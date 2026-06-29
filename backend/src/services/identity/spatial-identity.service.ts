import { assetRepository } from '../../repositories/asset.repository.js';
import { identityResolutionRepository } from '../../repositories/identity.repository.js';
import { observationRepository } from '../../repositories/observation.repository.js';
import {
  conflictRepository,
  notificationRepository,
  auditLogRepository,
} from '../../repositories/survey.repository.js';
import { fingerprintService } from './fingerprint.service.js';
import { enqueueFingerprintRefresh } from '../../queues/fingerprint.queue.js';
import {
  categorySimilarityScore,
  computeFinalConfidence,
  determineVerdict,
  effectiveGpsScore,
  buildExplanationSummary,
} from './similarity.js';
import {
  EMBEDDING_DIMENSION,
  IDENTITY_THRESHOLDS,
  type ConfidenceExplanation,
  type IdentityCandidate,
  type IdentityVerdict,
  type ResolveIdentityInput,
  type ResolveIdentityResult,
  type StoreObservationInput,
  type ViewType,
} from '../../types/identity.js';

export class SpatialIdentityService {
  async storeObservation(data: StoreObservationInput) {
    this.validateEmbedding(data.embedding);
    const observation = await observationRepository.create(data);

    if (data.assetId) {
      await enqueueFingerprintRefresh(data.assetId, 'observation');
    }

    return observation;
  }

  /** @deprecated Use storeObservation — kept for backward compatibility */
  async storeEmbedding(data: {
    projectId: string;
    assetId: string;
    embedding: number[];
    imageId?: string;
    detectionId?: string;
    categoryLabel?: string;
    heading?: number;
    latitude?: number;
    longitude?: number;
    capturedBy?: string;
    clientId?: string;
  }) {
    if (data.latitude == null || data.longitude == null) {
      throw new Error('latitude and longitude required for observations');
    }

    return this.storeObservation({
      projectId: data.projectId,
      assetId: data.assetId,
      embedding: data.embedding,
      imageId: data.imageId,
      detectionId: data.detectionId,
      categoryLabel: data.categoryLabel,
      heading: data.heading,
      latitude: data.latitude,
      longitude: data.longitude,
      capturedBy: data.capturedBy,
      clientId: data.clientId,
    });
  }

  async resolveIdentity(input: ResolveIdentityInput): Promise<ResolveIdentityResult> {
    this.validateEmbedding(input.embedding);

    const radius: number = input.radiusMeters ?? IDENTITY_THRESHOLDS.searchRadiusMeters;
    const categoryGroups = await observationRepository.getCategoryLabelGroups(input.projectId);

    const observationRows = await observationRepository.searchObservations(
      input.projectId,
      input.embedding,
      IDENTITY_THRESHOLDS.observationSearchLimit,
      radius,
      input.latitude,
      input.longitude
    );

    const candidates = fingerprintService.buildCandidatesFromObservations(
      observationRows as Parameters<typeof fingerprintService.buildCandidatesFromObservations>[0],
      input.categoryLabel,
      input.heading,
      input.accuracy,
      categoryGroups
    );

    let bestCandidate: IdentityCandidate | null = candidates[0] ?? null;
    let scores = {
      gps: 0,
      embedding: 0,
      category: categorySimilarityScore(input.categoryLabel, input.categoryLabel, categoryGroups),
      heading: 0.5,
    };
    let finalConfidence = 0;
    let verdict: IdentityVerdict = 'new_asset';
    let matchedAssetId: string | null = null;
    let insideCluster = false;
    let accuracyFactor = effectiveGpsScore(0, input.accuracy, null, 0).accuracyFactor;

    if (bestCandidate) {
      scores = {
        gps: bestCandidate.gps_score,
        embedding: bestCandidate.embedding_score,
        category: bestCandidate.category_score,
        heading: bestCandidate.heading_score,
      };
      finalConfidence = bestCandidate.final_confidence;
      verdict = determineVerdict(scores, finalConfidence);
      insideCluster = bestCandidate.inside_cluster ?? false;
      if (verdict !== 'new_asset') {
        matchedAssetId = bestCandidate.asset_id;
      }

      const gpsResult = effectiveGpsScore(
        bestCandidate.distance_meters,
        input.accuracy,
        bestCandidate.gps_cluster ?? null,
        bestCandidate.distance_meters
      );
      accuracyFactor = gpsResult.accuracyFactor;
    } else {
      finalConfidence = computeFinalConfidence(scores);
      verdict = 'new_asset';
    }

    const explanation: ConfidenceExplanation = {
      gps: scores.gps,
      embedding: scores.embedding,
      category: scores.category,
      heading: scores.heading,
      gps_accuracy_factor: accuracyFactor,
      inside_cluster: insideCluster,
      best_view: bestCandidate?.best_view_type ?? input.viewType ?? null,
      view_breakdown: bestCandidate?.view_scores,
      cluster_radius_m: bestCandidate?.gps_cluster?.radius_m,
      distance_to_centroid_m: bestCandidate?.distance_meters,
      visual_drift: bestCandidate?.visual_drift ?? null,
      last_seen_at: bestCandidate?.last_seen_at ?? null,
      summary: buildExplanationSummary(scores, {
        insideCluster,
        bestView: bestCandidate?.best_view_type ?? input.viewType,
        visualDrift: bestCandidate?.visual_drift,
        lastSeenAt: bestCandidate?.last_seen_at,
      }),
    };

    let resolutionStatus: 'pending' | 'auto_linked' = verdict === 'possible_match' ? 'pending' : 'auto_linked';
    if (verdict === 'new_asset') resolutionStatus = 'auto_linked';

    let conflictId: string | undefined;

    if (verdict === 'possible_match' && matchedAssetId && bestCandidate) {
      const existingAsset = await assetRepository.findById(matchedAssetId);
      const submittedByA = (existingAsset?.created_by as string | undefined) ?? input.createdBy ?? '';

      if (!submittedByA || !input.createdBy) {
        throw new Error('User context required for identity conflict');
      }

      const conflict = await conflictRepository.create({
        projectId: input.projectId,
        assetId: matchedAssetId,
        entityType: 'identity_resolution',
        entityId: input.detectionId ?? matchedAssetId,
        submissionA: {
          type: 'existing_asset',
          assetId: matchedAssetId,
          assetName: bestCandidate.asset_name,
          scores,
          view_scores: bestCandidate.view_scores,
        },
        submissionB: {
          type: 'new_detection',
          category: input.categoryLabel,
          location: { latitude: input.latitude, longitude: input.longitude },
          heading: input.heading,
          accuracy: input.accuracy,
          viewType: input.viewType,
          scores,
        },
        submittedByA,
        submittedByB: input.createdBy,
      });
      conflictId = conflict.id as string;

      const supervisors = await this.getSupervisors(input.projectId);
      for (const supervisorId of supervisors) {
        await notificationRepository.create({
          userId: supervisorId,
          type: 'conflict',
          title: 'Identity Match Review Required',
          body: `Possible duplicate: "${input.categoryLabel}" may match "${bestCandidate.asset_name}" (${Math.round(finalConfidence * 100)}% confidence)`,
          data: { conflictId, verdict, confidence: finalConfidence, explanation },
        });
      }
    }

    const resolution = await identityResolutionRepository.create({
      projectId: input.projectId,
      detectionId: input.detectionId,
      queryCategory: input.categoryLabel,
      latitude: input.latitude,
      longitude: input.longitude,
      queryHeading: input.heading,
      queryEmbedding: input.embedding,
      matchedAssetId: matchedAssetId ?? undefined,
      verdict,
      gpsScore: scores.gps,
      embeddingScore: scores.embedding,
      categoryScore: scores.category,
      headingScore: scores.heading,
      finalConfidence,
      candidateScores: candidates,
      resolutionStatus,
      conflictId,
      createdBy: input.createdBy,
      clientId: input.clientId,
      gpsAccuracy: input.accuracy,
      explanation,
      viewScores: bestCandidate?.view_scores ?? [],
      matchedViewType: bestCandidate?.best_view_type ?? input.viewType,
      visualDrift: bestCandidate?.visual_drift,
      lastSeenAt: bestCandidate?.last_seen_at,
    });

    if (verdict === 'same_asset' && matchedAssetId && input.detectionId) {
      await auditLogRepository.log({
        userId: input.createdBy,
        action: 'verify',
        entityType: 'identity_resolution',
        entityId: resolution.id as string,
        details: { verdict, matchedAssetId, autoLinked: true, explanation },
      });
    }

    return {
      resolutionId: resolution.id as string,
      verdict,
      matchedAssetId,
      finalConfidence,
      scores,
      explanation,
      candidates,
      requiresReview: verdict === 'possible_match',
      conflictId,
    };
  }

  async confirmResolution(
    resolutionId: string,
    resolvedBy: string,
    linkToAssetId?: string
  ) {
    const resolution = await identityResolutionRepository.findById(resolutionId);
    if (!resolution) throw new Error('Resolution not found');

    const assetId = linkToAssetId ?? (resolution.matched_asset_id as string);
    const updated = await identityResolutionRepository.resolve(
      resolutionId,
      'confirmed',
      resolvedBy,
      assetId
    );

    if (resolution.conflict_id) {
      await conflictRepository.resolve(
        resolution.conflict_id as string,
        { decision: 'confirmed_same_asset', assetId },
        resolvedBy
      );
    }

    await auditLogRepository.log({
      userId: resolvedBy,
      action: 'resolve_conflict',
      entityType: 'identity_resolution',
      entityId: resolutionId,
      details: { assetId, verdict: resolution.verdict },
    });

    return updated;
  }

  async rejectResolution(resolutionId: string, resolvedBy: string) {
    const resolution = await identityResolutionRepository.findById(resolutionId);
    if (!resolution) throw new Error('Resolution not found');

    const updated = await identityResolutionRepository.resolve(
      resolutionId,
      'rejected',
      resolvedBy
    );

    if (resolution.conflict_id) {
      await conflictRepository.resolve(
        resolution.conflict_id as string,
        { decision: 'new_asset' },
        resolvedBy
      );
    }

    await auditLogRepository.log({
      userId: resolvedBy,
      action: 'resolve_conflict',
      entityType: 'identity_resolution',
      entityId: resolutionId,
      details: { verdict: 'new_asset' },
    });

    return updated;
  }

  async linkDetectionToAsset(
    detectionId: string,
    assetId: string,
    embedding: number[],
    input: {
      projectId: string;
      categoryLabel: string;
      latitude: number;
      longitude: number;
      heading?: number;
      accuracy?: number;
      viewType?: ViewType;
      capturedBy?: string;
    }
  ) {
    await this.storeObservation({
      projectId: input.projectId,
      assetId,
      embedding,
      detectionId,
      categoryLabel: input.categoryLabel,
      heading: input.heading,
      latitude: input.latitude,
      longitude: input.longitude,
      accuracy: input.accuracy,
      viewType: input.viewType,
      capturedBy: input.capturedBy,
    });

    return assetRepository.findById(assetId);
  }

  async getAssetFingerprint(assetId: string) {
    return fingerprintService.getAssetFingerprint(assetId);
  }

  async getTemporalDrift(assetId: string) {
    return fingerprintService.computeTemporalDrift(assetId);
  }

  private validateEmbedding(embedding: number[]) {
    if (embedding.length !== EMBEDDING_DIMENSION) {
      throw new Error(`Expected ${EMBEDDING_DIMENSION}-dim embedding`);
    }
  }

  private async getSupervisors(projectId: string): Promise<string[]> {
    const { query } = await import('../../db/pool.js');
    const { rows } = await query<{ user_id: string }>(
      `SELECT DISTINCT u.id as user_id FROM users u
       JOIN team_members tm ON tm.user_id = u.id
       JOIN teams t ON t.id = tm.team_id
       WHERE t.project_id = $1 AND u.role IN ('supervisor', 'admin')`,
      [projectId]
    );
    return rows.map((r) => r.user_id);
  }
}

export const spatialIdentityService = new SpatialIdentityService();
