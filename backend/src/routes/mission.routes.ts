import type { FastifyInstance } from 'fastify';
import multipart from '@fastify/multipart';
import { z } from 'zod';
import { authenticate } from '../services/auth.service.js';
import { projectRepository } from '../repositories/project.repository.js';
import { missionRepository } from '../repositories/mission.repository.js';
import { missionService } from '../services/mission.service.js';
import { storageService } from '../services/storage.service.js';

const mapPointSchema = z.object({ x: z.number().min(0).max(1), y: z.number().min(0).max(1) });

const savePlanSchema = z.object({
  boundaryMap: z.array(mapPointSchema).default([]),
  northBearing: z.number().optional(),
  routeBuildingIds: z.array(z.string().uuid()).optional(),
  buildings: z.array(z.object({
    id: z.string().uuid().optional(),
    buildingNumber: z.number().int().positive(),
    censusHouseCount: z.number().int().positive().default(1),
    buildingType: z.enum([
      'pucca_residential', 'non_residential_pucca',
      'kutcha_residential', 'kutcha_non_residential',
    ]),
    mapX: z.number().min(0).max(1),
    mapY: z.number().min(0).max(1),
    latitude: z.number().optional(),
    longitude: z.number().optional(),
    routeSequence: z.number().int().optional(),
  })),
  landmarks: z.array(z.object({
    id: z.string().uuid().optional(),
    name: z.string().min(1),
    landmarkType: z.enum([
      'school', 'temple', 'mosque', 'church', 'hospital',
      'panchayat_office', 'park', 'pond', 'river', 'other',
    ]).default('other'),
    mapX: z.number().min(0).max(1),
    mapY: z.number().min(0).max(1),
  })).default([]),
});

async function checkProjectAccess(userId: string, role: string, projectId: string) {
  if (role === 'admin') return true;
  return projectRepository.isUserInProject(userId, projectId);
}

async function getBlockProjectId(ebId: string): Promise<string | null> {
  const block = await missionRepository.findBlockById(ebId);
  return block?.project_id as string ?? null;
}

