# Authentication Reference

## Cookie Sessions

| Attribute  | Value                                     | Why                                                                        |
| ---------- | ----------------------------------------- | -------------------------------------------------------------------------- |
| Name       | `__Host-session`                          | `__Host-` prefix forces `Secure`, `Path=/`, and no `Domain` attribute      |
| `HttpOnly` | always                                    | Unreadable from JavaScript                                                 |
| `Secure`   | always                                    | Never sent over HTTP; run local dev over HTTPS (`mkcert`) to keep the flag |
| `SameSite` | `Lax` (`Strict` for admin surfaces)       | Blocks cross-site POSTs; `Lax` still allows top-level navigation links     |
| `Path`     | `/`                                       | Required by `__Host-`                                                      |
| `Max-Age`  | 7 days, sliding                           | Idle timeout; an absolute cap is enforced server-side                      |
| Value      | Opaque random ID from `crypto.randomUUID` | Session data lives server-side; no claims in the cookie                    |

Rules:

- Rotate the session ID on login, privilege change, and password change (session fixation).
- Store sessions server-side (Redis, Postgres) keyed by ID; `iron-session` sealed cookies are acceptable for small, non-revocable payloads.
- Logout deletes the server session and clears the cookie with `maxAge: 0`.
- Read the session through one `getSession()` helper that returns `Session | null`; never parse cookies inline.

```ts
// src/lib/session.ts
import 'server-only';
import { cookies } from 'next/headers';
import { z } from 'zod';
import { sessionStore } from '@/data/session-store';

const SESSION_COOKIE = '__Host-session';
const SESSION_TTL_SECONDS = 60 * 60 * 24 * 7;

const SessionSchema = z.object({
  id: z.string(),
  userId: z.uuid(),
  role: z.enum(['member', 'admin']),
  expiresAt: z.coerce.date(),
});
export type Session = z.infer<typeof SessionSchema>;

const cookieOptions = { httpOnly: true, secure: true, sameSite: 'lax', path: '/' } as const;

export async function getSession(): Promise<Session | null> {
  const id = (await cookies()).get(SESSION_COOKIE)?.value;
  if (!id) return null;
  const parsed = SessionSchema.safeParse(await sessionStore.get(id));
  if (!parsed.success || parsed.data.expiresAt < new Date()) return null;
  return parsed.data;
}

export async function createSession(userId: string, role: Session['role']): Promise<void> {
  const id = crypto.randomUUID();
  const expiresAt = new Date(Date.now() + SESSION_TTL_SECONDS * 1000);
  await sessionStore.set(id, { id, userId, role, expiresAt }, SESSION_TTL_SECONDS);
  (await cookies()).set(SESSION_COOKIE, id, { ...cookieOptions, maxAge: SESSION_TTL_SECONDS });
}

export async function destroySession(): Promise<void> {
  const store = await cookies();
  const id = store.get(SESSION_COOKIE)?.value;
  if (id) await sessionStore.delete(id);
  store.set(SESSION_COOKIE, '', { ...cookieOptions, maxAge: 0 });
}
```

Use `better-auth` or `next-auth` (Auth.js) for credential handling, OAuth, and password hashing. Never write password hashing yourself; if a custom flow is unavoidable, use `@node-rs/argon2` with the OWASP recommended parameters.

## BFF Pattern

The browser never holds a third-party access token. A Backend-for-Frontend (Next.js route handlers, or a small Node service in front of a Vite SPA) owns the tokens and exchanges the session cookie for an `Authorization` header.

```text
Browser --(Cookie: __Host-session)--> BFF --(Authorization: Bearer <access>)--> Upstream API
                                       |
                                       +-- session store: { userId, accessToken, refreshToken, expiresAt }
```

