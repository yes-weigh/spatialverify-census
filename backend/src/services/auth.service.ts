import type { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { userRepository, UserRepository } from '../repositories/user.repository.js';
import { refreshTokenRepository } from '../repositories/refresh-token.repository.js';
import { env } from '../config/env.js';
import type { JwtPayload, UserRole } from '../types/index.js';

function parseExpiry(expiry: string): number {
  const match = expiry.match(/^(\d+)([smhd])$/);
  if (!match) return 900;
  const value = parseInt(match[1], 10);
  const unit = match[2];
  const multipliers: Record<string, number> = { s: 1, m: 60, h: 3600, d: 86400 };
  return value * (multipliers[unit] ?? 60);
}

export class AuthService {
  async login(
    app: FastifyInstance,
    email: string,
    password: string,
    deviceId: string
  ) {
    const user = await userRepository.findByEmail(email);
    if (!user) {
      throw new Error('Invalid credentials');
    }

    const valid = await userRepository.verifyPassword(user.password_hash, password);
    if (!valid) {
      throw new Error('Invalid credentials');
    }

    await userRepository.updateDeviceId(user.id, deviceId);

    const payload: JwtPayload = {
      sub: user.id,
      email: user.email,
      role: user.role,
      deviceId,
    };

    const accessToken = app.jwt.sign(payload, { expiresIn: env.jwtAccessExpiry });
    const refreshToken = UserRepository.generateToken();

    const expiresAt = new Date(Date.now() + parseExpiry(env.jwtRefreshExpiry) * 1000);
    await refreshTokenRepository.create(user.id, refreshToken, deviceId, expiresAt);

    return {
      accessToken,
      refreshToken,
      expiresIn: parseExpiry(env.jwtAccessExpiry),
      user: {
        id: user.id,
        email: user.email,
        firstName: user.first_name,
        lastName: user.last_name,
        role: user.role,
      },
    };
  }

  async refresh(app: FastifyInstance, refreshToken: string) {
    const tokenData = await refreshTokenRepository.findValid(refreshToken);
    if (!tokenData) {
      throw new Error('Invalid refresh token');
    }

    const user = await userRepository.findById(tokenData.user_id);
    if (!user) {
      throw new Error('User not found');
    }

    const payload: JwtPayload = {
      sub: user.id,
      email: user.email,
      role: user.role,
      deviceId: tokenData.device_id,
    };

    const accessToken = app.jwt.sign(payload, { expiresIn: env.jwtAccessExpiry });

    await refreshTokenRepository.revoke(refreshToken);
    const newRefreshToken = UserRepository.generateToken();
    const expiresAt = new Date(Date.now() + parseExpiry(env.jwtRefreshExpiry) * 1000);
    await refreshTokenRepository.create(user.id, newRefreshToken, tokenData.device_id, expiresAt);

    return {
      accessToken,
      refreshToken: newRefreshToken,
      expiresIn: parseExpiry(env.jwtAccessExpiry),
    };
  }

  async logout(refreshToken: string, userId: string, deviceId: string) {
    await refreshTokenRepository.revoke(refreshToken);
    await refreshTokenRepository.revokeForDevice(userId, deviceId);
  }

  async requestPasswordReset(email: string): Promise<string | null> {
    const token = UserRepository.generateToken();
    const expiresAt = new Date(Date.now() + 3600000);
    const updated = await userRepository.setPasswordResetToken(email, token, expiresAt);
    return updated ? token : null;
  }

  async resetPassword(token: string, newPassword: string): Promise<boolean> {
    return userRepository.resetPassword(token, newPassword);
  }
}

export const authService = new AuthService();

export async function authenticate(
  request: FastifyRequest,
  reply: FastifyReply
): Promise<void> {
  try {
    const payload = await request.jwtVerify<JwtPayload>();
    request.user = payload;
  } catch {
    reply.status(401).send({ error: 'Unauthorized' });
  }
}

export function requireRole(...roles: UserRole[]) {
  return async (request: FastifyRequest, reply: FastifyReply): Promise<void> => {
    if (!request.user) {
      reply.status(401).send({ error: 'Unauthorized' });
      return;
    }
    if (!roles.includes(request.user.role)) {
      reply.status(403).send({ error: 'Forbidden' });
    }
  };
}
