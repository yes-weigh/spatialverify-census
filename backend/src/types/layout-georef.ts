import type { GeoJSONPolygon } from './hlb-boundary.js';

export interface ImageBounds {
  north: number;
  south: number;
  east: number;
  west: number;
  rotation?: number;
}

export interface GpsPoint {
  lat: number;
  lng: number;
}

export interface PotentialStructure {
  id: string;
  label: string;
  sketchX: number;
  sketchY: number;
  lat?: number;
  lng?: number;
  confidence: number;
}

export interface LayoutControlPoint {
  id: string;
  label: string;
  sketchX: number;
  sketchY: number;
  lat: number;
  lng: number;
}

export interface LayoutGeorefSession {
  id: string;
  ebId: string;
  uploadedMapKey: string;
  previewMapKey: string | null;
  mimeType: string;
  status: 'uploaded' | 'aligning' | 'validated' | 'finalized';
  alignmentMode: 'satellite_registration' | 'landmark';
  layoutImageUrl?: string;
  imageBounds: ImageBounds | null;
  gpsBoundary: GpsPoint[];
  potentialStructures: PotentialStructure[];
  aiSuggestions: Record<string, unknown>;
  controlPoints: LayoutControlPoint[];
  sketchBoundary: Array<{ x: number; y: number }>;
  affineMatrix: number[] | null;
  boundaryPolygon: GeoJSONPolygon | null;
  landmarks: unknown[];
  roads: unknown[];
  waterBodies: unknown[];
  alignmentScore: string | null;
  rmsErrorMeters: number | null;
  polygonAreaSqMeters: number | null;
  missionIntelligence: Record<string, unknown> | null;
  alignmentQualityPercent: number | null;
  createdBy: string | null;
  createdAt: string;
  finalizedAt: string | null;
}

export interface GeorefValidation {
  polygonClosed: boolean;
  areaAboveMinimum: boolean;
  rmsErrorMeters: number;
  alignmentScore: 'excellent' | 'good' | 'needs_review';
  controlPointCount: number;
  potentialStructureCount: number;
  warnings: string[];
}
