# Security Headers Reference

## Header Table

| Header                         | Production value                                       | Why                                                               |
| ------------------------------ | ------------------------------------------------------ | ----------------------------------------------------------------- |
| `Content-Security-Policy`      | Nonce-based, see below                                 | Blocks injected scripts, inline handlers, and unexpected origins  |
| `Strict-Transport-Security`    | `max-age=63072000; includeSubDomains; preload`         | Forces HTTPS for two years; submit to hstspreload.org once stable |
| `X-Content-Type-Options`       | `nosniff`                                              | Stops MIME sniffing that turns uploads into executable scripts    |
| `Referrer-Policy`              | `strict-origin-when-cross-origin`                      | Keeps paths and query strings (IDs, tokens) off third-party logs  |
| `Permissions-Policy`           | `camera=(), microphone=(), geolocation=(), payment=()` | Disables powerful APIs the app does not use, including in iframes |
| `Cross-Origin-Opener-Policy`   | `same-origin`                                          | Severs `window.opener` links; required for cross-origin isolation |
| `Cross-Origin-Resource-Policy` | `same-origin`                                          | Stops other origins from embedding responses                      |
| `X-Frame-Options`              | `DENY`                                                 | Legacy clickjacking guard; `frame-ancestors` is authoritative     |
| `Cache-Control` (auth pages)   | `no-store`                                             | Keeps authenticated HTML out of shared caches and the back button |

Remove `X-Powered-By` (`poweredByHeader: false` in `next.config.ts`; `server_tokens off` in nginx).

## CSP Directive Rationale

| Directive                   | Value                                        | Notes                                                                 |
| --------------------------- | -------------------------------------------- | --------------------------------------------------------------------- |
| `default-src`               | `'self'`                                     | Deny-by-default baseline for every fetch directive not listed         |
| `script-src`                | `'self' 'nonce-<n>' 'strict-dynamic'`        | Nonce covers framework scripts; `strict-dynamic` trusts their imports |
| `style-src`                 | `'self' 'nonce-<n>'`                         | Tailwind and CSS modules emit stylesheets, not inline `<style>`       |
| `style-src-attr`            | `'unsafe-inline'` only if a library needs it | Inline `style=""` attributes from Radix or animation libraries        |
| `img-src`                   | `'self' blob: data: https://cdn.example.com` | Add the image CDN configured in `images.remotePatterns`               |
| `connect-src`               | `'self' https://api.example.com`             | Every `fetch`, WebSocket, and Sentry ingest host must be listed       |
| `font-src`                  | `'self'`                                     | Self-host fonts (`next/font` does this automatically)                 |
| `frame-ancestors`           | `'none'`                                     | Clickjacking protection; list origins only when embedding is real     |
| `frame-src`                 | `https://js.stripe.com`                      | Only when embedding third-party iframes                               |
| `base-uri`                  | `'self'`                                     | Stops `<base>` injection from rewriting relative script URLs          |
| `form-action`               | `'self'`                                     | Stops injected forms from posting credentials elsewhere               |
| `object-src`                | `'none'`                                     | No plugins                                                            |
| `upgrade-insecure-requests` | (no value)                                   | Rewrites stray `http://` subresources                                 |
| `report-to`                 | `csp-endpoint`                               | Pair with a `Reporting-Endpoints` header                              |

Never add `'unsafe-inline'` to `script-src`. A third-party widget that "needs" it gets loaded through a nonced `<Script nonce={nonce}>` or a same-origin proxy.

## Next.js: Nonce CSP in `proxy.ts`

The CSP changes per request (fresh nonce), so it is produced by `proxy.ts` (Next.js 16+; `middleware.ts` with a `middleware` export on Next.js 15). The nonce goes on the request headers so Next.js attaches it to its own scripts, and on the response so the browser enforces it.

```ts
// proxy.ts (Next.js 16+; on Next.js 15 the file is middleware.ts and the export is `middleware`)
import { NextResponse, type NextRequest } from 'next/server';

export function proxy(request: NextRequest): NextResponse {
  const nonce = Buffer.from(crypto.randomUUID()).toString('base64');
  const isDev = process.env.NODE_ENV === 'development';
  const csp = [
    `default-src 'self'`,
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'${isDev ? " 'unsafe-eval'" : ''}`,
    `style-src 'self' 'nonce-${nonce}'`,
    `img-src 'self' blob: data:`,
    `font-src 'self'`,
    `connect-src 'self' https://api.example.com`,
    `frame-ancestors 'none'`,
    `base-uri 'self'`,
    `form-action 'self'`,
    `object-src 'none'`,
    'upgrade-insecure-requests',
  ].join('; ');

  const requestHeaders = new Headers(request.headers);
  requestHeaders.set('x-nonce', nonce);
  requestHeaders.set('Content-Security-Policy', csp); // Next.js reads the nonce from here for its own scripts

  const response = NextResponse.next({ request: { headers: requestHeaders } });
  response.headers.set('Content-Security-Policy', csp);
  return response;
}

