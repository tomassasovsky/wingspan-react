---
name: react-accessibility
description: Audit or remediate React UI against WCAG 2.2 conformance levels A, AA, or AAA. Use when building, auditing, or reviewing components for screen reader support, keyboard navigation, focus management, color contrast, target size, reduced motion, live regions, headings, or skip links, or when setting up vitest-axe, @axe-core/playwright, or eslint-plugin-jsx-a11y.
argument-hint: "[file-or-directory] [A|AA|AAA]"
allowed-tools: Read Glob Grep
effort: high
---

# Accessibility

React accessibility auditing and remediation against WCAG 2.2 levels A, AA, and AAA — semantic HTML, keyboard operability, focus management, contrast, target size, motion, and live regions, verified with `vitest-axe`, `@axe-core/playwright`, and a manual screen reader pass.

---

## Core Standards

Apply these standards to ALL accessibility work:

- **Use semantic HTML before ARIA** — `<button>`, `<a href>`, `<nav>`, `<main>`, `<table>` carry role, state, and keyboard behavior for free; add ARIA only when no native element fits
- **Never attach click handlers to `div` or `span`** — use `<button type="button">`; `jsx-a11y/no-static-element-interactions` and `jsx-a11y/click-events-have-key-events` are errors
- **Every interactive element is keyboard reachable with a visible `:focus-visible` indicator** — 2px outline with 3:1 contrast against adjacent colors; never `outline: none` without a replacement
- **Every input has a `<label htmlFor>`** — placeholders are not labels; attach hints and errors with `aria-describedby`
- **Every icon-only button has an accessible name** — `aria-label` on the button, `aria-hidden="true"` on the icon
- **Text contrast 4.5:1, large text and UI components 3:1 at AA; 7:1 and 4.5:1 at AAA** — verify with axe in Playwright, never in jsdom
- **Pointer targets are at least 24x24 CSS px (2.5.8) and 44x44 by default** — enforce with `min-inline-size`/`min-block-size` inside the component, not at call sites
- **All motion respects `prefers-reduced-motion`** — gate transitions on a `--motion-duration-*` token that collapses to `0ms`; nothing flashes more than 3 times per second
- **Manage focus on route change and in dialogs** — move focus to the page `<h1>` (or `<main tabIndex={-1}>`) after navigation; Radix `Dialog` traps and restores focus, hand-rolled dialogs must do the same
- **Announce async status through a live region mounted before the update** — `role="status"` for progress and success, `role="alert"` for errors; never mount `aria-live` at update time
- **One `<h1>` per page and no skipped heading levels** — headings describe structure; style them with tokens instead of choosing a lower level
- **Provide a skip link as the first focusable element** — `<a href="#main">` targeting `<main id="main" tabIndex={-1}>`
- **`eslint-plugin-jsx-a11y` violations are build errors** — use `jsxA11y.flatConfigs.strict`; never disable a rule inline without a WCAG-cited justification
- **Every component ships with an axe test and a keyboard test** — `vitest-axe` in unit tests, `@axe-core/playwright` per route, and a manual screen reader pass before release

---

## Workflow

Every engagement follows four phases in sequence. Do not skip Phase 1.

### Phase 1 — Scope

Parse `$ARGUMENTS` as `[file-or-directory] [A|AA|AAA]`. If the level is missing, ask:

> "Which WCAG 2.2 conformance level are you targeting?
>
> - **A** — Removes the most critical barriers: text alternatives, keyboard access, no flashing, labels, error identification, status messages.
> - **AA** — Adds contrast (4.5:1 / 3:1), reflow, focus visibility, target size (24px), dragging alternatives, accessible authentication. The standard legal and compliance baseline.
> - **AAA** — Adds enhanced contrast (7:1), 44px targets, no timing, full motion control, focus appearance. Applied to specific components, rarely to whole products.
>
> Reply with A, AA, or AAA."

If the path is missing, default to `src/`. Record both; every check, report entry, and fix applies only the criteria for that level plus all lower levels.

### Phase 2 — Audit

Audit the scoped files across seven categories in order. For each finding capture: file path and line, WCAG criterion ID and name, severity, current behavior, expected behavior, before/after code.

