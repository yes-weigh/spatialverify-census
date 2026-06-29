import { createReconstructionWorker } from './queues/reconstruction.queue.js';
import { createFingerprintWorker } from './queues/fingerprint.queue.js';

const reconstructionWorker = createReconstructionWorker();
const fingerprintWorker = createFingerprintWorker();

reconstructionWorker.on('completed', (job, result) => {
  console.log(`[reconstruction] Job ${job.id} completed:`, result);
});

reconstructionWorker.on('failed', (job, error) => {
  console.error(`[reconstruction] Job ${job?.id} failed:`, error.message);
});

fingerprintWorker.on('completed', (job, result) => {
  console.log(`[fingerprint] Job ${job.id} completed:`, result);
});

fingerprintWorker.on('failed', (job, error) => {
  console.error(`[fingerprint] Job ${job?.id} failed:`, error.message);
});

console.log('SpatialVerify workers started: reconstruction, fingerprint');

process.on('SIGTERM', async () => {
  await Promise.all([reconstructionWorker.close(), fingerprintWorker.close()]);
  process.exit(0);
});
