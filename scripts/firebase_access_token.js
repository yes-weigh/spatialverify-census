#!/usr/bin/env node
'use strict';

// Obtain a Google OAuth access token for GCS upload + Firestore REST.
// Tries, in order: Application Default Credentials (google-github-actions/auth),
// FIREBASE_SERVICE_ACCOUNT JSON, then FIREBASE_TOKEN (firebase login:ci).

function resolveGoogleAuthLibrary() {
  const paths = [];
  if (process.env.NODE_PATH) {
    paths.push(...process.env.NODE_PATH.split(process.platform === 'win32' ? ';' : ':'));
  }
  try {
    const ftPath = require.resolve('firebase-tools/package.json');
    paths.push(require('path').join(require('path').dirname(ftPath), 'node_modules'));
  } catch (_) {
    /* firebase-tools optional when only SA/ADC is used */
  }
  try {
    return require(require.resolve('google-auth-library', { paths }));
  } catch (_) {
    return require('google-auth-library');
  }
}

async function getTokenFromAdc() {
  const { GoogleAuth } = resolveGoogleAuthLibrary();
  const auth = new GoogleAuth({
    scopes: ['https://www.googleapis.com/auth/cloud-platform'],
  });
  const client = await auth.getClient();
  const accessToken = await client.getAccessToken();
  if (!accessToken?.token) {
    throw new Error('Application Default Credentials returned no token');
  }
  return accessToken.token;
}

async function getTokenFromServiceAccount(json) {
  const credentials = typeof json === 'string' ? JSON.parse(json) : json;
  const { GoogleAuth } = resolveGoogleAuthLibrary();
  const auth = new GoogleAuth({
    credentials,
    scopes: ['https://www.googleapis.com/auth/cloud-platform'],
  });
  const client = await auth.getClient();
  const accessToken = await client.getAccessToken();
  if (!accessToken?.token) {
    throw new Error('Service account token exchange returned no token');
  }
  return accessToken.token;
}

async function getTokenFromFirebaseCi(refreshToken) {
  const { getAccessToken } = require('firebase-tools/lib/auth');
  const tokens = await getAccessToken(refreshToken, []);
  if (!tokens?.access_token) {
    throw new Error('firebase login:ci token exchange returned no access_token');
  }
  return tokens.access_token;
}

async function main() {
  const sa = process.env.FIREBASE_SERVICE_ACCOUNT;
  const refreshToken = process.env.FIREBASE_TOKEN;
  const hasAdc =
    process.env.GOOGLE_APPLICATION_CREDENTIALS ||
    process.env.GOOGLE_GHA_CREDS_PATH ||
    process.env.CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE;

  const attempts = [];
  if (hasAdc) {
    attempts.push({ label: 'Application Default Credentials', fn: getTokenFromAdc });
  }
  if (sa) {
    attempts.push({
      label: 'FIREBASE_SERVICE_ACCOUNT',
      fn: () => getTokenFromServiceAccount(sa),
    });
  }
  if (refreshToken) {
    attempts.push({
      label: 'FIREBASE_TOKEN',
      fn: () => getTokenFromFirebaseCi(refreshToken),
    });
  }

  if (attempts.length === 0) {
    console.error(
      'No credentials configured. Set GitHub secret FIREBASE_SERVICE_ACCOUNT (recommended) ' +
        'or FIREBASE_TOKEN (firebase login:ci).'
    );
    process.exit(1);
  }

  let lastErr;
  for (const { label, fn } of attempts) {
    try {
      const token = await fn();
      process.stdout.write(token);
      return;
    } catch (err) {
      lastErr = err;
      console.error(`Auth via ${label} failed: ${err.message || err}`);
    }
  }

  console.error(
    'All auth methods failed. For CI, create a GCP service account with Storage Object Admin ' +
      '+ Cloud Datastore User, download a JSON key, and run: ' +
      'gh secret set FIREBASE_SERVICE_ACCOUNT -R yes-weigh/spatialverify-census < key.json'
  );
  process.exit(1);
}

main();
