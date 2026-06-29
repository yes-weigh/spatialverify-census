import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticate, requireRole } from '../services/auth.service.js';
import { projectRepository } from '../repositories/project.repository.js';
import {
  getHlbBoundary,
  getHlbBoundaryMission,
  getHlbBoundaryMissionByEbId,
  importHlbBoundary,
  listHlbBoundaries,
  recordBoundaryAuditEvent,
} from '../services/hlb-boundary.service.js';
import { hlbBoundaryRepository } from '../repositories/hlb-boundary.repository.js';

const geoJsonPolygonSchema = z.object({
  type: z.literal('Polygon'),
  coordinates: z.array(z.array(z.tuple([z.number(), z.number()]))),
});

const importSchema = z.object({
  projectId: z.string().uuid(),
  hlbCode: z.string().min(1).max(20),
  name: z.string().optional(),
  boundary: geoJsonPolygonSchema.optional(),
  wkt: z.string().optional(),
  northDescription: z.string().optional(),
  southDescription: z.string().optional(),
  eastDescription: z.string().optional(),
  westDescription: z.string().optional(),
  assignedEnumeratorId: z.string().uuid().optional(),
}).refine((d) => d.boundary || d.wkt, { message: 'boundary or wkt required' });

const auditEventSchema = z.object({
  event: z.enum(['entered', 'left', 'start_reached', 'discovery_started']),
});

export async function hlbBoundaryRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', authenticate);

  app.get('/', async (request) => {
    const { projectId } = request.query as { projectId?: string };
    if (projectId) {
      const user = request.user!;
      if (user.role !== 'admin') {
        const ok = await projectRepository.isUserInProject(user.sub, projectId);
        if (!ok) return { error: 'Forbidden' };
      }
    }
    return listHlbBoundaries(projectId);
  });

  app.get('/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const boundary = await getHlbBoundary(id);
    if (!boundary) return reply.status(404).send({ error: 'HLB boundary not found' });
    return boundary;
  });

  app.get('/:id/mission', async (request, reply) => {
    const { id } = request.params as { id: string };
    const pkg = await getHlbBoundaryMission(id);
    if (!pkg) return reply.status(404).send({ error: 'HLB mission not found' });
    return pkg;
  });

  app.get('/by-eb/:ebId/mission', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const pkg = await getHlbBoundaryMissionByEbId(ebId);
    if (!pkg) return reply.status(404).send({ error: 'No official boundary for this HLB' });
    return pkg;
  });

  app.post('/import', { preHandler: requireRole('admin') }, async (request) => {
    const body = importSchema.parse(request.body);
    return importHlbBoundary({
      ...body,
      createdBy: request.user!.sub,
    });
  });

  app.post('/eb/:ebId/audit', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const body = auditEventSchema.parse(request.body);
    const block = await hlbBoundaryRepository.findByEbId(ebId);
    if (!block) return reply.status(404).send({ error: 'No official boundary for this HLB' });
    await recordBoundaryAuditEvent(ebId, body.event, request.user!.sub);
    return { ok: true };
  });

  app.post('/eb/:ebId/outside-discovery', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const body = z.object({
      latitude: z.number(),
      longitude: z.number(),
      label: z.string(),
      overridden: z.boolean(),
    }).parse(request.body);
    const block = await hlbBoundaryRepository.findByEbId(ebId);
    if (!block) return reply.status(404).send({ error: 'No official boundary for this HLB' });
    await hlbBoundaryRepository.appendOutsideDiscovery(ebId, body);
    return { ok: true };
  });
}
