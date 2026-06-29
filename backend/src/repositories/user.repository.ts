import bcrypt from 'bcrypt';
import { createHash, randomBytes } from 'crypto';
import { query } from '../db/pool.js';
import type { User, UserRole } from '../types/index.js';

export class UserRepository {
  async findByEmail(email: string): Promise<(User & { password_hash: string }) | null> {
    const { rows } = await query<User & { password_hash: string }>(
      'SELECT * FROM users WHERE email = $1 AND is_active = true',
      [email.toLowerCase()]
    );
    return rows[0] ?? null;
  }

  async findById(id: string): Promise<User | null> {
    const { rows } = await query<User>(
      'SELECT id, email, first_name, last_name, role, is_active, device_id, last_login_at, created_at, updated_at FROM users WHERE id = $1',
      [id]
    );
    return rows[0] ?? null;
  }

  async create(data: {
    email: string;
    password: string;
    firstName: string;
    lastName: string;
    role: UserRole;
  }): Promise<User> {
    const passwordHash = await bcrypt.hash(data.password, 12);
    const { rows } = await query<User>(
      `INSERT INTO users (email, password_hash, first_name, last_name, role)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, email, first_name, last_name, role, is_active, device_id, last_login_at, created_at, updated_at`,
      [data.email.toLowerCase(), passwordHash, data.firstName, data.lastName, data.role]
    );
    return rows[0];
  }

  async updateDeviceId(userId: string, deviceId: string): Promise<void> {
    await query('UPDATE users SET device_id = $1, last_login_at = NOW() WHERE id = $2', [
      deviceId,
      userId,
    ]);
  }

  async setPasswordResetToken(email: string, token: string, expiresAt: Date): Promise<boolean> {
    const { rowCount } = await query(
      'UPDATE users SET password_reset_token = $1, password_reset_expires = $2 WHERE email = $3 AND is_active = true',
      [token, expiresAt.toISOString(), email.toLowerCase()]
    );
    return (rowCount ?? 0) > 0;
  }

  async resetPassword(token: string, newPassword: string): Promise<boolean> {
    const passwordHash = await bcrypt.hash(newPassword, 12);
    const { rowCount } = await query(
      `UPDATE users SET password_hash = $1, password_reset_token = NULL, password_reset_expires = NULL
       WHERE password_reset_token = $2 AND password_reset_expires > NOW() AND is_active = true`,
      [passwordHash, token]
    );
    return (rowCount ?? 0) > 0;
  }

  async list(role?: UserRole): Promise<User[]> {
    if (role) {
      const { rows } = await query<User>(
        'SELECT id, email, first_name, last_name, role, is_active, device_id, last_login_at, created_at, updated_at FROM users WHERE role = $1 ORDER BY created_at DESC',
        [role]
      );
      return rows;
    }
    const { rows } = await query<User>(
      'SELECT id, email, first_name, last_name, role, is_active, device_id, last_login_at, created_at, updated_at FROM users ORDER BY created_at DESC'
    );
    return rows;
  }

  async verifyPassword(hash: string, password: string): Promise<boolean> {
    return bcrypt.compare(password, hash);
  }

  static hashToken(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }

  static generateToken(): string {
    return randomBytes(32).toString('hex');
  }
}

export const userRepository = new UserRepository();
