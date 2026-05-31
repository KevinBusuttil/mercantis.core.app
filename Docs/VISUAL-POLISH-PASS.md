# Mercantis — Visual Polish Pass (Brand, Status & Surfaces)

_Last updated: 2026-05-31_

This pass moves Mercantis from a "clean technical app" toward a "polished
business product" **without** redesigning the UI or making it colourful. It
refines the design tokens so the product has a recognisable identity, scannable
operational states, and finished-feeling surfaces — while staying a native
macOS business platform, not a web ERP.

The work is token-first: Core owns the colour decisions; Hub consumes them
instead of defining one-off colours.

---

## 1. Brand colour decisions

Defined in `mercantis core/UIShell/DesignTokens/MercantisTheme.swift` and
exposed publicly on `MercantisTheme` so Hub (and any third-party consumer of
`MercantisCoreUI`) can use them.

| Token | Light | Dark | Use |
|---|---|---|---|
| `brandPrimary` | `#4338CA` (indigo-700) | `#4F46E5` (indigo-600) | Primary buttons, product identity (sidebar logo square, hero header chip) |
| `brandPrimaryHover` | `#4F46E5` | `#6366F1` | Optional hover state |
| `brandPrimaryPressed` | `#3730A3` (indigo-800) | `#4338CA` | Primary button pressed state |
| `brandPrimarySoft` | `brandPrimary @ 12%` | — | Tinted cards / identity chips / soft fills |
| `brandPrimaryBorder` | `brandPrimary @ 32%` | — | Hairline ring on tinted surfaces |
| `brandSecondary` | blue-teal | blue-teal | Sparing secondary accent (the indigo's partner) |
| `brandAccent` | cyan | cyan | Rare highlight (focus glints) |

**Direction:** a deep **indigo** — deliberately distinct from the stock macOS
azure accent so Mercantis reads as its own product colour, while staying in the
trustworthy blue-indigo enterprise family. Its partner is the blue-teal
`brandSecondary`. Not bright, not SaaS. All brand colours are **adaptive**
(light/dark) via `MercantisTheme.adaptive(light:dark:)`, which builds a dynamic
`NSColor`/`UIColor` — the package ships no asset catalog.

**Contrast:** `brandPrimary` is tuned so **white text clears WCAG AAA** in both
appearances (≈7.9:1 light, ≈6.3:1 dark). If you ever darken/brighten it, re-check
white-on-brand contrast stays ≥ 4.5:1.

**Note:** the Accounting module tone is also indigo-ish; since the brand now
leans indigo, the two can look related in a side-by-side. They live in different
contexts (brand on buttons/identity, module on small sidebar chips), so this is
acceptable — but if it ever reads as muddy, nudge the Accounting module tone
toward blue-violet to re-separate them.

### What still uses the system accent

`MercantisTheme.accent` is **still `Color.accentColor`** on purpose. Native
selection, list selection tint, and standard control tint continue to respect
the user's macOS accent choice. Only **product identity and the primary action**
were moved to the brand colour. Do **not** globally override `.tint` to brand —
that would recolour native selection and break the native feel.

---

## 2. Semantic status mapping

Defined as `MercantisStatusTone` + the `MercantisStatusBadge` view.

`MercantisStatusTone(status:)` classifies free-form ERP status strings
(case/space/punctuation-tolerant) into a small business palette. Each tone maps
to a semantic colour **and** an SF Symbol, so colour is never the only signal.

| Status (examples) | Tone | Colour | Glyph |
|---|---|---|---|
| Draft, Open, New | `.draft` | muted/grey | `pencil.line` |
| Submitted, Approved, Confirmed | `.submitted` | info/blue | `paperplane.fill` |
| Paid | `.paid` | success/green | `checkmark.seal.fill` |
| Unpaid | `.unpaid` | warning | `exclamationmark.circle` |
| Overdue | `.overdue` | danger | `exclamationmark.triangle.fill` |
| Cancelled, Rejected, Failed | `.cancelled` | danger | `xmark.circle` |
| Closed | `.closed` | muted | `lock.fill` |
| Completed, Done, Delivered | `.completed` | success/green | `checkmark.circle.fill` |
| In Progress, Processing, Partly Paid | `.inProgress` | info | `clock` |
| Stopped, On Hold, Pending | `.stopped` | warning | `pause.circle` |
| Ordered, To Order | `.ordered` | info | `shippingbox.fill` |
| Lost, Expired, Void | `.lost` | danger | `xmark.bin` |
| Reconciled, Settled, Cleared | `.reconciled` | success/green | `checkmark.seal` |
| Active, Enabled, Live | `.active` | success/green | `circle.fill` |
| Inactive, Disabled, Archived | `.inactive` | muted | `circle` |
| _anything unmatched_ | `.neutral` | muted | `circle.dashed` |

**Rules:**
1. Badges always show **text**.
2. Colour is **never** the only indicator (glyph + text always present).
3. Fills are soft tonal + hairline ring → readable in light **and** dark.
4. Unknown statuses degrade gracefully to `.neutral`.
5. Badges stay subtle and business-like — they must not shout.

**Applied to:** `GenericListView` row badges, the Hub record/detail lifecycle
header (`HubDocumentEditor`), and Hub error/snapshot states.

---

## 3. Module colour usage rules

Module tones (`MercantisModuleTone` → `MercantisTheme.moduleTint/Fill/Border`)
are now **adaptive** so they read in light mode without going neon in dark mode.

- CRM blue · Selling green · Buying orange · Stock purple · Accounting indigo ·
  Manufacturing rust · Setup slate · Platform cyan.
- Use them **only** as accents: sidebar icon chips, low-opacity fills, badges,
  selected indicators, dashboard accents.
- **Never** fill a whole module page, sidebar, or large surface with module
  colour. Keep fills ≤ ~12% opacity (see `moduleFill`).

---

## 4. Light / dark mode notes

- Brand, semantic (success/warning/danger/info) and module colours are all
  adaptive; dark variants are brighter but kept slightly desaturated.
- Surfaces/borders/text use native `NSColor`/`UIColor` dynamic colours.
- Primary button keeps white text in both modes (AA-safe).
- Status badge fill + ring read in both modes.
- Verify with `#Preview("Status badges")` in `MercantisTheme.swift` in both
  appearances.

---

## 5. Buttons

`MercantisPrimaryButtonStyle` / `MercantisSecondaryButtonStyle` /
`MercantisDestructiveButtonStyle` are now `public` with a `public init()`:

- **Primary:** brand fill, white label, distinct pressed state, dimmed (`0.45`)
  when disabled. Compact macOS sizing.
- **Secondary:** native, calm, hairline-bordered; does not compete with primary.
- **Destructive:** restrained danger (soft fill + danger label + ring), not a
  loud solid red.

Use these for **product** actions. Leave deep builder/tooling sheets on native
`.bordered`/`.borderedProminent` where a fully native control is more
appropriate — don't force every control into brand colour.

---

## 6. Cards & surfaces

- `.mercantisCard(padding:tinted:)` is the canonical card: consistent corner
  radius (`MercantisSpacing.cardCornerRadius`), native surface fill, hairline
  border, optional brand tint. Prefer it over bespoke card chrome.
- Keep shadows out; lean on borders + native materials for depth.
- Consistent corner radius and padding across cards/tiles/headers.

---

## 7. What NOT to do in future UI work

- ❌ Don't globally set `.tint` to the brand colour (breaks native selection).
- ❌ Don't replace `MercantisTheme.accent` (system accent) wholesale — it's
  intentional for native selection/control tint.
- ❌ Don't use raw `.red` / `.green` / `.orange` / `Color.accentColor` in Hub —
  consume `MercantisTheme` tokens / `MercantisStatusBadge` instead.
- ❌ Don't over-colour the sidebar or fill module pages with saturated colour.
- ❌ Don't use colour as the only status indicator — always text + glyph.
- ❌ Don't add heavy gradients, glassmorphism, or web-dashboard decoration.
- ❌ Don't hard-code ERP domain logic in Core; status **mapping** is generic and
  string-driven, not domain-coupled.

---

## 8. File map

**Core (`MercantisCoreUI`):**
- `UIShell/DesignTokens/MercantisTheme.swift` — brand palette, adaptive helper,
  semantic + module tones, `MercantisStatusTone`, `MercantisStatusBadge`,
  public button styles, `.mercantisCard`.
- `UIShell/GenericListView.swift` — row status badge → `MercantisStatusBadge`.
- `UIShell/Components/WorkspaceHeroHeader.swift` — brand identity chip.
- `UIShell/Components/MercantisSidebarComponents.swift` — brand logo square.

**Hub (`MercantisCoreUI` consumer):**
- `UI/RootView.swift` — lifecycle/workflow status badges, semantic error styling.
- `UI/Home/HubHomeView.swift` — brand identity, semantic checklist/banner,
  brand-tinted card surface, brand primary CTA.
- `UI/Dashboards/HubDashboardView.swift` — semantic error tile, brand shortcut.
