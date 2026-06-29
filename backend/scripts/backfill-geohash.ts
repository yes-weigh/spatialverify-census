import { pool } from '../src/db/pool.js';
import { observationRepository } from '../src/repositories/observation.repository.js';

async function main() {
  let total = 0;
  let batch = 0;

  do {
    batch = await observationRepository.backfillGeohash(10000);
    total += batch;
    if (batch > 0) {
      process.stdout.write(`\rBackfilled ${total} rows...`);
    }
  } while (batch > 0);

  console.log(`\nGeohash backfill complete: ${total} rows updated`);
  await pool.end();
}

main().catch((err) => {
  console.error('Backfill failed:', err);
  process.exit(1);
});
