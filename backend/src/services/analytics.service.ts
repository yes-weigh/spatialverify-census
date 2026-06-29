import { query } from '../db/pool.js';
import { assetRepository } from '../repositories/asset.repository.js';
import { conflictRepository } from '../repositories/survey.repository.js';

export class AnalyticsService {
  async getProjectDashboard(projectId: string) {
    const statusCounts = await assetRepository.countByStatus(projectId);

    const { rows: coverageRows } = await query<{ avg_coverage: string }>(
      `SELECT COALESCE(AVG(coverage_percentage), 0)::text as avg_coverage
       FROM survey_sessions WHERE project_id = $1`,
      [projectId]
    );

    const { rows: conflictRows } = await query<{ count: string }>(
      `SELECT COUNT(*)::text as count FROM conflicts WHERE project_id = $1 AND status = 'open'`,
      [projectId]
    );

    const { rows: workerStats } = await query(
      `SELECT u.id, u.first_name, u.last_name,
              COUNT(DISTINCT v.id) as verifications,
              COUNT(DISTINCT ss.id) as sessions
       FROM users u
       JOIN team_members tm ON tm.user_id = u.id
       JOIN teams t ON t.id = tm.team_id
       LEFT JOIN verifications v ON v.verified_by = u.id
       LEFT JOIN survey_sessions ss ON ss.user_id = u.id AND ss.project_id = $1
       WHERE t.project_id = $1 AND u.role = 'field_worker'
       GROUP BY u.id, u.first_name, u.last_name`,
      [projectId]
    );

    const { rows: dailyTrends } = await query(
      `SELECT DATE(verified_at) as date,
              COUNT(*) FILTER (WHERE human_decision = 'confirmed') as confirmed,
              COUNT(*) FILTER (WHERE human_decision = 'rejected') as rejected
       FROM verifications v
       JOIN detections d ON d.id = v.detection_id
       WHERE d.project_id = $1 AND verified_at > NOW() - INTERVAL '30 days'
       GROUP BY DATE(verified_at)
       ORDER BY date`,
      [projectId]
    );

    const { rows: heatmapData } = await query(
      `SELECT ST_AsGeoJSON(coverage_geometry) as geometry, coverage_percentage, heatmap_data
       FROM coverage_maps WHERE project_id = $1
       ORDER BY generated_at DESC LIMIT 1`,
      [projectId]
    );

    return {
      coverage: parseFloat(coverageRows[0]?.avg_coverage ?? '0'),
      assets: {
        verified: statusCounts.verified,
        pending: statusCounts.pending,
        rejected: statusCounts.rejected,
        notSurveyed: statusCounts.not_surveyed,
        total: Object.values(statusCounts).reduce((a, b) => a + b, 0),
      },
      conflicts: parseInt(conflictRows[0]?.count ?? '0', 10),
      workerProductivity: workerStats,
      dailyTrends,
      heatmap: heatmapData[0] ?? null,
    };
  }
}

export const analyticsService = new AnalyticsService();
