import { assetRepository } from '../repositories/asset.repository.js';
import { detectionRepository, verificationRepository } from '../repositories/detection.repository.js';
import {
  conflictRepository,
  notificationRepository,
  auditLogRepository,
} from '../repositories/survey.repository.js';
import type { HumanDecision } from '../types/index.js';

export class VerificationService {
  async processVerification(data: {
    detectionId: string;
    humanDecision: HumanDecision;
    editedCategory?: string;
    editedLocation?: GeoJSON.Point;
    notes?: string;
    verifiedBy: string;
    projectId: string;
    clientId?: string;
    matchedAssetId?: string;
    identityResolutionId?: string;
    embedding?: number[];
  }) {
    const detection = await detectionRepository.findById(data.detectionId);
    if (!detection) {
      throw new Error('Detection not found');
    }

    const existingVerifications = await verificationRepository.findByDetection(data.detectionId);
    if (existingVerifications.length > 0) {
      const conflicting = existingVerifications.find(
        (v) => v.human_decision !== data.humanDecision || v.edited_category !== data.editedCategory
      );
      if (conflicting && conflicting.verified_by !== data.verifiedBy) {
        const conflict = await conflictRepository.create({
          projectId: data.projectId,
          entityType: 'verification',
          entityId: data.detectionId,
          submissionA: {
            decision: conflicting.human_decision,
            category: conflicting.edited_category,
            verifiedBy: conflicting.verified_by,
          },
          submissionB: {
            decision: data.humanDecision,
            category: data.editedCategory,
            verifiedBy: data.verifiedBy,
          },
          submittedByA: conflicting.verified_by,
          submittedByB: data.verifiedBy,
        });

        const supervisors = await this.getSupervisors(data.projectId);
        for (const supervisorId of supervisors) {
          await notificationRepository.create({
            userId: supervisorId,
            type: 'conflict',
            title: 'Verification Conflict',
            body: `Conflicting verifications for detection ${data.detectionId}`,
            data: { conflictId: conflict.id },
          });
        }

        return { conflict: true, conflictId: conflict.id };
      }
    }

    let assetId: string | undefined;
    let assetStatus: 'verified' | 'rejected' | 'pending' = 'pending';

    if (data.humanDecision === 'confirmed' || data.humanDecision === 'edited') {
      const category = data.editedCategory ?? detection.category_label;
      const location = data.editedLocation ?? detection.location;

      if (!location) {
        throw new Error('Location required for asset creation');
      }

      if (data.matchedAssetId) {
        assetId = data.matchedAssetId;
        assetStatus = 'verified';
        await assetRepository.updateStatus(assetId, assetStatus, data.verifiedBy);

        if (data.embedding && data.embedding.length > 0) {
          const { spatialIdentityService } = await import('./identity/spatial-identity.service.js');
          const coords = location.coordinates;
          await spatialIdentityService.storeEmbedding({
            projectId: data.projectId,
            assetId,
            embedding: data.embedding,
            detectionId: data.detectionId,
            categoryLabel: category,
            heading: detection.heading ?? undefined,
            latitude: coords[1],
            longitude: coords[0],
            capturedBy: data.verifiedBy,
            clientId: data.clientId,
          });
        }

        if (data.identityResolutionId) {
          const { spatialIdentityService } = await import('./identity/spatial-identity.service.js');
          await spatialIdentityService.confirmResolution(
            data.identityResolutionId,
            data.verifiedBy,
            assetId
          );
        }
      } else {
        const asset = await assetRepository.create({
          projectId: data.projectId,
          name: category,
          status: 'verified',
          geometryType: 'point',
          location,
          altitude: detection.altitude ?? undefined,
          heading: detection.heading ?? undefined,
          createdBy: data.verifiedBy,
          clientId: data.clientId,
          metadata: { source_detection_id: detection.id },
        });
        assetId = asset.id;
        assetStatus = 'verified';

        if (data.embedding && data.embedding.length > 0) {
          const { spatialIdentityService } = await import('./identity/spatial-identity.service.js');
          const coords = location.coordinates;
          await spatialIdentityService.storeEmbedding({
            projectId: data.projectId,
            assetId,
            embedding: data.embedding,
            detectionId: data.detectionId,
            categoryLabel: category,
            heading: detection.heading ?? undefined,
            latitude: coords[1],
            longitude: coords[0],
            capturedBy: data.verifiedBy,
            clientId: data.clientId,
          });
        }
      }
    } else if (data.humanDecision === 'rejected') {
      assetStatus = 'rejected';
    }

    const verification = await verificationRepository.create({
      detectionId: data.detectionId,
      assetId,
      aiPrediction: detection.category_label,
      confidence: detection.confidence,
      humanDecision: data.humanDecision,
      editedCategory: data.editedCategory,
      editedLocation: data.editedLocation,
      notes: data.notes,
      verifiedBy: data.verifiedBy,
      clientId: data.clientId,
    });

    if (assetId) {
      await assetRepository.updateStatus(assetId, assetStatus, data.verifiedBy);
    }

    await auditLogRepository.log({
      userId: data.verifiedBy,
      action: data.humanDecision === 'rejected' ? 'reject' : 'verify',
      entityType: 'detection',
      entityId: data.detectionId,
      details: { verificationId: verification.id, assetId },
    });

    return { conflict: false, verification, assetId };
  }

  private async getSupervisors(projectId: string): Promise<string[]> {
    const { query } = await import('../db/pool.js');
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

export const verificationService = new VerificationService();
