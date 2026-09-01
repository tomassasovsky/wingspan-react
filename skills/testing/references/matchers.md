# Matchers Quick Reference

Register `@testing-library/jest-dom` once in `src/test/setup.ts` with `import '@testing-library/jest-dom/vitest';`.

## `@testing-library/jest-dom`

| Matcher                             | Asserts                                            | Use when                                                         |
| ----------------------------------- | -------------------------------------------------- | ---------------------------------------------------------------- |
| `toBeInTheDocument()`               | Element is attached to the document                | Presence after `getBy*`/`findBy*`; absence with `queryBy*`       |
| `toBeVisible()`                     | Element and ancestors are not hidden               | Content toggled with `hidden`, `display: none`, or `opacity: 0`  |
| `toBeEmptyDOMElement()`             | Element has no children or text                    | Cleared containers                                               |
| `toHaveTextContent(text)`           | Text content matches string or regex               | Alerts, headings, cells; use instead of `getByText` for partials |
| `toHaveAccessibleName(name)`        | Computed accessible name matches                   | Icon buttons, images, custom controls                            |
| `toHaveAccessibleDescription(desc)` | `aria-describedby` text matches                    | Field hints and validation messages                              |
| `toHaveAccessibleErrorMessage(msg)` | `aria-errormessage` text matches                   | Fields exposing errors through `aria-errormessage`               |
| `toHaveRole(role)`                  | Element has the given ARIA role                    | Custom components that must expose a role                        |
| `toHaveAttribute(name, value?)`     | Attribute exists with optional value               | `href`, `type`, `aria-expanded`, `data-state`                    |
| `toHaveClass(...classes)`           | Element has the classes                            | Only for state classes that drive behavior; never for styling    |
| `toHaveStyle(css)`                  | Computed style matches                             | Rarely; visibility or direction-dependent behavior only          |
| `toHaveFocus()`                     | Element is `document.activeElement`                | Focus management in dialogs, menus, and after navigation         |
| `toBeDisabled()` / `toBeEnabled()`  | Element is disabled through attribute or fieldset  | Submit buttons during pending mutations                          |
| `toBeRequired()`                    | `required` or `aria-required="true"`               | Form field contracts                                             |
| `toBeInvalid()` / `toBeValid()`     | `aria-invalid` or constraint validation state      | Validation feedback                                              |
| `toBeChecked()`                     | Checkbox, radio, or `aria-checked` state           | Toggles and option groups                                        |
| `toBePartiallyChecked()`            | `aria-checked="mixed"`                             | Parent checkboxes in tree selections                             |
| `toHaveValue(value)`                | Input, select, or textarea value                   | Controlled inputs after typing                                   |
| `toHaveDisplayValue(value)`         | Displayed value of select or input                 | Selects with option labels that differ from values               |
| `toHaveFormValues(values)`          | Form's current values as an object                 | Whole-form assertions before submit                              |
| `toContainElement(element)`         | Element contains another element                   | Use `within(parent).getBy*` instead                              |
| `toContainHTML(html)`               | Raw HTML substring                                 | Avoid; couples to markup                                         |
| `toHaveErrorMessage(msg)`           | Deprecated alias of `toHaveAccessibleErrorMessage` | Do not use                                                       |

## `vitest` Core Matchers