```ts
// app/api/proxy/[...path]/route.ts
import { NextResponse, type NextRequest } from 'next/server';
import { serverEnv } from '@/env.server';
import { getSession } from '@/lib/session';
import { getAccessToken } from '@/lib/tokens';

const ALLOWED_METHODS = new Set(['GET', 'POST', 'PUT', 'PATCH', 'DELETE']);
type Context = { params: Promise<{ path: string[] }> };

async function handler(request: NextRequest, { params }: Context): Promise<NextResponse> {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'UNAUTHORIZED' }, { status: 401 });
  if (!ALLOWED_METHODS.has(request.method)) return NextResponse.json({ error: 'METHOD' }, { status: 405 });

  const { path } = await params;
  // Host is fixed by config; the client controls only the path segments, which are re-encoded.
  const upstream = new URL(path.map(encodeURIComponent).join('/'), serverEnv.API_BASE_URL);
  upstream.search = request.nextUrl.search;

  const accessToken = await getAccessToken(session); // refreshes when within 60s of expiry
  const response = await fetch(upstream, {
    method: request.method,
    headers: {
      authorization: `Bearer ${accessToken}`,
      'content-type': request.headers.get('content-type') ?? 'application/json',
    },
    body: request.method === 'GET' ? undefined : await request.text(),
    signal: AbortSignal.timeout(10_000),
  });

  return new NextResponse(response.body, {
    status: response.status,
    headers: { 'content-type': response.headers.get('content-type') ?? 'application/json' },
  });
}

export { handler as DELETE, handler as GET, handler as PATCH, handler as POST, handler as PUT };
```

## Token Refresh

| Token         | Lives in                                                   | Lifetime   | Refresh                                                    |
| ------------- | ---------------------------------------------------------- | ---------- | ---------------------------------------------------------- |
| Session ID    | `__Host-session` cookie                                    | 7 days     | Sliding on activity                                        |
| Access token  | BFF session store, or a module variable in a SPA           | 5 - 15 min | BFF refreshes before forwarding; SPA calls `/auth/refresh` |
| Refresh token | BFF session store, or `httpOnly` cookie on `/auth/refresh` | 30 days    | Rotated on every use; reuse detection revokes the family   |

SPA without a BFF: keep the access token in a module-level variable (not `zustand`, not web storage), refresh on 401 with a single in-flight promise, and accept that a page reload costs one refresh call.

```ts
// src/lib/token-cache.ts (SPA without a BFF)
import { z } from 'zod';

const RefreshResponse = z.object({ token: z.string().min(1) });

let accessToken: string | null = null;
let inflight: Promise<string> | null = null;

export function getCachedToken(): string | null {
  return accessToken;
}

export function clearCachedToken(): void {
  accessToken = null;
}

export function refreshAccessToken(): Promise<string> {
  inflight ??= fetch('/auth/refresh', { method: 'POST', credentials: 'same-origin' })
    .then(async (res) => {
      if (!res.ok) throw new Error('REFRESH_FAILED');
      accessToken = RefreshResponse.parse(await res.json()).token;
      return accessToken;
    })
    .finally(() => {
      inflight = null;
    });
  return inflight;
}
```

## CSRF

| Setup                                      | Defense                                                                                                            |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------ |
| Next.js Server Actions                     | Built-in `Origin`/`Host` comparison; set `serverActions.allowedOrigins` when behind a reverse proxy                |
| Next.js route handlers with cookie auth    | `SameSite=Lax` plus the explicit `isSameOrigin()` check below on every non-GET                                     |
| Vite SPA + separate API with cookie auth   | `SameSite=Lax`, strict CORS origin allow-list, and a required custom header so every mutation triggers a preflight |
| `SameSite=None` cookies or legacy browsers | Double-submit token: random value in a non-`httpOnly` cookie, echoed in `X-CSRF-Token`, compared server-side       |

```ts
// src/lib/csrf.ts
import 'server-only';
import { serverEnv } from '@/env.server';

const SAFE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);
const TRUSTED_ORIGINS = new Set([serverEnv.APP_ORIGIN]);

/** Browsers send `Origin` on every cross-origin request and on same-origin non-GET requests. */
export function isSameOrigin(request: Request): boolean {
  if (SAFE_METHODS.has(request.method)) return true;
  const origin = request.headers.get('origin');
  return origin !== null && TRUSTED_ORIGINS.has(origin);
}
```

```ts
// app/api/items/route.ts (excerpt)
export async function POST(request: Request): Promise<Response> {
  if (!isSameOrigin(request)) return Response.json({ error: 'FORBIDDEN' }, { status: 403 });
  const session = await getSession();
  if (!session) return Response.json({ error: 'UNAUTHORIZED' }, { status: 401 });
  // ...validate with zod, then act
}
```

## Secure Fetch Wrapper

