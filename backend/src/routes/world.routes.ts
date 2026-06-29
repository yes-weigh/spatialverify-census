import type { FastifyInstance } from 'fastify';
import { authenticate } from '../services/auth.service.js';
import { projectRepository } from '../repositories/project.repository.js';
import { missionRepository } from '../repositories/mission.repository.js';
import { evidencePipelineService } from '../domains/pipeline/evidence-pipeline.service.js';
import {
  appendEvidenceBodySchema,
  toAppendInput,
} from '../domains/evidence/validator.js';
import type { EvidenceEnvelope } from '../domains/evidence/types.js';

async function checkEbAccess(userId: string, role: string, ebId: string) {
  const block = await missionRepository.findBlockById(ebId);
  if (!block) return { ok: false as const, status: 404 as const };
  const projectId = block.project_id as string;
  if (role !== 'admin' && !(await projectRepository.isUserInProject(userId, projectId))) {
    return { ok: false as const, status: 403 as const };
  }
  return { ok: true as const, block };
}

export async function worldRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', authenticate);

  app.post<{ Params: { ebId: string } }>('/ebs/:ebId/evidence', async (request, reply) => {
    const access = await checkEbAccess(request.user!.sub, request.user!.role, request.params.ebId);
    if (!access.ok) return reply.status(access.status).send({ error: 'Not found or forbidden' });

    const parsed = appendEvidenceBodySchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'Invalid evidence envelope', details: parsed.error.flatten() });
    }

    try {
      const input = toAppendInput(request.params.ebId, parsed.data, request.user!.sub);
      const result = await evidencePipelineService.appendAndProject(input);
      return reply.status(201).send({
        evidence: {
          id: result.evidence.id,
          sequenceNum: result.evidence.sequenceNum,
          hash: result.evidence.hash,
          previousHash: result.evidence.previousHash,
          evidenceType: result.evidence.evidenceType,
          schemaVersion: result.evidence.schemaVersion,
        },
        world: result.world,
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Evidence append failed';
      return reply.status(400).send({ error: message });
    }
  });

  app.get<{ Params: { ebId: string } }>('/ebs/:ebId/world', async (request, reply) => {
    const access = await checkEbAccess(request.user!.sub, request.user!.role, request.params.ebId);
    if (!access.ok) return reply.status(access.status).send({ error: 'Not found or forbidden' });

    const world = await evidencePipelineService.getWorld(request.params.ebId);
    return reply.send(world);
  });

  app.get<{ Params: { ebId: string } }>('/ebs/:ebId/replay', async (request, reply) => {
    const access = await checkEbAccess(request.user!.sub, request.user!.role, request.params.ebId);
    if (!access.ok) return reply.status(access.status).send({ error: 'Not found or forbidden' });

    const replay = await evidencePipelineService.getReplay(request.params.ebId);
    return reply.send(replay);
  });

  app.get<{ Params: { ebId: string } }>('/ebs/:ebId/evidence/integrity', async (request, reply) => {
    const access = await checkEbAccess(request.user!.sub, request.user!.role, request.params.ebId);
    if (!access.ok) return reply.status(access.status).send({ error: 'Not found or forbidden' });

    const integrity = await evidencePipelineService.getEvidenceIntegrity(request.params.ebId);
    return reply.send(integrity);
  });

  app.get<{ Params: { ebId: string } }>('/ebs/:ebId/metrics/flow', async (request, reply) => {
    const access = await checkEbAccess(request.user!.sub, request.user!.role, request.params.ebId);
    if (!access.ok) return reply.status(access.status).send({ error: 'Not found or forbidden' });

    const metrics = await evidencePipelineService.getFlowMetrics(request.params.ebId);
    return reply.send({ missionId: request.params.ebId, metrics });
  });

  app.get<{ Params: { ebId: string } }>('/ebs/:ebId/evidence', async (request, reply) => {
    const access = await checkEbAccess(request.user!.sub, request.user!.role, request.params.ebId);
    if (!access.ok) return reply.status(access.status).send({ error: 'Not found or forbidden' });

    const { evidenceReplay } = await import('../domains/evidence/evidence-replay.js');
    const events = await evidenceReplay.loadVerified(request.params.ebId);
    return reply.send({
      count: events.length,
      chainValid: true,
      events: events.map((e: EvidenceEnvelope) => ({
        id: e.id,
        sequenceNum: e.sequenceNum,
        evidenceType: e.evidenceType,
        schemaVersion: e.schemaVersion,
        hash: e.hash,
        occurredAt: e.occurredAt,
      })),
    });
  });
}