| Matcher                               | Asserts                                              | Use when                                     |
| ------------------------------------- | ---------------------------------------------------- | -------------------------------------------- |
| `toBe(value)`                         | `Object.is` equality                                 | Primitives and referential identity          |
| `toEqual(value)`                      | Deep structural equality, ignores `undefined` keys   | Objects, arrays, DTOs                        |
| `toStrictEqual(value)`                | Deep equality including `undefined` keys and classes | Mapper output where shape must match exactly |
| `toMatchObject(partial)`              | Subset of properties match                           | Large objects where only some fields matter  |
| `toHaveLength(n)`                     | `length` property equals `n`                         | Arrays and query results                     |
| `toContain(item)`                     | Array or string contains item                        | Membership checks                            |
| `toContainEqual(item)`                | Array contains a deep-equal item                     | Arrays of objects                            |
| `toBeInstanceOf(Class)`               | Prototype chain includes `Class`                     | Typed errors such as `ApiError`              |
| `toThrow(matcher?)`                   | Function throws                                      | Synchronous validation and mappers           |
| `rejects.toThrow(matcher?)`           | Promise rejects                                      | Async clients and repositories               |
| `resolves.toEqual(value)`             | Promise resolves to value                            | Async clients and repositories               |
| `toHaveBeenCalledTimes(n)`            | Spy call count                                       | Callbacks and mocked boundaries              |
| `toHaveBeenCalledWith(...args)`       | Spy called with args (any call)                      | Callback payloads                            |
| `toHaveBeenLastCalledWith(...args)`   | Most recent call args                                | Debounced or repeated callbacks              |
| `toHaveBeenNthCalledWith(n, ...args)` | Specific call args                                   | Ordered side effects                         |
| `toMatchSnapshot()`                   | Serialized value equals stored snapshot              | Serialized data only; never components       |
| `toMatchInlineSnapshot()`             | Serialized value equals inline snapshot              | Small serialized data such as query keys     |

## Asymmetric Matchers

| Matcher                          | Use when                                             |
| -------------------------------- | ---------------------------------------------------- |
| `expect.objectContaining({...})` | Callback payload has extra fields that do not matter |
| `expect.arrayContaining([...])`  | Order or extra items do not matter                   |
| `expect.stringMatching(/regex/)` | Generated ids, timestamps, or messages               |
| `expect.any(Function)`           | Callback props passed through                        |
| `expect.anything()`              | Any non-null value                                   |

```ts
expect(onSubmit).toHaveBeenCalledWith(
  expect.objectContaining({ email: 'dash@example.com', createdAt: expect.any(String) }),
);
```

## `@playwright/test` Matchers

Every Playwright matcher auto-retries until the timeout; always `await` them.

| Matcher                            | Asserts                                             |
| ---------------------------------- | --------------------------------------------------- |
| `toBeVisible()` / `toBeHidden()`   | Locator is visible or hidden                        |
| `toHaveText(text)`                 | Locator text matches string, regex, or array        |
| `toContainText(text)`              | Locator text contains substring                     |
| `toHaveValue(value)`               | Input value                                         |
| `toBeEnabled()` / `toBeDisabled()` | Control state                                       |
| `toBeChecked()`                    | Checkbox or radio state                             |
| `toHaveAttribute(name, value)`     | Attribute value                                     |
| `toHaveCount(n)`                   | Number of matching elements                         |
| `toBeFocused()`                    | Locator has focus                                   |
| `toHaveURL(url)`                   | Page URL matches string or regex                    |
| `toHaveTitle(title)`               | Document title                                      |
| `toHaveScreenshot()`               | Visual comparison; use only for design-system pages |

## Choosing a Matcher

| Goal                             | Use                                                       | Not                                |
| -------------------------------- | --------------------------------------------------------- | ---------------------------------- |
| Element exists                   | `expect(screen.getByRole(...)).toBeInTheDocument()`       | `expect(...).toBeTruthy()`         |
| Element absent                   | `expect(screen.queryByRole(...)).not.toBeInTheDocument()` | `expect(() => getBy...).toThrow()` |
| Element hidden by CSS but in DOM | `not.toBeVisible()`                                       | `not.toBeInTheDocument()`          |
| Button unavailable               | `toBeDisabled()`                                          | `toHaveAttribute('disabled')`      |
| Text inside a region             | `expect(region).toHaveTextContent(/.../)`                 | `getByText` on the whole document  |
| Callback payload                 | `toHaveBeenCalledWith({...})`                             | `mock.calls[0][0].email === ...`   |
| Async error from a client        | `await expect(promise).rejects.toBeInstanceOf(ApiError)`  | `try/catch` with a boolean flag    |
