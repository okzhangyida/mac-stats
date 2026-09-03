interface AnalyticsEngineDataset {
  writeDataPoint(event: {
    indexes?: string[];
    blobs?: string[];
    doubles?: number[];
  }): void;
}

interface Env {
  USAGE: AnalyticsEngineDataset;
}

const events = new Set(['install', 'daily_active', 'version_changed']);
const architectures = new Set(['arm64', 'x86_64', 'other']);
const languages = new Set(['zh-Hans', 'en', 'other']);

type UsagePayload = {
  schemaVersion: number;
  event: string;
  appVersion: string;
  build: string;
  osMajor: number;
  architecture: string;
  language: string;
  channel: string;
};

function isValid(payload: unknown): payload is UsagePayload {
  if (!payload || typeof payload !== 'object') return false;
  const value = payload as Record<string, unknown>;
  return value.schemaVersion === 1
    && typeof value.event === 'string' && events.has(value.event)
    && typeof value.appVersion === 'string' && /^[0-9A-Za-z.-]{1,24}$/.test(value.appVersion)
    && typeof value.build === 'string' && /^[0-9A-Za-z.-]{1,16}$/.test(value.build)
    && typeof value.osMajor === 'number' && Number.isInteger(value.osMajor) && value.osMajor >= 13 && value.osMajor <= 99
    && typeof value.architecture === 'string' && architectures.has(value.architecture)
    && typeof value.language === 'string' && languages.has(value.language)
    && value.channel === 'direct';
}

function response(status: number, body?: string): Response {
  return new Response(body ?? null, {
    status,
    headers: {
      'Cache-Control': 'no-store',
      ...(body ? { 'Content-Type': 'application/json; charset=utf-8' } : {}),
    },
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === 'GET' && url.pathname === '/health') {
      return response(200, JSON.stringify({ status: 'ok' }));
    }
    if (request.method !== 'POST' || url.pathname !== '/v1/events') {
      return response(404);
    }

    const contentLength = Number(request.headers.get('content-length') ?? '0');
    if (contentLength > 2048) return response(413);
    if (!request.headers.get('content-type')?.toLowerCase().startsWith('application/json')) {
      return response(415);
    }

    let raw: string;
    try {
      raw = await request.text();
    } catch {
      return response(400);
    }
    if (raw.length > 2048) return response(413);

    let payload: unknown;
    try {
      payload = JSON.parse(raw);
    } catch {
      return response(400);
    }
    if (!isValid(payload)) return response(400);

    // Analytics Engine assigns the timestamp. No IP, country, header, cookie,
    // device identifier, or user-specific index is read or written here.
    env.USAGE.writeDataPoint({
      indexes: [payload.event],
      blobs: [
        payload.event,
        payload.appVersion,
        payload.build,
        String(payload.osMajor),
        payload.architecture,
        payload.language,
        payload.channel,
      ],
      doubles: [1],
    });

    return response(204);
  },
};
