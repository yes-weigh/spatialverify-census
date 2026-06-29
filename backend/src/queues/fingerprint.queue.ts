import { Queue, Worker } from 'bullmq';
import { env } from '../config/env.js';
import { fingerprintService } from '../services/identity/fingerprint.service.js';

const connection = { url: env.redisUrl };

export const FINGERPRINT_REFRESH_JOB = 'refresh-fingerprint';

export interface FingerprintRefreshJobData {
  assetId: string;
  triggeredBy?: 'observation' | 'manual' | 'backfill';
}

export const fingerprintQueue = new Queue<FingerprintRefreshJobData>('fingerprint', { connection });

export async function enqueueFingerprintRefresh(
  assetId: string,
  triggeredBy: FingerprintRefreshJobData['triggeredBy'] = 'observation'
) {
  try {
    const jobId = `fingerprint:${assetId}`;

    const existing = await fingerprintQueue.getJob(jobId);
    if (existing) {
      const state = await existing.getState();
      if (state === 'waiting' || state === 'delayed' || state === 'active') {
        return existing;
      }
    }

    return fingerprintQueue.add(
      FINGERPRINT_REFRESH_JOB,
      { assetId, triggeredBy },
      {
        jobId,
        removeOnComplete: 100,
        removeOnFail: 50,
        attempts: 3,
        backoff: { type: 'exponential', delay: 2000 },
      }
    );
  } catch (error) {
    console.warn(`[fingerprint] Queue unavailable for asset ${assetId}, skipping async refresh:`, error);
    return null;
  }
}

export function createFingerprintWorker() {
  return new Worker<FingerprintRefreshJobData>(
    'fingerprint',
    async (job) => {
      const { assetId } = job.data;
      const result = await fingerprintService.refreshAssetFingerprint(assetId);
      return {
        assetId,
        clusterUpdated: result != null,
        driftScore: result?.drift_score ?? null,
        interpretation: result?.interpretation ?? null,
      };
    },
    { connection, concurrency: 4 }
  );
}
