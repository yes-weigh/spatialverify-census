import type { GpsPoint, ImageBounds } from './layout-georef.js';
import type { HlbDigitalTwin } from './digital-twin.js';

export interface ObservationTarget {
  id: string;
  label: string;
  sketchX: number;
  sketchY: number;
  lat?: number;
  lng?: number;
  confidence: number;
}

export interface IntelligenceLandmark {
  id: string;
  label: string;
  lat: number;
  lng: number;
  confidence: number;
}

export interface IntelligenceRoadSegment {
  id: string;
  label: string;
  points: GpsPoint[];
  confidence: number;
}

export interface SpatialConfidence {
  boundary: number;
  structures: number;
  roads: number;
  landmarks: number;
  alignment: number;
  overall: number;
}

export interface MissionIntelligence {
  generatedAt: string;
  engine: 'spatial_cv';
  engineVersion: string;
  alignment: {
    autoAligned: boolean;
    qualityPercent: number;
    score: 'excellent' | 'good' | 'needs_review';
    imageBounds: ImageBounds;
  };
  confidence: SpatialConfidence;
  boundary: {
    source: 'cv_detected' | 'manual';
    confidence: number;
    gpsRing: GpsPoint[];
    uvRing: Array<{ x: number; y: number }>;
  };
  hypotheses: {
    observationTargets: ObservationTarget[];
    roads: IntelligenceRoadSegment[];
    landmarks: IntelligenceLandmark[];
    waterBodies: Array<{ id: string; label: string; lat: number; lng: number }>;
    canalCrossings: Array<{ id: string; label: string; lat: number; lng: number }>;
    vegetationPatches: Array<{ id: string; label: string; lat: number; lng: number }>;
  };
  summary: {
    observationTargets: number;
    roadSegments: number;
    possibleLandmarks: number;
    canalCrossings: number;
    vegetationPatches: number;
  };
  digitalTwin: HlbDigitalTwin;
}
