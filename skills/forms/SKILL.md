---
name: react-forms
description: Best practices for forms in React using react-hook-form with zod schemas via @hookform/resolvers. Use when writing, modifying, or reviewing forms, validation schemas, field components, submit handling, server error mapping, or tests that use react-hook-form, zod, @hookform/resolvers, or useActionState.
allowed-tools: Read Glob Grep
---

# Forms

Schema-first forms with `react-hook-form` for field state and submission, `zod` for validation, and `@hookform/resolvers/zod` to connect them.

---

## Core Standards

Apply these standards to ALL form work:

- **Schema first** — write the `zod` schema before the component; the schema is the contract
- **One schema, shared by client and server** — export it from the feature or a shared package; never duplicate rules
- **Types come from `z.infer`** — never hand-write an interface that mirrors a schema
- **Native inputs use `register`** — `Controller` only for non-native components such as Radix `Select`, date pickers, or rich text
- **No `useState` per field** — `react-hook-form` owns field values; component state is for UI only
- **Accessible errors** — every invalid field has `aria-invalid` and `aria-describedby` pointing at a `role="alert"` message
- **Submit states are explicit** — render `isSubmitting`, `isSubmitSuccessful`, and `errors.root` distinctly
- **Server errors map onto fields with `setError`** — never show a generic toast when the server names the field
- **Disable submit only while submitting** — never disable until the form is valid
- **Form logic lives in hooks** — the component renders; a `use<Name>Form` hook owns `useForm`, submission, and error mapping when logic exceeds a few lines
- **Every form ships with a `@testing-library/user-event` test** — validation messages and the submitted payload

---

## Package Roles

| Package                       | Role                                                        |
| ----------------------------- | ----------------------------------------------------------- |
| `zod`                         | Schema, parsing, type inference, shared with the server     |
| `react-hook-form`             | Field registration, values, touched/dirty state, submission |
| `@hookform/resolvers`         | `zodResolver` runs the schema on validate                   |
| `@testing-library/user-event` | Drives forms in tests the way a user does                   |

---

## Naming Conventions

| Thing          | Pattern                      | Example                        |
| -------------- | ---------------------------- | ------------------------------ |
| Schema         | `<name>Schema`               | `loginSchema`                  |
| Input type     | `<Name>Input` from `z.infer` | `LoginInput`                   |
| Form component | `<Name>Form`                 | `LoginForm`                    |
| Form hook      | `use<Name>Form`              | `useLoginForm`                 |
| Submit result  | `SubmitResult<Input>`        | `SubmitResult<LoginInput>`     |
| Schema file    | `<name>Schema.ts`            | `features/auth/loginSchema.ts` |

---

## Complete Example: Login Form

### Schema

```ts
// src/features/auth/loginSchema.ts
import { z } from 'zod';

export const loginSchema = z.object({
  email: z.email('Enter a valid email address'),
  password: z.string().min(8, 'Password must be at least 8 characters'),
});

export type LoginInput = z.infer<typeof loginSchema>;
```

### Submit Result Contract

```ts
// src/lib/forms/submitResult.ts
export type SubmitResult<Input> =
  | { ok: true }
  | {
      ok: false;
      formError?: string;
      fieldErrors?: Partial<Record<keyof Input, string>>;
    };
```

### Component

```tsx
// src/features/auth/components/LoginForm.tsx
import { zodResolver } from '@hookform/resolvers/zod';
import { useId } from 'react';
import { useForm } from 'react-hook-form';
import type { SubmitResult } from '@/lib/forms/submitResult';
import { loginSchema, type LoginInput } from '../loginSchema';

interface LoginFormProps {
  onSubmit: (values: LoginInput) => Promise<SubmitResult<LoginInput>>;
}

export function LoginForm({ onSubmit }: LoginFormProps) {
  const id = useId();
  const {
    register,
    handleSubmit,
    setError,
    formState: { errors, isSubmitting },
  } = useForm<LoginInput>({
    resolver: zodResolver(loginSchema),
    defaultValues: { email: '', password: '' },
  });

  const submit = handleSubmit(async (values) => {
    const result = await onSubmit(values);
    if (result.ok) return;
    for (const field of Object.keys(result.fieldErrors ?? {}) as (keyof LoginInput)[]) {
      const message = result.fieldErrors?.[field];
      if (message) setError(field, { type: 'server', message });
    }
    if (result.formError) setError('root.serverError', { type: 'server', message: result.formError });
  });

  const emailError = errors.email?.message;
  const passwordError = errors.password?.message;
  const formError = errors.root?.serverError?.message;

  return (
    <form onSubmit={submit} noValidate aria-busy={isSubmitting}>
      <div>
        <label htmlFor={`${id}-email`}>Email</label>
        <input
          id={`${id}-email`}
          type="email"
          autoComplete="email"
          aria-invalid={emailError ? true : undefined}
          aria-describedby={emailError ? `${id}-email-error` : undefined}
          {...register('email')}
        />
        {emailError ? (
          <p id={`${id}-email-error`} role="alert">
            {emailError}
          </p>
        ) : null}
      </div>

      <div>
        <label htmlFor={`${id}-password`}>Password</label>
        <input
          id={`${id}-password`}
          type="password"
          autoComplete="current-password"
          aria-invalid={passwordError ? true : undefined}
          aria-describedby={passwordError ? `${id}-password-error` : undefined}
          {...register('password')}
        />
        {passwordError ? (
          <p id={`${id}-password-error`} role="alert">
            {passwordError}
          </p>
        ) : null}
      </div>

      {formError ? <p role="alert">{formError}</p> : null}

      <button type="submit" disabled={isSubmitting}>
        {isSubmitting ? 'Signing in' : 'Sign in'}
      </button>
    </form>
  );
}
```

