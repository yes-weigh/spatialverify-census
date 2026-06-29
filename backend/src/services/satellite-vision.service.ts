import { env } from '../config/env.js';

/** @deprecated Not on critical path — use spatial-cv engine. Kept for legacy landmark sketch mode only. */



export interface PotentialStructure {

  id: string;

  label: string;

  sketchX: number;

  sketchY: number;

  confidence: number;

}



export interface SatelliteFeatureExtraction {

  potentialStructures: PotentialStructure[];

  roads: Array<{ label: string; sketchX: number; sketchY: number }>;

  waterBodies: Array<{ label: string; sketchX: number; sketchY: number }>;

  boundaryHint?: Array<{ x: number; y: number }>;

  confidence: Record<string, number>;

}



export interface MissionIntelligenceExtraction extends SatelliteFeatureExtraction {

  boundaryPolygon: Array<{ x: number; y: number }>;

  landmarks: Array<{ id?: string; label: string; sketchX: number; sketchY: number; confidence?: number }>;

  roadSegments: Array<{

    id?: string;

    label: string;

    points: Array<{ x: number; y: number }>;

    confidence?: number;

  }>;

  canalCrossings: Array<{ label: string; sketchX: number; sketchY: number }>;

  vegetationPatches: Array<{ label: string; sketchX: number; sketchY: number }>;

}



const SATELLITE_PROMPT = `You are analyzing an officer-provided HLB satellite map image (already a satellite/aerial view with a boundary line drawn around the block).



Return ONLY valid JSON:

{

  "potentialStructures": [{"id": "s1", "label": "Building cluster", "sketchX": 0.5, "sketchY": 0.4, "confidence": 0.8}],

  "roads": [{"label": "Main road", "sketchX": 0.5, "sketchY": 0.5}],

  "waterBodies": [{"label": "Canal", "sketchX": 0.2, "sketchY": 0.7}],

  "boundaryHint": [{"x": 0.1, "y": 0.1}, {"x": 0.9, "y": 0.1}],

  "confidence": {"overall": 0.75}

}



sketchX/sketchY and boundary x/y are normalized 0-1 (top-left origin).

Detect building roof clusters, roads, canals/rivers visible in the satellite image.

boundaryHint: approximate corners of the drawn HLB boundary polygon if visible (red/yellow line).

Omit uncertain items. No markdown.`;



const MISSION_INTELLIGENCE_PROMPT = `You are the Mission Intelligence Engine for Census HLB field mapping.



Analyze this officer-provided satellite image of an HLB (House Listing Block). The image shows:

- Satellite/aerial imagery of the block

- A drawn boundary (red/yellow/highlighted polygon line) around the HLB

- Visible roads, canals, buildings, vegetation



Return ONLY valid JSON (no markdown):

{

  "boundaryPolygon": [{"x": 0.12, "y": 0.15}, {"x": 0.88, "y": 0.14}, {"x": 0.91, "y": 0.82}, {"x": 0.10, "y": 0.85}],

  "potentialStructures": [{"id": "s1", "label": "Residential cluster", "sketchX": 0.45, "sketchY": 0.38, "confidence": 0.82}],

  "landmarks": [{"id": "lm1", "label": "Temple", "sketchX": 0.3, "sketchY": 0.5, "confidence": 0.7}],

  "roadSegments": [{"id": "rd1", "label": "Main road", "points": [{"x": 0.1, "y": 0.5}, {"x": 0.9, "y": 0.52}], "confidence": 0.8}],

  "waterBodies": [{"label": "Canal", "sketchX": 0.2, "sketchY": 0.7}],

  "canalCrossings": [{"label": "Bridge over canal", "sketchX": 0.35, "sketchY": 0.68}],

  "vegetationPatches": [{"label": "Tree cover", "sketchX": 0.6, "sketchY": 0.3}],

  "confidence": {"overall": 0.85, "boundary": 0.9, "alignment": 0.82}

}



Rules:

- x/y/sketchX/sketchY are normalized 0-1, origin top-left

- boundaryPolygon: trace the drawn HLB boundary line clockwise (6-20 points for curves)

- potentialStructures: roof/building clusters — hypotheses only, not confirmed

- landmarks: temples, schools, mosques, junctions, bridges visible in imagery

- roadSegments: polylines along visible roads (2-8 points each)

- canalCrossings: where roads cross water

- vegetationPatches: large tree cover / vacant vegetated plots

- confidence.overall: 0-1 estimate of extraction quality

- Omit uncertain items. Return empty arrays rather than guessing.`;



