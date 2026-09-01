# React 19 Migration Reference

Run the codemods first, then work through the tables in order. Every code block shows the pattern the codemod leaves behind or cannot handle.

## 1. Codemods

```bash
pnpm up -r react@19 react-dom@19 @types/react@19 @types/react-dom@19 @testing-library/react@latest @testing-library/dom@latest
npx codemod@latest react/19/migration-recipe     # replace-reactdom-render, replace-string-ref, replace-act-import, replace-use-form-state, prop-types-typescript-codemod
npx types-react-codemod@latest preset-19 ./src   # useRef required argument, React.JSX namespace, deprecated type aliases
pnpm typecheck && pnpm lint && pnpm test
```

## 2. Removed APIs

| Removed                                            | Replacement                                                                  |
| -------------------------------------------------- | ---------------------------------------------------------------------------- |
| `ReactDOM.render`, `ReactDOM.hydrate`              | `createRoot(el).render(...)`, `hydrateRoot(el, ...)` from `react-dom/client` |
| `unmountComponentAtNode`                           | `root.unmount()`                                                             |
| `ReactDOM.findDOMNode`                             | A `ref` on the element                                                       |
| String refs (`ref="input"`)                        | `useRef` or a ref callback                                                   |
| Legacy context (`contextTypes`, `getChildContext`) | `createContext` + `use(Context)`                                             |
| `propTypes` and `defaultProps` on functions        | TypeScript props and default parameter values                                |
| `react-dom/test-utils` (except `act`)              | `@testing-library/react`; `act` from `react`                                 |
| `react-test-renderer/shallow`                      | `@testing-library/react`                                                     |
| `element.ref`                                      | `element.props.ref`                                                          |
| UMD builds                                         | ESM from a CDN, or bundle                                                    |

## 3. `ref` as a Prop

`forwardRef` still works in 19 but is deprecated. Function components receive `ref` as a normal prop.

```tsx
// Before
import { forwardRef, type ComponentPropsWithoutRef } from 'react';

export const Input = forwardRef<HTMLInputElement, ComponentPropsWithoutRef<'input'>>(function Input(props, ref) {
  return <input ref={ref} {...props} />;
});
```

```tsx
// After
import type { ComponentProps } from 'react';

export function Input({ ref, ...props }: ComponentProps<'input'>) {
  return <input ref={ref} {...props} />;
}
```

`ComponentProps<'input'>` already includes `ref` in `@types/react@19`; `ComponentPropsWithRef` is no longer needed. Libraries that still call `forwardRef` keep working.

## 4. Ref Callback Cleanup

A ref callback may now return a cleanup function. Implicit arrow returns become type errors because the returned value is treated as cleanup.

```tsx
// Before: implicit return of the assignment (type error in 19)
<div ref={(node) => (nodeRef.current = node)} />

// After: block body, and optional cleanup
<div
  ref={(node) => {
    nodeRef.current = node;
    return () => {
      nodeRef.current = null;
    };
  }}
/>
```

## 5. Context as Provider

```tsx
// Before
<ThemeContext.Provider value={theme}>{children}</ThemeContext.Provider>

// After (Provider still works; the codemod does not rewrite it)
<ThemeContext value={theme}>{children}</ThemeContext>
```

Read context with `use(ThemeContext)`; unlike `useContext`, `use` is allowed inside conditionals and loops.

## 6. Actions, `useActionState`, `useFormStatus`, `useOptimistic`

`useFormState` from `react-dom` is replaced by `useActionState` from `react`, which adds `isPending`.

```tsx
// src/features/profile/components/ProfileForm.tsx
import { useActionState } from 'react';
import { useFormStatus } from 'react-dom';
import { updateProfile } from '../actions';

type FormState = { ok: true } | { ok: false; error: string } | null;

function SubmitButton() {
  const { pending } = useFormStatus(); // must render inside the <form>
  return (
    <button type="submit" disabled={pending}>
      {pending ? 'Saving' : 'Save'}
    </button>
  );
}

export function ProfileForm() {
  const [state, formAction, isPending] = useActionState<FormState, FormData>(
    async (_previous, formData) => updateProfile({ displayName: formData.get('displayName') }),
    null,
  );

  return (
    <form action={formAction} aria-busy={isPending}>
      <label>
        Display name
        <input name="displayName" required />
      </label>
      <SubmitButton />
      {state && !state.ok && <p role="alert">{state.error}</p>}
    </form>
  );
}
```

