import {
  IDENTITY_THRESHOLDS,
  type GpsCluster,
  type ViewType,
} from '../../types/identity.js';

export function gpsAccuracyConfidence(accuracyMeters: number | null | undefined): number {
  if (accuracyMeters == null || accuracyMeters <= 0) return 0.75;
  if (accuracyMeters <= 3) return 1.0;
  if (accuracyMeters <= 8) return 0.85;
  if (accuracyMeters <= 15) return 0.65;
  if (accuracyMeters <= 25) return 0.45;
  return 0.25;
}

export function gpsSimilarityScore(
  distanceMeters: number,
  maxDistance: number = IDENTITY_THRESHOLDS.gpsMaxDistanceMeters,
  decayScale: number = IDENTITY_THRESHOLDS.gpsDecayScaleMeters
): number {
  if (distanceMeters <= 0) return 1;
  if (distanceMeters >= maxDistance * 3) return 0;
  return 1 / (1 + distanceMeters / decayScale);
}

export function gpsClusterScore(
  distanceToCentroidM: number,
  cluster: GpsCluster | null,
  queryAccuracy?: number | null
): { score: number; insideCluster: boolean } {
  if (!cluster || cluster.observation_count === 0) {
    return { score: 0, insideCluster: false };
  }

  const insideCluster = distanceToCentroidM <= cluster.radius_m;
  let score: number;

  if (insideCluster) {
    score = 1 - (distanceToCentroidM / Math.max(cluster.radius_m, 1)) * 0.3;
  } else {
    const beyond = distanceToCentroidM - cluster.radius_m;
    score = gpsSimilarityScore(beyond, cluster.radius_m * 2, IDENTITY_THRESHOLDS.gpsDecayScaleMeters);
  }

  const accuracyFactor = gpsAccuracyConfidence(queryAccuracy);
  return {
    score: Math.max(0, Math.min(1, score * accuracyFactor)),
    insideCluster,
  };
}

export function effectiveGpsScore(
  distanceMeters: number,
  queryAccuracy: number | null | undefined,
  cluster: GpsCluster | null,
  distanceToCentroidM: number
): { score: number; insideCluster: boolean; accuracyFactor: number } {
  const accuracyFactor = gpsAccuracyConfidence(queryAccuracy);

  if (cluster && cluster.observation_count >= 2) {
    const clusterResult = gpsClusterScore(distanceToCentroidM, cluster, queryAccuracy);
    return { ...clusterResult, accuracyFactor };
  }

  const baseScore = gpsSimilarityScore(distanceMeters);
  return {
    score: Math.max(0, Math.min(1, baseScore * accuracyFactor)),
    insideCluster: distanceMeters <= (cluster?.radius_m ?? IDENTITY_THRESHOLDS.gpsMaxDistanceMeters),
    accuracyFactor,
  };
}

export function headingSimilarityScore(headingA: number | null | undefined, headingB: number | null | undefined): number {
  if (headingA == null || headingB == null) return 0.5;
  let diff = Math.abs(headingA - headingB) % 360;
  if (diff > 180) diff = 360 - diff;
  return 1 - diff / 180;
}

export function headingProfileScore(
  queryHeading: number | null | undefined,
  profileMean: number | null | undefined,
  profileVariance: number | null | undefined
): number {
  if (queryHeading == null || profileMean == null) return 0.5;
  let diff = Math.abs(queryHeading - profileMean) % 360;
  if (diff > 180) diff = 360 - diff;

  const tolerance = profileVariance != null && profileVariance > 0
    ? Math.min(90, Math.sqrt(profileVariance) * 2)
    : 45;
  if (diff <= tolerance) {
    return tolerance > 0 ? 1 - (diff / tolerance) * 0.3 : 1;
  }
  return Math.max(0, 1 - diff / 180);
}

