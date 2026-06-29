import type { FastifyInstance } from 'fastify';
import multipart from '@fastify/multipart';
import { z } from 'zod';
import { authenticate } from '../services/auth.service.js';
import { projectRepository } from '../repositories/project.repository.js';
import { missionRepository } from '../repositories/mission.repository.js';
import {
  computeTransform,
  detectSatelliteStructures,
  extractLandmarks,
  finalizeGeoref,
  getLayoutGeorefSession,
  saveControlPoints,
  saveGpsBoundary,
  saveImageBounds,
  saveSketchBoundary,
  uploadLayoutMap,
  validateGeoref,
} from '../services/layout-georef.service.js';
import {
  confirmMissionIntelligence,
  generateMissionIntelligence,
  getMissionIntelligence,
} from '../services/mission-intelligence.service.js';
import { askFieldAssistant } from '../services/gemini-assistant.service.js';
import { learningEngineStats, recordLearningFeedback } from '../engines/mission-learning/feedback-store.js';

const imageBoundsSchema = z.object({
  north: z.number(),
  south: z.number(),
  east: z.number(),
  west: z.number(),
  rotation: z.number().optional(),
});

const gpsPointSchema = z.object({ lat: z.number(), lng: z.number() });

const controlPointSchema = z.object({
  id: z.string(),
  label: z.string(),
  sketchX: z.number().min(0).max(1),
  sketchY: z.number().min(0).max(1),
  lat: z.number(),
  lng: z.number(),
});

async function checkEbAccess(userId: string, role: string, ebId: string) {
  const block = await missionRepository.findBlockById(ebId);
  if (!block) return { ok: false as const, status: 404 };
  const projectId = block.project_id as string;
  if (role !== 'admin' && !(await projectRepository.isUserInProject(userId, projectId))) {
    return { ok: false as const, status: 403 };
  }
  return { ok: true as const, block };
}

