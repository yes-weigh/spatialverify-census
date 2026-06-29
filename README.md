# SpatialVerify

Production-grade geospatial survey, verification, mapping, and AR-assisted field data collection platform.

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────┐
│  Flutter App    │────▶│  Fastify API     │────▶│  PostgreSQL │
│  (Offline-first)│◀────│  + WebSocket     │     │  + PostGIS  │
└────────┬────────┘     └────────┬─────────┘     └─────────────┘
         │                       │
         │ Hive + Drift          ├── Redis + BullMQ
         │ TFLite + AR           └── MinIO (S3)
         └── Mapbox
```

## Quick Start

### Prerequisites

- Docker & Docker Compose
- Node.js 20+
- Flutter 3.24+ stable

### Infrastructure

```bash
cp .env.example .env
docker compose up -d
```

### Backend

```bash
cd backend
npm install
npm run migrate
npm run seed
npm run dev
```

API: `http://localhost:3000`
Health: `http://localhost:3000/health`

### Mobile

```bash
cd mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

Configure `mobile/lib/core/config/env.dart` with your API URL and Mapbox token.

## Default Credentials (seed)

| Role          | Email                    | Password      |
|---------------|--------------------------|---------------|
| Admin         | admin@spatialverify.com  | Admin123!     |
| Supervisor    | supervisor@spatialverify.com | Supervisor123! |
| Field Worker  | worker@spatialverify.com | Worker123!    |

## Modules

- **Authentication** — JWT + refresh tokens, device binding, password reset
- **Project Management** — boundaries, teams, survey rules, asset categories
- **GIS** — PostGIS spatial queries, geofencing, radius/bbox search
- **Map** — Mapbox with clustering, offline tiles, status-colored markers
- **Camera Scanner** — TFLite object detection with human verification workflow
- **AR** — spatial anchors, floating labels, tap interaction
- **3D Reconstruction** — multi-phase point cloud → mesh → glTF pipeline
- **Offline Sync** — conflict-aware bidirectional sync engine
- **Analytics** — coverage, productivity, heatmaps, trends

## License

Proprietary — All rights reserved.