`noValidate` turns off browser validation so `zod` messages are the only messages. `aria-busy` announces the pending submission.

### Test

```tsx
// src/features/auth/components/LoginForm.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import type { SubmitResult } from '@/lib/forms/submitResult';
import type { LoginInput } from '../loginSchema';
import { LoginForm } from './LoginForm';

type OnSubmit = (values: LoginInput) => Promise<SubmitResult<LoginInput>>;

describe('LoginForm', () => {
  it('shows validation messages and does not submit invalid input', async () => {
    const user = userEvent.setup();
    const onSubmit = vi.fn<OnSubmit>().mockResolvedValue({ ok: true });
    render(<LoginForm onSubmit={onSubmit} />);

    await user.type(screen.getByLabelText('Email'), 'not-an-email');
    await user.click(screen.getByRole('button', { name: 'Sign in' }));

    expect(await screen.findByText('Enter a valid email address')).toBeInTheDocument();
    expect(screen.getByText('Password must be at least 8 characters')).toBeInTheDocument();
    expect(screen.getByLabelText('Email')).toHaveAttribute('aria-invalid', 'true');
    expect(screen.getByLabelText('Email')).toHaveAccessibleDescription('Enter a valid email address');
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it('submits the parsed payload', async () => {
    const user = userEvent.setup();
    const onSubmit = vi.fn<OnSubmit>().mockResolvedValue({ ok: true });
    render(<LoginForm onSubmit={onSubmit} />);

    await user.type(screen.getByLabelText('Email'), 'ada@example.com');
    await user.type(screen.getByLabelText('Password'), 'correct-horse');
    await user.click(screen.getByRole('button', { name: 'Sign in' }));

    expect(onSubmit).toHaveBeenCalledTimes(1);
    expect(onSubmit).toHaveBeenCalledWith({ email: 'ada@example.com', password: 'correct-horse' });
  });

  it('maps server field and form errors', async () => {
    const user = userEvent.setup();
    const onSubmit = vi.fn<OnSubmit>().mockResolvedValue({
      ok: false,
      formError: 'Email or password is incorrect',
      fieldErrors: { email: 'No account for this email' },
    });
    render(<LoginForm onSubmit={onSubmit} />);

    await user.type(screen.getByLabelText('Email'), 'ada@example.com');
    await user.type(screen.getByLabelText('Password'), 'correct-horse');
    await user.click(screen.getByRole('button', { name: 'Sign in' }));

    expect(await screen.findByText('No account for this email')).toBeInTheDocument();
    expect(screen.getByText('Email or password is incorrect')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Sign in' })).toBeEnabled();
  });
});
```

---

## `Controller` for Non-Native Components

```tsx
import { Controller, useForm } from 'react-hook-form';
import { Select } from '@acme/ui';

<Controller
  control={control}
  name="role"
  render={({ field, fieldState }) => (
    <Select
      ref={field.ref}
      name={field.name}
      value={field.value}
      onValueChange={field.onChange}
      onBlur={field.onBlur}
      options={roleOptions}
      label="Role"
      error={fieldState.error?.message}
    />
  )}
/>
```

Pass `field.ref` so `react-hook-form` can focus the first invalid field on submit. The custom component owns `aria-invalid` and `aria-describedby` from its `error` prop.

---

## Submit States

| `formState` field    | Render                                                       |
| -------------------- | ------------------------------------------------------------ |
| `isSubmitting`       | Pending label on the button, `aria-busy` on the form         |
| `isSubmitSuccessful` | Success message, or navigate away; call `reset()` if staying |
| `errors.root.<key>`  | Form-level error from the server, `role="alert"`             |
| `errors.<field>`     | Inline error next to the field                               |
| `isDirty`            | Unsaved-changes guard on navigation                          |

---

## Anti-Patterns

| Anti-Pattern                                    | Problem                                           | Correct Approach                                |
| ----------------------------------------------- | ------------------------------------------------- | ----------------------------------------------- |
| `useState` per field + manual `if` validation   | Duplicated rules, no types, no a11y               | `useForm` + `zodResolver(schema)`               |
| `interface LoginInput { email: string; ... }`   | Drifts from the schema                            | `type LoginInput = z.infer<typeof loginSchema>` |
| Separate validation on the API route            | Client and server disagree                        | Import the same schema on the server            |
| `<Controller>` around a native `<input>`        | Extra re-renders, more code                       | `{...register('name')}`                         |
| `<p className="error">` with no `role` or `id`  | Screen readers never hear it                      | `role="alert"` + `aria-describedby`             |
| `disabled={!isValid}` on submit                 | Users cannot discover what is wrong               | Enable submit; show errors on submit            |
| `toast.error('Something went wrong')` for a 422 | Server named the field; the user cannot see which | `setError(field, { type: 'server', message })`  |
| `watch()` with no arguments                     | Re-renders the whole form on every keystroke      | `watch('field')` or `useWatch({ name })`        |
| Validation logic inside JSX callbacks           | Untestable, duplicated                            | Schema `refine`/`superRefine`                   |
| Not passing `field.ref` in `Controller`         | Focus does not land on the first invalid field    | `ref={field.ref}`                               |

---

## References

- [references/patterns.md](references/patterns.md) — field arrays, dependent fields with `watch`/`useWatch`, async validation, multi-step forms, Next.js Server Actions with `useActionState`
- [references/testing.md](references/testing.md) — `user-event` recipes, testing `Controller` fields, field arrays, async validation with `msw`, server error mapping, `vitest-axe`
