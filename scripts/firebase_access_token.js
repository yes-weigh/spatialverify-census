#!/usr/bin/env node
'use strict';

// Exchange FIREBASE_TOKEN (firebase login:ci refresh token) for a Google OAuth
// access token using firebase-tools' bundled OAuth client credentials.
const { getAccessToken } = require('firebase-tools/lib/auth');

const token = process.env.FIREBASE_TOKEN;
if (!token) {
  console.error('FIREBASE_TOKEN is required (firebase login:ci)');
  process.exit(1);
}

getAccessToken(token, [])
  .then((tokens) => {
    if (!tokens?.access_token) {
      console.error('Token exchange returned no access_token');
      process.exit(1);
    }
    process.stdout.write(tokens.access_token);
  })
  .catch((err) => {
    console.error(`Failed to exchange FIREBASE_TOKEN: ${err.message || err}`);
    console.error('Re-run: firebase login:ci && gh secret set FIREBASE_TOKEN');
    process.exit(1);
  });
