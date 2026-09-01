# Accessibility — Element and ARIA Pattern Mapping

Quick reference for the HTML element or ARIA pattern each common component requires, the keyboard behavior users expect, and the Radix primitive that implements it.

---

## Native Elements First

| Need                            | Element                                                 | Why                                                        |
| ------------------------------- | ------------------------------------------------------- | ---------------------------------------------------------- |
| Trigger an action               | `<button type="button">`                                | Focusable, `Enter`/`Space` activation, `role="button"`     |
| Navigate                        | `<a href>` or router `<Link>`                           | `Enter` activation, announced as link, history integration |
| Submit a form                   | `<button type="submit">` inside `<form>`                | `Enter` from any field submits                             |
| Text input                      | `<input>` or `<textarea>` with `<label htmlFor>`        | Name, value, and autofill for free                         |
| Single choice from a short list | `<input type="radio">` inside `<fieldset>` + `<legend>` | Arrow-key group navigation                                 |
| Single choice from a long list  | `<select>` or Radix `Select`                            | Typeahead and native mobile pickers                        |
| Boolean                         | `<input type="checkbox">` or Radix `Switch`             | State announced as checked/unchecked or on/off             |
| Tabular data                    | `<table>` + `<caption>` + `<th scope>`                  | Row and column header announcement                         |
| Grouped content                 | `<section aria-labelledby>` with a heading              | Landmark navigation                                        |
| Page regions                    | `<header>`, `<nav>`, `<main>`, `<aside>`, `<footer>`    | Landmark navigation; one `<main>` per page                 |
| Status text                     | `<output>` or `role="status"`                           | Live announcement without focus change                     |
| Progress                        | `<progress>` or `role="progressbar"` + `aria-valuenow`  | Value announced                                            |

---

## Composite Widgets

