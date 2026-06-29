import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticate, requireRole } from '../services/auth.service.js';
import {
  anchorRepository,
  surveySessionRepository,
  conflictRepository,
  notificationRepository,
} from '../repositories/survey.repository.js';
import { syncService } from '../services/sync.service.js';
import { analyticsService } from '../services/analytics.service.js';
import { storageService } from '../services/storage.service.js';
import { projectRepository } from '../repositories/project.repository.js';
import { auditLogRepository } from '../repositories/survey.repository.js';

export async function surveyRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', authenticate);

  app.post('/sessions', async (request) => {
    const body = z.object({
      projectId: z.string().uuid(),
      clientId: z.string().optional(),
    }).parse(request.body);

    return surveySessionRepository.create({
      projectId: body.projectId,
      userId: request.user!.sub,
      clientId: body.clientId,
    });
  });

  app.patch('/sessions/:id/coverage', async (request, reply) => {
    const { id } = request.params as { id: string };
    const body = z.object({
      coveragePercentage: z.number().min(0).max(100),
      path: z.object({
        type: z.literal('MultiLineString'),
        coordinates: z.array(z.array(z.tuple([z.number(), z.number()]))),
      }).optional(),
      visitedArea: z.object({
        type: z.literal('MultiPolygon'),
        coordinates: z.array(z.array(z.array(z.tuple([z.number(), z.number()])))),
      }).optional(),
    }).parse(request.body);

    const session = await surveySessionRepository.updateCoverage(
      id, body.coveragePercentage, body.path, body.visitedArea
    );
    if (!session) return reply.status(404).send({ error: 'Session not found' });
    return session;
  });

  app.post('/sessions/:id/end', async (request, reply) => {
    const { id } = request.params as { id: string };
    const session = await surveySessionRepository.endSession(id);
    if (!session) return reply.status(404).send({ error: 'Session not found' });
    return session;
  });

  app.get('/sessions/active/:projectId', async (request) => {
    const { projectId } = request.params as { projectId: string };
    return surveySessionRepository.findActive(projectId, request.user!.sub);
  });

  app.get('/anchors/project/:projectId', async (request, reply) => {
    const { projectId } = request.params as { projectId: string };
    const user = request.user!;
    if (user.role !== 'admin') {
      const hasAccess = await projectRepository.isUserInProject(user.sub, projectId);
      if (!hasAccess) return reply.status(403).send({ error: 'Forbidden' });
    }
    return anchorRepository.listByProject(projectId);
  });

  app.post('/anchors', async (request) => {
    const body = z.object({
      projectId: z.string().uuid(),
      assetId: z.string().uuid().optional(),
      anchorId: z.string().min(1),
      latitude: z.number(),
      longitude: z.number(),
      altitude: z.number().optional(),
      heading: z.number().optional(),
      cameraOrientation: z.record(z.number()).optional(),
      anchorData: z.record(z.unknown()).optional(),
      clientId: z.string().optional(),
    }).parse(request.body);

    return anchorRepository.create({
      ...body,
      createdBy: request.user!.sub,
    });
  });

  app.patch('/anchors/:id/relocate', async (request, reply) => {
    const { id } = request.params as { id: string };
    const body = z.object({
      latitude: z.number(),
      longitude: z.number(),
      altitude: z.number().optional(),
      heading: z.number().optional(),
      cameraOrientation: z.record(z.number()).optional(),
      anchorData: z.record(z.unknown()).optional(),
    }).parse(request.body);

    const anchor = await anchorRepository.relocate(id, body);
    if (!anchor) return reply.status(404).send({ error: 'Anchor not found' });
    return anchor;
  });

  app.post('/sync/push', async (request) => {
    const body = z.object({
      deviceId: z.string(),
      items: z.array(z.object({
        entity_type: z.string(),
        entity_id: z.string(),
        client_id: z.string(),
        operation: z.enum(['create', 'update', 'delete']),
        payload: z.record(z.unknown()),
        timestamp: z.string(),
      })),
    }).parse(request.body);

    return syncService.pushChanges(request.user!.sub, body.deviceId, body.items);
  });

  app.get('/sync/pull/:projectId', async (request, reply) => {
    const { projectId } = request.params as { projectId: string };
    const { since } = request.query as { since?: string };
    const user = request.user!;
    if (user.role !== 'admin') {
      const hasAccess = await projectRepository.isUserInProject(user.sub, projectId);
      if (!hasAccess) return reply.status(403).send({ error: 'Forbidden' });
    }
    return syncService.pullChanges(user.sub, projectId, since);
  });

  app.get('/conflicts', { preHandler: requireRole('supervisor', 'admin') }, async (request) => {
    const { projectId } = request.query as { projectId?: string };
    return conflictRepository.listOpen(projectId);
  });

  app.post('/conflicts/:id/resolve', { preHandler: requireRole('supervisor', 'admin') }, async (request, reply) => {
    const { id } = request.params as { id: string };
    const body = z.object({
      resolution: z.record(z.unknown()),
    }).parse(request.body);

    const conflict = await conflictRepository.resolve(id, body.resolution, request.user!.sub);
    if (!conflict) return reply.status(404).send({ error: 'Conflict not found' });

    await auditLogRepository.log({
      userId: request.user!.sub,
      action: 'resolve_conflict',
      entityType: 'conflict',
      entityId: id,
      details: body.resolution,
    });
    return conflict;
  });

  app.get('/analytics/:projectId', { preHandler: requireRole('supervisor', 'admin') }, async (request, reply) => {
    const { projectId } = request.params as { projectId: string };
    return analyticsService.getProjectDashboard(projectId);
  });

  app.get('/notifications', async (request) => {
    return notificationRepository.listUnread(request.user!.sub);
  });

  app.post('/notifications/:id/read', async (request) => {
    const { id } = request.params as { id: string };
    await notificationRepository.markRead(id, request.user!.sub);
    return { success: true };
  });

  app.post('/images/presign', async (request) => {
    const body = z.object({
      projectId: z.string().uuid(),
      filename: z.string(),
      contentType: z.string(),
    }).parse(request.body);

    const key = storageService.generateKey(`projects/${body.projectId}/images`, body.filename);
    const uploadUrl = await storageService.getPresignedUploadUrl(key, body.contentType);
    return { uploadUrl, key, bucket: process.env.S3_BUCKET ?? 'spatialverify' };
  });

  app.post('/reconstruction', async (request) => {
    const body = z.object({
      projectId: z.string().uuid(),
      sessionId: z.string().uuid().optional(),
      assetId: z.string().uuid().optional(),
      imageKeys: z.array(z.string()).min(2),
      clientId: z.string().optional(),
    }).parse(request.body);

    const { query } = await import('../db/pool.js');
    const { rows } = await query(
      `INSERT INTO point_clouds (project_id, asset_id, session_id, phase, metadata, created_by, client_id)
       VALUES ($1, $2, $3, 'capture', $4, $5, $6) RETURNING *`,
      [
        body.projectId, body.assetId ?? null, body.sessionId ?? null,
        JSON.stringify({ image_keys: body.imageKeys, image_count: body.imageKeys.length }),
        request.user!.sub, body.clientId ?? null,
      ]
    );

    const { reconstructionQueue } = await import('../queues/reconstruction.queue.js');
    await reconstructionQueue.add('sparse-point-cloud', {
      pointCloudId: rows[0].id,
      imageKeys: body.imageKeys,
    });

    return rows[0];
  });
}