async function callGemini(imageBase64: string, mimeType: string, prompt: string): Promise<string> {

  if (!env.geminiApiKey) return '{}';

  const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${env.geminiApiKey}`;

  const res = await fetch(url, {

    method: 'POST',

    headers: { 'Content-Type': 'application/json' },

    body: JSON.stringify({

      contents: [{

        parts: [

          { text: prompt },

          { inline_data: { mime_type: mimeType, data: imageBase64 } },

        ],

      }],

      generationConfig: { temperature: 0.12, maxOutputTokens: 16384 },

    }),

  });

  if (!res.ok) throw new Error(`Gemini API error: ${res.status}`);

  const data = await res.json() as {

    candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;

  };

  const text = data.candidates?.[0]?.content?.parts?.[0]?.text ?? '{}';

  return text.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();

}



export async function extractSatelliteFeatures(

  imageBase64: string,

  mimeType: string

): Promise<SatelliteFeatureExtraction> {

  const jsonStr = await callGemini(imageBase64, mimeType, SATELLITE_PROMPT);

  return parseBasicExtraction(jsonStr);

}



export async function extractMissionIntelligenceFeatures(

  imageBase64: string,

  mimeType: string

): Promise<MissionIntelligenceExtraction> {

  const jsonStr = await callGemini(imageBase64, mimeType, MISSION_INTELLIGENCE_PROMPT);

  return parseMissionExtraction(jsonStr);

}



function parseBasicExtraction(jsonStr: string): SatelliteFeatureExtraction {

  try {

    const raw = JSON.parse(jsonStr) as SatelliteFeatureExtraction;

    return {

      potentialStructures: (raw.potentialStructures ?? []).map((s, i) => ({

        id: s.id ?? `s${i + 1}`,

        label: s.label ?? 'Possible structure',

        sketchX: clamp01(s.sketchX),

        sketchY: clamp01(s.sketchY),

        confidence: s.confidence ?? 0.5,

      })),

      roads: (raw.roads ?? []).map((r) => ({

        label: r.label ?? 'Road',

        sketchX: clamp01(r.sketchX),

        sketchY: clamp01(r.sketchY),

      })),

      waterBodies: (raw.waterBodies ?? []).map((w) => ({

        label: w.label ?? 'Water',

        sketchX: clamp01(w.sketchX),

        sketchY: clamp01(w.sketchY),

      })),

      boundaryHint: raw.boundaryHint?.map((p) => ({ x: clamp01(p.x), y: clamp01(p.y) })),

      confidence: raw.confidence ?? { overall: 0.5 },

    };

  } catch {

    return emptyBasic();

  }

}



function parseMissionExtraction(jsonStr: string): MissionIntelligenceExtraction {

  try {

    const raw = JSON.parse(jsonStr) as MissionIntelligenceExtraction;

    const basic = parseBasicExtraction(jsonStr);

    return {

      ...basic,

      boundaryPolygon: (raw.boundaryPolygon ?? raw.boundaryHint ?? []).map((p) => ({

        x: clamp01(p.x),

        y: clamp01(p.y),

      })),

      landmarks: (raw.landmarks ?? []).map((l, i) => ({

        id: l.id ?? `lm${i + 1}`,

        label: l.label ?? 'Landmark',

        sketchX: clamp01(l.sketchX),

        sketchY: clamp01(l.sketchY),

        confidence: l.confidence ?? 0.6,

      })),

      roadSegments: (raw.roadSegments ?? []).map((r, i) => ({

        id: r.id ?? `rd${i + 1}`,

        label: r.label ?? 'Road',

        points: (r.points ?? []).map((p) => ({ x: clamp01(p.x), y: clamp01(p.y) })),

        confidence: r.confidence ?? 0.6,

      })),

      canalCrossings: (raw.canalCrossings ?? []).map((c) => ({

        label: c.label ?? 'Canal crossing',

        sketchX: clamp01(c.sketchX),

        sketchY: clamp01(c.sketchY),

      })),

      vegetationPatches: (raw.vegetationPatches ?? []).map((v) => ({

        label: v.label ?? 'Vegetation',

        sketchX: clamp01(v.sketchX),

        sketchY: clamp01(v.sketchY),

      })),

      confidence: raw.confidence ?? basic.confidence,

    };

  } catch {

    return { ...emptyBasic(), boundaryPolygon: [], landmarks: [], roadSegments: [], canalCrossings: [], vegetationPatches: [] };

  }

}



function emptyBasic(): SatelliteFeatureExtraction {

  return { potentialStructures: [], roads: [], waterBodies: [], confidence: { overall: 0 } };

}



function clamp01(n: number): number {

  if (typeof n !== 'number' || Number.isNaN(n)) return 0.5;

  return Math.max(0, Math.min(1, n));

}


