#!/usr/bin/env node
'use strict';

/**
 * Seed system/pricing in Firestore (run once with Firebase Admin credentials).
 *   GOOGLE_APPLICATION_CREDENTIALS=path/to/sa.json node scripts/seed_system_pricing.js
 */
const admin = require('firebase-admin');

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'spatialverify-census';

if (!admin.apps.length) {
  admin.initializeApp({ projectId: PROJECT_ID });
}

const db = admin.firestore();

async function main() {
  await db.doc('system/pricing').set({
    upiId: process.env.LICENSING_UPI_ID || 'yourupi@okaxis',
    merchantName: 'SpatialVerify',
    dailyFreeCredits: 10,
    plans: [
      { id: 'pack_50', label: '50 Credits', credits: 50, amountInr: 499 },
      { id: 'pack_120', label: '120 Credits', credits: 120, amountInr: 999 },
      { id: 'pack_300', label: '300 Credits', credits: 300, amountInr: 1999 },
    ],
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log('Seeded system/pricing');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
