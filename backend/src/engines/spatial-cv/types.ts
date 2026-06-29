/** Normalized 0–1 coordinates (top-left origin). */
export interface UvPoint {
  x: number;
  y: number;
}

export interface CvDetection {
  id: string;
  label: string;
  sketchX: number;
  sketchY: number;
  confidence: number;
}

export interface CvRoadSegment {
  id: string;
  label: string;
  points: UvPoint[];
  confidence: number;
}

export interface CvExtractionResult {
  engine: 'spatial_cv';
  engineVersion: string;
  boundaryPolygon: UvPoint[];
  observationTargets: CvDetection[];
  roadSegments: CvRoadSegment[];
  landmarks: CvDetection[];
  waterBodies: CvDetection[];
  canalCrossings: CvDetection[];
  vegetationPatches: CvDetection[];
  confidence: {
    boundary: number;
    structures: number;
    roads: number;
    landmarks: number;
    alignment: number;
    overall: number;
  };
  diagnostics: Record<string, number>;
}

export const SPATIAL_CV_VERSION = '1.0.0';
