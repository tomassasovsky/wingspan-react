# Accessibility — Before and After Examples

Remediation examples for every audit category, with the tests that lock each fix in place.

---

## 1. Semantics and Names

### Clickable `div` to `button`

```tsx
// Before — no role, not focusable, no keyboard activation (2.1.1, 4.1.2)
<div className="card" onClick={() => openProject(project.id)}>
  {project.name}
</div>

// After
<button type="button" className="card" onClick={() => openProject(project.id)}>
  {project.name}
</button>
```

### Images and SVG icons

```tsx
// Before — filename announced; icon announced as "image"
<img src="/chart-q3.png" />
<svg><use href="#trash" /></svg>

// After — informative image described; decorative SVG hidden
<img src="/chart-q3.png" alt="Q3 revenue rose 12% to 4.1M, driven by subscriptions" />
<svg aria-hidden="true" focusable="false"><use href="#trash" /></svg>

// After — decorative image
<img src="/divider.png" alt="" />
```

### Visible text plus `aria-label` (2.5.3 Label in Name)

```tsx
// Before — voice control users say "Save" but the name is "Persist changes"
<button type="submit" aria-label="Persist changes">Save</button>

// After — name starts with the visible text
<button type="submit" aria-label="Save draft to server">Save</button>
```

---

## 2. Keyboard and Focus

### Focus ring

```css
/* Before — keyboard users lose their place (2.4.7) */
button:focus {
  outline: none;
}

/* After — 2px ring, 3:1 against adjacent colors, only for keyboard focus */
:where(a, button, input, select, textarea, [tabindex]):focus-visible {
  outline: 2px solid var(--color-focus-ring);
  outline-offset: 2px;
  border-radius: var(--radius-sm);
}

/* Sticky header must not cover the focused element (2.4.11) */
html {
  scroll-padding-block-start: var(--size-header);
}
```

### Skip link

```tsx
// src/app/RootLayout.tsx
import { Outlet } from 'react-router';
import { useRouteFocus } from './useRouteFocus';

export function RootLayout() {
  useRouteFocus();
  return (
    <>
      <a href="#main" className="skip-link">
        Skip to main content
      </a>
      <header>{/* navigation */}</header>
      <main id="main" tabIndex={-1}>
        <Outlet />
      </main>
    </>
  );
}
```

```css
.skip-link {
  position: absolute;
  inset-block-start: var(--space-2);
  inset-inline-start: var(--space-2);
  transform: translateY(-200%);
}
.skip-link:focus-visible {
  transform: none;
}
```

### Focus after route change

React Router does not move focus on navigation. Move it to the page `<h1>` so screen reader users hear the new page.

```ts
// src/app/useRouteFocus.ts
import { useEffect, useRef } from 'react';
import { useLocation } from 'react-router';

export function useRouteFocus() {
  const { pathname } = useLocation();
  const previousPathname = useRef(pathname);

  useEffect(() => {
    if (previousPathname.current === pathname) return;
    previousPathname.current = pathname;
    const target = document.querySelector<HTMLElement>('h1[tabindex="-1"]') ?? document.getElementById('main');
    target?.focus();
  }, [pathname]);
}
```

Every page renders `<h1 tabIndex={-1}>` and sets `<title>` (React 19 renders `<title>` from anywhere in the tree). Next.js App Router announces route changes itself; still move focus to the `<h1>` from a client component keyed on `usePathname()`.