1. **Semantics and Names** — native elements, `alt`, accessible names, `aria-hidden` on decorative content, ARIA only where needed
2. **Keyboard and Focus** — reachability, DOM-order tab sequence, `:focus-visible`, dialog focus trap and restore, route-change focus, no keyboard traps
3. **Forms and Errors** — `<label htmlFor>`, `autoComplete`, `aria-invalid`, `aria-describedby`, error text with a suggestion, `role="alert"` on submit failures
4. **Contrast and Color** — text, icon, border, and focus ring ratios at the selected level; color never the sole signal
5. **Target Size and Pointer** — 24px minimum (44px default), single-pointer alternative for drag, actions on `click` not `pointerdown`
6. **Motion** — `prefers-reduced-motion` gating, no auto-playing motion longer than 5 seconds without a pause control, no flashing
7. **Structure and Navigation** — landmarks, heading hierarchy, skip link, `document.title` per route, `<html lang>`, `aria-current`

Run `pnpm eslint <path>` and the existing `vitest-axe` and Playwright suites first; treat their output as findings with automated evidence, then complete the manual checks the tools cannot cover (focus order, names, reading order, live region timing).

### Phase 3 — Report

Produce the report using the level template in [references/audit-templates.md](references/audit-templates.md). Order findings by severity, then by file.

### Phase 4 — Remediation Scope

Use the `AskUserQuestion` tool with one question:

```yaml
question: "The audit is complete. How would you like to proceed with fixes?"
header: "Fix scope"
options:
  - label: "All issues"
    description: "Fix every CRITICAL, MAJOR, and MINOR finding"
  - label: "Critical + Major only"
    description: "Fix blockers and significant barriers; skip MINOR polish items"
  - label: "Critical only"
    description: "Fix only what blocks assistive technology users entirely"
  - label: "Specific findings"
    description: "List the finding numbers you want fixed"
```

Apply exactly the selected fixes, add or update the matching `vitest-axe` and keyboard tests, and confirm: "Fixed [N] findings ([severities]). [N remaining] remain open."

---

## WCAG 2.2 Criteria to React Patterns

Level AA includes all Level A criteria; Level AAA includes A and AA. WCAG 2.2 removed 4.1.1 Parsing; do not report it.

### Level A

| WCAG ID | Criterion                 | React Check                                                                                                                                 |
| ------- | ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| 1.1.1   | Non-text Content          | `alt` on every `<img>`; `alt=""` on decorative images; `aria-hidden="true"` on decorative SVG; `<title>` or `aria-label` on informative SVG |
| 1.3.1   | Info and Relationships    | Semantic elements; `<label htmlFor>`; `<th scope>`; `<fieldset>` + `<legend>` for groups; real `<ul>`/`<ol>` for lists                      |
| 1.3.2   | Meaningful Sequence       | DOM order matches reading order; no CSS `order` or `row-reverse` that reorders focus; no positive `tabIndex`                                |
| 1.3.3   | Sensory Characteristics   | Instructions never rely on shape, position, size, or sound alone                                                                            |
| 1.4.1   | Use of Color              | Pair color with text, icon, or pattern; links inside body text are underlined                                                               |
| 2.1.1   | Keyboard                  | Native elements or Radix primitives; custom widgets implement the APG keyboard pattern                                                      |
| 2.1.2   | No Keyboard Trap          | Focus can leave every widget; `Escape` closes overlays and returns focus                                                                    |
| 2.1.4   | Character Key Shortcuts   | Single-key shortcuts only while the widget has focus, or remappable                                                                         |
| 2.2.2   | Pause, Stop, Hide         | Carousels and tickers have a pause control; nothing auto-advances without one                                                               |
| 2.3.1   | Three Flashes or Below    | No content flashes more than 3 times per second                                                                                             |
| 2.4.1   | Bypass Blocks             | Skip link first in DOM; `<main>`, `<nav>`, `<header>`, `<footer>` landmarks                                                                 |
| 2.4.2   | Page Titled               | Unique `<title>` per route (React 19 `<title>` or Next `metadata`)                                                                          |
| 2.4.3   | Focus Order               | DOM order; portals restore focus to the trigger on close                                                                                    |
| 2.4.4   | Link Purpose (In Context) | Link text describes the destination; no bare "click here" or "read more"                                                                    |
| 2.5.1   | Pointer Gestures          | Drag and multipoint gestures have a single-pointer alternative                                                                              |
| 2.5.2   | Pointer Cancellation      | Actions fire on `click`, never on `pointerdown` or `mousedown`                                                                              |
| 2.5.3   | Label in Name             | `aria-label` starts with the visible text                                                                                                   |
| 3.1.1   | Language of Page          | `<html lang>` set from the active locale                                                                                                    |
| 3.2.1   | On Focus                  | Focusing never navigates, submits, or opens an overlay                                                                                      |
| 3.2.2   | On Input                  | Changing a `<select>` or checkbox never navigates without an explicit submit                                                                |
| 3.2.6   | Consistent Help           | Help links and contact controls sit in the same position on every page                                                                      |
| 3.3.1   | Error Identification      | Errors described in text; `aria-invalid` and `aria-describedby` on the field                                                                |
| 3.3.2   | Labels or Instructions    | Visible labels; required fields marked in text, not color alone                                                                             |
| 3.3.7   | Redundant Entry           | Multi-step forms prefill or offer previously entered values                                                                                 |
| 4.1.2   | Name, Role, Value         | Native element, or complete ARIA pattern: role, state, keyboard handling                                                                    |
| 4.1.3   | Status Messages           | `role="status"` or `role="alert"` region mounted before the update                                                                          |

