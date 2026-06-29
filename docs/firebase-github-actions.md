# Firebase deploy via GitHub Actions

Pushes to `main` that change `firebase/**`, `firebase.json`, or `.firebaserc` run [`.github/workflows/firebase-deploy.yml`](../.github/workflows/firebase-deploy.yml) and deploy Firestore rules/indexes and Storage rules to **spatialverify-census**.

## One-time: add CI token to GitHub

GitHub Actions cannot use your local `firebase login` session. Generate a deploy token once:

```powershell
firebase login:ci
```

Copy the token, then:

```powershell
cd d:\census
gh secret set FIREBASE_TOKEN
# paste token when prompted
```

Or in one line (PowerShell):

```powershell
firebase login:ci | gh secret set FIREBASE_TOKEN
```

Verify:

```powershell
gh secret list
```

## Manual deploy from Actions

GitHub → **Actions** → **Firebase Deploy** → **Run workflow**.

## Local deploy (same as CI)

```powershell
cd d:\census
firebase deploy --only firestore,storage --project spatialverify-census
```
