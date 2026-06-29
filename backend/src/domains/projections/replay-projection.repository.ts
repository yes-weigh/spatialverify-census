import { query } from '../../db/pool.js';
import type { ReplayProjection } from './replay-projection.js';

export class ReplayProjectionRepository {
  async get(missionId: string): Promise<ReplayProjection | null> {
    const { rows } = await query<{ projection: ReplayProjection }>(
      `SELECT projection FROM replay_projection_cache WHERE mission_id = $1`,
      [missionId]
    );
    return rows[0]?.projection ?? null;
  }

  async save(missionId: string, projection: ReplayProjection, builderVersion: string): Promise<void> {
    await query(
      `INSERT INTO replay_projection_cache (mission_id, projection, builder_version, updated_at)
       VALUES ($1, $2, $3, NOW())
       ON CONFLICT (mission_id) DO UPDATE SET
         projection = EXCLUDED.projection,
         builder_version = EXCLUDED.builder_version,
         updated_at = NOW()`,
      [missionId, JSON.stringify(projection), builderVersion]
    );
  }
}

export const replayProjectionRepository = new ReplayProjectionRepository();
