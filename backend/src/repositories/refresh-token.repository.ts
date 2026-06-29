import { createHash } from 'crypto';
import { query } from '../db/pool.js';

export class RefreshTokenRepository {
  async create(userId: string, token: string, deviceId: string, expiresAt: Date): Promise<void> {
    const tokenHash = createHash('sha256').update(token).digest('hex');
    await query(
      'INSERT INTO refresh_tokens (user_id, token_hash, device_id, expires_at) VALUES ($1, $2, $3, $4)',
      [userId, tokenHash, deviceId, expiresAt.toISOString()]
    );
  }

  async findValid(token: string): Promise<{ user_id: string; device_id: string } | null> {
    const tokenHash = createHash('sha256').update(token).digest('hex');
    const { rows } = await query<{ user_id: string; device_id: string }>(
      `SELECT user_id, device_id FROM refresh_tokens
       WHERE token_hash = $1 AND expires_at > NOW() AND revoked_at IS NULL`,
      [tokenHash]
    );
    return rows[0] ?? null;
  }

  async revoke(token: string): Promise<void> {
    const tokenHash = createHash('sha256').update(token).digest('hex');
    await query('UPDATE refresh_tokens SET revoked_at = NOW() WHERE token_hash = $1', [tokenHash]);
  }

  async revokeAllForUser(userId: string): Promise<void> {
    await query('UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = $1 AND revoked_at IS NULL', [
      userId,
    ]);
  }

  async revokeForDevice(userId: string, deviceId: string): Promise<void> {
    await query(
      'UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = $1 AND device_id = $2 AND revoked_at IS NULL',
      [userId, deviceId]
    );
  }
}

export const refreshTokenRepository = new RefreshTokenRepository();
