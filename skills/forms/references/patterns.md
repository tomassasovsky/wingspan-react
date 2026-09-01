# Form Patterns

## Field Arrays

Use `useFieldArray` for repeatable groups. Key rows by the generated `field.id`, never by index.

```ts
// src/features/invoices/invoiceSchema.ts
import { z } from 'zod';

export const lineItemSchema = z.object({
  description: z.string().min(1, 'Description is required'),
  quantity: z.coerce.number().int().min(1, 'Quantity must be at least 1'),
  unitPrice: z.coerce.number().min(0, 'Price cannot be negative'),
});

export const invoiceSchema = z.object({
  customerId: z.string().min(1, 'Choose a customer'),
  lineItems: z.array(lineItemSchema).min(1, 'Add at least one line item'),
});

export type InvoiceInput = z.infer<typeof invoiceSchema>;
```

```tsx
// src/features/invoices/components/LineItemsField.tsx
import { useFieldArray, useFormContext } from 'react-hook-form';
import type { InvoiceInput } from '../invoiceSchema';

export function LineItemsField() {
  const { control, register, formState: { errors } } = useFormContext<InvoiceInput>();
  const { fields, append, remove } = useFieldArray({ control, name: 'lineItems' });

  return (
    <fieldset>
      <legend>Line items</legend>
      {fields.map((field, index) => {
        const rowErrors = errors.lineItems?.[index];
        return (
          <div key={field.id} role="group" aria-label={`Line item ${index + 1}`}>
            <label htmlFor={`${field.id}-description`}>Description</label>
            <input
              id={`${field.id}-description`}
              aria-invalid={rowErrors?.description ? true : undefined}
              aria-describedby={rowErrors?.description ? `${field.id}-description-error` : undefined}
              {...register(`lineItems.${index}.description`)}
            />
            {rowErrors?.description ? (
              <p id={`${field.id}-description-error`} role="alert">{rowErrors.description.message}</p>
            ) : null}

            <label htmlFor={`${field.id}-quantity`}>Quantity</label>
            <input id={`${field.id}-quantity`} type="number" inputMode="numeric" {...register(`lineItems.${index}.quantity`)} />

            <label htmlFor={`${field.id}-unitPrice`}>Unit price</label>
            <input id={`${field.id}-unitPrice`} type="number" inputMode="decimal" step="0.01" {...register(`lineItems.${index}.unitPrice`)} />

            <button type="button" onClick={() => remove(index)} disabled={fields.length === 1}>
              Remove line item {index + 1}
            </button>
          </div>
        );
      })}
      {errors.lineItems?.root ? <p role="alert">{errors.lineItems.root.message}</p> : null}
      <button type="button" onClick={() => append({ description: '', quantity: 1, unitPrice: 0 })}>
        Add line item
      </button>
    </fieldset>
  );
}
```

`z.coerce.number()` converts the string a number input yields. Array-level errors (`min(1)`) surface at `errors.lineItems.root`.

## Dependent Fields

Subscribe to one field with `useWatch`; it re-renders only the subscriber.

```tsx
// src/features/shipping/components/ShippingAddressFields.tsx
import { useEffect } from 'react';
import { useFormContext, useWatch } from 'react-hook-form';
import type { CheckoutInput } from '../checkoutSchema';

export function ShippingAddressFields() {
  const { control, register, resetField } = useFormContext<CheckoutInput>();
  const sameAsBilling = useWatch({ control, name: 'shipping.sameAsBilling' });

  useEffect(() => {
    if (sameAsBilling) resetField('shipping.address');
  }, [sameAsBilling, resetField]);

  return (
    <>
      <label>
        <input type="checkbox" {...register('shipping.sameAsBilling')} />
        Same as billing address
      </label>
      {sameAsBilling ? null : <AddressFields prefix="shipping.address" />}
    </>
  );
}
```

Express the dependency in the schema too, so the server enforces it:

```ts
export const checkoutSchema = z.object({
  billing: z.object({ address: addressSchema }),
  shipping: z
    .object({
      sameAsBilling: z.boolean(),
      address: addressSchema.optional(),
    })
    .refine((s) => s.sameAsBilling || s.address !== undefined, {
      message: 'Shipping address is required',
      path: ['address'],
    }),
});
```

