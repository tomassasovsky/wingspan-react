# Package Quick Reference

| Package                                        | Security role                                           | Replaces / Prevents                                |
| ---------------------------------------------- | ------------------------------------------------------- | -------------------------------------------------- |
| `zod`                                          | Runtime validation at every trust boundary              | `as` casts on JSON, unchecked params and form data |
| `dompurify` / `isomorphic-dompurify`           | HTML sanitization before `dangerouslySetInnerHTML`      | Stored and reflected XSS                           |
| `server-only`                                  | Build-time guard for server-only modules                | Secrets imported into client bundles               |
| `@t3-oss/env-nextjs` / `@t3-oss/env-core`      | Typed env with client/server split (optional)           | Hand-rolled `env.ts`                               |
| `better-auth` / `next-auth`                    | Sessions, OAuth, credentials, password hashing          | Custom auth flows                                  |
| `iron-session`                                 | Sealed, encrypted cookie sessions                       | Signed JWT in `localStorage`                       |
| `next-safe-action`                             | Server Actions with input schema and auth middleware    | Unvalidated, unauthorized action arguments         |
| `@node-rs/argon2`                              | Password hashing when an auth library is not used       | `sha256` or unsalted hashes for passwords          |
| `helmet`                                       | Security headers for an Express or Fastify BFF          | Manual header lists                                |
| `@upstash/ratelimit` / `rate-limiter-flexible` | Rate limiting on auth and expensive routes              | Credential stuffing, brute force                   |
| `osv-scanner`                                  | CVE scan of `pnpm-lock.yaml`                            | Unknown vulnerable transitive dependencies         |
| `eslint-plugin-react`                          | `no-danger`, `jsx-no-script-url`, `jsx-no-target-blank` | Unsanitized HTML, `javascript:` hrefs, tabnabbing  |
| `eslint-plugin-no-unsanitized`                 | Lints `innerHTML`, `outerHTML`, `insertAdjacentHTML`    | DOM-sink XSS outside React                         |
| `eslint-plugin-security`                       | Lints `eval`, unsafe regex, `child_process`             | Server-side injection and ReDoS                    |

## ESLint Rules

```ts
// eslint.config.ts (excerpt)
import noUnsanitized from 'eslint-plugin-no-unsanitized';
import react from 'eslint-plugin-react';
import security from 'eslint-plugin-security';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  {
    files: ['**/*.{ts,tsx}'],
    plugins: { react, 'no-unsanitized': noUnsanitized, security },
    rules: {
      'react/no-danger': 'error',
      'react/jsx-no-script-url': 'error',
      'react/jsx-no-target-blank': ['error', { enforceDynamicLinks: 'always' }],
      'no-unsanitized/method': 'error',
      'no-unsanitized/property': 'error',
      'no-eval': 'error',
      'no-implied-eval': 'error',
      'no-new-func': 'error',
      'no-restricted-globals': ['error', { name: 'localStorage', message: 'Use the storage repository; never store auth material.' }],
      'no-restricted-properties': [
        'error',
        { object: 'process', property: 'env', message: 'Import from env.server.ts or env.client.ts.' },
      ],
    },
  },
  {
    files: ['src/env.server.ts', 'src/env.client.ts'],
    rules: { 'no-restricted-properties': 'off' },
  },
  {
    files: ['app/**/route.ts', 'app/**/actions.ts', 'src/server/**/*.ts'],
    rules: { ...security.configs.recommended.rules },
  },
);
```

## Severity Guide

Triage every finding into one of these tiers and lead the report with Critical items.

| Severity | Examples                                                                                                                                                                                                                                                                                      |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Critical | Secret in `NEXT_PUBLIC_*`/`VITE_*`; session token in web storage; `dangerouslySetInnerHTML` with unsanitized user data; Server Action or route handler without an auth check; open redirect on an auth callback; `fetch` of a request-supplied URL on the server; `rejectUnauthorized: false` |
| Warning  | `'unsafe-inline'` in `script-src`; missing HSTS; `res.json() as T` on external data; no rate limit on login; public source maps; missing `Origin` check on a cookie-authenticated mutation; `pnpm audit` high finding; `overrides` or ignored advisory without a justification                |
| Note     | Missing `Permissions-Policy` or COOP; no `minimumReleaseAge`; `save-exact` off; `pnpm outdated` shows security patches; `console.log` of request metadata; third-party `<script>` without SRI                                                                                                 |

## Report Format

```markdown
## Security Review: <scope>

| Severity | File:line                  | Standard violated            | Fix                                 |
| -------- | -------------------------- | ---------------------------- | ----------------------------------- |
| Critical | app/api/export/route.ts:12 | No auth in route handler     | Call `getSession()` and return 401  |
| Warning  | next.config.ts:8           | CSP allows `'unsafe-inline'` | Move CSP to `proxy.ts` with a nonce |

Dependency scan: `pnpm audit` 0 high, `osv-scanner` 1 finding (GHSA-..., transitive via `<pkg>`), fix: `pnpm up <pkg>`.
```
