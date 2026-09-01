# Helper Tests

The `vitest` suites for the helpers defined in the skill. Keep them colocated with the helpers (`src/lib/*.test.ts`); every allow-list change gets a new case here first.

## `sanitizeHtml()`

```ts
// src/lib/sanitize.test.ts
// @vitest-environment jsdom
import { describe, expect, it } from 'vitest';
import { sanitizeHtml } from './sanitize';

describe('sanitizeHtml', () => {
  it('strips scripts and event handlers', () => {
    expect(sanitizeHtml('<p onclick="x()">ok</p><script>x()</script>')).toBe('<p>ok</p>');
  });

  it('blocks javascript: URLs and forces rel on target=_blank', () => {
    expect(sanitizeHtml('<a href="javascript:x()">x</a>')).toBe('<a>x</a>');
    expect(sanitizeHtml('<a href="https://a.io" target="_blank">x</a>')).toBe(
      '<a href="https://a.io" target="_blank" rel="noopener noreferrer">x</a>',
    );
  });
});
```

`isomorphic-dompurify` needs a DOM; the `@vitest-environment jsdom` pragma scopes it to this file so the rest of the suite stays on the faster `node` environment.

## `safeRedirectPath()` and `safeHref()`

```ts
// src/lib/safe-url.test.ts
import { describe, expect, it } from 'vitest';
import { safeHref, safeRedirectPath } from './safe-url';

describe('safeRedirectPath', () => {
  it.each([
    ['/dashboard?tab=1#top', '/dashboard?tab=1#top'],
    ['//evil.example', '/'],
    ['/\\evil.example', '/'],
    ['https://evil.example', '/'],
    ['javascript:alert(1)', '/'],
    [null, '/'],
  ])('maps %j to %s', (input, expected) => {
    expect(safeRedirectPath(input)).toBe(expected);
  });
});

describe('safeHref', () => {
  it('blocks javascript: and data: schemes', () => {
    expect(safeHref('javascript:alert(1)')).toBeUndefined();
    expect(safeHref('data:text/html,<b>x</b>')).toBeUndefined();
    expect(safeHref('https://example.com/a')).toBe('https://example.com/a');
  });
});
```

Add a case for every new bypass class you read about (encoded slashes, tab and newline characters, `data:` in `href`); the `it.each` table is the regression list.