| API                  | Re-renders                        | Use when                       |
| -------------------- | --------------------------------- | ------------------------------ |
| `useWatch({ name })` | Only the calling component        | Default choice                 |
| `watch('name')`      | The component that owns `useForm` | Small forms with one component |
| `watch()`            | Everything on every keystroke     | Never                          |

## Async Validation

Put async checks in the schema with `superRefine` so client and server share them, and make the resolver run them only on submit or blur.

```ts
// src/features/auth/signupSchema.ts
import { z } from 'zod';
import type { AuthRepository } from '@acme/auth-repository';

export function createSignupSchema(repository: Pick<AuthRepository, 'isEmailAvailable'>) {
  return z
    .object({
      email: z.email('Enter a valid email address'),
      password: z.string().min(12, 'Password must be at least 12 characters'),
      confirmPassword: z.string(),
    })
    .refine((v) => v.password === v.confirmPassword, {
      message: 'Passwords do not match',
      path: ['confirmPassword'],
    })
    .superRefine(async (v, ctx) => {
      if (!z.email().safeParse(v.email).success) return;
      const available = await repository.isEmailAvailable(v.email);
      if (!available) {
        ctx.addIssue({ code: 'custom', path: ['email'], message: 'This email is already registered' });
      }
    });
}

export type SignupInput = z.infer<ReturnType<typeof createSignupSchema>>;
```

```ts
const repository = useAuthRepository();
const schema = useMemo(() => createSignupSchema(repository), [repository]);
const form = useForm<SignupInput>({
  resolver: zodResolver(schema),
  mode: 'onBlur',
  reValidateMode: 'onSubmit',
});
```

Guard the network call behind the cheap synchronous check so a malformed email never triggers a request. `mode: 'onBlur'` avoids one request per keystroke.

## Multi-Step Forms

One `useForm` for the whole schema, wrapped in `FormProvider`. Each step validates only its own fields with `trigger`.

```tsx
// src/features/onboarding/components/OnboardingForm.tsx
import { zodResolver } from '@hookform/resolvers/zod';
import { useState } from 'react';
import { FormProvider, useForm, type FieldPath } from 'react-hook-form';
import { onboardingSchema, type OnboardingInput } from '../onboardingSchema';
import { AccountStep } from './AccountStep';
import { ProfileStep } from './ProfileStep';
import { ReviewStep } from './ReviewStep';

const steps: { label: string; fields: FieldPath<OnboardingInput>[]; Component: () => JSX.Element }[] = [
  { label: 'Account', fields: ['email', 'password'], Component: AccountStep },
  { label: 'Profile', fields: ['displayName', 'timezone'], Component: ProfileStep },
  { label: 'Review', fields: [], Component: ReviewStep },
];

interface OnboardingFormProps {
  onSubmit: (values: OnboardingInput) => Promise<void>;
}

export function OnboardingForm({ onSubmit }: OnboardingFormProps) {
  const [stepIndex, setStepIndex] = useState(0);
  const form = useForm<OnboardingInput>({
    resolver: zodResolver(onboardingSchema),
    defaultValues: { email: '', password: '', displayName: '', timezone: 'UTC' },
  });
  const step = steps[stepIndex];
  if (!step) throw new Error(`Invalid step ${stepIndex}`);
  const isLast = stepIndex === steps.length - 1;

  const next = async () => {
    const valid = await form.trigger(step.fields, { shouldFocus: true });
    if (valid) setStepIndex((i) => i + 1);
  };

  return (
    <FormProvider {...form}>
      <form onSubmit={form.handleSubmit(onSubmit)} noValidate>
        <nav aria-label="Progress">
          <ol>
            {steps.map((s, i) => (
              <li key={s.label} aria-current={i === stepIndex ? 'step' : undefined}>{s.label}</li>
            ))}
          </ol>
        </nav>
        <step.Component />
        <div>
          {stepIndex > 0 ? (
            <button type="button" onClick={() => setStepIndex((i) => i - 1)}>Back</button>
          ) : null}
          {isLast ? (
            <button type="submit" disabled={form.formState.isSubmitting}>Finish</button>
          ) : (
            <button type="button" onClick={next}>Next</button>
          )}
        </div>
      </form>
    </FormProvider>
  );
}
```

