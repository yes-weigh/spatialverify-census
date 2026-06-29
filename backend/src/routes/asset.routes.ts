import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticate } from '../services/auth.service.js';
import { assetRepository } from '../repositories/asset.repository.js';
import { projectRepository } from '../repositories/project.repository.js';

const createAssetSchema = z.object({
  categoryId: z.string().uuid().optional(),
  name: z.string().min(1),
  description: z.string().optional(),
  geometryType: z.enum(['point', 'line', 'polygon']).default('point'),
  location: z.object({
    type: z.enum(['Point', 'LineString', 'Polygon']),
    coordinates: z.unknown(),
  }),
  altitude: z.number().optional(),
  heading: z.number().optional(),
  metadata: z.record(z.unknown()).optional(),
  clientId: z.string().optional(),
});

export async function assetRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', authenticate);

  async function checkAccess(userId: string, role: string, projectId: string) {
    if (role === 'admin') return true;
    return projectRepository.isUserInProject(userId, projectId);
  }

  app.get('/project/:projectId', async (request, reply) => {
    const { projectId } = request.params as { projectId: string };
    const { status } = request.query as { status?: string };
    const user = request.user!;

    if (!(await checkAccess(user.sub, user.role, projectId))) {
      return reply.status(403).send({ error: 'Forbidden' });
    }

    return assetRepository.listByProject(
      projectId,
      status as 'verified' | 'pending' | 'rejected' | 'not_surveyed' | undefined
    );
  });

  app.get('/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const asset = await assetRepository.findById(id);
    if (!asset) return reply.status(404).send({ error: 'Asset not found' });

    const user = request.user!;
    if (!(await checkAccess(user.sub, user.role, asset.project_id))) {
      return reply.status(403).send({ error: 'Forbidden' });
    }
    return asset;
  });

  app.post('/project/:projectId', async (request, reply) => {
    const { projectId } = request.params as { projectId: string };
    const user = request.user!;
    if (!(await checkAccess(user.sub, user.role, projectId))) {
      return reply.status(403).send({ error: 'Forbidden' });
    }

    const body = createAssetSchema.parse(request.body);
    return assetRepository.create({
      projectId,
      categoryId: body.categoryId,
      name: body.name,
      description: body.description,
      geometryType: body.geometryType,
      location: body.location as GeoJSON.Geometry,
      altitude: body.altitude,
      heading: body.heading,
      metadata: body.metadata,
      createdBy: user.sub,
      clientId: body.clientId,
    });
  });

  app.get('/project/:projectId/search/radius', async (request, reply) => {
    const { projectId } = request.params as { projectId: string };
    const { lng, lat, radius, status } = request.query as {
      lng: string; lat: string; radius: string; status?: string;
    };
    const user = request.user!;
    if (!(await checkAccess(user.sub, user.role, projectId))) {
      return reply.status(403).send({ error: 'Forbidden' });
    }
    return assetRepository.searchRadius(
      projectId, parseFloat(lng), parseFloat(lat), parseFloat(radius),
      status as 'verified' | 'pending' | 'rejected' | 'not_surveyed' | undefined
    );
  });

  app.get('/project/:projectId/search/bbox', async (request, reply) => {
    const { projectId } = request.params as { projectId: string };
    const { minLng, minLat, maxLng, maxLat, status } = request.query as {
      minLng: string; minLat: string; maxLng: string; maxLat: string; status?: string;
    };
    const user = request.user!;
    if (!(await checkAccess(user.sub, user.role, projectId))) {
      return reply.status(403).send({ error: 'Forbidden' });
    }
    return assetRepository.searchBbox(
      projectId,
      parseFloat(minLng), parseFloat(minLat),
      parseFloat(maxLng), parseFloat(maxLat),
      status as 'verified' | 'pending' | 'rejected' | 'not_surveyed' | undefined
    );
  });

  app.get('/project/:projectId/nearby', async (request, reply) => {
    const { projectId } = request.params as { projectId: string };
    const { lng, lat, limit } = request.query as { lng: string; lat: string; limit?: string };
    const user = request.user!;
    if (!(await checkAccess(user.sub, user.role, projectId))) {
      return reply.status(403).send({ error: 'Forbidden' });
    }
    return assetRepository.nearby(projectId, parseFloat(lng), parseFloat(lat), limit ? parseInt(limit, 10) : 20);
  });

  app.get('/project/:projectId/geofence', async (request, reply) => {
    const { projectId } = request.params as { projectId: string };
    const { lng, lat } = request.query as { lng: string; lat: string };
    const inside = await assetRepository.isInsideGeofence(projectId, parseFloat(lng), parseFloat(lat));
    return { inside };
  });
}