export const config = {
  matcher: [
    {
      source: '/((?!api|_next/static|_next/image|favicon.ico).*)',
      missing: [
        { type: 'header', key: 'next-router-prefetch' },
        { type: 'header', key: 'purpose', value: 'prefetch' },
      ],
    },
  ],
};
```

## Next.js: Static Headers in `next.config.ts`

CSP with a nonce must come from `proxy.ts`/`middleware.ts` because it changes per request. Every other header is static:

```ts
// next.config.ts
import type { NextConfig } from 'next';

const securityHeaders = [
  { key: 'Strict-Transport-Security', value: 'max-age=63072000; includeSubDomains; preload' },
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
  { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=(), payment=()' },
  { key: 'Cross-Origin-Opener-Policy', value: 'same-origin' },
  { key: 'X-Frame-Options', value: 'DENY' },
] as const;

const nextConfig: NextConfig = {
  poweredByHeader: false,
  productionBrowserSourceMaps: false,
  async headers() {
    return [{ source: '/(.*)', headers: [...securityHeaders] }];
  },
};

export default nextConfig;
```

## Next.js: Reading the Nonce in Components

```tsx
// app/layout.tsx
import { headers } from 'next/headers';
import Script from 'next/script';
import type { ReactNode } from 'react';

export default async function RootLayout({ children }: { children: ReactNode }) {
  const nonce = (await headers()).get('x-nonce') ?? undefined;
  return (
    <html lang="en">
      <body>
        {children}
        <Script src="https://js.stripe.com/v3/" nonce={nonce} strategy="afterInteractive" />
      </body>
    </html>
  );
}
```

Every `<Script>` and every `<style>` rendered by hand takes the `nonce` prop; framework-emitted scripts get it automatically from the request header. Reading `headers()` makes the layout dynamic, which a nonce-based CSP requires anyway.

## Report-Only Rollout

1. Ship the policy under `Content-Security-Policy-Report-Only` with `report-to`.
2. Collect violations for a full release cycle (Sentry, report-uri.com, or a route handler that logs `application/reports+json`).
3. Fix or allow-list each source; never add `'unsafe-inline'` to close a report.
4. Rename the header to `Content-Security-Policy`.

```ts
response.headers.set('Reporting-Endpoints', 'csp-endpoint="https://app.example.com/api/csp-report"');
response.headers.set('Content-Security-Policy-Report-Only', `${csp}; report-to csp-endpoint`);
```

## Vite SPA

A static SPA has no per-request nonce. A production Vite build emits no inline scripts, so `script-src 'self'` is sufficient; hash any inline `<script>` you add to `index.html` yourself (`openssl dgst -sha256 -binary | openssl base64 -A`).

```ts
// vite.config.ts (dev server headers only; production headers come from the web server below)
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [react()],
  build: { sourcemap: 'hidden' },
  server: {
    headers: {
      // Dev-only relaxation: Vite injects inline styles for HMR.
      'Content-Security-Policy':
        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self' ws://localhost:5173; img-src 'self' data: blob:",
    },
  },
});
```

```nginx
# /etc/nginx/snippets/security-headers.conf
add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self' https://api.example.com; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'; upgrade-insecure-requests" always;
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()" always;
add_header Cross-Origin-Opener-Policy "same-origin" always;
add_header X-Frame-Options "DENY" always;
```

```nginx
# /etc/nginx/conf.d/app.conf (serving dist/)
server {
  listen 443 ssl;
  http2 on;
  server_name app.example.com;
  root /srv/app/dist;
  server_tokens off;
  include snippets/security-headers.conf;

  location ~* \.map$ {
    return 404; # never serve source maps
  }

  location /assets/ {
    include snippets/security-headers.conf; # add_header in a location block replaces inherited headers
    add_header Cache-Control "public, max-age=31536000, immutable" always;
  }

  location / {
    include snippets/security-headers.conf;
    add_header Cache-Control "no-cache" always;
    try_files $uri /index.html;
  }
}
```

`add_header` inside a `location` block discards every header inherited from `server`, which is why the snippet is included again in each location that sets its own header.

## Verifying

```bash
curl -sI https://app.example.com | grep -iE "content-security|strict-transport|x-content-type|referrer|permissions|frame|opener"
curl -sI https://app.example.com/assets/index-abc123.js.map | head -1   # expect 404
```

Cross-check with Mozilla Observatory or securityheaders.com before release; a grade below A means a header in the table above is missing or weakened.
