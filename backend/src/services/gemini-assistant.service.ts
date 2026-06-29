import { env } from '../config/env.js';

const ASSISTANT_PROMPT = `You are an optional field assistant for Census HLB mapping. You help enumerators with classification questions only — you do NOT extract geometry from images.

Answer briefly. If asked to detect boundaries or count buildings from an image, decline and explain that spatial extraction is handled offline by the CV engine.

Context provided by the app may include object labels and types.`;

export interface AssistantRequest {
  question: string;
  context?: {
    objectLabel?: string;
    objectType?: string;
    buildingType?: string;
  };
}

export interface AssistantResponse {
  answer: string;
  suggestedClassification?: string;
  confidence?: number;
  source: 'gemini_assistant' | 'offline_stub';
}

export async function askFieldAssistant(req: AssistantRequest): Promise<AssistantResponse> {
  if (!env.geminiApiKey) {
    return {
      answer: 'Assistant unavailable offline. Use standard Census classification codes.',
      source: 'offline_stub',
    };
  }

  const contextStr = req.context
    ? `\nContext: ${JSON.stringify(req.context)}`
    : '';

  const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${env.geminiApiKey}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{
        parts: [{ text: `${ASSISTANT_PROMPT}${contextStr}\n\nEnumerator question: ${req.question}` }],
      }],
      generationConfig: { temperature: 0.3, maxOutputTokens: 512 },
    }),
  });

  if (!res.ok) {
    return { answer: 'Assistant temporarily unavailable.', source: 'offline_stub' };
  }

  const data = await res.json() as {
    candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
  };
  const text = data.candidates?.[0]?.content?.parts?.[0]?.text ?? 'No response.';

  return { answer: text.trim(), source: 'gemini_assistant' };
}