```tsx
// src/app/useRouteFocus.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { Link, MemoryRouter, Outlet, Route, Routes } from 'react-router';
import { describe, expect, it } from 'vitest';
import { useRouteFocus } from './useRouteFocus';

function Layout() {
  useRouteFocus();
  return <Outlet />;
}

function Page({ title }: { title: string }) {
  return (
    <>
      <h1 tabIndex={-1}>{title}</h1>
      <Link to="/orders">Orders</Link>
    </>
  );
}

function renderApp() {
  render(
    <MemoryRouter initialEntries={['/']}>
      <Routes>
        <Route element={<Layout />}>
          <Route path="/" element={<Page title="Home" />} />
          <Route path="/orders" element={<Page title="Orders" />} />
        </Route>
      </Routes>
    </MemoryRouter>,
  );
}

describe('useRouteFocus', () => {
  it('leaves focus alone on initial render', () => {
    renderApp();
    expect(screen.getByRole('heading', { level: 1 })).not.toHaveFocus();
  });

  it('focuses the h1 after navigation', async () => {
    const user = userEvent.setup();
    renderApp();
    await user.click(screen.getByRole('link', { name: 'Orders' }));
    expect(screen.getByRole('heading', { level: 1, name: 'Orders' })).toHaveFocus();
  });
});
```

### Hand-rolled modal to Radix

```tsx
// Before — no role, no focus trap, no Escape, focus lost on close (2.1.2, 2.4.3, 4.1.2)
{open && (
  <div className="overlay" onClick={close}>
    <div className="modal" onClick={(event) => event.stopPropagation()}>
      <h2>Delete project?</h2>
      <button onClick={close}>Cancel</button>
      <button onClick={confirm}>Delete</button>
    </div>
  </div>
)}

// After — Radix supplies role, labelling, trap, Escape, and restore
<ConfirmDialog
  trigger={<button type="button">Delete</button>}
  title="Delete project?"
  description="This cannot be undone."
  confirmLabel="Delete"
  cancelLabel="Cancel"
  onConfirm={confirm}
/>
```

```tsx
// packages/ui/src/ConfirmDialog.tsx
import * as Dialog from '@radix-ui/react-dialog';
import type { ReactNode } from 'react';

type ConfirmDialogProps = {
  trigger: ReactNode;
  title: string;
  description: string;
  confirmLabel: string;
  cancelLabel: string;
  onConfirm: () => void;
};

export function ConfirmDialog({ trigger, title, description, confirmLabel, cancelLabel, onConfirm }: ConfirmDialogProps) {
  return (
    <Dialog.Root>
      <Dialog.Trigger asChild>{trigger}</Dialog.Trigger>
      <Dialog.Portal>
        <Dialog.Overlay className="dialog-overlay" />
        <Dialog.Content className="dialog-content">
          <Dialog.Title>{title}</Dialog.Title>
          <Dialog.Description>{description}</Dialog.Description>
          <div className="dialog-actions">
            <Dialog.Close asChild>
              <button type="button">{cancelLabel}</button>
            </Dialog.Close>
            <Dialog.Close asChild>
              <button type="button" onClick={onConfirm}>{confirmLabel}</button>
            </Dialog.Close>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
```

```css
/* packages/ui/src/ConfirmDialog.css */
.dialog-overlay {
  position: fixed;
  inset: 0;
  background: var(--color-overlay);
  animation: fade-in var(--motion-duration-base) var(--motion-easing-standard);
}
.dialog-content {
  position: fixed;
  inset-block-start: 50%;
  inset-inline-start: 50%;
  transform: translate(-50%, -50%);
  max-inline-size: min(90vw, 32rem);
  padding: var(--space-6);
  border-radius: var(--radius-lg);
  background: var(--color-surface-raised);
  box-shadow: var(--shadow-lg);
}
.dialog-actions {
  display: flex;
  justify-content: flex-end;
  gap: var(--space-2);
  margin-block-start: var(--space-6);
}
@keyframes fade-in {
  from { opacity: 0; }
}
```

Labels arrive as props so `packages/ui` stays free of the i18n runtime. The keyboard and axe tests are in [testing.md](testing.md).

---

## 3. Forms and Errors