Steps read the form with `useFormContext<OnboardingInput>()`. Values persist across steps because the form is never unmounted. Put the step index in the URL when users should be able to link to or refresh a step.

## Next.js Server Actions with `useActionState`

The server action validates with the same schema and returns a serializable result. The client runs `react-hook-form` for instant feedback and hands the payload to the action inside a transition.

```ts
// src/features/auth/actions/loginAction.ts
'use server';

import { redirect } from 'next/navigation';
import { z } from 'zod';
import { authRepository } from '@/lib/repositories';
import type { SubmitResult } from '@/lib/forms/submitResult';
import { loginSchema, type LoginInput } from '../loginSchema';

export type LoginActionState = SubmitResult<LoginInput> | null;

export async function loginAction(_previous: LoginActionState, formData: FormData): Promise<LoginActionState> {
  const parsed = loginSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) {
    const { fieldErrors } = z.flattenError(parsed.error);
    return {
      ok: false,
      fieldErrors: {
        email: fieldErrors.email?.[0],
        password: fieldErrors.password?.[0],
      },
    };
  }

  const session = await authRepository.login(parsed.data);
  if (!session) return { ok: false, formError: 'Email or password is incorrect' };

  redirect('/');
}
```

```tsx
// src/features/auth/components/LoginForm.tsx
'use client';

import { zodResolver } from '@hookform/resolvers/zod';
import { startTransition, useActionState, useEffect, useId } from 'react';
import { useForm } from 'react-hook-form';
import { loginAction } from '../actions/loginAction';
import { loginSchema, type LoginInput } from '../loginSchema';

export function LoginForm() {
  const id = useId();
  const [state, formAction, isPending] = useActionState(loginAction, null);
  const {
    register,
    handleSubmit,
    setError,
    formState: { errors },
  } = useForm<LoginInput>({
    resolver: zodResolver(loginSchema),
    defaultValues: { email: '', password: '' },
  });

  useEffect(() => {
    if (!state || state.ok) return;
    for (const field of Object.keys(state.fieldErrors ?? {}) as (keyof LoginInput)[]) {
      const message = state.fieldErrors?.[field];
      if (message) setError(field, { type: 'server', message });
    }
    if (state.formError) setError('root.serverError', { type: 'server', message: state.formError });
  }, [state, setError]);

  const submit = handleSubmit((values) => {
    const formData = new FormData();
    formData.set('email', values.email);
    formData.set('password', values.password);
    startTransition(() => formAction(formData));
  });

  return (
    <form action={formAction} onSubmit={submit} noValidate aria-busy={isPending}>
      <label htmlFor={`${id}-email`}>Email</label>
      <input
        id={`${id}-email`}
        type="email"
        autoComplete="email"
        aria-invalid={errors.email ? true : undefined}
        aria-describedby={errors.email ? `${id}-email-error` : undefined}
        {...register('email')}
      />
      {errors.email ? <p id={`${id}-email-error`} role="alert">{errors.email.message}</p> : null}

      <label htmlFor={`${id}-password`}>Password</label>
      <input
        id={`${id}-password`}
        type="password"
        autoComplete="current-password"
        aria-invalid={errors.password ? true : undefined}
        aria-describedby={errors.password ? `${id}-password-error` : undefined}
        {...register('password')}
      />
      {errors.password ? <p id={`${id}-password-error`} role="alert">{errors.password.message}</p> : null}

      {errors.root?.serverError ? <p role="alert">{errors.root.serverError.message}</p> : null}

      <button type="submit" disabled={isPending}>{isPending ? 'Signing in' : 'Sign in'}</button>
    </form>
  );
}
```

| Piece                      | Responsibility                                                |
| -------------------------- | ------------------------------------------------------------- |
| `action={formAction}`      | Progressive enhancement: submits without JavaScript           |
| `onSubmit={submit}`        | With JavaScript: validate client-side first, then call action |
| `startTransition`          | Required to call `formAction` outside a form submission       |
| `useEffect` on `state`     | Copies server errors onto the form                            |
| `redirect()` in the action | Navigates on success; never returns `{ ok: true }` to render  |

Never put secrets or unvalidated `formData` values into the returned state; it is serialized to the client.
