'use strict';

const cors = require('cors');
const express = require('express');
const admin = require('firebase-admin');
const jwt = require('jsonwebtoken');
const { onRequest } = require('firebase-functions/v2/https');
const { defineString, defineSecret } = require('firebase-functions/params');

const adminUser = defineString('ADMIN_USER', { default: 'admin' });
const adminPassword = defineSecret('ADMIN_PASSWORD');
const jwtSecret = defineSecret('ADMIN_JWT_SECRET');

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const bucket = admin.storage().bucket('spatialverify-census.firebasestorage.app');

const app = express();
app.use(cors({ origin: true }));
app.use(express.json({ limit: '2mb' }));

function requireAdmin(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (!token) {
    res.status(401).json({ error: 'Missing authorization' });
    return;
  }
  try {
    const payload = jwt.verify(token, jwtSecret.value());
    if (payload.role !== 'admin') {
      res.status(403).json({ error: 'Forbidden' });
      return;
    }
    req.admin = payload;
    next();
  } catch {
    res.status(401).json({ error: 'Invalid or expired token' });
  }
}

const router = express.Router();

router.post('/login', (req, res) => {
  const { username, password } = req.body || {};
  const expectedUser = adminUser.value();
  const expectedPass = adminPassword.value();
  if (!expectedPass) {
    res.status(503).json({ error: 'Admin password not configured' });
    return;
  }
  if (username !== expectedUser || password !== expectedPass) {
    res.status(401).json({ error: 'Invalid credentials' });
    return;
  }
  const token = jwt.sign({ role: 'admin', sub: username }, jwtSecret.value(), {
    expiresIn: '12h',
  });
  res.json({ token, expiresIn: 43200 });
});

