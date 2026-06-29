import type { JwtPayload } from '../types/index.js';

declare module '@fastify/jwt' {
  interface FastifyJWT {
    payload: JwtPayload;
    user: JwtPayload;
  }
}

declare module 'fastify' {
  interface FastifyRequest {
    user: JwtPayload;
  }
}

export function getAuthUser(request: { user: JwtPayload }): JwtPayload {
  return request.user;
}
