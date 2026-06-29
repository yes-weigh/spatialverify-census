import { query } from '../db/pool.js';
import type { Project } from '../types/index.js';

function rowToProject(row: Record<string, unknown>): Project {
  return {
    id: row.id as string,
    name: row.name as string,
    description: row.description as string | null,
    boundary: row.boundary ? JSON.parse(row.boundary as string) : null,
    survey_rules: row.survey_rules as Record<string, unknown>,
    is_active: row.is_active as boolean,
    created_by: row.created_by as string,
    created_at: row.created_at as string,
    updated_at: row.updated_at as string,
  };
}

export class ProjectRepository {
  async findById(id: string): Promise<Project | null> {
    const { rows } = await query(
      `SELECT id, name, description, ST_AsGeoJSON(boundary) as boundary,
              survey_rules, is_active, created_by, created_at, updated_at
       FROM projects WHERE id = $1`,
      [id]
    );
    return rows[0] ? rowToProject(rows[0]) : null;
  }

  async list(userId?: string, role?: string): Promise<Project[]> {
    if (role === 'admin') {
      const { rows } = await query(
        `SELECT id, name, description, ST_AsGeoJSON(boundary) as boundary,
                survey_rules, is_active, created_by, created_at, updated_at
         FROM projects WHERE is_active = true ORDER BY created_at DESC`
      );
      return rows.map(rowToProject);
    }

    const { rows } = await query(
      `SELECT DISTINCT p.id, p.name, p.description, ST_AsGeoJSON(p.boundary) as boundary,
              p.survey_rules, p.is_active, p.created_by, p.created_at, p.updated_at
       FROM projects p
       JOIN teams t ON t.project_id = p.id
       JOIN team_members tm ON tm.team_id = t.id
       WHERE tm.user_id = $1 AND p.is_active = true
       ORDER BY p.created_at DESC`,
      [userId]
    );
    return rows.map(rowToProject);
  }

  async create(data: {
    name: string;
    description?: string;
    boundary?: GeoJSON.Polygon;
    surveyRules?: Record<string, unknown>;
    createdBy: string;
  }): Promise<Project> {
    const boundaryWkt = data.boundary
      ? `ST_SetSRID(ST_GeomFromGeoJSON('${JSON.stringify(data.boundary)}'), 4326)`
      : 'NULL';

    const { rows } = await query(
      `INSERT INTO projects (name, description, boundary, survey_rules, created_by)
       VALUES ($1, $2, ${boundaryWkt === 'NULL' ? 'NULL' : boundaryWkt}, $3, $4)
       RETURNING id, name, description, ST_AsGeoJSON(boundary) as boundary,
                 survey_rules, is_active, created_by, created_at, updated_at`,
      [data.name, data.description ?? null, JSON.stringify(data.surveyRules ?? {}), data.createdBy]
    );
    return rowToProject(rows[0]);
  }

  async update(id: string, data: Partial<{
    name: string;
    description: string;
    boundary: GeoJSON.Polygon;
    surveyRules: Record<string, unknown>;
    isActive: boolean;
  }>): Promise<Project | null> {
    const sets: string[] = [];
    const params: unknown[] = [];
    let idx = 1;

    if (data.name !== undefined) {
      sets.push(`name = $${idx++}`);
      params.push(data.name);
    }
    if (data.description !== undefined) {
      sets.push(`description = $${idx++}`);
      params.push(data.description);
    }
    if (data.surveyRules !== undefined) {
      sets.push(`survey_rules = $${idx++}`);
      params.push(JSON.stringify(data.surveyRules));
    }
    if (data.isActive !== undefined) {
      sets.push(`is_active = $${idx++}`);
      params.push(data.isActive);
    }
    if (data.boundary !== undefined) {
      sets.push(`boundary = ST_SetSRID(ST_GeomFromGeoJSON($${idx++}), 4326)`);
      params.push(JSON.stringify(data.boundary));
    }

    if (sets.length === 0) return this.findById(id);

    params.push(id);
    const { rows } = await query(
      `UPDATE projects SET ${sets.join(', ')} WHERE id = $${idx}
       RETURNING id, name, description, ST_AsGeoJSON(boundary) as boundary,
                 survey_rules, is_active, created_by, created_at, updated_at`,
      params
    );
    return rows[0] ? rowToProject(rows[0]) : null;
  }

  async isUserInProject(userId: string, projectId: string): Promise<boolean> {
    const { rows } = await query<{ exists: boolean }>(
      `SELECT EXISTS(
        SELECT 1 FROM team_members tm
        JOIN teams t ON t.id = tm.team_id
        WHERE tm.user_id = $1 AND t.project_id = $2
      ) as exists`,
      [userId, projectId]
    );
    return rows[0]?.exists ?? false;
  }

  async getAssetCategories(projectId: string) {
    const { rows } = await query(
      'SELECT * FROM asset_categories WHERE project_id = $1 ORDER BY name',
      [projectId]
    );
    return rows;
  }

  async getTeams(projectId: string) {
    const { rows } = await query(
      `SELECT t.*, json_agg(json_build_object(
        'id', u.id, 'email', u.email, 'first_name', u.first_name,
        'last_name', u.last_name, 'role', u.role
      )) as members
       FROM teams t
       LEFT JOIN team_members tm ON tm.team_id = t.id
       LEFT JOIN users u ON u.id = tm.user_id
       WHERE t.project_id = $1
       GROUP BY t.id`,
      [projectId]
    );
    return rows;
  }
}

export const projectRepository = new ProjectRepository();
