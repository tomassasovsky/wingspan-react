# Internationalization — Setup

Complete configuration for both lanes: `react-i18next` for Vite and `next-intl` for Next.js App Router, with typed keys, shared `Intl` formatters, language switchers, and extraction tooling.

---

## Vite Lane

### Install

```bash
pnpm add i18next react-i18next i18next-icu i18next-browser-languagedetector i18next-resources-to-backend
pnpm add -D i18next-parser
```

### File layout

```text
locales/
  en/
    common.json
    cart.json
  es/
    common.json
    cart.json
  ar/
    common.json
    cart.json
src/i18n/
  index.ts          # runtime init
  i18next.d.ts      # typed keys
  format.ts         # Intl helpers
  direction.ts      # RTL set
```

### Runtime

```ts
// src/i18n/index.ts
import i18next from 'i18next';
import LanguageDetector from 'i18next-browser-languagedetector';
import ICU from 'i18next-icu';
import resourcesToBackend from 'i18next-resources-to-backend';
import { initReactI18next } from 'react-i18next';
import { getDirection } from './direction';

export const supportedLngs = ['en', 'es', 'ar'] as const;
export type SupportedLanguage = (typeof supportedLngs)[number];
export const defaultNS = 'common';

export function isSupportedLanguage(value: string): value is SupportedLanguage {
  return (supportedLngs as ReadonlyArray<string>).includes(value);
}

void i18next
  .use(ICU)
  .use(LanguageDetector)
  .use(resourcesToBackend((language: string, namespace: string) => import(`../../locales/${language}/${namespace}.json`)))
  .use(initReactI18next)
  .init({
    supportedLngs,
    fallbackLng: 'en',
    load: 'languageOnly',
    defaultNS,
    ns: [defaultNS],
    interpolation: { escapeValue: false },
    detection: { order: ['querystring', 'localStorage', 'navigator'], lookupQuerystring: 'lng', caches: ['localStorage'] },
    react: { useSuspense: true },
  });

i18next.on('languageChanged', (language) => {
  document.documentElement.lang = language;
  document.documentElement.dir = getDirection(language);
});

export default i18next;
```

```ts
// src/i18n/direction.ts
const rtlLanguages = new Set(['ar', 'fa', 'he', 'ur']);

export type Direction = 'ltr' | 'rtl';

export function getDirection(locale: string): Direction {
  const language = new Intl.Locale(locale).language;
  return rtlLanguages.has(language) ? 'rtl' : 'ltr';
}
```

```tsx
// src/main.tsx
import { StrictMode, Suspense } from 'react';
import { createRoot } from 'react-dom/client';
import './i18n';
import { App } from './App';

const root = document.getElementById('root');
if (!root) throw new Error('Missing #root');

createRoot(root).render(
  <StrictMode>
    <Suspense fallback={null}>
      <App />
    </Suspense>
  </StrictMode>,
);
```

Feature namespaces load on demand: `useTranslation('cart')` triggers the `cart` bundle for the active language and suspends until it arrives. Wrap route elements in `<Suspense>` boundaries so only the feature waits.

### Typed keys

```json
// tsconfig.json (excerpt)
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "resolveJsonModule": true
  }
}
```

```ts
// src/i18n/i18next.d.ts
import 'i18next';
import type cart from '../../locales/en/cart.json';
import type common from '../../locales/en/common.json';

declare module 'i18next' {
  interface CustomTypeOptions {
    defaultNS: 'common';
    resources: {
      common: typeof common;
      cart: typeof cart;
    };
  }
}
```

`import type` of JSON produces no runtime import, so `en` stays lazy-loaded. `t('cart:itemCount')` and `useTranslation('cart')` + `t('itemCount')` both type check; `t('itemCoutn')` is a compile error.

### Extraction

```ts
// i18next-parser.config.ts
import type { UserConfig } from 'i18next-parser';

const config: UserConfig = {
  locales: ['en', 'es', 'ar'],
  input: ['src/**/*.{ts,tsx}'],
  output: 'locales/$LOCALE/$NAMESPACE.json',
  defaultNamespace: 'common',
  keySeparator: '.',
  namespaceSeparator: ':',
  sort: true,
  keepRemoved: false,
  failOnUpdate: process.env['CI'] === 'true',
  failOnWarnings: true,
};

export default config;
```

```json
// package.json (excerpt)
{
  "scripts": {
    "i18n:extract": "i18next --config i18next-parser.config.ts",
    "typecheck": "tsc --noEmit"
  }
}
```

Locally, `pnpm i18n:extract` adds new keys to every locale with an empty value. In CI, `failOnUpdate` fails the job when source keys and `locales/` disagree.

---

## Next.js Lane

### Install

```bash
pnpm add next-intl
```

### File layout