export function categorySimilarityScore(
  queryCategory: string,
  candidateCategory: string | null,
  relatedLabels: string[][] = []
): number {
  if (!candidateCategory) return 0;
  const q = normalizeLabel(queryCategory);
  const c = normalizeLabel(candidateCategory);
  if (q === c) return 1;

  for (const group of relatedLabels) {
    const normalized = group.map(normalizeLabel);
    if (normalized.includes(q) && normalized.includes(c)) return 0.8;
  }

  if (q.includes(c) || c.includes(q)) return 0.85;
  return 0;
}

export function embeddingSimilarityScore(cosineDistance: number): number {
  const similarity = 1 - cosineDistance;
  return Math.max(0, Math.min(1, similarity));
}

export function computeFinalConfidence(scores: {
  gps: number;
  embedding: number;
  category: number;
  heading: number;
}): number {
  const w = { gps: 0.25, embedding: 0.50, category: 0.15, heading: 0.10 };
  return (
    scores.gps * w.gps +
    scores.embedding * w.embedding +
    scores.category * w.category +
    scores.heading * w.heading
  );
}

export function determineVerdict(
  scores: { gps: number; embedding: number; category: number; heading: number },
  finalConfidence: number
): import('../../types/identity.js').IdentityVerdict {
  const t = IDENTITY_THRESHOLDS;

  if (
    finalConfidence >= t.sameAsset.final &&
    scores.embedding >= t.sameAsset.embedding &&
    scores.gps >= t.sameAsset.gps
  ) {
    return 'same_asset';
  }

  if (
    finalConfidence >= t.possibleMatch.final ||
    (scores.embedding >= t.possibleMatch.embedding && scores.gps >= t.possibleMatch.gps)
  ) {
    return 'possible_match';
  }

  return 'new_asset';
}

export function computeVisualDrift(embeddings: number[][]): number {
  if (embeddings.length < 2) return 0;

  let totalDistance = 0;
  let pairs = 0;

  for (let i = 0; i < embeddings.length; i++) {
    for (let j = i + 1; j < embeddings.length; j++) {
      totalDistance += 1 - cosineSimilarity(embeddings[i], embeddings[j]);
      pairs++;
    }
  }

  return pairs > 0 ? totalDistance / pairs : 0;
}

export function interpretDrift(driftScore: number): 'stable' | 'moderate_change' | 'significant_change' {
  if (driftScore <= IDENTITY_THRESHOLDS.driftStable) return 'stable';
  if (driftScore <= IDENTITY_THRESHOLDS.driftModerate) return 'moderate_change';
  return 'significant_change';
}

export function buildExplanationSummary(
  scores: { gps: number; embedding: number; category: number; heading: number },
  extras: {
    insideCluster?: boolean;
    bestView?: ViewType | null;
    visualDrift?: number | null;
    lastSeenAt?: string | null;
  }
): string {
  const parts: string[] = [];

  if (scores.embedding >= 0.8) parts.push('strong visual match');
  else if (scores.embedding >= 0.65) parts.push('moderate visual match');
  else parts.push('weak visual match');

  if (extras.insideCluster) parts.push('inside GPS cluster');
  else if (scores.gps >= 0.55) parts.push('near GPS cluster');
  else parts.push('GPS uncertain');

  if (extras.bestView && extras.bestView !== 'unknown') {
    parts.push(`best view: ${extras.bestView}`);
  }

  if (extras.visualDrift != null && extras.visualDrift > IDENTITY_THRESHOLDS.driftModerate) {
    parts.push('significant visual change over time');
  }

  if (extras.lastSeenAt) {
    parts.push(`last seen ${extras.lastSeenAt}`);
  }

  return parts.join('; ');
}

export function cosineSimilarity(a: number[], b: number[]): number {
  if (a.length !== b.length || a.length === 0) return 0;
  let dot = 0;
  let normA = 0;
  let normB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  const denom = Math.sqrt(normA) * Math.sqrt(normB);
  return denom === 0 ? 0 : dot / denom;
}

function normalizeLabel(label: string): string {
  return label.toLowerCase().trim().replace(/[\s-]+/g, '_');
}
