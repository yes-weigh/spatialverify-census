import { query } from '../../db/pool.js';
import type { WorldProjection } from './world-projection.js';

export class WorldProjectionRepository {
  async get(missionId: string): Promise<WorldProjection | null> {
    const { rows } = await query<{ projection: WorldProjection }>(
      `SELECT projection FROM world_projection_cache WHERE mission_id = $1`,
      [missionId]
    );
    return rows[0]?.projection ?? null;
  }

  async save(missionId: string, projection: WorldProjection, builderVersion: string): Promise<void> {
    await query(
      `INSERT INTO world_projection_cache (mission_id, projection, builder_version, updated_at)
       VALUES ($1, $2, $3, NOW())
       ON CONFLICT (mission_id) DO UPDATE SET
         projection = EXCLUDED.projection,
         builder_version = EXCLUDED.builder_version,
         updated_at = NOW()`,
      [missionId, JSON.stringify(projection), builderVersion]
    );
  }

  async delete(missionId: string): Promise<void> {
    await query(`DELETE FROM world_projection_cache WHERE mission_id = $1`, [missionId]);
  }
}

export const worldProjectionRepository = new WorldProjectionRepository();
