---
name: react-static-security
description: Static security review for React web apps built with Vite or Next.js. Covers secrets leaking through VITE_ and NEXT_PUBLIC_ env vars, session token storage, XSS through dangerouslySetInnerHTML, zod validation at trust boundaries, nonce-based CSP and security headers, open redirects, unsafe href schemes, CSRF, Server Action authorization, SSRF, source maps, and supply-chain hygiene with pnpm audit and osv-scanner. Use when reviewing or writing code that handles secrets, user data, HTML rendering, redirects, cookies, authentication, or dependencies, or when the user says "security review", "audit for XSS", "check for leaked secrets", "OWASP", "harden the app", or "add CSP". Static analysis only, not pen-testing or runtime analysis.
argument-hint: "[file-or-directory]"
allowed-tools: Read Glob Grep Bash
---

# Static Security

Every byte of a React bundle runs in an untrusted browser, and every Server Action, route handler, and loader is a public HTTP endpoint. This skill covers findings detectable by reading source code and configuration, mapped to the [OWASP Top 10 (2021)](https://owasp.org/Top10/).

---

## Core Standards

Apply these standards to ALL React security work:

- **Never put secrets in `VITE_*` or `NEXT_PUBLIC_*` variables** — both prefixes inline the value into the browser bundle; secrets live only in server-only env vars read through a validated `env.server.ts`
- **Session tokens live in `httpOnly; Secure; SameSite` cookies** — never in `localStorage`, `sessionStorage`, or a `zustand` store; any XSS reads web storage in one line
- **`dangerouslySetInnerHTML` only with `dompurify` output** — route every HTML string through one `sanitizeHtml()` helper; markdown, CMS, and user HTML are never trusted
- **Validate every external input with `zod` at the boundary** — API responses, URL params, form data, Server Action arguments, and webhook bodies are `unknown` until parsed
- **Ship a nonce-based CSP with no `'unsafe-inline'`** — `script-src 'self' 'nonce-...' 'strict-dynamic'`; relax only in development and only in the dev server config
- **Redirect only to allow-listed relative paths** — `?next=` and `?returnTo=` values pass through `safeRedirectPath()`; never redirect to a raw query value
- **Validate URL schemes on dynamic `href`** — `javascript:` and `data:` are blocked; allow `http`, `https`, `mailto`, `tel`, and same-origin relative paths only
- **Authorize inside every Server Action and route handler** — anyone with the action ID can call it; check the session and resource ownership on every invocation, never only in a layout or page
- **Protect cookie-authenticated mutations against CSRF** — `SameSite=Lax` plus an `Origin` header check on every non-GET route handler
- **Never fetch user-supplied URLs from server code** — SSRF reaches internal networks and cloud metadata endpoints; allow-list outbound hosts
- **Commit the lockfile and gate CI on `pnpm audit --audit-level=high` and `osv-scanner`** — install with `--frozen-lockfile`; set `minimumReleaseAge` in `pnpm-workspace.yaml`
- **Do not ship source maps to production** — `productionBrowserSourceMaps: false` and `build.sourcemap: 'hidden'`; upload maps to the error tracker only

---

## Secrets and Environment Variables

Anything prefixed `VITE_` (`import.meta.env`) or `NEXT_PUBLIC_` (`process.env`) is string-replaced into the client bundle at build time and readable by every visitor. Validate both sides with `zod` and make the server side impossible to import from the client.

```ts
// src/env.server.ts
import 'server-only'; // Next.js: the build fails if a client component imports this file
import { z } from 'zod';

const ServerEnv = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']),
  APP_ORIGIN: z.url(),
  DATABASE_URL: z.url(),
  SESSION_SECRET: z.string().min(32),
  STRIPE_SECRET_KEY: z.string().startsWith('sk_'),
});

export const serverEnv = ServerEnv.parse(process.env);
```

```ts
// src/env.client.ts
import { z } from 'zod';

const ClientEnv = z.object({
  NEXT_PUBLIC_API_URL: z.url(),
  NEXT_PUBLIC_SENTRY_DSN: z.url().optional(),
});

// List each key explicitly: Next.js inlines NEXT_PUBLIC_* by name, not by object access.
export const clientEnv = ClientEnv.parse({
  NEXT_PUBLIC_API_URL: process.env.NEXT_PUBLIC_API_URL,
  NEXT_PUBLIC_SENTRY_DSN: process.env.NEXT_PUBLIC_SENTRY_DSN,
});
```

For Vite, the client schema parses `import.meta.env` with `VITE_` keys and there is no server side. `.env`, `.env.local`, and `.env.*.local` are gitignored; only `.env.example` with placeholder values is committed.

---

## Session and Token Storage

| Storage                         | Readable by XSS | Sent automatically | Verdict                                  |
| ------------------------------- | --------------- | ------------------ | ---------------------------------------- |
| `httpOnly; Secure; SameSite`    | No              | Yes (same-site)    | Use for session IDs and refresh tokens   |
| In-memory variable              | Yes             | No                 | Acceptable for short-lived access tokens |
| `localStorage`/`sessionStorage` | Yes             | No                 | Never for tokens, PII, or session state  |
| Non-`httpOnly` cookie           | Yes             | Yes                | Never for auth material                  |

```ts
// app/api/auth/login/route.ts (excerpt)
import { cookies } from 'next/headers';

const cookieStore = await cookies();
cookieStore.set('__Host-session', sessionId, {
  httpOnly: true,
  secure: true,
  sameSite: 'lax',
  path: '/',
  maxAge: 60 * 60 * 24 * 7,
});
```

See [references/auth.md](references/auth.md) for the cookie session lifecycle, token refresh, the BFF pattern, CSRF checks, and a secure `apiFetch` wrapper with its `msw` test.

---

## XSS and HTML Rendering

React escapes text children by default. The escape hatches are `dangerouslySetInnerHTML`, `href`/`src` with attacker-controlled schemes, `eval`/`new Function`, and third-party scripts. Sanitize once, in one helper.

```ts
// src/lib/sanitize.ts
import DOMPurify from 'isomorphic-dompurify'; // 'dompurify' in a browser-only Vite app

const ALLOWED_TAGS = ['a', 'b', 'blockquote', 'br', 'code', 'em', 'i', 'li', 'ol', 'p', 'pre', 'strong', 'ul'];
const ALLOWED_ATTR = ['href', 'rel', 'target', 'title'];

DOMPurify.addHook('afterSanitizeAttributes', (node) => {
  if (node.tagName === 'A' && node.getAttribute('target') === '_blank') {
    node.setAttribute('rel', 'noopener noreferrer');
  }
});

export function sanitizeHtml(dirty: string): string {
  return DOMPurify.sanitize(dirty, {
    ALLOWED_TAGS,
    ALLOWED_ATTR,
    ALLOWED_URI_REGEXP: /^(?:https?|mailto|tel):|^[/#]/i,
  });
}
```

```tsx
// src/components/RichText.tsx
import { useMemo } from 'react';
import { sanitizeHtml } from '@/lib/sanitize';

export function RichText({ html }: { html: string }) {
  const clean = useMemo(() => sanitizeHtml(html), [html]);
  // eslint-disable-next-line react/no-danger -- the only permitted call site; input is sanitized above
  return <div dangerouslySetInnerHTML={{ __html: clean }} />;
}
```

Set `react/no-danger`, `react/jsx-no-script-url`, and `react/jsx-no-target-blank` to `error`; `RichText` is the only component allowed to disable the first one. Tests for `sanitizeHtml()` are in [references/helpers.md](references/helpers.md).

---

## Redirects and URLs

```ts
// src/lib/safe-url.ts
const SAFE_SCHEMES = new Set(['http:', 'https:', 'mailto:', 'tel:']);

/** Returns `candidate` only when it is a same-origin absolute path; otherwise `fallback`. */
export function safeRedirectPath(candidate: string | null | undefined, fallback = '/'): string {
  if (!candidate || !candidate.startsWith('/')) return fallback;
  // "//host", "/\host", backslashes, and control characters resolve off-origin in some browsers.
  if (/^\/[/\\]/.test(candidate) || /[\u0000-\u001f\\]/.test(candidate)) return fallback;
  const url = new URL(candidate, 'http://placeholder');
  if (url.origin !== 'http://placeholder') return fallback;
  return `${url.pathname}${url.search}${url.hash}`;
}

/** Returns an href safe to render, or `undefined` when the scheme is not allow-listed. */
export function safeHref(candidate: string): string | undefined {
  if (/^\/(?![/\\])/.test(candidate)) return candidate;
  try {
    const url = new URL(candidate);
    return SAFE_SCHEMES.has(url.protocol) ? url.href : undefined;
  } catch {
    return undefined;
  }
}
```

Tests for both helpers are in [references/helpers.md](references/helpers.md). Usage: `redirect(safeRedirectPath(searchParams.get('next')))` and `<a href={safeHref(link.url)}>`. `<Link>` from Next.js and React Router is safe for relative paths, but any absolute `href` string still goes through `safeHref()`.

---

## Input Validation at the Boundary

Every value that crosses into the app is `unknown`. Parse it once with `zod`, then pass typed data inward.

| Boundary               | Parse with                                                       |
| ---------------------- | ---------------------------------------------------------------- |
| API response           | `UserDto.parse(await res.json())` inside the API client          |
| URL search params      | `SearchSchema.parse(Object.fromEntries(searchParams))` in loader |
| Route params           | `z.object({ id: z.uuid() }).parse(params)`                       |
| Form data              | `react-hook-form` + `zodResolver`, and again on the server       |
| Server Action argument | `Schema.safeParse(rawInput)` as the first statement after auth   |
| Webhook body           | Verify the signature, then `Schema.parse(JSON.parse(body))`      |

```ts
// app/profile/actions.ts
'use server';
import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { getSession } from '@/lib/session';
import { profileRepository } from '@/repositories/profile';

const UpdateProfileInput = z.object({
  displayName: z.string().trim().min(1).max(80),
  bio: z.string().max(500).optional(),
});

type ActionResult = { ok: true } | { ok: false; error: 'UNAUTHORIZED' | 'INVALID_INPUT' };

export async function updateProfile(rawInput: unknown): Promise<ActionResult> {
  const session = await getSession(); // 1. authenticate on every call
  if (!session) return { ok: false, error: 'UNAUTHORIZED' };
  const parsed = UpdateProfileInput.safeParse(rawInput); // 2. validate on every call
  if (!parsed.success) return { ok: false, error: 'INVALID_INPUT' };
  await profileRepository.update(session.userId, parsed.data); // 3. scope the write to the caller
  revalidatePath('/profile');
  return { ok: true };
}
```

A Server Action is a POST endpoint: never accept a `userId` from the client, never trust a hidden field, and return generic error codes (no stack traces, no SQL, no internal paths).

---

## CSP and Security Headers

The CSP is generated per request in `proxy.ts` (Next.js 16+; `middleware.ts` on 15): a fresh base64 nonce, `script-src 'self' 'nonce-<n>' 'strict-dynamic'`, `style-src 'self' 'nonce-<n>'`, `frame-ancestors 'none'`, `base-uri 'self'`, `form-action 'self'`, `object-src 'none'`, and `'unsafe-eval'` only when `NODE_ENV === 'development'`. The nonce is set on the request `Content-Security-Policy` header so Next.js applies it to its own scripts, and on the response so the browser enforces it. Static headers live in `next.config.ts`.

| Header                       | Value                                          |
| ---------------------------- | ---------------------------------------------- |
| `Content-Security-Policy`    | Nonce-based policy above; no `'unsafe-inline'` |
| `Strict-Transport-Security`  | `max-age=63072000; includeSubDomains; preload` |
| `X-Content-Type-Options`     | `nosniff`                                      |
| `Referrer-Policy`            | `strict-origin-when-cross-origin`              |
| `Permissions-Policy`         | `camera=(), microphone=(), geolocation=()`     |
| `Cross-Origin-Opener-Policy` | `same-origin`                                  |
| `X-Frame-Options`            | `DENY` (legacy fallback for `frame-ancestors`) |

See [references/headers.md](references/headers.md) for the complete `proxy.ts` nonce middleware, the full header table with rationale, `next.config.ts` `headers()`, reading the nonce in components, Vite dev server and nginx configs, and a report-only rollout.

---

## Server-Side Risks

- **SSRF** — never `fetch(url)` where `url` comes from a request; resolve against an allow-list of hosts and reject private ranges (`10/8`, `172.16/12`, `192.168/16`, `169.254/16`, `::1`)
- **Injection** — use the ORM query builder (`prisma`, `drizzle-orm`) with parameters; no template-string SQL, no `child_process.exec` with request data
- **Rate limiting** — login, signup, password reset, and OTP routes are rate limited per IP and per account
- **Error exposure** — route handlers return `{ error: 'GENERIC_CODE' }`; details go to the logger with PII and tokens scrubbed
- **CORS** — explicit origin allow-list; `Access-Control-Allow-Origin: *` never combines with `credentials: 'include'`

---

## Supply Chain and Build Output

| Control                                         | Where                                             |
| ----------------------------------------------- | ------------------------------------------------- |
| `pnpm install --frozen-lockfile`                | CI install step                                   |
| `pnpm audit --audit-level=high`                 | CI, fails the job                                 |
| `osv-scanner --lockfile=pnpm-lock.yaml`         | CI, fails on any CVE                              |
| `minimumReleaseAge: 1440` (minutes)             | `pnpm-workspace.yaml`                             |
| `onlyBuiltDependencies` allow-list              | `pnpm-workspace.yaml`; install scripts stay off   |
| `save-exact=true`                               | `.npmrc`; Renovate or Dependabot moves versions   |
| `productionBrowserSourceMaps: false`            | `next.config.ts` (default)                        |
| `build.sourcemap: 'hidden'` + upload to tracker | `vite.config.ts`; never serve `.map` from the CDN |

See [references/supply-chain.md](references/supply-chain.md) for the complete `pnpm-workspace.yaml`, the CI workflow, Renovate and Dependabot configs, provenance, and typosquatting signals.

---

## OWASP Top 10 (2021) Mapping

| Category                      | React / Next.js mitigation                                                                                |
| ----------------------------- | --------------------------------------------------------------------------------------------------------- |
| A01 Broken Access Control     | Authorize in every Server Action, route handler, and loader; scope queries by session user; safe redirect |
| A02 Cryptographic Failures    | `httpOnly; Secure` cookies, HSTS, no secrets in the bundle, Web Crypto only, no custom hashing            |
| A03 Injection                 | `zod` at every boundary, `sanitizeHtml()`, ORM parameters, `safeHref()`, no `eval`                        |
| A04 Insecure Design           | BFF pattern, deny by default, rate limiting on auth flows, threat model per feature                       |
| A05 Security Misconfiguration | Nonce CSP, header table, `NODE_ENV=production`, no source maps, explicit CORS                             |
| A06 Vulnerable Components     | `pnpm audit`, `osv-scanner`, Renovate, `minimumReleaseAge`, frozen lockfile                               |
| A07 Auth Failures             | Cookie sessions via `better-auth` or `next-auth`, rotate on login, CSRF, no tokens in web storage         |
| A08 Integrity Failures        | Lockfile, `onlyBuiltDependencies`, SRI on third-party `<script>`, `zod` on deserialized data              |
| A09 Logging Failures          | Structured server logs with PII scrubbed, auth events audited, `beforeSend` scrubbing in Sentry           |
| A10 SSRF                      | Outbound host allow-list, no user URLs in server `fetch`, block private IP ranges                         |

---

## Review Workflow

1. Detect the framework (`next.config.*` or `vite.config.*`) and locate env files, `proxy.ts`/`middleware.ts`, route handlers, and `'use server'` files.
2. Run the grep pass below and open every hit.
3. Check each hit against the Core Standards; record file, line, severity, and fix.
4. Run `pnpm audit --audit-level=high` and `osv-scanner --lockfile=pnpm-lock.yaml`.
5. Report using the severity guide in [references/packages.md](references/packages.md).

```bash
rg -n "dangerouslySetInnerHTML" src app
rg -in "(localStorage|sessionStorage)\.setItem\(.*(token|jwt|session|secret)" src app
rg -n "(NEXT_PUBLIC|VITE)_[A-Z0-9_]*(SECRET|KEY|TOKEN|PASSWORD|PRIVATE)" . -g '!node_modules'
rg -n "\beval\(|new Function\(|setTimeout\(\s*['\"]" src app
rg -n "href=\{" src app                                            # confirm safeHref() on dynamic values
rg -n "redirect\(.*(searchParams|query|params|formData)" src app
rg -n "'unsafe-inline'|'unsafe-eval'" . -g '!node_modules'
rg -n "rejectUnauthorized:\s*false|NODE_TLS_REJECT_UNAUTHORIZED" . -g '!node_modules'
rg -l "'use server'" src app | xargs rg -L "getSession|auth\("      # Server Actions with no auth call
rg -n "fetch\(\s*(req|request|body|params|searchParams)" src app   # SSRF candidates
rg -n "productionBrowserSourceMaps:\s*true|sourcemap:\s*true" . -g '!node_modules'
rg -in "console\.(log|info|debug)\(.*(token|password|secret|authorization)" src app
```

---

## Anti-Patterns

| Anti-Pattern                                       | Problem                                                 | Correct Approach                                                |
| -------------------------------------------------- | ------------------------------------------------------- | --------------------------------------------------------------- |
| `NEXT_PUBLIC_STRIPE_SECRET_KEY`                    | Secret inlined into the bundle                          | `STRIPE_SECRET_KEY` read via `env.server.ts` with `server-only` |
| `localStorage.setItem('token', jwt)`               | Any XSS exfiltrates the session                         | `httpOnly; Secure; SameSite=Lax` cookie set by the server       |
| `dangerouslySetInnerHTML={{ __html: post.body }}`  | Stored XSS                                              | `sanitizeHtml(post.body)` through `dompurify`                   |
| `redirect(searchParams.get('next'))`               | Open redirect to an attacker domain                     | `redirect(safeRedirectPath(searchParams.get('next')))`          |
| `<a href={user.website}>`                          | `javascript:` URL executes on click                     | `<a href={safeHref(user.website)}>`                             |
| `const data = (await res.json()) as User`          | Type assertion, no runtime check                        | `UserDto.parse(await res.json())`                               |
| Auth check only in `layout.tsx`                    | Server Actions and route handlers are callable directly | `getSession()` inside every action and handler                  |
| `script-src 'self' 'unsafe-inline'`                | CSP no longer blocks injected scripts                   | Nonce + `'strict-dynamic'`                                      |
| `fetch(body.url)` in a route handler               | SSRF into the internal network                          | Allow-list hosts, reject private IPs                            |
| `pnpm install` without a lockfile in CI            | Non-reproducible builds, silent upgrades                | `pnpm install --frozen-lockfile`                                |
| `// eslint-disable react/no-danger` across the app | Sanitization bypassed per component                     | One `RichText` component owns the disable                       |

---

## Additional Resources

See [references/packages.md](references/packages.md) for the approved package table, ESLint rules, and the severity triage guide. See [references/helpers.md](references/helpers.md) for the `vitest` suites of `sanitizeHtml()`, `safeRedirectPath()`, and `safeHref()`. See [references/auth.md](references/auth.md) for authentication patterns and [references/supply-chain.md](references/supply-chain.md) for dependency hygiene.