```text
messages/
  en.json
  es.json
  ar.json
src/
  i18n/
    routing.ts
    navigation.ts
    request.ts
    direction.ts
  middleware.ts        # proxy.ts on Next 16+
  app/
    [locale]/
      layout.tsx
      page.tsx
global.d.ts
next.config.ts
```

### Configuration

```ts
// next.config.ts
import type { NextConfig } from 'next';
import createNextIntlPlugin from 'next-intl/plugin';

const withNextIntl = createNextIntlPlugin('./src/i18n/request.ts');

const nextConfig: NextConfig = {};

export default withNextIntl(nextConfig);
```

```ts
// src/i18n/routing.ts
import { defineRouting } from 'next-intl/routing';

export const routing = defineRouting({
  locales: ['en', 'es', 'ar'],
  defaultLocale: 'en',
  localePrefix: 'always',
});

export type Locale = (typeof routing.locales)[number];
```

```ts
// src/i18n/navigation.ts
import { createNavigation } from 'next-intl/navigation';
import { routing } from './routing';

export const { Link, redirect, usePathname, useRouter, getPathname } = createNavigation(routing);
```

```ts
// src/i18n/request.ts
import { hasLocale } from 'next-intl';
import { getRequestConfig } from 'next-intl/server';
import { routing } from './routing';

export default getRequestConfig(async ({ requestLocale }) => {
  const requested = await requestLocale;
  const locale = hasLocale(routing.locales, requested) ? requested : routing.defaultLocale;
  const messages = (await import(`../../messages/${locale}.json`)).default;

  return {
    locale,
    messages,
    timeZone: 'UTC',
    onError(error) {
      if (process.env.NODE_ENV !== 'production') throw error;
      console.error(error);
    },
    getMessageFallback({ namespace, key }) {
      return `${namespace ?? ''}.${key}`;
    },
  };
});
```

```ts
// src/middleware.ts
import createMiddleware from 'next-intl/middleware';
import { routing } from './i18n/routing';

export default createMiddleware(routing);

export const config = {
  matcher: ['/((?!api|_next|_vercel|.*\\..*).*)'],
};
```

```tsx
// src/app/[locale]/layout.tsx
import { hasLocale, NextIntlClientProvider } from 'next-intl';
import { setRequestLocale } from 'next-intl/server';
import { notFound } from 'next/navigation';
import type { ReactNode } from 'react';
import { getDirection } from '@/i18n/direction';
import { routing } from '@/i18n/routing';

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

type LocaleLayoutProps = { children: ReactNode; params: Promise<{ locale: string }> };

export default async function LocaleLayout({ children, params }: LocaleLayoutProps) {
  const { locale } = await params;
  if (!hasLocale(routing.locales, locale)) notFound();
  setRequestLocale(locale);

  return (
    <html lang={locale} dir={getDirection(locale)}>
      <body>
        <NextIntlClientProvider>{children}</NextIntlClientProvider>
      </body>
    </html>
  );
}
```

`NextIntlClientProvider` without props inherits locale, messages, time zone, and formats from `request.ts`. Pass a `messages` subset only when the client bundle must be trimmed.

### Typed keys

```ts
// global.d.ts
import type { routing } from './src/i18n/routing';
import type messages from './messages/en.json';

declare module 'next-intl' {
  interface AppConfig {
    Locale: (typeof routing.locales)[number];
    Messages: typeof messages;
  }
}
```

`useTranslations('Cart')` only accepts namespaces present in `en.json`; `t('itemCount')` only accepts keys under it; `useLocale()` returns the `Locale` union.

### Language switcher

```tsx
// src/components/LanguageSwitcher.tsx
'use client';

import { useLocale, useTranslations } from 'next-intl';
import { useParams } from 'next/navigation';
import { usePathname, useRouter } from '@/i18n/navigation';
import { routing, type Locale } from '@/i18n/routing';

export function LanguageSwitcher() {
  const t = useTranslations('LanguageSwitcher');
  const locale = useLocale();
  const router = useRouter();
  const pathname = usePathname();
  const params = useParams();

  function onChange(next: Locale) {
    router.replace({ pathname, params }, { locale: next });
  }

  return (
    <label>
      {t('label')}
      <select value={locale} onChange={(event) => onChange(event.target.value as Locale)}>
        {routing.locales.map((option) => (
          <option key={option} value={option} lang={option}>
            {new Intl.DisplayNames(option, { type: 'language' }).of(option)}
          </option>
        ))}
      </select>
    </label>
  );
}
```

The `as Locale` cast is safe because every `<option>` value comes from `routing.locales`. Passing `params` keeps dynamic segments such as `[slug]` intact.

### Key parity check