```tsx
// src/features/signup/components/SignupForm.tsx
import { zodResolver } from '@hookform/resolvers/zod';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { TextField } from '@acme/ui';

const signupSchema = z.object({
  email: z.string().email('Enter an email like name@example.com'),
  password: z.string().min(12, 'Use at least 12 characters'),
});

type SignupValues = z.infer<typeof signupSchema>;

type SignupFormProps = { onSubmit: (values: SignupValues) => Promise<void> };

export function SignupForm({ onSubmit }: SignupFormProps) {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting, submitCount },
  } = useForm<SignupValues>({ resolver: zodResolver(signupSchema) });

  const errorCount = Object.keys(errors).length;

  return (
    <form noValidate onSubmit={handleSubmit(onSubmit)} aria-labelledby="signup-heading">
      <h1 id="signup-heading" tabIndex={-1}>
        Create account
      </h1>
      {submitCount > 0 && errorCount > 0 ? (
        <p role="alert">Fix {errorCount} {errorCount === 1 ? 'error' : 'errors'} to continue.</p>
      ) : null}
      <TextField
        label="Email"
        type="email"
        autoComplete="email"
        required
        error={errors.email?.message}
        {...register('email')}
      />
      <TextField
        label="Password"
        type="password"
        autoComplete="new-password"
        hint="At least 12 characters. Paste is allowed."
        required
        error={errors.password?.message}
        {...register('password')}
      />
      <button type="submit" disabled={isSubmitting}>
        {isSubmitting ? 'Creating account' : 'Create account'}
      </button>
    </form>
  );
}
```

`noValidate` hands validation to `zod` so messages are consistent and announced through `role="alert"`. `autoComplete` satisfies 1.3.5 and 3.3.8. Never block paste on password fields.

---

## 4. Contrast and Color

```tsx
// Before — status conveyed by color only (1.4.1); gray text fails 4.5:1 (1.4.3)
<span style={{ color: status === 'active' ? 'green' : 'red' }}>{name}</span>
<p style={{ color: '#9aa0a6' }}>Last synced 5 minutes ago</p>

// After — icon plus text; token colors verified against the surface
<span className={`status status--${status}`}>
  <CheckIcon aria-hidden="true" />
  {status === 'active' ? 'Active' : 'Inactive'}
</span>
<p className="text-muted">Last synced 5 minutes ago</p>
```

```css
.text-muted {
  color: var(--color-on-surface-muted); /* 4.6:1 on --color-surface, verified in Playwright */
}
```

---

## 5. Target Size and Pointer

```tsx
// Before — 16px hit area (2.5.8); action fires on pointerdown (2.5.2)
<span className="chip-remove" onPointerDown={() => remove(tag)}>
  <XIcon width={16} height={16} />
</span>

// After — 44px target from the component; click event; name
<IconButton label={`Remove ${tag}`} icon={<XIcon width={16} height={16} />} onClick={() => remove(tag)} />
```

Sortable lists must offer a non-drag path (2.5.7):

```tsx
<li>
  {item.title}
  <IconButton label={`Move ${item.title} up`} icon={<ArrowUpIcon />} onClick={() => move(item.id, -1)} disabled={index === 0} />
  <IconButton label={`Move ${item.title} down`} icon={<ArrowDownIcon />} onClick={() => move(item.id, 1)} disabled={index === last} />
</li>
```

---

## 6. Motion

```css
/* tokens.css — every transition and animation reads these */
:root {
  --motion-duration-fast: 150ms;
  --motion-duration-base: 250ms;
  --motion-easing-standard: cubic-bezier(0.2, 0, 0, 1);
}
@media (prefers-reduced-motion: reduce) {
  :root {
    --motion-duration-fast: 0ms;
    --motion-duration-base: 0ms;
  }
}
```

JavaScript-driven animation reads the same preference:

```ts
// packages/ui/src/useReducedMotion.ts
import { useSyncExternalStore } from 'react';

const QUERY = '(prefers-reduced-motion: reduce)';

function subscribe(onChange: () => void) {
  const mql = window.matchMedia(QUERY);
  mql.addEventListener('change', onChange);
  return () => mql.removeEventListener('change', onChange);
}

export function useReducedMotion(): boolean {
  return useSyncExternalStore(subscribe, () => window.matchMedia(QUERY).matches, () => false);
}
```

