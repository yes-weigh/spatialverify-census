export interface LearningFeedbackEvent {
  id: string;
  ebId: string;
  eventType:
    | 'observation_target_confirmed'
    | 'observation_target_rejected'
    | 'gap_resolved'
    | 'gap_false_positive'
    | 'classification_override';
  objectId?: string;
  metadata: Record<string, unknown>;
  recordedAt: string;
}

/** In-memory stub — persists to DB in production learning pipeline. */
const feedbackBuffer: LearningFeedbackEvent[] = [];

export function recordLearningFeedback(event: Omit<LearningFeedbackEvent, 'id' | 'recordedAt'>): LearningFeedbackEvent {
  const record: LearningFeedbackEvent = {
    ...event,
    id: `lf_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    recordedAt: new Date().toISOString(),
  };
  feedbackBuffer.push(record);
  if (feedbackBuffer.length > 5000) feedbackBuffer.shift();
  return record;
}

export function getRecentFeedback(limit = 100): LearningFeedbackEvent[] {
  return feedbackBuffer.slice(-limit);
}

export function learningEngineStats() {
  return {
    eventsBuffered: feedbackBuffer.length,
    status: 'stub',
    message: 'Learning engine collects feedback; model training activates after 100+ completed HLBs.',
  };
}
