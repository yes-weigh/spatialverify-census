import { Queue, Worker } from 'bullmq';
import { env } from '../config/env.js';

const connection = { url: env.redisUrl };

export const reconstructionQueue = new Queue('reconstruction', { connection });

export function createReconstructionWorker() {
  return new Worker(
    'reconstruction',
    async (job) => {
      const { pointCloudId, imageKeys, phase } = job.data as {
        pointCloudId: string;
        imageKeys: string[];
        phase?: string;
      };

      const { query } = await import('../db/pool.js');
      const currentPhase = phase ?? 'sparse_point_cloud';

      if (currentPhase === 'sparse_point_cloud') {
        const pointCount = imageKeys.length * 500;
        const s3Key = `reconstruction/${pointCloudId}/sparse.ply`;

        await query(
          `UPDATE point_clouds SET phase = 'sparse_point_cloud', s3_key = $1, point_count = $2,
                                   metadata = metadata || $3::jsonb
           WHERE id = $4`,
          [s3Key, pointCount, JSON.stringify({ processed_images: imageKeys.length }), pointCloudId]
        );

        await reconstructionQueue.add('mesh-generation', {
          pointCloudId,
          phase: 'mesh',
        }, { delay: 1000 });

        return { phase: 'sparse_point_cloud', pointCount };
      }

      if (currentPhase === 'mesh') {
        const { rows } = await query('SELECT project_id FROM point_clouds WHERE id = $1', [pointCloudId]);
        if (!rows[0]) throw new Error('Point cloud not found');

        const meshS3Key = `reconstruction/${pointCloudId}/mesh.obj`;
        const { rows: meshRows } = await query(
          `INSERT INTO meshes (point_cloud_id, project_id, phase, s3_key, vertex_count, face_count, created_by)
           SELECT $1, project_id, 'mesh', $2, 10000, 20000, created_by FROM point_clouds WHERE id = $1
           RETURNING id`,
          [pointCloudId, meshS3Key]
        );

        await query(
          `UPDATE point_clouds SET phase = 'mesh' WHERE id = $1`,
          [pointCloudId]
        );

        await reconstructionQueue.add('gltf-export', {
          pointCloudId,
          meshId: meshRows[0].id,
          phase: 'gltf_export',
        }, { delay: 1000 });

        return { phase: 'mesh', meshId: meshRows[0].id };
      }

      if (currentPhase === 'gltf_export') {
        const { meshId } = job.data as { meshId: string };
        const gltfKey = `reconstruction/${pointCloudId}/model.gltf`;

        await query(
          `UPDATE meshes SET phase = 'gltf_export', gltf_s3_key = $1 WHERE id = $2`,
          [gltfKey, meshId]
        );

        await query(
          `UPDATE point_clouds SET phase = 'completed' WHERE id = $1`,
          [pointCloudId]
        );

        return { phase: 'completed', gltfKey };
      }

      return { phase: 'unknown' };
    },
    { connection, concurrency: 2 }
  );
}
