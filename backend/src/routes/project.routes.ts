import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticate, requireRole } from '../services/auth.service.js';
import { projectRepository } from '../repositories/project.repository.js';
import { auditLogRepository } from '../repositories/survey.repository.js';

const createProjectSchema = z.object({
  name: z.string().min(1).max(255),
  description: z.string().optional(),
  boundary: z.object({
    type: z.literal('Polygon'),
    coordinates: z.array(z.array(z.tuple([z.number(), z.number()]))),
  }).optional(),
  surveyRules: z.record(z.unknown()).optional(),
});

const createCategorySchema = z.object({
  name: z.string().min(1),
  description: z.string().optional(),
  detectionLabels: z.array(z.string()).default([]),
  icon: z.string().optional(),
  color: z.string().optional(),
});

export async function projectRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', authenticate);

  app.get('/', async (request) => {
    const user = request.user!;
    return projectRepository.list(user.sub, user.role);
  });

  app.get('/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const user = request.user!;

    if (user.role !== 'admin') {
      const hasAccess = await projectRepository.isUserInProject(user.sub, id);
      if (!hasAccess) {
        return reply.status(403).send({ error: 'Forbidden' });
      }
    }

    const project = await projectRepository.findById(id);
    if (!project) {
      return reply.status(404).send({ error: 'Project not found' });
    }
    return project;
  });

  app.post('/', { preHandler: requireRole('admin') }, async (request) => {
    const body = createProjectSchema.parse(request.body);
    const project = await projectRepository.create({
      name: body.name,
      description: body.description,
      boundary: body.boundary,
      surveyRules: body.surveyRules,
      createdBy: request.user!.sub,
    });
    await auditLogRepository.log({
      userId: request.user!.sub,
      action: 'create',
      entityType: 'project',
      entityId: project.id,
    });
    return project;
  });

  app.patch('/:id', { preHandler: requireRole('admin') }, async (request, reply) => {
    const { id } = request.params as { id: string };
    const body = createProjectSchema.partial().parse(request.body);
    const project = await projectRepository.update(id, {
      name: body.name,
      description: body.description,
      boundary: body.boundary,
      surveyRules: body.surveyRules,
    });
    if (!project) {
      return reply.status(404).send({ error: 'Project not found' });
    }
    return project;
  });

  app.get('/:id/categories', async (request, reply) => {
    const { id } = request.params as { id: string };
    const user = request.user!;
    if (user.role !== 'admin') {
      const hasAccess = await projectRepository.isUserInProject(user.sub, id);
      if (!hasAccess) return reply.status(403).send({ error: 'Forbidden' });
    }
    return projectRepository.getAssetCategories(id);
  });

  app.post('/:id/categories', { preHandler: requireRole('admin', 'supervisor') }, async (request, reply) => {
    const { id } = request.params as { id: string };
    const body = createCategorySchema.parse(request.body);
    const { query } = await import('../db/pool.js');
    const { rows } = await query(
      `INSERT INTO asset_categories (project_id, name, description, detection_labels, icon, color)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
      [id, body.name, body.description ?? null, JSON.stringify(body.detectionLabels), body.icon ?? null, body.color ?? null]
    );
    return rows[0];
  });

  app.get('/:id/teams', async (request, reply) => {
    const { id } = request.params as { id: string };
    const user = request.user!;
    if (user.role !== 'admin') {
      const hasAccess = await projectRepository.isUserInProject(user.sub, id);
      if (!hasAccess) return reply.status(403).send({ error: 'Forbidden' });
    }
    return projectRepository.getTeams(id);
  });
}