export async function layoutGeorefRoutes(app: FastifyInstance): Promise<void> {
  await app.register(multipart, { limits: { fileSize: 25 * 1024 * 1024 } });
  app.addHook('preHandler', authenticate);

  app.get('/eb/:ebId', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const access = await checkEbAccess(request.user!.sub, request.user!.role, ebId);
    if (!access.ok) return reply.status(access.status).send({ error: 'Forbidden' });

    const session = await getLayoutGeorefSession(ebId);
    if (!session) return reply.status(404).send({ error: 'No layout georef session' });
    return session;
  });

  app.post('/eb/:ebId/upload', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const access = await checkEbAccess(request.user!.sub, request.user!.role, ebId);
    if (!access.ok) return reply.status(access.status).send({ error: 'Forbidden' });

    let buffer: Buffer | null = null;
    let mime = 'image/jpeg';
    let filename = 'layout.jpg';
    let previewBuffer: Buffer | undefined;

    const parts = request.parts();
    for await (const part of parts) {
      if (part.type !== 'file') continue;
      const data = await part.toBuffer();
      if (part.fieldname === 'preview') {
        previewBuffer = data;
      } else {
        buffer = data;
        mime = part.mimetype || mime;
        filename = part.filename || filename;
      }
    }

    if (!buffer) return reply.status(400).send({ error: 'No file uploaded' });

    const session = await uploadLayoutMap(
      ebId,
      buffer,
      mime,
      filename,
      request.user!.sub,
      previewBuffer
    );
    return session;
  });

  app.post('/eb/:ebId/extract-landmarks', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const access = await checkEbAccess(request.user!.sub, request.user!.role, ebId);
    if (!access.ok) return reply.status(access.status).send({ error: 'Forbidden' });

    try {
      const extraction = await extractLandmarks(ebId);
      return extraction;
    } catch (e) {
      return reply.status(400).send({ error: (e as Error).message });
    }
  });

  app.put('/eb/:ebId/image-bounds', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const body = z.object({ bounds: imageBoundsSchema }).parse(request.body);
    const access = await checkEbAccess(request.user!.sub, request.user!.role, ebId);
    if (!access.ok) return reply.status(access.status).send({ error: 'Forbidden' });

    return saveImageBounds(ebId, body.bounds);
  });

  app.put('/eb/:ebId/gps-boundary', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const body = z.object({ boundary: z.array(gpsPointSchema).min(3) }).parse(request.body);
    const access = await checkEbAccess(request.user!.sub, request.user!.role, ebId);
    if (!access.ok) return reply.status(access.status).send({ error: 'Forbidden' });

    return saveGpsBoundary(ebId, body.boundary);
  });

  app.post('/eb/:ebId/detect-structures', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const access = await checkEbAccess(request.user!.sub, request.user!.role, ebId);
    if (!access.ok) return reply.status(access.status).send({ error: 'Forbidden' });

    try {
      return await detectSatelliteStructures(ebId);
    } catch (e) {
      return reply.status(400).send({ error: (e as Error).message });
    }
  });

  app.post('/eb/:ebId/generate-intelligence', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const body = z.object({ lat: z.number(), lng: z.number() }).parse(request.body);
    const access = await checkEbAccess(request.user!.sub, request.user!.role, ebId);
    if (!access.ok) return reply.status(access.status).send({ error: 'Forbidden' });

    try {
      return await generateMissionIntelligence(ebId, body.lat, body.lng);
    } catch (e) {
      return reply.status(400).send({ error: (e as Error).message });
    }
  });

  app.get('/eb/:ebId/intelligence', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const access = await checkEbAccess(request.user!.sub, request.user!.role, ebId);
    if (!access.ok) return reply.status(access.status).send({ error: 'Forbidden' });

    const intelligence = await getMissionIntelligence(ebId);
    if (!intelligence) return reply.status(404).send({ error: 'No mission intelligence' });
    const session = await getLayoutGeorefSession(ebId);
    return { intelligence, layoutImageUrl: session?.layoutImageUrl };
  });

  app.post('/eb/:ebId/confirm-intelligence', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const access = await checkEbAccess(request.user!.sub, request.user!.role, ebId);
    if (!access.ok) return reply.status(access.status).send({ error: 'Forbidden' });

    try {
      return await confirmMissionIntelligence(ebId);
    } catch (e) {
      return reply.status(400).send({ error: (e as Error).message });
    }
  });

  app.put('/eb/:ebId/control-points', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const body = z.object({ points: z.array(controlPointSchema).min(1) }).parse(request.body);
    const access = await checkEbAccess(request.user!.sub, request.user!.role, ebId);
    if (!access.ok) return reply.status(access.status).send({ error: 'Forbidden' });

    return saveControlPoints(ebId, body.points);
  });

  app.put('/eb/:ebId/sketch-boundary', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const body = z.object({
      boundary: z.array(z.object({ x: z.number().min(0).max(1), y: z.number().min(0).max(1) })).min(3),
    }).parse(request.body);
    const access = await checkEbAccess(request.user!.sub, request.user!.role, ebId);
    if (!access.ok) return reply.status(access.status).send({ error: 'Forbidden' });

    return saveSketchBoundary(ebId, body.boundary);
  });

  app.post('/eb/:ebId/compute-transform', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const access = await checkEbAccess(request.user!.sub, request.user!.role, ebId);
    if (!access.ok) return reply.status(access.status).send({ error: 'Forbidden' });

    try {
      const result = await computeTransform(ebId);
      const session = await getLayoutGeorefSession(ebId, false);
      const validation = session ? validateGeoref(session) : null;
      return { ...result, validation };
    } catch (e) {
      return reply.status(400).send({ error: (e as Error).message });
    }
  });

  app.get('/eb/:ebId/validate', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const access = await checkEbAccess(request.user!.sub, request.user!.role, ebId);
    if (!access.ok) return reply.status(access.status).send({ error: 'Forbidden' });

    const session = await getLayoutGeorefSession(ebId, false);
    if (!session) return reply.status(404).send({ error: 'No session' });
    return validateGeoref(session);
  });

  app.post('/eb/:ebId/finalize', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const access = await checkEbAccess(request.user!.sub, request.user!.role, ebId);
    if (!access.ok) return reply.status(access.status).send({ error: 'Forbidden' });

    try {
      return await finalizeGeoref(ebId, request.user!.sub);
    } catch (e) {
      return reply.status(400).send({ error: (e as Error).message });
    }
  });

  app.post('/assistant/ask', async (request, reply) => {
    const body = z.object({
      question: z.string().min(1),
      context: z
        .object({
          objectLabel: z.string().optional(),
          objectType: z.string().optional(),
          buildingType: z.string().optional(),
        })
        .optional(),
    }).parse(request.body);
    return askFieldAssistant(body);
  });

  app.post('/eb/:ebId/learning-feedback', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const body = z.object({
      eventType: z.enum([
        'observation_target_confirmed',
        'observation_target_rejected',
        'gap_resolved',
        'gap_false_positive',
        'classification_override',
      ]),
      objectId: z.string().optional(),
      metadata: z.record(z.unknown()).optional(),
    }).parse(request.body);
    const access = await checkEbAccess(request.user!.sub, request.user!.role, ebId);
    if (!access.ok) return reply.status(access.status).send({ error: 'Forbidden' });
    return recordLearningFeedback({ ebId, ...body, metadata: body.metadata ?? {} });
  });

  app.get('/learning/stats', async () => learningEngineStats());
}
