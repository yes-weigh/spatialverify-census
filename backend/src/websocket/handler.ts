import type { FastifyInstance } from 'fastify';
import type { WebSocket } from 'ws';
import { env } from '../config/env.js';

interface ConnectedClient {
  socket: WebSocket;
  userId: string;
  projectId?: string;
}

const clients = new Map<string, ConnectedClient>();

export function setupWebSocket(app: FastifyInstance): void {
  app.get('/ws', { websocket: true }, async (socket, request) => {
    const token = (request.query as { token?: string }).token;
    if (!token) {
      socket.close(4001, 'Authentication required');
      return;
    }

    let userId: string;
    try {
      const payload = app.jwt.verify<{ sub: string }>(token);
      userId = payload.sub;
    } catch {
      socket.close(4001, 'Invalid token');
      return;
    }

    const clientId = `${userId}-${Date.now()}`;
    clients.set(clientId, { socket, userId });

    socket.send(JSON.stringify({ type: 'connected', clientId }));

  socket.on('message', (raw: Buffer) => {
      try {
        const message = JSON.parse(raw.toString());
        handleMessage(clientId, message);
      } catch {
        socket.send(JSON.stringify({ type: 'error', message: 'Invalid message format' }));
      }
    });

    socket.on('close', () => {
      clients.delete(clientId);
    });
  });
}

function handleMessage(clientId: string, message: Record<string, unknown>): void {
  const client = clients.get(clientId);
  if (!client) return;

  switch (message.type) {
    case 'subscribe':
      client.projectId = message.projectId as string;
      client.socket.send(JSON.stringify({
        type: 'subscribed',
        projectId: client.projectId,
      }));
      break;

    case 'ping':
      client.socket.send(JSON.stringify({ type: 'pong', timestamp: Date.now() }));
      break;

    case 'location_update':
      broadcastToProject(client.projectId, {
        type: 'worker_location',
        userId: client.userId,
        location: message.location,
        timestamp: Date.now(),
      }, clientId);
      break;

    default:
      client.socket.send(JSON.stringify({ type: 'error', message: 'Unknown message type' }));
  }
}

export function broadcastToProject(
  projectId: string | undefined,
  data: Record<string, unknown>,
  excludeClientId?: string
): void {
  if (!projectId) return;

  const payload = JSON.stringify(data);
  for (const [id, client] of clients) {
    if (id !== excludeClientId && client.projectId === projectId && client.socket.readyState === 1) {
      client.socket.send(payload);
    }
  }
}

export function notifyUser(userId: string, data: Record<string, unknown>): void {
  const payload = JSON.stringify(data);
  for (const client of clients.values()) {
    if (client.userId === userId && client.socket.readyState === 1) {
      client.socket.send(payload);
    }
  }
}
