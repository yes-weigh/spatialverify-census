import { query } from '../../db/pool.js';
import type { KnowledgeGraph } from '../reasoning/reasoning-engine.js';

export class KnowledgeGraphRepository {
  async get(missionId: string): Promise<KnowledgeGraph | null> {
    const { rows } = await query<{ graph: KnowledgeGraph }>(
      `SELECT graph FROM knowledge_graph_snapshots WHERE mission_id = $1`,
      [missionId]
    );
    return rows[0]?.graph ?? null;
  }

  async save(
    graph: KnowledgeGraph,
    factEngineVersion: string,
    reasoningEngineVersion: string
  ): Promise<void> {
    await query(
      `INSERT INTO knowledge_graph_snapshots (
        mission_id, graph, fact_engine_version, reasoning_engine_version, last_evidence_sequence, updated_at
      ) VALUES ($1, $2, $3, $4, $5, NOW())
      ON CONFLICT (mission_id) DO UPDATE SET
        graph = EXCLUDED.graph,
        fact_engine_version = EXCLUDED.fact_engine_version,
        reasoning_engine_version = EXCLUDED.reasoning_engine_version,
        last_evidence_sequence = EXCLUDED.last_evidence_sequence,
        updated_at = NOW()`,
      [
        graph.missionId,
        JSON.stringify(graph),
        factEngineVersion,
        reasoningEngineVersion,
        graph.meta.lastEvidenceSequence,
      ]
    );
  }
}

export const knowledgeGraphRepository = new KnowledgeGraphRepository();