```tsx
// src/features/profile/components/ProfileForm.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { ProfileForm } from './ProfileForm';

const updateProfile = vi.hoisted(() => vi.fn());
vi.mock('../actions', () => ({ updateProfile }));

describe('ProfileForm', () => {
  it('submits the display name through the action and shows the error state', async () => {
    updateProfile.mockResolvedValueOnce({ ok: false, error: 'INVALID_INPUT' });
    render(<ProfileForm />);

    await userEvent.type(screen.getByRole('textbox', { name: 'Display name' }), 'Ada');
    await userEvent.click(screen.getByRole('button', { name: 'Save' }));

    expect(updateProfile).toHaveBeenCalledWith({ displayName: 'Ada' });
    expect(await screen.findByRole('alert')).toHaveTextContent('INVALID_INPUT');
  });
});
```

`<form action={fn}>` resets the form after a successful action; pass `defaultValue` from state when the value must persist.

## 7. Error Handling

Uncaught render errors are no longer re-thrown; they are reported through `window.reportError` and the new root options.

```tsx
// src/main.tsx
import { createRoot } from 'react-dom/client';
import { App } from './App';
import { reportError } from './lib/reporting';

const container = document.getElementById('root');
if (!container) throw new Error('Missing #root');

createRoot(container, {
  onUncaughtError: (error, info) => reportError(error, { componentStack: info.componentStack }),
  onCaughtError: (error, info) => reportError(error, { componentStack: info.componentStack, caught: true }),
  onRecoverableError: (error, info) => reportError(error, { componentStack: info.componentStack, recoverable: true }),
}).render(<App />);
```

Hydration mismatches now print one diff instead of many warnings; fix the nondeterministic render rather than silencing it.

## 8. `@types/react` 19 Changes

| Change                                                  | Fix                                                                         |
| ------------------------------------------------------- | --------------------------------------------------------------------------- |
| `useRef()` requires an argument                         | `useRef<HTMLDivElement>(null)`; `useRef<number>(0)`                         |
| `useRef<T>(null)` returns `RefObject<T \| null>`        | Narrow before use: `if (ref.current) ...`; `MutableRefObject` is deprecated |
| Global `JSX` namespace removed                          | `React.JSX.Element`, `React.JSX.IntrinsicElements`                          |
| `ReactElement` props default to `unknown`               | Type the element: `ReactElement<ButtonProps>`                               |
| `ref` included in `ComponentProps<'input'>`             | Drop `ComponentPropsWithRef`; delete `forwardRef` generics                  |
| `React.ElementRef` deprecated                           | `React.ComponentRef<typeof Comp>`                                           |
| `ReactChild`, `ReactFragment`, `ReactNodeArray` removed | `ReactNode`                                                                 |
| `LegacyRef`, `RefForwardingComponent` removed           | `Ref<T>`, plain function component with `ref` prop                          |
| Ref callback return type is `void \| (() => void)`      | Use a block body (section 4)                                                |
| `propTypes` typings removed                             | Delete `propTypes` blocks; props are TypeScript                             |

`npx types-react-codemod@latest preset-19 ./src` applies most of these; run `pnpm typecheck` and fix the rest by hand.

## 9. Testing

- Import `act` from `react`, never from `react-dom/test-utils`.
- `@testing-library/react@16` requires `@testing-library/dom` as an explicit devDependency.
- `react-test-renderer` is deprecated; snapshot with `@testing-library/react` `render().asFragment()` only where a snapshot is justified.
- StrictMode in development double-invokes render, effects, and now `useMemo`/`useCallback` initializers; tests run without StrictMode unless the `renderWithProviders` helper wraps it on purpose.

## 10. Library Compatibility

| Library                  | Minimum for React 19 | Notes                                                              |
| ------------------------ | -------------------- | ------------------------------------------------------------------ |
| `@tanstack/react-query`  | 5.x                  | Already object-only API; `useSuspenseQuery` pairs with `use`       |
| `react-hook-form`        | 7.53+                | `ref` prop works without `forwardRef` in custom inputs             |
| `zustand`                | 5.x                  | Drops `use-sync-external-store` shim; requires React 18+           |
| `react-router`           | 7.x                  | Framework and data modes; `react-router-dom` is a re-export only   |
| `@testing-library/react` | 16.x                 | Peer on `@testing-library/dom`                                     |
| `next`                   | 15.x (19 required)   | App Router ships React 19 canary; Pages Router supports 18 and 19  |
| `@radix-ui/react-*`      | Latest 1.x           | Older releases warn on `element.ref`; update before the React bump |
| `storybook`              | 8.4+                 | `@storybook/react-vite` with React 19 peer range                   |

Run `pnpm why react` after the bump; any package still pinning `react@^18` as a hard dependency (not a peer) is a duplicate-React risk and gets an override or a replacement.
