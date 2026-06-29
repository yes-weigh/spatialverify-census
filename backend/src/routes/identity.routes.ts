import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticate, requireRole } from '../services/auth.service.js';
import { spatialIdentityService } from '../services/identity/spatial-identity.service.js';
import { embeddingRepository, identityResolutionRepository } from '../repositories/identity.repository.js';
import { observationRepository } from '../repositories/observation.repository.js';
import { projectRepository } from '../repositories/project.repository.js';
import { EMBEDDING_DIMENSION } from '../types/identity.js';

const embeddingSchema = z.array(z.number()).length(EMBEDDING_DIMENSION);
const viewTypeSchema = z.enum(['front', 'left', 'right', 'rear', 'far', 'unknown']);

const resolveSchema = z.object({
  projectId: z.string().uuid(),
  categoryLabel: z.string().min(1),
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  heading: z.number().min(0).max(360).optional(),
  accuracy: z.number().min(0).optional(),
  verticalAccuracy: z.number().min(0).optional(),
  bearingAccuracy: z.number().min(0).optional(),
  viewType: viewTypeSchema.optional(),
  weather: z.string().optional(),
  lighting: z.string().optional(),
  embedding: embeddingSchema,
  detectionId: z.string().uuid().optional(),
  imageId: z.string().uuid().optional(),
  radiusMeters: z.number().min(1).max(500).optional(),
  deviceModel: z.string().max(100).optional(),
  cameraFov: z.number().min(0).max(180).optional(),
  cameraResolution: z.string().max(20).optional(),
  clientId: z.string().optional(),
});

const storeObservationSchema = z.object({
  projectId: z.string().uuid(),
  assetId: z.string().uuid().optional(),
  embedding: embeddingSchema,
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  altitude: z.number().optional(),
  accuracy: z.number().min(0).optional(),
  verticalAccuracy: z.number().min(0).optional(),
  heading: z.number().min(0).max(360).optional(),
  bearingAccuracy: z.number().min(0).optional(),
  viewType: viewTypeSchema.optional(),
  categoryLabel: z.string().optional(),
  weather: z.string().optional(),
  lighting: z.string().optional(),
  imageId: z.string().uuid().optional(),
  detectionId: z.string().uuid().optional(),
  clientId: z.string().optional(),
  deviceModel: z.string().max(100).optional(),
  cameraFov: z.number().min(0).max(180).optional(),
  cameraResolution: z.string().max(20).optional(),
});

const storeEmbeddingSchema = z.object({
  projectId: z.string().uuid(),
  assetId: z.string().uuid(),
  embedding: embeddingSchema,
  imageId: z.string().uuid().optional(),
  detectionId: z.string().uuid().optional(),
  categoryLabel: z.string().optional(),
  heading: z.number().optional(),
  latitude: z.number().optional(),
  longitude: z.number().optional(),
  clientId: z.string().optional(),
});