```tsx
// Before — parallax always runs (2.3.3)
<motion.div animate={{ y: scrollY * 0.3 }} />

// After
const reducedMotion = useReducedMotion();
<motion.div animate={reducedMotion ? { y: 0 } : { y: scrollY * 0.3 }} />
```

---

## 7. Structure and Navigation

### Data table

```tsx
// packages/ui/src/DataTable.tsx
type SortDirection = 'ascending' | 'descending';

type Column<Row> = {
  key: keyof Row & string;
  header: string;
  numeric?: boolean;
  isRowHeader?: boolean;
};

type DataTableProps<Row extends { id: string }> = {
  caption: string;
  columns: ReadonlyArray<Column<Row>>;
  rows: ReadonlyArray<Row>;
  sort?: { key: keyof Row & string; direction: SortDirection };
  onSort?: (key: keyof Row & string) => void;
};

export function DataTable<Row extends { id: string }>({ caption, columns, rows, sort, onSort }: DataTableProps<Row>) {
  return (
    <div className="table-scroll" role="region" aria-label={caption} tabIndex={0}>
      <table>
        <caption>{caption}</caption>
        <thead>
          <tr>
            {columns.map((column) => {
              const sorted = sort?.key === column.key ? sort.direction : undefined;
              return (
                <th key={column.key} scope="col" aria-sort={sorted ?? 'none'} className={column.numeric ? 'numeric' : undefined}>
                  {onSort ? (
                    <button type="button" onClick={() => onSort(column.key)}>
                      {column.header}
                      <span className="sr-only">{sorted ? `, sorted ${sorted}` : ''}</span>
                    </button>
                  ) : (
                    column.header
                  )}
                </th>
              );
            })}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.id}>
              {columns.map((column) =>
                column.isRowHeader ? (
                  <th key={column.key} scope="row">{String(row[column.key])}</th>
                ) : (
                  <td key={column.key} className={column.numeric ? 'numeric' : undefined}>{String(row[column.key])}</td>
                ),
              )}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
```

The scroll region is focusable and named so keyboard users can scroll wide tables (1.4.10). `aria-sort` sits on the `<th>`, never on the button.

```tsx
// packages/ui/src/DataTable.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { axe } from '../../src/test/axe';
import { DataTable } from './DataTable';

type Order = { id: string; number: string; total: number };

const columns = [
  { key: 'number', header: 'Order', isRowHeader: true },
  { key: 'total', header: 'Total', numeric: true },
] as const;

const rows: Order[] = [
  { id: '1', number: 'A-100', total: 42 },
  { id: '2', number: 'A-101', total: 17 },
];

describe('DataTable', () => {
  it('exposes caption, headers, and sort state', async () => {
    const onSort = vi.fn();
    const { container } = render(
      <DataTable caption="Orders" columns={columns} rows={rows} sort={{ key: 'total', direction: 'ascending' }} onSort={onSort} />,
    );

    expect(screen.getByRole('table', { name: 'Orders' })).toBeInTheDocument();
    expect(screen.getByRole('columnheader', { name: /Total/ })).toHaveAttribute('aria-sort', 'ascending');
    expect(screen.getByRole('rowheader', { name: 'A-100' })).toBeInTheDocument();
    expect(await axe(container)).toHaveNoViolations();
  });

  it('sorts from the keyboard', async () => {
    const user = userEvent.setup();
    const onSort = vi.fn();
    render(<DataTable caption="Orders" columns={columns} rows={rows} onSort={onSort} />);

    await user.tab();
    await user.tab();
    await user.keyboard('{Enter}');
    expect(onSort).toHaveBeenCalledWith('number');
  });
});
```

### Heading hierarchy

```tsx
// Before — h4 chosen for its size; outline jumps from h1 to h4
<h1>Settings</h1>
<h4>Profile</h4>

// After — correct level, size from a typography token
<h1>Settings</h1>
<h2 className="text-title-sm">Profile</h2>
```
