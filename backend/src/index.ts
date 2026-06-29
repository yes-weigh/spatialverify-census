import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import jwt from '@fastify/jwt';
import websocket from '@fastify/websocket';
import { env } from './config/env.js';
import { checkDatabaseHealth } from './db/pool.js';
import { authRoutes } from './routes/auth.routes.js';
import { projectRoutes } from './routes/project.routes.js';
import { assetRoutes } from './routes/asset.routes.js';
import { detectionRoutes } from './routes/detection.routes.js';
import { surveyRoutes } from './routes/survey.routes.js';
import { identityRoutes } from './routes/identity.routes.js';
import { missionRoutes } from './routes/mission.routes.js';
import { hlbBoundaryRoutes } from './routes/hlb-boundary.routes.js';
import { layoutGeorefRoutes } from './routes/layout-georef.routes.js';
import { worldRoutes } from './routes/world.routes.js';
import { setupWebSocket } from './websocket/handler.js';

const app = Fastify({
  logger: {
    level: env.isDev ? 'info' : 'warn',
  },
});

async function build() {
  await app.register(helmet, { contentSecurityPolicy: false });
  await app.register(cors, { origin: env.corsOrigin });
  await app.register(rateLimit, {
    max: env.rateLimitMax,
    timeWindow: env.rateLimitWindowMs,
  });
  await app.register(jwt, {
    secret: env.jwtSecret,
  });
  await app.register(websocket);

  app.get('/health', async () => {
    const dbHealthy = await checkDatabaseHealth();
    return {
      status: dbHealthy ? 'healthy' : 'degraded',
      timestamp: new Date().toISOString(),
      services: { database: dbHealthy },
    };
  });

  await app.register(authRoutes, { prefix: '/api/v1/auth' });
  await app.register(projectRoutes, { prefix: '/api/v1/projects' });
  await app.register(assetRoutes, { prefix: '/api/v1/assets' });
  await app.register(detectionRoutes, { prefix: '/api/v1/detections' });
  await app.register(surveyRoutes, { prefix: '/api/v1/survey' });
  await app.register(identityRoutes, { prefix: '/api/v1/identity' });
  await app.register(missionRoutes, { prefix: '/api/v1/mission' });
  await app.register(hlbBoundaryRoutes, { prefix: '/api/v1/hlb-boundaries' });
  await app.register(layoutGeorefRoutes, { prefix: '/api/v1/layout-georef' });
  await app.register(worldRoutes, { prefix: '/api/v1/mission' });

  setupWebSocket(app);

  return app;
}

async function start() {
  try {
    const server = await build();
    await server.listen({ port: env.port, host: '0.0.0.0' });
    console.log(`SpatialVerify API running on port ${env.port}`);
  } catch (error) {
    console.error('Failed to start server:', error);
    process.exit(1);
  }
}

start();

export { build };
