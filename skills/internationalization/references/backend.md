# Internationalization — Backend

Loading translations from a backend or CDN, caching and fallback, and localizing server-provided content and error messages.

---

## When to Load Remotely

| Situation                                                        | Approach                                                                        |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| Translations change with releases                                | Bundle them; lazy-load per namespace with `import()`                            |
| Translations change between releases (CMS, translation platform) | Fetch from a CDN with a version in the URL; ship `en` in the bundle as fallback |
| Per-tenant vocabulary ("Projects" vs "Workspaces")               | Fetch a tenant overlay namespace and merge after the base bundle                |

Never fetch translations from an unversioned URL; a broken upload would break every session.

---

## Vite Lane: CDN Backend with Bundled Fallback

```bash
pnpm add i18next-http-backend i18next-chained-backend
```

```ts
// src/i18n/index.ts (backend section)
import i18next from 'i18next';
import ChainedBackend from 'i18next-chained-backend';
import HttpBackend from 'i18next-http-backend';
import ICU from 'i18next-icu';
import resourcesToBackend from 'i18next-resources-to-backend';
import { initReactI18next } from 'react-i18next';

const translationsVersion = import.meta.env['VITE_TRANSLATIONS_VERSION'] ?? 'local';
const translationsBaseUrl = import.meta.env['VITE_TRANSLATIONS_URL'];

const bundled = resourcesToBackend((language: string, namespace: string) => import(`../../locales/${language}/${namespace}.json`));
const remoteOptions = {
  loadPath: `${translationsBaseUrl ?? ''}/${translationsVersion}/{{lng}}/{{ns}}.json`,
  requestOptions: { cache: 'force-cache' },
};

void i18next
  .use(ICU)
  .use(ChainedBackend)
  .use(initReactI18next)
  .init({
    supportedLngs: ['en', 'es', 'ar'],
    fallbackLng: 'en',
    defaultNS: 'common',
    interpolation: { escapeValue: false },
    backend: translationsBaseUrl
      ? { backends: [HttpBackend, bundled], backendOptions: [remoteOptions, {}] }
      : { backends: [bundled], backendOptions: [{}] },
  });

export default i18next;
```

Order matters: the HTTP backend is tried first; when it fails or returns 404 the bundled JSON serves the same namespace. `VITE_TRANSLATIONS_VERSION` is a content hash or release tag baked in at build time so the CDN URL is immutable and cacheable forever.

### Cache headers

| Asset                             | `Cache-Control`                       |
| --------------------------------- | ------------------------------------- |
| `/<version>/<lng>/<ns>.json`      | `public, max-age=31536000, immutable` |
| `/latest/manifest.json` (if used) | `public, max-age=60`                  |

Never rely on `localStorage` caching of translation JSON; the browser HTTP cache with immutable URLs is faster and cannot serve stale text after a deploy.

---

## Next.js Lane: Remote Messages in `request.ts`

```ts
// src/i18n/request.ts
import { hasLocale } from 'next-intl';
import { getRequestConfig } from 'next-intl/server';
import { routing } from './routing';

type Messages = Record<string, unknown>;

async function loadRemoteMessages(locale: string): Promise<Messages | null> {
  const base = process.env['TRANSLATIONS_URL'];
  const version = process.env['TRANSLATIONS_VERSION'];
  if (!base || !version) return null;

  const response = await fetch(`${base}/${version}/${locale}.json`, { next: { revalidate: false } });
  if (!response.ok) return null;
  return (await response.json()) as Messages;
}

export default getRequestConfig(async ({ requestLocale }) => {
  const requested = await requestLocale;
  const locale = hasLocale(routing.locales, requested) ? requested : routing.defaultLocale;
  const bundled = (await import(`../../messages/${locale}.json`)).default as Messages;
  const remote = await loadRemoteMessages(locale);

  return {
    locale,
    messages: remote ? { ...bundled, ...remote } : bundled,
    timeZone: 'UTC',
  };
});
```

`fetch` in `request.ts` runs on the server and is cached by Next.js; `revalidate: false` matches the immutable URL. The bundled file remains the source of truth for types, so a remote overlay can only change values, never add keys the code does not know about.

---

## Server Content

Backend-owned text (product descriptions, CMS pages) is localized by the backend:

1. Store one row per entity per locale, or a JSON column keyed by locale.
2. Clients send `Accept-Language` or an explicit `locale` query parameter on every request; the Next.js lane forwards `await getLocale()` from `next-intl/server`.
3. The backend returns the requested locale or the entity's default locale plus a `Content-Language` header; the client displays whatever it receives without a second lookup.

```ts
// packages/catalog-api-client/src/catalogClient.ts (excerpt)
export async function getProduct(id: string, locale: string, signal?: AbortSignal): Promise<Product> {
  const response = await fetch(`${baseUrl}/products/${id}`, {
    headers: { 'Accept-Language': locale },
    signal,
  });
  if (!response.ok) throw new ApiError(response.status);
  return productSchema.parse(await response.json());
}
```

TanStack Query keys include the locale so a language switch refetches localized content:

```ts
export const productKeys = {
  detail: (id: string, locale: string) => ['products', 'detail', id, locale] as const,
};
```

---

## Error Messages

Backends return stable error codes, never translated prose. The client maps codes to message keys through a typed record so extraction and type checking see every key.

```ts
// src/features/auth/errors.ts
import type { TFunction } from 'i18next';

export const authErrorCodes = ['invalid_credentials', 'account_locked', 'code_expired'] as const;
export type AuthErrorCode = (typeof authErrorCodes)[number];

const authErrorKeys = {
  invalid_credentials: 'errors.invalidCredentials',
  account_locked: 'errors.accountLocked',
  code_expired: 'errors.codeExpired',
} as const satisfies Record<AuthErrorCode, string>;

export function isAuthErrorCode(value: unknown): value is AuthErrorCode {
  return typeof value === 'string' && (authErrorCodes as ReadonlyArray<string>).includes(value);
}

export function authErrorMessage(t: TFunction<'auth'>, code: unknown): string {
  return isAuthErrorCode(code) ? t(authErrorKeys[code]) : t('errors.generic');
}
```

```ts
// src/features/auth/errors.test.ts
import { describe, expect, it } from 'vitest';
import { testI18n } from '@/test/i18n';
import { authErrorMessage } from './errors';

describe('authErrorMessage', () => {
  const t = testI18n.getFixedT('en', 'auth');

  it('maps known codes', () => {
    expect(authErrorMessage(t, 'account_locked')).toBe('Your account is locked. Contact support to unlock it.');
  });

  it('falls back for unknown codes', () => {
    expect(authErrorMessage(t, 'something_new')).toBe('Something went wrong. Try again.');
  });
});
```

HTTP status codes without a body code map the same way: `401` to `errors.unauthorized`, `429` to `errors.rateLimited`, everything else to `errors.generic`. Validation errors from `zod` schemas shared with the server carry message keys, not English text, and are translated at render time.
