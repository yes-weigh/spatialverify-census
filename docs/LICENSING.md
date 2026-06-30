# Mission Credits & Licensing

Isolated monetization layer for SpatialVerify Census. **Does not modify** mission, evidence, discovery, or CV architecture.

## Model

| Concept | Behavior |
|---------|----------|
| **Daily free credits** | 10/day (configurable in `system/pricing`), reset at IST midnight, do not roll over |
| **Purchased credits** | Never expire; used after daily credits are exhausted |
| **Premium operations** | Import PDF, boundary detection, CV, generate mission, offline PDF export |
| **Free forever** | Browse maps, view missions, replay, reports, navigation |

## Firestore

```
users/{uid}
  email, phone?
  credits { dailyRemaining, dailyLimit, purchasedRemaining, lastDailyReset, totalPurchased }
  license { active, plan, expiresAt, approvedAt }   # reserved for future org licenses

users/{uid}/credit_history/{id}

payment_requests/{id}
  uid, email, reference, upiTransactionId, amount, creditsRequested,
  screenshotStoragePath?, status, createdAt, deviceInfo, appVersion

system/pricing
  upiId, merchantName, dailyFreeCredits, plans[]
```

Users **cannot** modify `credits`, `license`, or payment status. Admin API (Cloud Functions + Admin SDK) approves payments and grants credits.

## Mobile (`mobile/lib/features/licensing/`)

| Component | Role |
|-----------|------|
| `CreditService` | `checkCost`, `consumeCredits`, `resetDailyCreditsIfNeeded` |
| `OperationCostCatalog` | Configurable per-operation costs |
| `PremiumOperationGate` | Confirmation dialog + deduction before premium work |
| `BuyCreditsScreen` | UPI intent, reference `SV-YYYYMMDD-XXXXX`, txn ID, optional screenshot |
| `MissionCreditsHudChip` | Live balance on map HUD (Firestore snapshot) |

Premium hooks (minimal touch points):

- `layout_georef_wizard_screen.dart` — import, boundary, CV, generate mission
- `mission_game_map_screen.dart` — HLB map PDF export

## Admin portal

Hosted at **`/admin`** on Firebase Hosting (same site as APK download).

```
https://<your-hosting-domain>/admin
```

API: `/api/admin/*` → Cloud Function `adminApi` (region `asia-south1`).

### One-time setup

1. **Deploy functions + hosting + rules**

```bash
cd functions && npm install && cd ..
firebase deploy --only functions,hosting,firestore,storage --project spatialverify-census
```

2. **Set admin secrets** (Firebase Functions params):

```bash
firebase functions:secrets:set ADMIN_PASSWORD --project spatialverify-census
firebase functions:secrets:set ADMIN_JWT_SECRET --project spatialverify-census
# Optional: ADMIN_USER (defaults to "admin")
```

3. **Seed pricing** (service account with Firestore write):

```bash
GOOGLE_APPLICATION_CREDENTIALS=path/to/sa.json node scripts/seed_system_pricing.js
```

Edit `system/pricing` in Firebase Console to set your real **UPI ID**.

### Admin workflow

1. User pays via UPI in app → submits txn ID + optional screenshot
2. Admin opens `/admin`, signs in
3. **Pending** tab → view reference, screenshot, txn ID
4. **Approve** → credits added to `users/{uid}.purchasedRemaining` instantly (app updates live)
5. **Reject** → optional reason

## Payment flow (v1 — no gateway)

```
Choose plan → UPI intent (upi://pay) → User pays → Confirm success
→ Enter UPI txn ID → Optional screenshot → payment_requests PENDING
→ Admin approve → credits appear (no app restart)
```

## v2 (future)

Replace only the payment step with Razorpay/Cashfree webhook → auto-approve. Keep `payment_requests`, `users.credits`, admin extend/grant, and `PremiumOperationGate`.

## Operation costs (defaults)

| Operation | Credits |
|-----------|---------|
| Import HLO PDF | 5 |
| Boundary detection | 5 |
| Computer vision / intelligence | 5 |
| Generate mission | 5 |
| Download offline PDF | 3 |

Change costs in `operation_cost_catalog.dart`.

## Security notes

- Firestore rules block users from increasing purchased credits or editing license
- Credit consumption only allows decrements (max 50 per write) or daily reset
- Admin credentials live in Functions secrets, not in client JS
- Screenshot URLs for admin are short-lived signed URLs from Admin SDK