router.get('/stats', requireAdmin, async (req, res) => {
  try {
    const [pendingSnap, approvedSnap, rejectedSnap, usersSnap] = await Promise.all([
      db.collection('payment_requests').where('status', '==', 'PENDING').get(),
      db.collection('payment_requests').where('status', '==', 'APPROVED').get(),
      db.collection('payment_requests').where('status', '==', 'REJECTED').get(),
      db.collection('users').select().get(),
    ]);

    let revenue = 0;
    approvedSnap.forEach((doc) => {
      revenue += Number(doc.data().amount || 0);
    });

    let expired = 0;
    const now = Date.now();
    usersSnap.forEach((doc) => {
      const lic = doc.data().license || {};
      if (lic.expiresAt && lic.expiresAt.toMillis && lic.expiresAt.toMillis() < now) {
        expired += 1;
      }
    });

    res.json({
      pending: pendingSnap.size,
      approved: approvedSnap.size,
      rejected: rejectedSnap.size,
      users: usersSnap.size,
      revenue,
      expired,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to load stats' });
  }
});

async function signedScreenshotUrl(storagePath) {
  if (!storagePath) return null;
  try {
    const [url] = await bucket.file(storagePath).getSignedUrl({
      action: 'read',
      expires: Date.now() + 60 * 60 * 1000,
    });
    return url;
  } catch (err) {
    console.warn('signedScreenshotUrl', err.message);
    return null;
  }
}

router.get('/payments', requireAdmin, async (req, res) => {
  try {
    const status = (req.query.status || 'PENDING').toString().toUpperCase();
    const limit = Math.min(Number(req.query.limit) || 50, 100);
    const snap = await db
      .collection('payment_requests')
      .where('status', '==', status)
      .orderBy('createdAt', 'desc')
      .limit(limit)
      .get();

    const items = await Promise.all(
      snap.docs.map(async (doc) => {
        const data = doc.data();
        const screenshotUrl = await signedScreenshotUrl(data.screenshotStoragePath);
        return { id: doc.id, ...data, screenshotUrl };
      }),
    );
    res.json({ items });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to list payments' });
  }
});

router.get('/payments/:id', requireAdmin, async (req, res) => {
  try {
    const doc = await db.collection('payment_requests').doc(req.params.id).get();
    if (!doc.exists) {
      res.status(404).json({ error: 'Not found' });
      return;
    }
    const data = doc.data();
    const screenshotUrl = await signedScreenshotUrl(data.screenshotStoragePath);
    res.json({ id: doc.id, ...data, screenshotUrl });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to load payment' });
  }
});

router.post('/payments/:id/approve', requireAdmin, async (req, res) => {
  const paymentId = req.params.id;
  const customCredits = req.body?.customCredits;

  try {
    await db.runTransaction(async (tx) => {
      const payRef = db.collection('payment_requests').doc(paymentId);
      const paySnap = await tx.get(payRef);
      if (!paySnap.exists) {
        throw new Error('NOT_FOUND');
      }
      const payment = paySnap.data();
      if (payment.status !== 'PENDING') {
        throw new Error('ALREADY_REVIEWED');
      }

      const creditsToAdd = Number(customCredits) > 0
        ? Number(customCredits)
        : Number(payment.creditsRequested || 0);
      if (creditsToAdd <= 0) {
        throw new Error('INVALID_CREDITS');
      }

      const userRef = db.collection('users').doc(payment.uid);
      const userSnap = await tx.get(userRef);
      if (!userSnap.exists) {
        throw new Error('USER_NOT_FOUND');
      }

      const user = userSnap.data();
      const credits = user.credits || {};
      const purchasedRemaining = Number(credits.purchasedRemaining || 0) + creditsToAdd;
      const totalPurchased = Number(credits.totalPurchased || 0) + creditsToAdd;

      tx.update(payRef, {
        status: 'APPROVED',
        reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
        reviewedBy: req.admin.sub || 'admin',
        creditsGranted: creditsToAdd,
      });

      tx.update(userRef, {
        'credits.purchasedRemaining': purchasedRemaining,
        'credits.totalPurchased': totalPurchased,
        'license.active': true,
        'license.approvedAt': admin.firestore.FieldValue.serverTimestamp(),
      });

      const historyRef = userRef.collection('credit_history').doc();
      tx.set(historyRef, {
        type: 'purchase_approved',
        amount: creditsToAdd,
        operation: null,
        reference: payment.reference || null,
        paymentRequestId: paymentId,
        balanceAfter: {
          dailyRemaining: credits.dailyRemaining ?? 10,
          purchasedRemaining,
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    res.json({ ok: true });
  } catch (err) {
    const code = err.message;
    if (code === 'NOT_FOUND') {
      res.status(404).json({ error: 'Payment not found' });
      return;
    }
    if (code === 'ALREADY_REVIEWED') {
      res.status(409).json({ error: 'Payment already reviewed' });
      return;
    }
    if (code === 'USER_NOT_FOUND') {
      res.status(404).json({ error: 'User not found' });
      return;
    }
    console.error(err);
    res.status(500).json({ error: 'Approval failed' });
  }
});

router.post('/payments/:id/reject', requireAdmin, async (req, res) => {
  const paymentId = req.params.id;
  const reason = (req.body?.reason || '').toString().slice(0, 500);

  try {
    const payRef = db.collection('payment_requests').doc(paymentId);
    const paySnap = await payRef.get();
    if (!paySnap.exists) {
      res.status(404).json({ error: 'Not found' });
      return;
    }
    const payment = paySnap.data();
    if (payment.status !== 'PENDING') {
      res.status(409).json({ error: 'Payment already reviewed' });
      return;
    }
    await payRef.update({
      status: 'REJECTED',
      rejectionReason: reason || null,
      reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      reviewedBy: req.admin?.sub || 'admin',
    });
    res.json({ ok: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Rejection failed' });
  }
});

router.post('/users/:uid/grant-credits', requireAdmin, async (req, res) => {
  const uid = req.params.uid;
  const credits = Number(req.body?.credits || 0);
  const extendDays = Number(req.body?.extendDays || 0);

  if (credits <= 0 && extendDays <= 0) {
    res.status(400).json({ error: 'Specify credits or extendDays' });
    return;
  }

  try {
    await db.runTransaction(async (tx) => {
      const userRef = db.collection('users').doc(uid);
      const userSnap = await tx.get(userRef);
      if (!userSnap.exists) {
        throw new Error('USER_NOT_FOUND');
      }
      const user = userSnap.data();
      const patch = {};

      if (credits > 0) {
        const c = user.credits || {};
        patch['credits.purchasedRemaining'] = Number(c.purchasedRemaining || 0) + credits;
        patch['credits.totalPurchased'] = Number(c.totalPurchased || 0) + credits;
      }

      if (extendDays > 0) {
        const lic = user.license || {};
        const base = lic.expiresAt?.toMillis?.() || Date.now();
        const from = Math.max(base, Date.now());
        patch['license.expiresAt'] = admin.firestore.Timestamp.fromMillis(
          from + extendDays * 24 * 60 * 60 * 1000,
        );
        patch['license.active'] = true;
      }

      tx.update(userRef, patch);

      if (credits > 0) {
        const historyRef = userRef.collection('credit_history').doc();
        tx.set(historyRef, {
          type: 'admin_grant',
          amount: credits,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          reviewedBy: req.admin?.sub || 'admin',
        });
      }
    });
    res.json({ ok: true });
  } catch (err) {
    if (err.message === 'USER_NOT_FOUND') {
      res.status(404).json({ error: 'User not found' });
      return;
    }
    console.error(err);
    res.status(500).json({ error: 'Grant failed' });
  }
});

app.use('/api/admin', router);

exports.adminApi = onRequest(
  { region: 'asia-south1', cors: true, secrets: [adminPassword, jwtSecret] },
  app,
);