### Level AA

| WCAG ID | Criterion                                 | React Check                                                                                       |
| ------- | ----------------------------------------- | ------------------------------------------------------------------------------------------------- |
| 1.3.5   | Identify Input Purpose                    | `autoComplete` tokens: `email`, `given-name`, `postal-code`, `current-password`                   |
| 1.4.3   | Contrast (Minimum)                        | Text 4.5:1; large text (24px, or 18.66px bold) 3:1                                                |
| 1.4.4   | Resize Text                               | Works at 200% zoom; `rem` units; no fixed heights around text                                     |
| 1.4.10  | Reflow                                    | No horizontal scroll at 320 CSS px; `overflow-x: auto` only on tables and code                    |
| 1.4.11  | Non-text Contrast                         | Borders, icons, and focus rings 3:1 against adjacent colors                                       |
| 1.4.12  | Text Spacing                              | No clipping when line height 1.5, letter spacing 0.12em, word spacing 0.16em                      |
| 1.4.13  | Content on Hover or Focus                 | Tooltips dismiss on `Escape`, stay while hovered, persist until dismissed (Radix `Tooltip`)       |
| 2.4.6   | Headings and Labels                       | Headings and labels describe the content that follows                                             |
| 2.4.7   | Focus Visible                             | `:focus-visible` styles on every interactive element                                              |
| 2.4.11  | Focus Not Obscured (Minimum)              | Sticky headers never cover the focused element; `scroll-padding-block-start` equals header height |
| 2.5.7   | Dragging Movements                        | Drag and drop has a button or keyboard alternative (move up/down, select target)                  |
| 2.5.8   | Target Size (Minimum)                     | 24x24 CSS px, or 24px spacing between smaller targets; inline text links exempt                   |
| 3.1.2   | Language of Parts                         | `lang` attribute on spans in another language                                                     |
| 3.2.3   | Consistent Navigation                     | Same navigation order on every route                                                              |
| 3.2.4   | Consistent Identification                 | Same icon and name for the same action everywhere                                                 |
| 3.3.3   | Error Suggestion                          | `zod` messages say how to fix the value                                                           |
| 3.3.4   | Error Prevention (Legal, Financial, Data) | Review step, confirmation, or undo before commit                                                  |
| 3.3.8   | Accessible Authentication (Minimum)       | Paste allowed; password managers work; no image CAPTCHA without alternative                       |

### Level AAA