```ts
// scripts/check-messages.ts
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

type Messages = { [key: string]: string | Messages };

function flatten(messages: Messages, prefix = ''): string[] {
  return Object.entries(messages).flatMap(([key, value]) =>
    typeof value === 'string' ? [`${prefix}${key}`] : flatten(value, `${prefix}${key}.`),
  );
}

const dir = join(process.cwd(), 'messages');
const load = (file: string): Messages => JSON.parse(readFileSync(join(dir, file), 'utf8')) as Messages;
const reference = new Set(flatten(load('en.json')));
let failed = false;

for (const file of readdirSync(dir).filter((name) => name.endsWith('.json') && name !== 'en.json')) {
  const keys = new Set(flatten(load(file)));
  const missing = [...reference].filter((key) => !keys.has(key));
  const extra = [...keys].filter((key) => !reference.has(key));
  if (missing.length > 0 || extra.length > 0) {
    failed = true;
    console.error(`${file}: missing ${missing.join(', ') || 'none'}; extra ${extra.join(', ') || 'none'}`);
  }
}

if (failed) process.exit(1);
console.log('Message catalogs are in sync.');
```

```json
// package.json (excerpt)
{
  "scripts": {
    "i18n:check": "tsx scripts/check-messages.ts"
  }
}
```

---

## Shared Intl Formatters (Vite lane)

`next-intl` exposes `useFormatter` with the same caching; Vite apps use this module.

```ts
// src/i18n/format.ts
const numberFormatters = new Map<string, Intl.NumberFormat>();
const dateFormatters = new Map<string, Intl.DateTimeFormat>();

function cached<T>(cache: Map<string, T>, key: string, create: () => T): T {
  let value = cache.get(key);
  if (!value) {
    value = create();
    cache.set(key, value);
  }
  return value;
}

export function formatCurrency(value: number, locale: string, currency: string): string {
  return cached(numberFormatters, `${locale}:currency:${currency}`, () =>
    new Intl.NumberFormat(locale, { style: 'currency', currency }),
  ).format(value);
}

export function formatNumber(value: number, locale: string, options: Intl.NumberFormatOptions = {}): string {
  return cached(numberFormatters, `${locale}:${JSON.stringify(options)}`, () => new Intl.NumberFormat(locale, options)).format(value);
}

export function formatDate(date: Date, locale: string, options: Intl.DateTimeFormatOptions = { dateStyle: 'medium' }): string {
  return cached(dateFormatters, `${locale}:${JSON.stringify(options)}`, () => new Intl.DateTimeFormat(locale, options)).format(date);
}

export function formatRelativeTime(date: Date, locale: string, now = new Date()): string {
  const seconds = Math.round((date.getTime() - now.getTime()) / 1000);
  const formatter = new Intl.RelativeTimeFormat(locale, { numeric: 'auto' });
  const units: ReadonlyArray<[Intl.RelativeTimeFormatUnit, number]> = [
    ['year', 31_536_000],
    ['month', 2_592_000],
    ['week', 604_800],
    ['day', 86_400],
    ['hour', 3_600],
    ['minute', 60],
  ];
  for (const [unit, size] of units) {
    if (Math.abs(seconds) >= size) return formatter.format(Math.round(seconds / size), unit);
  }
  return formatter.format(seconds, 'second');
}

export function formatList(items: ReadonlyArray<string>, locale: string): string {
  return new Intl.ListFormat(locale, { style: 'long', type: 'conjunction' }).format(items);
}
```

```ts
// src/i18n/format.test.ts
import { describe, expect, it } from 'vitest';
import { formatCurrency, formatDate, formatList, formatRelativeTime } from './format';

describe('format', () => {
  const now = new Date('2026-01-01T12:00:00Z');

  it('formats currency per locale', () => {
    expect(formatCurrency(1234.5, 'en-US', 'USD')).toBe('$1,234.50');
    expect(formatCurrency(1234.5, 'de-DE', 'EUR')).toBe('1.234,50 €');
  });

  it('formats dates per locale', () => {
    expect(formatDate(now, 'en-US', { dateStyle: 'medium', timeZone: 'UTC' })).toBe('Jan 1, 2026');
  });

  it('formats relative time with the largest fitting unit', () => {
    expect(formatRelativeTime(new Date('2026-01-01T11:55:00Z'), 'en', now)).toBe('5 minutes ago');
    expect(formatRelativeTime(new Date('2026-01-03T12:00:00Z'), 'en', now)).toBe('in 2 days');
    expect(formatRelativeTime(new Date('2026-01-01T12:00:00Z'), 'en', now)).toBe('now');
  });

  it('formats lists', () => {
    expect(formatList(['red', 'green', 'blue'], 'en')).toBe('red, green, and blue');
  });
});
```

Run Node with full ICU (the default since Node 13) so these assertions hold in CI.
