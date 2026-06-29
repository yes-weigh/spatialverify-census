import { verifyEvidenceChain } from './hash.js';
import { evidenceRepository } from './evidence.repository.js';
import type { EvidenceEnvelope } from './types.js';

export class EvidenceReplay {
  /** Load ordered evidence for a mission and verify hash chain integrity. */
  async loadVerified(missionId: string): Promise<EvidenceEnvelope[]> {
    const events = await evidenceRepository.listByMission(missionId);
    if (events.length > 0 && !verifyEvidenceChain(events)) {
      throw new Error(`Evidence chain integrity failed for mission ${missionId}`);
    }
    return events;
  }
}

export const evidenceReplay = new EvidenceReplay();
