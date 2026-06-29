import { env } from '../config/env.js';

export interface AiLandmarkSuggestion {
  label: string;
  type: string;
  sketchX: number;
  sketchY: number;
  confidence: number;
}

export interface LayoutMapExtraction {
  landmarks: AiLandmarkSuggestion[];
  roads: Array<{ label: string; sketchX: number; sketchY: number }>;
  waterBodies: Array<{ label: string; sketchX: number; sketchY: number }>;
  confidence: Record<string, number>;
}

const EXTRACTION_PROMPT = `You are analyzing a Census HLB (House Listing Block) hand-drawn layout map image.
Identify visible landmarks and features. Return ONLY valid JSON with this exact structure:
{
  "landmarks": [{"label": "Temple", "type": "temple", "sketchX": 0.5, "sketchY": 0.3, "confidence": 0.8}],
  "roads": [{"label": "Main Road", "sketchX": 0.5, "sketchY": 0.5}],
  "waterBodies": [{"label": "Canal", "sketchX": 0.2, "sketchY": 0.7}],
  "confidence": {"overall": 0.7}
}
sketchX and sketchY are normalized 0-1 coordinates (0,0 = top-left of image).
Types: school, temple, mosque, church, bridge, junction, panchayat_office, post_office, railway, road, canal, river, other.
If unsure, omit the item. No markdown, no explanation.`;

export async function extractLayoutFeatures(
  imageBase64: string,
  mimeType: string
): Promise<LayoutMapExtraction> {
  if (!env.geminiApiKey) {
    return stubExtraction();
  }

  const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${env.geminiApiKey}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{
        parts: [
          { text: EXTRACTION_PROMPT },
          { inline_data: { mime_type: mimeType, data: imageBase64 } },
        ],
      }],
      generationConfig: { temperature: 0.2, maxOutputTokens: 4096 },
    }),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Gemini API error: ${res.status} ${err}`);
  }

  const data = await res.json() as {
    candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
  };
  const text = data.candidates?.[0]?.content?.parts?.[0]?.text ?? '{}';
  const jsonStr = text.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
  return parseExtraction(jsonStr);
}

function parseExtraction(jsonStr: string): LayoutMapExtraction {
  try {
    const raw = JSON.parse(jsonStr) as LayoutMapExtraction;
    return {
      landmarks: (raw.landmarks ?? []).map((l) => ({
        label: l.label ?? 'Landmark',
        type: l.type ?? 'other',
        sketchX: clamp01(l.sketchX),
        sketchY: clamp01(l.sketchY),
        confidence: l.confidence ?? 0.5,
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
      confidence: raw.confidence ?? { overall: 0.5 },
    };
  } catch {
    return stubExtraction();
  }
}

function stubExtraction(): LayoutMapExtraction {
  return {
    landmarks: [],
    roads: [],
    waterBodies: [],
    confidence: { overall: 0, note: 0 },
  };
}

function clamp01(n: number): number {
  if (typeof n !== 'number' || Number.isNaN(n)) return 0.5;
  return Math.max(0, Math.min(1, n));
}
