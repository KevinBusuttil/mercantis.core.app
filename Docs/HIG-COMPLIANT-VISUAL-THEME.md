# MercantisCoreUI — HIG-Compliant Visual Theme (design-system layer)

> The reusable, **app-agnostic** half of the Mercantis visual theme. Hub composes
> these into screens; this document is the reference for the tokens and
> primitives that ship in `MercantisCoreUI`. For full layout direction (dashboard
> / document workspace / POS), see `mercantis.hub.app/Docs/HIG-COMPLIANT-VISUAL-THEME.md`.

## Where things live

- **Tokens:** `mercantis core/UIShell/DesignTokens/`
  (`MercantisTheme`, `MercantisSpacing`, `MercantisTypography`, `MercantisMaterials`)
- **Primitives:** `mercantis core/UIShell/Components/`
- `UIShell/` is the `MercantisCoreUI` SwiftPM product. `Views/DesignSystem/` is
  Core-app scaffolding only (not exported to Hub) — keep reusable work in
  `UIShell/`.

## Token rules

All colours resolve per appearance via `MercantisTheme.adaptive(light:dark:)` (or
native semantic colours). **No light-only constants.** Required groups:

| Group | Tokens |
|---|---|
| Surfaces | `appBackground`, `sidebarBackground`, `surfaceCard`, `surfaceElevated`, `surfaceMuted` |
| Lines / depth | `hairline`, `border`, `cardShadow` (soft in light, ~0 in dark) |
| Brand | `brandPrimary` (indigo) + `…Hover/Pressed`, `brandPrimarySoft`, `brandPrimaryBorder` |
| Status | `success`, `warning`, `danger`, `info` (small surfaces only) |
| Text | `textPrimary`, `textSecondary`, `textTertiary` |
| Tables | `tableRowHover`, `tableRowSelection`, `tableHeaderBackground` |
| KPI | `kpiPositive`, `kpiNegative`, `kpiNeutral` |

`Color.accentColor` stays the native selection/focus tint; `brandPrimary` is
product identity & primary actions. Saturated colour is for status badges and
KPI deltas only — never large fills.

## Primitives

`MercantisCard`, `MercantisMetricCard`, `MercantisPanelHeader`,
`MercantisInspectorCard` / `MercantisInspectorRow`, `MercantisStatusBadge`,
`MercantisToolbarSearchField`, `MercantisEmptyState`, and the sidebar family
(`MercantisSidebarRow` / `…ModuleHeader` / `…GroupHeader` / `…BrandHeader`).

Each is `public`, has a `#Preview`, and uses tokens (no inline hex). Pure
formatting/classification logic (e.g. `MercantisMetricCard.formatDeltaPercent`,
`Trend(change:)`) is unit-tested in `Tests/MercantisCoreUITests`.

## Do / Don't (design system)

- **Do** prefer the hairline border over shadows; use `cardShadow` for at most
  one shallow layer on genuinely floating surfaces.
- **Do** keep status text + SF Symbol together (never colour alone).
- **Do** use monospaced digits for financial/KPI values.
- **Don't** add custom fonts, light-only colours, heavy shadows/gradients, or
  put reusable components in `Views/DesignSystem/` (Hub can't see them).