Client-side wrapper for the same-origin BFF: relative paths only, cookies attached, a custom header that forces preflight for any cross-origin caller, a timeout, and a `zod` schema on every response.

```ts
// src/lib/api-fetch.ts
import { z } from 'zod';

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
  ) {
    super(`API ${status}: ${code}`);
    this.name = 'ApiError';
  }
}

const Problem = z.object({ error: z.string() }).partial();
const API_BASE = '/api/proxy';

type ApiFetchOptions<TSchema extends z.ZodType> = {
  schema: TSchema;
  method?: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
  body?: unknown;
  signal?: AbortSignal;
  timeoutMs?: number;
};

export async function apiFetch<TSchema extends z.ZodType>(
  path: string,
  { schema, method = 'GET', body, signal, timeoutMs = 10_000 }: ApiFetchOptions<TSchema>,
): Promise<z.infer<TSchema>> {
  if (!/^\/(?![/\\])/.test(path)) throw new Error('apiFetch: path must be a same-origin relative path');
  const timeout = AbortSignal.timeout(timeoutMs);
  const url = new URL(`${API_BASE}${path}`, window.location.origin);

  const response = await fetch(url, {
    method,
    credentials: 'same-origin',
    headers: {
      accept: 'application/json',
      'x-requested-with': 'fetch',
      ...(body === undefined ? {} : { 'content-type': 'application/json' }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: signal ? AbortSignal.any([signal, timeout]) : timeout,
  });

  if (!response.ok) {
    const problem = Problem.safeParse(await response.json().catch(() => null));
    throw new ApiError(response.status, problem.success ? (problem.data.error ?? 'UNKNOWN') : 'UNKNOWN');
  }
  return schema.parse(await response.json());
}
```

```ts
// src/lib/api-fetch.test.ts
// @vitest-environment jsdom
import { http, HttpResponse } from 'msw';
import { setupServer } from 'msw/node';
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';
import { z } from 'zod';
import { apiFetch } from './api-fetch';

const server = setupServer();
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const User = z.object({ id: z.string(), name: z.string() });

describe('apiFetch', () => {
  it('parses a valid response', async () => {
    server.use(http.get('/api/proxy/users/1', () => HttpResponse.json({ id: '1', name: 'Ada' })));
    await expect(apiFetch('/users/1', { schema: User })).resolves.toEqual({ id: '1', name: 'Ada' });
  });

  it('rejects a response that fails the schema', async () => {
    server.use(http.get('/api/proxy/users/1', () => HttpResponse.json({ id: 1 })));
    await expect(apiFetch('/users/1', { schema: User })).rejects.toThrow(z.ZodError);
  });

  it('maps non-2xx to ApiError with the server code', async () => {
    server.use(
      http.get('/api/proxy/users/1', () => HttpResponse.json({ error: 'UNAUTHORIZED' }, { status: 401 })),
    );
    await expect(apiFetch('/users/1', { schema: User })).rejects.toMatchObject({ status: 401, code: 'UNAUTHORIZED' });
  });

  it('sends cookies and the preflight-forcing header', async () => {
    let received: Headers | undefined;
    server.use(
      http.get('/api/proxy/users/1', ({ request }) => {
        received = request.headers;
        return HttpResponse.json({ id: '1', name: 'Ada' });
      }),
    );
    await apiFetch('/users/1', { schema: User });
    expect(received?.get('x-requested-with')).toBe('fetch');
  });

  it('refuses absolute and protocol-relative URLs', async () => {
    await expect(apiFetch('https://evil.example/x', { schema: User })).rejects.toThrow('relative path');
    await expect(apiFetch('//evil.example/x', { schema: User })).rejects.toThrow('relative path');
  });
});
```

## Logging

Never log `Authorization` headers, cookies, session IDs, tokens, passwords, or full user objects. Scrub in one place:

```ts
// src/lib/logger.ts (excerpt)
const REDACT_KEYS = /^(authorization|cookie|set-cookie|password|token|secret|session)$/i;

export function redact<T extends Record<string, unknown>>(record: T): T {
  return Object.fromEntries(
    Object.entries(record).map(([key, value]) => [key, REDACT_KEYS.test(key) ? '[redacted]' : value]),
  ) as T;
}
```

Configure the error tracker the same way (`beforeSend` in `@sentry/nextjs`) so request headers and cookies never leave the server.
