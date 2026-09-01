# Testing Forms

Stack: `vitest`, `@testing-library/react`, `@testing-library/user-event`, `@testing-library/jest-dom`, `msw`, `vitest-axe`. Drive every form through the DOM the way a user would; never call `handleSubmit` or `setValue` from a test.

## Rules

| Rule                                                    | Reason                                      |
| ------------------------------------------------------- | ------------------------------------------- |
| `const user = userEvent.setup()` per test               | Realistic typing, focus, and pointer events |
| Query fields by label: `getByLabelText('Email')`        | Verifies the label association              |
| Query errors with `findByText` or `findByRole('alert')` | Validation is async; `find*` waits          |
| Assert `aria-invalid` and `toHaveAccessibleDescription` | Proves the error is announced               |
| Assert the exact submitted payload                      | Catches coercion and transform mistakes     |
| One `it` per rule                                       | A failing test names the broken rule        |

## Schema Tests

Test schemas directly for rules that matter: transforms, refinements, coercion.

```ts
// src/features/invoices/invoiceSchema.test.ts
import { describe, expect, it } from 'vitest';
import { invoiceSchema } from './invoiceSchema';

describe('invoiceSchema', () => {
  it('coerces numeric strings from inputs', () => {
    const result = invoiceSchema.safeParse({
      customerId: 'c1',
      lineItems: [{ description: 'Work', quantity: '2', unitPrice: '10.50' }],
    });
    expect(result.success).toBe(true);
    expect(result.data?.lineItems[0]).toEqual({ description: 'Work', quantity: 2, unitPrice: 10.5 });
  });

  it('requires at least one line item', () => {
    const result = invoiceSchema.safeParse({ customerId: 'c1', lineItems: [] });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0]?.path).toEqual(['lineItems']);
  });
});
```

## Testing `Controller` Fields

Custom components expose an accessible role. Interact through it.

```tsx
// src/features/users/components/InviteForm.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { InviteForm } from './InviteForm';

describe('InviteForm', () => {
  it('submits the selected role', async () => {
    const user = userEvent.setup();
    const onSubmit = vi.fn().mockResolvedValue({ ok: true });
    render(<InviteForm onSubmit={onSubmit} />);

    await user.type(screen.getByLabelText('Email'), 'ada@example.com');
    await user.click(screen.getByRole('combobox', { name: 'Role' }));
    await user.click(screen.getByRole('option', { name: 'Admin' }));
    await user.click(screen.getByRole('button', { name: 'Send invite' }));

    expect(onSubmit).toHaveBeenCalledWith({ email: 'ada@example.com', role: 'admin' });
  });

  it('focuses the role field when it is missing', async () => {
    const user = userEvent.setup();
    render(<InviteForm onSubmit={vi.fn()} />);

    await user.type(screen.getByLabelText('Email'), 'ada@example.com');
    await user.click(screen.getByRole('button', { name: 'Send invite' }));

    expect(await screen.findByText('Choose a role')).toBeInTheDocument();
    expect(screen.getByRole('combobox', { name: 'Role' })).toHaveFocus();
  });
});
```

The focus assertion fails when `field.ref` is not forwarded.

## Testing Field Arrays

```tsx
// src/features/invoices/components/InvoiceForm.test.tsx
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { InvoiceForm } from './InvoiceForm';

describe('InvoiceForm', () => {
  it('adds and removes line items', async () => {
    const user = userEvent.setup();
    render(<InvoiceForm onSubmit={vi.fn()} />);

    await user.click(screen.getByRole('button', { name: 'Add line item' }));
    expect(screen.getAllByRole('group', { name: /Line item \d/ })).toHaveLength(2);

    await user.click(screen.getByRole('button', { name: 'Remove line item 2' }));
    expect(screen.getAllByRole('group', { name: /Line item \d/ })).toHaveLength(1);
  });

  it('submits coerced line items', async () => {
    const user = userEvent.setup();
    const onSubmit = vi.fn().mockResolvedValue({ ok: true });
    render(<InvoiceForm onSubmit={onSubmit} />);

    const row = within(screen.getByRole('group', { name: 'Line item 1' }));
    await user.type(row.getByLabelText('Description'), 'Consulting');
    await user.clear(row.getByLabelText('Quantity'));
    await user.type(row.getByLabelText('Quantity'), '3');
    await user.clear(row.getByLabelText('Unit price'));
    await user.type(row.getByLabelText('Unit price'), '100');
    await user.click(screen.getByRole('button', { name: 'Save invoice' }));

    expect(onSubmit).toHaveBeenCalledWith(
      expect.objectContaining({
        lineItems: [{ description: 'Consulting', quantity: 3, unitPrice: 100 }],
      }),
    );
  });
});
```

`within` scopes queries to one row so duplicate labels resolve.

## Testing Async Validation with `msw`