| WCAG ID | Criterion                            | React Check                                                             |
| ------- | ------------------------------------ | ----------------------------------------------------------------------- |
| 1.4.6   | Contrast (Enhanced)                  | Text 7:1; large text 4.5:1                                              |
| 1.4.8   | Visual Presentation                  | Line length under 80 characters; line height 1.5; no justified text     |
| 2.1.3   | Keyboard (No Exception)              | Every function keyboard operable, including drawing and drag            |
| 2.2.3   | No Timing                            | No time limits except real-time events                                  |
| 2.3.2   | Three Flashes                        | No flashing at all                                                      |
| 2.3.3   | Animation from Interactions          | All non-essential motion disabled under `prefers-reduced-motion`        |
| 2.4.8   | Location                             | Breadcrumbs and `aria-current="page"` in navigation                     |
| 2.4.9   | Link Purpose (Link Only)             | Link text alone identifies the destination                              |
| 2.4.12  | Focus Not Obscured (Enhanced)        | No part of the focused element is hidden by other content               |
| 2.4.13  | Focus Appearance                     | Indicator at least 2px around the perimeter with 3:1 change of contrast |
| 2.5.5   | Target Size (Enhanced)               | 44x44 CSS px                                                            |
| 3.3.6   | Error Prevention (All)               | Every submission reversible, checked, or confirmed                      |
| 3.3.9   | Accessible Authentication (Enhanced) | No cognitive test of any kind, including object recognition             |

---

## Accessible Components

Complete versions, including the Radix dialog, data table, route focus, and skip link, live in [references/examples.md](references/examples.md). Element-to-ARIA patterns with Radix equivalents live in [references/element-mapping.md](references/element-mapping.md).

### Icon Button

```tsx
// packages/ui/src/IconButton.tsx
import type { ComponentProps, ReactNode } from 'react';

type IconButtonProps = Omit<ComponentProps<'button'>, 'children' | 'aria-label'> & {
  label: string;
  icon: ReactNode;
};

export function IconButton({ label, icon, type = 'button', className = '', ...rest }: IconButtonProps) {
  return (
    <button type={type} aria-label={label} className={`icon-button ${className}`.trim()} {...rest}>
      <span aria-hidden="true">{icon}</span>
    </button>
  );
}
```

`.icon-button` sets `min-inline-size: 44px; min-block-size: 44px` and a `:focus-visible` outline of `2px solid var(--color-focus-ring)`; the transition reads `var(--motion-duration-fast)`.

### Form Field

```tsx
// packages/ui/src/TextField.tsx
import { useId, type ComponentProps } from 'react';

type TextFieldProps = Omit<ComponentProps<'input'>, 'id'> & {
  label: string;
  hint?: string;
  error?: string;
};

export function TextField({ label, hint, error, ...rest }: TextFieldProps) {
  const id = useId();
  const hintId = `${id}-hint`;
  const errorId = `${id}-error`;
  const describedBy = [hint ? hintId : null, error ? errorId : null]
    .filter((value): value is string => value !== null)
    .join(' ');

  return (
    <div className="field">
      <label htmlFor={id}>{label}</label>
      {hint ? <p id={hintId} className="field-hint">{hint}</p> : null}
      <input
        id={id}
        aria-invalid={error ? true : undefined}
        aria-describedby={describedBy === '' ? undefined : describedBy}
        {...rest}
      />
      {error ? (
        <p id={errorId} role="alert" className="field-error">
          {error}
        </p>
      ) : null}
    </div>
  );
}
```

### Dialog (Radix)

```tsx
<ConfirmDialog
  trigger={<button type="button">Delete</button>}
  title="Delete project?"
  description="This cannot be undone."
  confirmLabel="Delete"
  cancelLabel="Cancel"
  onConfirm={deleteProject}
/>
```

`ConfirmDialog` wraps `@radix-ui/react-dialog`, which supplies `role="dialog"`, `aria-modal`, `aria-labelledby`, `aria-describedby`, focus trap, `Escape`, and focus restoration. Never rebuild these by hand.

### Live Region (Toast and Status)