export async function missionRoutes(app: FastifyInstance): Promise<void> {
  await app.register(multipart, { limits: { fileSize: 25 * 1024 * 1024 } });
  app.addHook('preHandler', authenticate);

  // List EBs for project
  app.get('/projects/:projectId/ebs', async (request, reply) => {
    const { projectId } = request.params as { projectId: string };
    const user = request.user!;

    if (!(await checkProjectAccess(user.sub, user.role, projectId))) {
      return reply.status(403).send({ error: 'Forbidden' });
    }

    const blocks = await missionRepository.listBlocks(projectId, user.sub);
    return blocks;
  });

  // Create personal mission (EB)
  app.post('/projects/:projectId/ebs', async (request, reply) => {
    const { projectId } = request.params as { projectId: string };
    const body = z.object({
      ebCode: z.string().min(1).max(20),
      name: z.string().optional(),
    }).parse(request.body);

    if (!(await checkProjectAccess(request.user!.sub, request.user!.role, projectId))) {
      return reply.status(403).send({ error: 'Forbidden' });
    }

    const block = await missionRepository.createBlock({
      projectId,
      ebCode: body.ebCode,
      name: body.name,
      createdBy: request.user!.sub,
    });
    return block;
  });

  // Upload layout map image/PDF page as image
  app.post('/ebs/:ebId/layout-upload', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const projectId = await getBlockProjectId(ebId);
    if (!projectId) return reply.status(404).send({ error: 'EB not found' });

    if (!(await checkProjectAccess(request.user!.sub, request.user!.role, projectId))) {
      return reply.status(403).send({ error: 'Forbidden' });
    }

    const file = await request.file();
    if (!file) return reply.status(400).send({ error: 'No file uploaded' });

    const buffer = await file.toBuffer();
    const mime = file.mimetype || 'image/jpeg';
    const key = storageService.generateKey(`layout-maps/${ebId}`, file.filename || 'layout.jpg');

    await storageService.upload(key, buffer, mime);
    const block = await missionRepository.updateLayoutImage(ebId, key, mime);
    const layoutImageUrl = await missionService.getLayoutImageUrl(key);

    return { block, layoutImageUrl };
  });

  // Get full mission plan
  app.get('/ebs/:ebId', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const plan = await missionService.getFullPlan(ebId);
    if (!plan) return reply.status(404).send({ error: 'EB not found' });

    const projectId = plan.block.project_id as string;
    if (!(await checkProjectAccess(request.user!.sub, request.user!.role, projectId))) {
      return reply.status(403).send({ error: 'Forbidden' });
    }

    return plan;
  });

  // Save mission plan (layout map editor)
  app.put('/ebs/:ebId/plan', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const projectId = await getBlockProjectId(ebId);
    if (!projectId) return reply.status(404).send({ error: 'EB not found' });

    if (!(await checkProjectAccess(request.user!.sub, request.user!.role, projectId))) {
      return reply.status(403).send({ error: 'Forbidden' });
    }

    const plan = savePlanSchema.parse(request.body);
    await missionService.savePlan(ebId, plan);
    return missionService.getFullPlan(ebId);
  });

  // Start mission (was publish — no supervisor gate)
  app.post('/ebs/:ebId/start', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const projectId = await getBlockProjectId(ebId);
    if (!projectId) return reply.status(404).send({ error: 'EB not found' });

    const stats = await missionRepository.getBuildingStats(ebId);
    if ((stats.total as number) === 0) {
      return reply.status(400).send({ error: 'Add buildings to the layout map before starting' });
    }

    const block = await missionRepository.updateBlockMeta(ebId, { status: 'published' });
    return block;
  });

  // Legacy alias
  app.post('/ebs/:ebId/publish', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const stats = await missionRepository.getBuildingStats(ebId);
    if ((stats.total as number) === 0) {
      return reply.status(400).send({ error: 'Add buildings to the layout map before starting' });
    }
    const block = await missionRepository.updateBlockMeta(ebId, { status: 'published' });
    return block;
  });

  // Mission dashboard (GPS-aware next building)
  app.get('/ebs/:ebId/dashboard', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const query = z.object({
      lat: z.coerce.number().optional(),
      lng: z.coerce.number().optional(),
    }).parse(request.query);

    const dashboard = await missionService.getDashboard(ebId, query.lat, query.lng);
    if (!dashboard) return reply.status(404).send({ error: 'EB not found' });
    return dashboard;
  });

  // End-of-day review with ETA
  app.get('/ebs/:ebId/day-review', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const query = z.object({
      lat: z.coerce.number().optional(),
      lng: z.coerce.number().optional(),
    }).parse(request.query);

    const review = await missionService.getDayReview(ebId, query.lat, query.lng);
    if (!review) return reply.status(404).send({ error: 'EB not found' });
    return review;
  });

  // Route list
  app.get('/ebs/:ebId/route', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const route = await missionService.getRouteList(ebId);
    return { buildings: route };
  });

  // Update building status
  app.patch('/buildings/:buildingId/status', async (request, reply) => {
    const { buildingId } = request.params as { buildingId: string };
    const body = z.object({
      status: z.enum(['not_visited', 'visited', 'completed', 'revisit_required']),
      notes: z.string().optional(),
      assetId: z.string().uuid().optional(),
      latitude: z.number().optional(),
      longitude: z.number().optional(),
    }).parse(request.body);

    const building = await missionRepository.getBuildingById(buildingId);
    if (!building) return reply.status(404).send({ error: 'Building not found' });

    const projectId = await getBlockProjectId(building.eb_id as string);
    if (!projectId || !(await checkProjectAccess(request.user!.sub, request.user!.role, projectId))) {
      return reply.status(403).send({ error: 'Forbidden' });
    }

    const updated = await missionRepository.updateBuildingStatus(
      buildingId,
      body.status,
      request.user!.sub,
      body.notes,
      body.assetId,
      body.latitude,
      body.longitude,
    );

    if (body.status === 'completed') {
      await missionService.recordTravelOnComplete(
        building.eb_id as string,
        buildingId,
        request.user!.sub,
        body.latitude,
        body.longitude,
      );
    }

    return updated;
  });

  // GPS breadcrumb
  app.post('/ebs/:ebId/breadcrumbs', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const body = z.object({
      latitude: z.number(),
      longitude: z.number(),
      accuracy: z.number().optional(),
    }).parse(request.body);

    const projectId = await getBlockProjectId(ebId);
    if (!projectId || !(await checkProjectAccess(request.user!.sub, request.user!.role, projectId))) {
      return reply.status(403).send({ error: 'Forbidden' });
    }

    const crumb = await missionRepository.addBreadcrumb(
      ebId,
      request.user!.sub,
      body.latitude,
      body.longitude,
      body.accuracy
    );
    return crumb;
  });

  app.get('/ebs/:ebId/breadcrumbs', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const crumbs = await missionRepository.getBreadcrumbs(ebId);
    return crumbs;
  });

  // Coverage analysis
  app.get('/ebs/:ebId/coverage', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const coverage = await missionService.analyzeCoverage(ebId);
    if (!coverage) return reply.status(404).send({ error: 'EB not found' });
    return coverage;
  });

  app.get('/ebs/:ebId/offline-snapshot', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const { getOfflineSnapshot } = await import('../services/offline-snapshot.service.js');
    const snapshot = await getOfflineSnapshot(ebId);
    if (!snapshot) return reply.status(404).send({ error: 'EB not found' });
    return snapshot;
  });

  // HLB discovery status
  app.get('/ebs/:ebId/discovery', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const discovery = await missionService.getDiscovery(ebId);
    if (!discovery) return reply.status(404).send({ error: 'EB not found' });
    return discovery;
  });

  app.get('/ebs/:ebId/draft-map', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const map = await missionService.getDraftMap(ebId);
    if (!map) return reply.status(404).send({ error: 'EB not found' });
    return map;
  });

  app.get('/ebs/:ebId/suggest-number', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const query = z.object({ lat: z.coerce.number(), lng: z.coerce.number() }).parse(request.query);
    return missionService.suggestSerpentineNumber(ebId, query.lat, query.lng);
  });

  app.get('/ebs/:ebId/gaps', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const query = z.object({ lat: z.coerce.number().optional(), lng: z.coerce.number().optional() }).parse(request.query);
    const gaps = await missionService.getCoverageGaps(ebId, query.lat, query.lng);
    if (!gaps) return reply.status(404).send({ error: 'EB not found' });
    return gaps;
  });

  app.post('/ebs/:ebId/gaps/:gapId/resolve', async (request, reply) => {
    const { ebId, gapId } = request.params as { ebId: string; gapId: string };
    const body = z.object({
      resolution: z.enum(['building_found', 'no_building', 'not_accessible', 'investigated']),
      notes: z.string().optional(),
      gapType: z.string(),
      gapReason: z.string(),
      latitude: z.number().optional(),
      longitude: z.number().optional(),
      resolvedLatitude: z.number().optional(),
      resolvedLongitude: z.number().optional(),
    }).parse(request.body);

    const projectId = await getBlockProjectId(ebId);
    if (!projectId || !(await checkProjectAccess(request.user!.sub, request.user!.role, projectId))) {
      return reply.status(403).send({ error: 'Forbidden' });
    }

    const result = await missionService.resolveCoverageGap(ebId, decodeURIComponent(gapId), request.user!.sub, body);
    return result;
  });

  app.get('/ebs/:ebId/validate', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const discovery = await missionService.getDiscovery(ebId);
    if (!discovery) return reply.status(404).send({ error: 'EB not found' });
    const canFinalize =
      discovery.boundaryClosed &&
      discovery.buildingsDiscovered > 0 &&
      discovery.gapSummary.highPriority === 0;
    return {
      canFinalize,
      warnings: discovery.zeroExclusionWarnings,
      coverageGaps: discovery.coverageGaps,
      gapSummary: discovery.gapSummary,
      numberingIssues: discovery.numberingIssues,
    };
  });

  // Ground-truth: confirm building at GPS
  app.post('/ebs/:ebId/buildings/discover', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const body = z.object({
      latitude: z.number(),
      longitude: z.number(),
      buildingType: z.enum([
        'pucca_residential', 'non_residential_pucca',
        'kutcha_residential', 'kutcha_non_residential',
      ]).default('pucca_residential'),
      censusHouseCount: z.number().int().positive().optional(),
      buildingNumber: z.number().int().positive().optional(),
    }).parse(request.body);

    const projectId = await getBlockProjectId(ebId);
    if (!projectId || !(await checkProjectAccess(request.user!.sub, request.user!.role, projectId))) {
      return reply.status(403).send({ error: 'Forbidden' });
    }

    const building = await missionService.discoverBuilding(ebId, body);
    return building;
  });

  // Ground-truth: boundary vertex while walking HLB perimeter
  app.post('/ebs/:ebId/boundary-vertices', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const body = z.object({
      latitude: z.number(),
      longitude: z.number(),
    }).parse(request.body);

    const projectId = await getBlockProjectId(ebId);
    if (!projectId || !(await checkProjectAccess(request.user!.sub, request.user!.role, projectId))) {
      return reply.status(403).send({ error: 'Forbidden' });
    }

    return missionRepository.addBoundaryVertex(ebId, body.latitude, body.longitude);
  });

  // Ground-truth: landmark discovery
  app.post('/ebs/:ebId/landmarks/discover', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const body = z.object({
      name: z.string().min(1),
      landmarkType: z.enum([
        'school', 'temple', 'mosque', 'church', 'hospital',
        'panchayat_office', 'park', 'pond', 'river', 'other',
      ]).default('other'),
      latitude: z.number(),
      longitude: z.number(),
    }).parse(request.body);

    const projectId = await getBlockProjectId(ebId);
    if (!projectId || !(await checkProjectAccess(request.user!.sub, request.user!.role, projectId))) {
      return reply.status(403).send({ error: 'Forbidden' });
    }

    return missionService.discoverLandmark(ebId, body);
  });

  // Finalize draft HLB map → start house listing
  app.post('/ebs/:ebId/finalize-draft', async (request, reply) => {
    const { ebId } = request.params as { ebId: string };
    const projectId = await getBlockProjectId(ebId);
    if (!projectId || !(await checkProjectAccess(request.user!.sub, request.user!.role, projectId))) {
      return reply.status(403).send({ error: 'Forbidden' });
    }

    try {
      const block = await missionService.finalizeDraftMap(ebId);
      return block;
    } catch (err) {
      return reply.status(400).send({ error: (err as Error).message });
    }
  });
}