export async function identityRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', authenticate);

  async function checkProjectAccess(userId: string, role: string, projectId: string) {
    if (role === 'admin') return true;
    return projectRepository.isUserInProject(userId, projectId);
  }

  app.post('/resolve', async (request, reply) => {
    const body = resolveSchema.parse(request.body);
    const user = request.user;

    if (!(await checkProjectAccess(user.sub, user.role, body.projectId))) {
      return reply.status(403).send({ error: 'Forbidden' });
    }

    try {
      const result = await spatialIdentityService.resolveIdentity({
        ...body,
        createdBy: user.sub,
      });

      return {
        resolutionId: result.resolutionId,
        verdict: result.verdict.toUpperCase(),
        matchedAssetId: result.matchedAssetId,
        finalConfidence: result.finalConfidence,
        scores: {
          gps: result.scores.gps,
          embedding: result.scores.embedding,
          category: result.scores.category,
          heading: result.scores.heading,
        },
        explanation: result.explanation,
        candidates: result.candidates,
        requiresReview: result.requiresReview,
        conflictId: result.conflictId,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Identity resolution failed';
      return reply.status(400).send({ error: message });
    }
  });

  app.post('/observations', async (request, reply) => {
    const body = storeObservationSchema.parse(request.body);
    const user = request.user;

    if (!(await checkProjectAccess(user.sub, user.role, body.projectId))) {
      return reply.status(403).send({ error: 'Forbidden' });
    }

    const record = await spatialIdentityService.storeObservation({
      ...body,
      capturedBy: user.sub,
    });

    return record;
  });

  app.get('/observations/asset/:assetId', async (request) => {
    const { assetId } = request.params as { assetId: string };
    return observationRepository.findByAsset(assetId);
  });

  app.get('/assets/:assetId/fingerprint', async (request, reply) => {
    const { assetId } = request.params as { assetId: string };
    const fingerprint = await spatialIdentityService.getAssetFingerprint(assetId);
    if (!fingerprint) return reply.status(404).send({ error: 'Asset not found' });
    return fingerprint;
  });

  app.get('/assets/:assetId/drift', async (request, reply) => {
    const { assetId } = request.params as { assetId: string };
    const drift = await spatialIdentityService.getTemporalDrift(assetId);
    if (!drift) {
      return reply.status(404).send({ error: 'Insufficient observations for drift analysis' });
    }
    return drift;
  });

  app.post('/embeddings', async (request, reply) => {
    const body = storeEmbeddingSchema.parse(request.body);
    const user = request.user;

    if (!(await checkProjectAccess(user.sub, user.role, body.projectId))) {
      return reply.status(403).send({ error: 'Forbidden' });
    }

    const record = await spatialIdentityService.storeEmbedding({
      ...body,
      capturedBy: user.sub,
    });

    return record;
  });

  app.get('/embeddings/asset/:assetId', async (request) => {
    const { assetId } = request.params as { assetId: string };
    return embeddingRepository.findByAsset(assetId);
  });

  app.get('/resolutions/pending', { preHandler: requireRole('supervisor', 'admin') }, async (request) => {
    const { projectId } = request.query as { projectId?: string };
    return identityResolutionRepository.listPending(projectId);
  });

  app.get('/resolutions/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const resolution = await identityResolutionRepository.findById(id);
    if (!resolution) return reply.status(404).send({ error: 'Not found' });
    return resolution;
  });

  app.post('/resolutions/:id/confirm', { preHandler: requireRole('supervisor', 'admin', 'field_worker') }, async (request, reply) => {
    const { id } = request.params as { id: string };
    const body = z.object({
      linkToAssetId: z.string().uuid().optional(),
    }).parse(request.body ?? {});

    try {
      const result = await spatialIdentityService.confirmResolution(
        id,
        request.user.sub,
        body.linkToAssetId
      );
      return result;
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Confirm failed';
      return reply.status(400).send({ error: message });
    }
  });

  app.post('/resolutions/:id/reject', { preHandler: requireRole('supervisor', 'admin', 'field_worker') }, async (request, reply) => {
    const { id } = request.params as { id: string };

    try {
      const result = await spatialIdentityService.rejectResolution(id, request.user.sub);
      return result;
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Reject failed';
      return reply.status(400).send({ error: message });
    }
  });

  app.post('/link', async (request, reply) => {
    const body = z.object({
      detectionId: z.string().uuid(),
      assetId: z.string().uuid(),
      projectId: z.string().uuid(),
      categoryLabel: z.string(),
      latitude: z.number(),
      longitude: z.number(),
      heading: z.number().optional(),
      accuracy: z.number().optional(),
      viewType: viewTypeSchema.optional(),
      embedding: embeddingSchema,
    }).parse(request.body);

    const user = request.user;
    if (!(await checkProjectAccess(user.sub, user.role, body.projectId))) {
      return reply.status(403).send({ error: 'Forbidden' });
    }

    const asset = await spatialIdentityService.linkDetectionToAsset(
      body.detectionId,
      body.assetId,
      body.embedding,
      { ...body, capturedBy: user.sub }
    );

    return asset;
  });
}