```tsx
// src/features/auth/components/SignupForm.test.tsx
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { describe, expect, it, vi } from 'vitest';
import { renderWithProviders } from '@/test/renderWithProviders';
import { server } from '@/test/server';
import { SignupForm } from './SignupForm';

describe('SignupForm', () => {
  it('rejects an email that is already registered', async () => {
    server.use(
      http.get('/api/auth/email-available', ({ request }) => {
        const email = new URL(request.url).searchParams.get('email');
        return HttpResponse.json({ available: email !== 'taken@example.com' });
      }),
    );
    const user = userEvent.setup();
    renderWithProviders(<SignupForm onSubmit={vi.fn()} />);

    await user.type(screen.getByLabelText('Email'), 'taken@example.com');
    await user.tab();

    expect(await screen.findByText('This email is already registered')).toBeInTheDocument();
  });

  it('does not call the API for a malformed email', async () => {
    const handler = vi.fn(() => HttpResponse.json({ available: true }));
    server.use(http.get('/api/auth/email-available', handler));
    const user = userEvent.setup();
    renderWithProviders(<SignupForm onSubmit={vi.fn()} />);

    await user.type(screen.getByLabelText('Email'), 'nope');
    await user.tab();

    expect(await screen.findByText('Enter a valid email address')).toBeInTheDocument();
    expect(handler).not.toHaveBeenCalled();
  });
});
```

## Testing Server Error Mapping

Covered in the `LoginForm` test in `SKILL.md`. For a form wired to a mutation instead of an `onSubmit` prop, return the error from an `msw` handler and assert the same DOM:

```tsx
server.use(
  http.post('/api/login', () =>
    HttpResponse.json({ fieldErrors: { email: 'No account for this email' } }, { status: 422 }),
  ),
);
```

## Testing Multi-Step Forms

```tsx
it('blocks the next step until the current step is valid', async () => {
  const user = userEvent.setup();
  render(<OnboardingForm onSubmit={vi.fn()} />);

  await user.click(screen.getByRole('button', { name: 'Next' }));

  expect(await screen.findByText('Enter a valid email address')).toBeInTheDocument();
  expect(screen.getByRole('listitem', { current: 'step' })).toHaveTextContent('Account');
});

it('keeps values when navigating back', async () => {
  const user = userEvent.setup();
  render(<OnboardingForm onSubmit={vi.fn()} />);

  await user.type(screen.getByLabelText('Email'), 'ada@example.com');
  await user.type(screen.getByLabelText('Password'), 'correct-horse-battery');
  await user.click(screen.getByRole('button', { name: 'Next' }));
  await user.click(await screen.findByRole('button', { name: 'Back' }));

  expect(screen.getByLabelText('Email')).toHaveValue('ada@example.com');
});
```

## Testing a Server Action Form

Mock the action module; the form's contract is "calls the action with this `FormData`".

```tsx
// src/features/auth/components/LoginForm.test.tsx (Next.js)
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { loginAction } from '../actions/loginAction';
import { LoginForm } from './LoginForm';

vi.mock('../actions/loginAction', () => ({
  loginAction: vi.fn(),
}));

describe('LoginForm (server action)', () => {
  it('calls the action with form data after client validation passes', async () => {
    vi.mocked(loginAction).mockResolvedValue(null);
    const user = userEvent.setup();
    render(<LoginForm />);

    await user.type(screen.getByLabelText('Email'), 'ada@example.com');
    await user.type(screen.getByLabelText('Password'), 'correct-horse');
    await user.click(screen.getByRole('button', { name: 'Sign in' }));

    const formData = vi.mocked(loginAction).mock.calls[0]?.[1];
    expect(formData?.get('email')).toBe('ada@example.com');
    expect(formData?.get('password')).toBe('correct-horse');
  });

  it('renders errors returned by the action', async () => {
    vi.mocked(loginAction).mockResolvedValue({ ok: false, formError: 'Email or password is incorrect' });
    const user = userEvent.setup();
    render(<LoginForm />);

    await user.type(screen.getByLabelText('Email'), 'ada@example.com');
    await user.type(screen.getByLabelText('Password'), 'correct-horse');
    await user.click(screen.getByRole('button', { name: 'Sign in' }));

    expect(await screen.findByText('Email or password is incorrect')).toBeInTheDocument();
  });
});
```

Test the action itself as a plain async function with a `FormData` argument and an `msw`-backed repository.

## Accessibility Check

```tsx
import { axe } from 'vitest-axe';

it('has no accessibility violations with errors shown', async () => {
  const user = userEvent.setup();
  const { container } = render(<LoginForm onSubmit={vi.fn()} />);
  await user.click(screen.getByRole('button', { name: 'Sign in' }));
  await screen.findByText('Enter a valid email address');

  expect(await axe(container)).toHaveNoViolations();
});
```

Run the axe check in the error state as well as the pristine state; unlabeled error text is the most common violation.
