# Accessibility — Audit Report Templates

Report templates by WCAG 2.2 conformance level, including the severity guide and passed-check lists for levels A, AA, and AAA.

---

## Severity Guide

| Severity     | Meaning                                                      | Examples                                                                                                                                                        |
| ------------ | ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **CRITICAL** | Blocks assistive technology users entirely; fix before merge | `div` click handler on a required flow; unlabeled form field; dialog without focus trap; missing accessible name on the primary action; focus indicator removed |
| **MAJOR**    | Significant barrier; fix in the current sprint               | Contrast fails by more than 1 point; target under 20px; live region missing on submit errors; focus lost after route change; skipped heading levels             |
| **MINOR**    | Degraded experience or polish; schedule next sprint          | Contrast fails marginally; hint text not linked with `aria-describedby`; 1px focus ring; non-critical status not announced                                      |

Severity applies only to criteria in scope for the selected level. A Level AAA failure in a Level AA audit is listed under "Out of Scope Observations", never as a finding.

---

## Report Template (all levels)

```text
# React Accessibility Audit

**Date:** YYYY-MM-DD
**WCAG Level:** [A | AA | AAA]
**Scope:** path/to/directory
**Automated evidence:** eslint-plugin-jsx-a11y [pass | N errors], vitest-axe [pass | N violations], @axe-core/playwright [pass | N violations | not run]

## Summary
| Severity | Count |
|----------|-------|
| CRITICAL |  0    |
| MAJOR    |  0    |
| MINOR    |  0    |

## Findings

### 1. [Short descriptive title]
- **File:** path/to/Component.tsx:42
- **WCAG:** [ID] [name] (Level [A | AA | AAA])
- **Category:** [Semantics and Names | Keyboard and Focus | Forms and Errors | Contrast and Color | Target Size and Pointer | Motion | Structure and Navigation]
- **Severity:** [CRITICAL | MAJOR | MINOR]
- **Detected by:** [jsx-a11y rule name | axe rule id | manual]
- **Issue:** [what a user experiences]
- **Fix:**
  // Before
  [existing code]

  // After
  [fixed code]
- **Test:** [vitest-axe | user-event keyboard | Playwright] assertion to add

### 2. [Next finding]

## Passed Checks
[copy the applicable list below and mark each item]

## Out of Scope Observations
[higher-level criteria noticed during the audit, one line each]
```

---

## Passed Checks — Level A

```text
- [x] 1 Semantics and Names — native elements used; every image has alt; every control has a name (1.1.1, 1.3.1, 4.1.2)
- [x] 2 Keyboard and Focus — every control reachable and operable; no traps; DOM order matches reading order (2.1.1, 2.1.2, 2.4.3)
- [x] 3 Forms and Errors — visible labels; errors described in text (3.3.1, 3.3.2)
- [x] 4 Contrast and Color — color never the sole signal (1.4.1)
- [x] 5 Target Size and Pointer — actions fire on click; drag has single-pointer alternative (2.5.1, 2.5.2)
- [x] 6 Motion — nothing flashes above 3 Hz; auto-updating content can be paused (2.2.2, 2.3.1)
- [x] 7 Structure and Navigation — skip link; landmarks; unique page titles; html lang set; help in consistent position (2.4.1, 2.4.2, 3.1.1, 3.2.6)
- [x] 8 Status Messages — live region mounted before updates (4.1.3)
- [x] 9 Redundant Entry — multi-step forms reuse entered data (3.3.7)
```

## Passed Checks — Level AA (Level A plus these)

```text
- [x] 2 Keyboard and Focus — focus-visible ring 3:1, not obscured by sticky UI (2.4.7, 2.4.11)
- [x] 3 Forms and Errors — autoComplete tokens; error suggestions; confirm or undo for legal and financial submissions; auth allows paste and password managers (1.3.5, 3.3.3, 3.3.4, 3.3.8)
- [x] 4 Contrast and Color — text 4.5:1, large text and UI components 3:1 (1.4.3, 1.4.11)
- [x] 5 Target Size and Pointer — 24x24 CSS px minimum; drag has button or keyboard alternative (2.5.7, 2.5.8)
- [x] 7 Structure and Navigation — reflow at 320 px; 200% zoom; text spacing; consistent navigation; descriptive headings (1.4.4, 1.4.10, 1.4.12, 2.4.6, 3.2.3)
- [x] 8 Hover and Focus Content — tooltips dismissable, hoverable, persistent (1.4.13)
```

## Passed Checks — Level AAA (Levels A and AA plus these)

```text
- [x] 2 Keyboard and Focus — every function keyboard operable; 2px perimeter focus ring; focused element never obscured (2.1.3, 2.4.12, 2.4.13)
- [x] 4 Contrast and Color — text 7:1, large text 4.5:1 (1.4.6)
- [x] 5 Target Size and Pointer — 44x44 CSS px (2.5.5)
- [x] 6 Motion — all non-essential motion disabled under reduced motion; no flashing (2.3.2, 2.3.3)
- [x] 7 Structure and Navigation — breadcrumbs or aria-current; section headings; link text self-describing (2.4.8, 2.4.9, 2.4.10)
- [x] 9 Timing — no time limits; interruptions postponable; timeout warnings (2.2.3, 2.2.4, 2.2.6)
- [x] 10 Help and Prevention — context help; every submission reversible or confirmed; no cognitive auth test (3.3.5, 3.3.6, 3.3.9)
```

---

## Finding Example

```text
### 3. Icon-only close button has no accessible name
- **File:** src/features/cart/components/CartDrawer.tsx:58
- **WCAG:** 4.1.2 Name, Role, Value (Level A)
- **Category:** Semantics and Names
- **Severity:** CRITICAL
- **Detected by:** jsx-a11y/control-has-associated-label; axe button-name
- **Issue:** Screen readers announce "button" with no purpose; users cannot tell how to close the drawer.
- **Fix:**
  // Before
  <button onClick={close}><XIcon /></button>

  // After
  <IconButton label="Close cart" icon={<XIcon />} onClick={close} />
- **Test:** screen.getByRole('button', { name: 'Close cart' }) in CartDrawer.test.tsx; axe(container) passes
```
