import { query } from '../db/pool.js';
import {
  assetRepository,
} from '../repositories/asset.repository.js';
import {
  anchorRepository,
  conflictRepository,
  surveySessionRepository,
  syncQueueRepository,
} from '../repositories/survey.repository.js';
import { detectionRepository } from '../repositories/detection.repository.js';
import type { SyncItem } from '../types/index.js';

export class SyncService {
  async pushChanges(
    userId: string,
    deviceId: string,
    items: SyncItem[]
  ): Promise<{ synced: string[]; conflicts: string[]; failed: string[] }> {
    const synced: string[] = [];
    const conflicts: string[] = [];
    const failed: string[] = [];

    for (const item of items) {
      try {
        const queueEntry = await syncQueueRepository.enqueue({
          userId,
          deviceId,
          entityType: item.entity_type,
          entityId: item.entity_id,
          clientId: item.client_id,
          operation: item.operation,
          payload: item.payload,
        });

        await syncQueueRepository.updateStatus(queueEntry.id, 'uploading');

        const result = await this.processItem(userId, item);
        if (result.conflict) {
          await syncQueueRepository.updateStatus(queueEntry.id, 'conflict');
          conflicts.push(item.client_id);
        } else {
          await syncQueueRepository.updateStatus(queueEntry.id, 'synced');
          synced.push(item.client_id);
        }
      } catch (error) {
        failed.push(item.client_id);
        console.error(`Sync failed for ${item.client_id}:`, error);
      }
    }

    return { synced, conflicts, failed };
  }

  private async processItem(
    userId: string,
    item: SyncItem
  ): Promise<{ conflict: boolean }> {
    switch (item.entity_type) {
      case 'asset':
        return this.syncAsset(userId, item);
      case 'detection':
        return this.syncDetection(userId, item);
      case 'anchor':
        return this.syncAnchor(userId, item);
      case 'survey_session':
        return this.syncSurveySession(userId, item);
      default:
        return { conflict: false };
    }
  }

  private async syncAsset(userId: string, item: SyncItem): Promise<{ conflict: boolean }> {
    const existing = await assetRepository.findByClientId(item.client_id);
    const payload = item.payload;

    if (item.operation === 'create' && !existing) {
      await assetRepository.create({
        projectId: payload.project_id as string,
        categoryId: payload.category_id as string | undefined,
        name: payload.name as string,
        description: payload.description as string | undefined,
        status: payload.status as 'pending' | 'verified' | 'rejected' | 'not_surveyed',
        geometryType: payload.geometry_type as 'point' | 'line' | 'polygon',
        location: payload.location as GeoJSON.Geometry,
        altitude: payload.altitude as number | undefined,
        heading: payload.heading as number | undefined,
        metadata: payload.metadata as Record<string, unknown> | undefined,
        createdBy: userId,
        clientId: item.client_id,
      });
      return { conflict: false };
    }

    if (existing && item.operation === 'update') {
      const serverVersion = existing.version;
      const clientVersion = payload.version as number;
      if (clientVersion < serverVersion) {
        await conflictRepository.create({
          projectId: existing.project_id,
          assetId: existing.id,
          entityType: 'asset',
          entityId: existing.id,
          submissionA: existing as unknown as Record<string, unknown>,
          submissionB: payload,
          submittedByA: existing.created_by ?? userId,
          submittedByB: userId,
        });
        return { conflict: true };
      }
    }

    return { conflict: false };
  }

  private async syncDetection(userId: string, item: SyncItem): Promise<{ conflict: boolean }> {
    const payload = item.payload;
    if (item.operation === 'create') {
      await detectionRepository.create({
        projectId: payload.project_id as string,
        sessionId: payload.session_id as string | undefined,
        categoryLabel: payload.category_label as string,
        confidence: payload.confidence as number,
        boundingBox: payload.bounding_box as { x: number; y: number; width: number; height: number },
        location: payload.location as GeoJSON.Point | undefined,
        altitude: payload.altitude as number | undefined,
        heading: payload.heading as number | undefined,
        createdBy: userId,
        clientId: item.client_id,
      });
    }
    return { conflict: false };
  }

  private async syncAnchor(userId: string, item: SyncItem): Promise<{ conflict: boolean }> {
    const payload = item.payload;
    const existing = await anchorRepository.findByAnchorId(payload.anchor_id as string);

    if (!existing && item.operation === 'create') {
      await anchorRepository.create({
        projectId: payload.project_id as string,
        assetId: payload.asset_id as string | undefined,
        anchorId: payload.anchor_id as string,
        latitude: payload.latitude as number,
        longitude: payload.longitude as number,
        altitude: payload.altitude as number | undefined,
        heading: payload.heading as number | undefined,
        cameraOrientation: payload.camera_orientation as Record<string, number> | undefined,
        anchorData: payload.anchor_data as Record<string, unknown> | undefined,
        createdBy: userId,
        clientId: item.client_id,
      });
    } else if (existing && item.operation === 'update') {
      await anchorRepository.relocate(existing.id, {
        latitude: payload.latitude as number,
        longitude: payload.longitude as number,
        altitude: payload.altitude as number | undefined,
        heading: payload.heading as number | undefined,
        cameraOrientation: payload.camera_orientation as Record<string, number> | undefined,
        anchorData: payload.anchor_data as Record<string, unknown> | undefined,
      });
    }
    return { conflict: false };
  }

  private async syncSurveySession(userId: string, item: SyncItem): Promise<{ conflict: boolean }> {
    const payload = item.payload;
    if (item.operation === 'update' && payload.id) {
      await surveySessionRepository.updateCoverage(
        payload.id as string,
        payload.coverage_percentage as number,
        payload.path as GeoJSON.MultiLineString | undefined,
        payload.visited_area as GeoJSON.MultiPolygon | undefined
      );
    }
    return { conflict: false };
  }

  async pullChanges(
    userId: string,
    projectId: string,
    since?: string
  ): Promise<Record<string, unknown[]>> {
    const sinceClause = since ? `AND updated_at > $3` : '';
    const params: unknown[] = [projectId, userId];
    if (since) params.push(since);

    const { rows: assets } = await query(
      `SELECT id, project_id, category_id, name, status, geometry_type,
              ST_AsGeoJSON(location) as location, altitude, heading, metadata,
              client_id, version, updated_at
       FROM assets WHERE project_id = $1 ${sinceClause}`,
      since ? params : [projectId]
    );

    const { rows: conflicts } = await query(
      `SELECT * FROM conflicts WHERE project_id = $1 AND status = 'open'`,
      [projectId]
    );

    return {
      assets: assets.map((a) => ({ ...a, location: JSON.parse(a.location as string) })),
      conflicts,
    };
  }
}

export const syncService = new SyncService();
