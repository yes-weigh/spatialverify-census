import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticate } from '../services/auth.service.js';
import { detectionRepository } from '../repositories/detection.repository.js';
import { verificationService } from '../services/verification.service.js';
import { projectRepository } from '../repositories/project.repository.js';
import { EMBEDDING_DIMENSION } from '../types/identity.js';

const createDetectionSchema = z.object({
  sessionId: z.string().uuid().optional(),
  categoryLabel: z.string().min(1),
  confidence: z.number().min(0).max(1),
  boundingBox: z.object({
    x: z.number(), y: z.number(), width: z.number(), height: z.number(),
  }),
  location: z.object({
    type: z.literal('Point'),
    coordinates: z.tuple([z.number(), z.number()]),
  }).optional(),
  altitude: z.number().optional(),
  heading: z.number().optional(),
  aiModel: z.string().default('yolov8'),
  clientId: z.string().optional(),
});

const verifySchema = z.object({
  humanDecision: z.enum(['confirmed', 'rejected', 'edited']),
  editedCategory: z.string().optional(),
  editedLocation: z.object({
    type: z.literal('Point'),
    coordinates: z.tuple([z.number(), z.number()]),
  }).optional(),
  notes: z.string().optional(),
  clientId: z.string().optional(),
  matchedAssetId: z.string().uuid().optional(),
  identityResolutionId: z.string().uuid().optional(),
  embedding: z.array(z.number()).length(EMBEDDING_DIMENSION).optional(),
});

export async function detectionRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', authenticate);

  app.get('/project/:projectId', async (request, reply) => {
    const { projectId } = request.params as { projectId: string };
    const { sessionId } = request.query as { sessionId?: string };
    const user = request.user!;
    if (user.role !== 'admin') {
      const hasAccess = await projectRepository.isUserInProject(user.sub, projectId);
      if (!hasAccess) return reply.status(403).send({ error: 'Forbidden' });
    }
    return detectionRepository.listByProject(projectId, sessionId);
  });

  app.post('/project/:projectId', async (request, reply) => {
    const { projectId } = request.params as { projectId: string };
    const user = request.user!;
    if (user.role !== 'admin') {
      const hasAccess = await projectRepository.isUserInProject(user.sub, projectId);
      if (!hasAccess) return reply.status(403).send({ error: 'Forbidden' });
    }

    const body = createDetectionSchema.parse(request.body);
    return detectionRepository.create({
      projectId,
      sessionId: body.sessionId,
      categoryLabel: body.categoryLabel,
      confidence: body.confidence,
      boundingBox: body.boundingBox,
      location: body.location,
      altitude: body.altitude,
      heading: body.heading,
      aiModel: body.aiModel,
      createdBy: user.sub,
      clientId: body.clientId,
    });
  });

  app.post('/:id/verify', async (request, reply) => {
    const { id } = request.params as { id: string };
    const body = verifySchema.parse(request.body);
    const user = request.user!;

    const detection = await detectionRepository.findById(id);
    if (!detection) return reply.status(404).send({ error: 'Detection not found' });

    try {
      const result = await verificationService.processVerification({
        detectionId: id,
        humanDecision: body.humanDecision,
        editedCategory: body.editedCategory,
        editedLocation: body.editedLocation,
        notes: body.notes,
        verifiedBy: user.sub,
        projectId: detection.project_id,
        clientId: body.clientId,
        matchedAssetId: body.matchedAssetId,
        identityResolutionId: body.identityResolutionId,
        embedding: body.embedding,
      });
      return result;
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Verification failed';
      return reply.status(400).send({ error: message });
    }
  });
}