```tsx
// packages/ui/src/StatusRegion.tsx
type StatusRegionProps = { message: string; tone?: 'status' | 'alert' };

export function StatusRegion({ message, tone = 'status' }: StatusRegionProps) {
  return (
    <div role={tone} aria-live={tone === 'alert' ? 'assertive' : 'polite'} aria-atomic="true" className="sr-only">
      {message}
    </div>
  );
}
```

Mount `StatusRegion` once at the app root with an empty message; update `message` from mutation callbacks. Toast libraries that render a new node per toast must also mount a persistent region.

---

## Tests

Full setup for `vitest-axe`, `@axe-core/playwright`, keyboard tests, and the manual screen reader checklist is in [references/testing.md](references/testing.md).

```tsx
// packages/ui/src/IconButton.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { axe } from 'vitest-axe';
import { IconButton } from './IconButton';

describe('IconButton', () => {
  it('has no axe violations', async () => {
    const { container } = render(<IconButton label="Close" icon={<svg />} />);
    expect(await axe(container)).toHaveNoViolations();
  });

  it('exposes its label and activates from the keyboard', async () => {
    const user = userEvent.setup();
    const onClick = vi.fn();
    render(<IconButton label="Close" icon={<svg />} onClick={onClick} />);

    await user.tab();
    expect(screen.getByRole('button', { name: 'Close' })).toHaveFocus();
    await user.keyboard('{Enter}');
    expect(onClick).toHaveBeenCalledOnce();
  });
});
```

---

## Anti-Patterns

| Anti-Pattern                            | Problem                                       | Correct Approach                                                    |
| --------------------------------------- | --------------------------------------------- | ------------------------------------------------------------------- |
| `<div onClick>`                         | No role, no focus, no keyboard activation     | `<button type="button">`                                            |
| `<a>` without `href` used as a button   | Not focusable; wrong role                     | `<button>` for actions, `<a href>` for navigation                   |
| `outline: none` on `:focus`             | Keyboard users lose their place (2.4.7)       | Style `:focus-visible` with a 2px, 3:1 ring                         |
| Placeholder as the only label           | Disappears on input; not announced as a label | `<label htmlFor>` plus optional placeholder                         |
| Icon button without a name              | Announced as "button"                         | `aria-label` on the button, `aria-hidden` on the icon               |
| `aria-live` mounted at update time      | Screen readers miss the first announcement    | Persistent `role="status"` region at the root                       |
| Positive `tabIndex`                     | Unpredictable focus order (2.4.3)             | DOM order; `tabIndex={0}` or `-1` only                              |
| Custom dropdown built from `div`s       | No role, state, or keyboard pattern           | Radix `Select`, `DropdownMenu`, or native `<select>`                |
| Color-only validation state             | Invisible to color-blind users (1.4.1)        | Text message plus `aria-invalid`                                    |
| Skipping heading levels for visual size | Broken outline for screen reader navigation   | Correct level; style with typography tokens                         |
| Animations ignoring reduced motion      | Vestibular harm (2.3.3)                       | `--motion-duration-*` tokens collapsing to `0ms`                    |
| `eslint-disable jsx-a11y/*`             | Hides real barriers                           | Fix the markup; document the rare exception with the WCAG criterion |
| Running color-contrast in jsdom         | jsdom has no layout; false passes             | Run contrast checks in Playwright                                   |

---

## Additional Resources

- [Element and ARIA pattern mapping](references/element-mapping.md) — menu, tabs, combobox, dialog, disclosure, tooltip, with keyboard expectations and Radix equivalents
- [Testing](references/testing.md) — `vitest-axe` setup, `@axe-core/playwright` route checks, keyboard tests with `@testing-library/user-event`, manual screen reader checklist
- [Audit report templates](references/audit-templates.md) — severity guide and templates for levels A, AA, and AAA
- [Before and after examples](references/examples.md) — remediation examples for each audit category, including `ConfirmDialog`, data table, route focus, skip link, and reduced motion
- [WCAG 2.2 Understanding Documents](https://www.w3.org/WAI/WCAG22/Understanding/)
- [ARIA Authoring Practices Guide](https://www.w3.org/WAI/ARIA/apg/patterns/)
