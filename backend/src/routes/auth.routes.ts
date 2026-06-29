import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { env } from '../config/env.js';
import { authService, authenticate } from '../services/auth.service.js';
import { auditLogRepository } from '../repositories/survey.repository.js';

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  deviceId: z.string().min(1),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(1),
});

const resetRequestSchema = z.object({
  email: z.string().email(),
});

const resetPasswordSchema = z.object({
  token: z.string().min(1),
  password: z.string().min(8),
});

export async function authRoutes(app: FastifyInstance): Promise<void> {
  app.post('/login', async (request, reply) => {
    const body = loginSchema.parse(request.body);
    try {
      const result = await authService.login(app, body.email, body.password, body.deviceId);
      await auditLogRepository.log({
        userId: result.user.id,
        action: 'login',
        ipAddress: request.ip,
        userAgent: request.headers['user-agent'],
      });
      return result;
    } catch {
      return reply.status(401).send({ error: 'Invalid credentials' });
    }
  });

  app.post('/refresh', async (request, reply) => {
    const body = refreshSchema.parse(request.body);
    try {
      return await authService.refresh(app, body.refreshToken);
    } catch {
      return reply.status(401).send({ error: 'Invalid refresh token' });
    }
  });

  app.post('/logout', { preHandler: authenticate }, async (request, reply) => {
    const body = refreshSchema.parse(request.body);
    const user = request.user!;
    await authService.logout(body.refreshToken, user.sub, user.deviceId);
    await auditLogRepository.log({
      userId: user.sub,
      action: 'logout',
      ipAddress: request.ip,
    });
    return { success: true };
  });

  app.post('/password-reset/request', async (request, reply) => {
    const body = resetRequestSchema.parse(request.body);
    const token = await authService.requestPasswordReset(body.email);
    if (env.isDev && token) {
      return { message: 'Reset token generated', token };
    }
    return { message: 'If the email exists, a reset link has been sent' };
  });

  app.post('/password-reset/confirm', async (request, reply) => {
    const body = resetPasswordSchema.parse(request.body);
    const success = await authService.resetPassword(body.token, body.password);
    if (!success) {
      return reply.status(400).send({ error: 'Invalid or expired token' });
    }
    return { message: 'Password reset successful' };
  });

  app.get('/me', { preHandler: authenticate }, async (request) => {
    const { userRepository } = await import('../repositories/user.repository.js');
    const user = await userRepository.findById(request.user!.sub);
    if (!user) {
      return { error: 'User not found' };
    }
    return {
      id: user.id,
      email: user.email,
      firstName: user.first_name,
      lastName: user.last_name,
      role: user.role,
    };
  });
}