| Component               | Role structure                                                                                                | Keyboard                                                                                     | Radix primitive                                    | Notes                                                                                            |
| ----------------------- | ------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Menu button             | `button[aria-haspopup=menu][aria-expanded]` + `menu` > `menuitem`                                             | `Enter`/`Space`/`ArrowDown` open; arrows move; `Escape` closes and restores focus; typeahead | `@radix-ui/react-dropdown-menu`                    | Only for action lists; never for navigation links                                                |
| Navigation menu         | `nav` > `ul` > `li` > `a`                                                                                     | `Tab` between links                                                                          | `@radix-ui/react-navigation-menu`                  | No `menu` role on site navigation                                                                |
| Tabs                    | `tablist` > `tab[aria-selected][aria-controls]`; `tabpanel[aria-labelledby]`                                  | Arrows move between tabs; `Tab` moves into panel; `Home`/`End`                               | `@radix-ui/react-tabs`                             | Roving `tabIndex`; automatic or manual activation, pick one per app                              |
| Combobox                | `input[role=combobox][aria-expanded][aria-controls][aria-autocomplete]` + `listbox` > `option[aria-selected]` | Arrows move active option (`aria-activedescendant`); `Enter` selects; `Escape` closes        | `cmdk` or `@radix-ui/react-select` (single choice) | Announce result count through a `role="status"` region                                           |
| Select                  | `button[role=combobox][aria-expanded]` + `listbox`                                                            | Same as combobox without typing                                                              | `@radix-ui/react-select`                           | Use native `<select>` when styling freedom is not required                                       |
| Dialog                  | `dialog[aria-modal=true][aria-labelledby][aria-describedby]`                                                  | Focus trapped; `Escape` closes; focus returns to trigger                                     | `@radix-ui/react-dialog`                           | Inert background; scroll lock                                                                    |
| Alert dialog            | `alertdialog` with the same wiring                                                                            | Same as dialog; `Escape` cancels                                                             | `@radix-ui/react-alert-dialog`                     | Destructive confirmations; initial focus on cancel                                               |
| Disclosure              | `button[aria-expanded][aria-controls]` + content region                                                       | `Enter`/`Space` toggles                                                                      | `@radix-ui/react-collapsible`                      | Content in DOM order right after the button                                                      |
| Accordion               | Heading > `button[aria-expanded][aria-controls]`; `region[aria-labelledby]`                                   | `Enter`/`Space` toggles; arrows optional                                                     | `@radix-ui/react-accordion`                        | Button inside a heading element of the correct level                                             |
| Tooltip                 | `tooltip` referenced by `aria-describedby` on the trigger                                                     | Appears on focus and hover; `Escape` dismisses; stays while hovered                          | `@radix-ui/react-tooltip`                          | Never put interactive content inside; trigger must be focusable                                  |
| Popover                 | `dialog` (non-modal) or content with `aria-expanded` trigger                                                  | `Escape` closes; focus moves in on open and back on close                                    | `@radix-ui/react-popover`                          | Non-modal; background stays operable                                                             |
| Toggle button           | `button[aria-pressed]`                                                                                        | `Enter`/`Space` toggles                                                                      | `@radix-ui/react-toggle`                           | Label stays the same; state changes                                                              |
| Switch                  | `button[role=switch][aria-checked]`                                                                           | `Space` toggles                                                                              | `@radix-ui/react-switch`                           | Prefer a checkbox when the change needs a submit                                                 |
| Checkbox group          | `group[aria-labelledby]` or `fieldset` > `checkbox`                                                           | `Space` toggles                                                                              | `@radix-ui/react-checkbox`                         | Native `<input type="checkbox">` unless custom styling is required                               |
| Radio group             | `radiogroup[aria-labelledby]` > `radio[aria-checked]`                                                         | Arrows move and select; `Tab` leaves group                                                   | `@radix-ui/react-radio-group`                      | Roving `tabIndex`                                                                                |
| Slider                  | `slider[aria-valuemin][aria-valuemax][aria-valuenow][aria-valuetext]`                                         | Arrows adjust; `Home`/`End`; `PageUp`/`PageDown`                                             | `@radix-ui/react-slider`                           | `aria-valuetext` for units ("30 minutes")                                                        |
| Toast                   | `role="status"` (info) or `role="alert"` (error) region                                                       | Not focused; dismiss button reachable by `Tab`                                               | `@radix-ui/react-toast`                            | Persistent region mounted at root; toasts must not time out below 5 seconds without user control |
| Breadcrumb              | `nav[aria-label=Breadcrumb]` > `ol` > `li` > `a[aria-current=page]`                                           | `Tab`                                                                                        | None needed                                        | Current page is plain text or `aria-current="page"` link                                         |
| Pagination              | `nav[aria-label=Pagination]` > list of links; `aria-current="page"`                                           | `Tab`                                                                                        | None needed                                        | Links with page numbers as text; `aria-label="Next page"` on icon links                          |
| Data grid (interactive) | `grid` > `row` > `gridcell`/`columnheader`                                                                    | Arrows move cell focus; single `tabIndex` stop                                               | `@tanstack/react-table` + APG grid pattern         | Only when cells are interactive; otherwise plain `<table>`                                       |
| Skip link               | `a[href="#main"]` first in DOM, visible on focus                                                              | `Tab` once from page load                                                                    | None needed                                        | Target `<main id="main" tabIndex={-1}>`                                                          |

---

## ARIA Rules of Engagement

| Rule                                         | Detail                                                                           |
| -------------------------------------------- | -------------------------------------------------------------------------------- |
| No ARIA is better than bad ARIA              | A `div` with `role="button"` and no keyboard handler is worse than a plain `div` |
| Roles set expectations for keyboard behavior | Adding `role="tab"` obliges arrow-key navigation                                 |
| Never change native semantics                | No `role="heading"` on a `<button>`; no `role="button"` on a `<h2>`              |
| Interactive elements are focusable           | Anything with an interactive role has `tabIndex={0}` or is natively focusable    |
| Do not hide focusable content                | `aria-hidden="true"` never wraps a focusable element                             |
| Every interactive element has a name         | Content, `aria-label`, or `aria-labelledby`                                      |
| `aria-label` overrides content               | Use `aria-labelledby` when the visible text already exists                       |
| `aria-describedby` supplements               | Hints and errors, not the name                                                   |
| Live regions are persistent                  | Mounted before the first update                                                  |

---

## References

- [ARIA Authoring Practices Guide patterns](https://www.w3.org/WAI/ARIA/apg/patterns/)
- [Radix Primitives accessibility](https://www.radix-ui.com/primitives/docs/overview/accessibility)
- [HTML Accessibility API Mappings](https://www.w3.org/TR/html-aam-1.0/)
