# Mercantis Core — UX Direction & Native macOS Design Strategy

_Last updated: 2026-05-04_

## 1. Purpose

Mercantis Core owns the reusable UX foundations for the Mercantis ecosystem. Its responsibility is not to encode ERP domain behavior, but to provide the native macOS UI platform that host applications can configure and extend.

Core UX foundations include:

- the application shell and navigation model;
- metadata-driven forms and lists;
- record collection workspaces;
- dashboards and reports;
- command bar and quick-create flows;
- inspector surfaces;
- design tokens, semantic tones, spacing, typography, and materials;
- Visual Builder infrastructure for DocTypes and future workspace/report/dashboard composition.

This document defines the UX direction for those reusable foundations. It is intentionally documentation-first: it guides future implementation and should not be read as a request to rewrite the UI in one large pass.

## 2. Design Principle

> Mercantis should feel like a native macOS business platform, not a web ERP embedded in SwiftUI.

The product should follow native macOS structure and interaction patterns while building a stronger, more memorable product character. The target feel is closer to Finder + Mail + Numbers + Xcode than to a browser dashboard:

- **Finder:** clear navigation, view modes, sidebar/list/detail structure, predictable selection behavior.
- **Mail:** fast list/detail productivity, recents, search, and efficient triage flows.
- **Numbers:** clean tables, document presentation, lightweight visual polish without sacrificing readability.
- **Xcode:** inspector-led editing, builder tools, command/navigation efficiency, and professional power-user workflows.

The UI should be elegant and productive first. Visual distinction should come from hierarchy, spacing, materials, semantic color, and polished states — not from heavy decoration.

## 3. Current UX Assets in Core

Core already has strong native macOS foundations:

| Asset | Current role |
|---|---|
| `mercantis core/UIShell/NavigationShell.swift` | Production shell using `NavigationSplitView`, sidebar navigation, command bar, recents, reports, dashboards, inspector, and quick create flows. |
| `mercantis core/UIShell/RecordCollectionHostView.swift` | Record workspace container with list, browse, and detail view modes plus persisted view mode preference. |
| `mercantis core/UIShell/MercantisTheme.swift` | Current semantic tone and styling layer: cards, badges, primary/secondary/destructive buttons, sidebar selection, input styling, and basic typography tokens. |
| `mercantis core/Views/DesignSystem/LiquidGlassShellView.swift` | DEBUG/design-lab surface with richer visual patterns — native tables, section cards, status badges, filter chips, builder canvas treatments, and inspector examples — that should be harvested into production components selectively. |

The design-lab surface is useful as a source of patterns, not as a shell to copy wholesale.

## 4. Main UX Diagnosis

Core is structurally native and promising. The weakness is not architecture; the weakness is visual hierarchy and product character.

The current shell already uses the right native building blocks, but future work should make the UI more memorable and easier to scan through:

- stronger workspace headers;
- subtle materials and surface layering;
- semantic module tones;
- better form grouping;
- richer dashboard and report presentation;
- more intentional empty, loading, error, validation, and save states;
- production-grade builder workflows.

The goal is not to make Core louder. The goal is to make Core clearer, more polished, and more obviously suited to complex business work.

## 5. Recommended Core UX Direction

### 5.1 Promote selected `LiquidGlassShellView` ideas into production

Do not copy the whole demo shell blindly. Extract reusable parts that strengthen the existing production shell:

- `WorkspaceHeroHeader`
- `SectionCard`
- `MetricCard`
- `StatusBadge`
- `FilterChipRow`
- `ActionCard`
- `InspectorPane`
- Builder canvas visual patterns

A possible future structure is:

```text
mercantis core/UIShell/
├── DesignTokens/
│   ├── MercantisTheme.swift
│   ├── MercantisSpacing.swift
│   ├── MercantisTypography.swift
│   └── MercantisMaterials.swift
├── Components/
│   ├── WorkspaceHeroHeader.swift
│   ├── MetricCard.swift
│   ├── SectionCard.swift
│   ├── StatusBadge.swift
│   ├── FilterChipRow.swift
│   ├── CommandBarView.swift
│   └── InspectorPane.swift
└── Shell/
    ├── NavigationShell.swift
    ├── RecordCollectionHostView.swift
    └── WorkspaceDashboardView.swift
```

This is a proposed direction, not an immediate required refactor. Component extraction should happen incrementally when production screens need the components.

### 5.2 Add workspace hero headers

Every DocType, report, dashboard, module, and builder screen should eventually have a compact workspace header with:

- icon;
- title;
- subtitle;
- badges;
- primary action;
- record count or status text.

Example visual layout:

```text
[Customer icon] Customers
Manage customer records, contacts, addresses and CRM activity

[124 records] [CRM] [Last updated today]                    [+ New Customer]
```

Headers should be compact enough for business workflows and should not become oversized marketing banners. They should clarify where the user is, what the workspace does, and what the primary action is.

### 5.3 Improve record collection views

`RecordCollectionHostView` already provides the right workspace abstraction. Future polish should focus on the quality of each mode:

- use macOS `Table` for list mode where appropriate;
- treat browse mode as list + detail preview;
- give detail mode a header, grouped sections, metadata, and save status;
- improve empty states using `ContentUnavailableView`;
- add inline validation summary near save actions;
- show save confirmation and conflict/sync status when available;
- preserve view mode preference as the current implementation already does.

List mode should be dense, sortable, and keyboard-friendly. Browse/detail modes should make selection and editing feel native rather than form-only.

### 5.4 Improve metadata-driven forms

Metadata-driven forms will always feel flat unless Core supports layout semantics. Add layout metadata or form layout definitions for:

- sections;
- columns;
- field groups;
- help text;
- icons;
- read-only/system sections.

This does not require making DocTypes visual-design-specific. A lightweight layout layer can describe business meaning and grouping while Core renders it through native SwiftUI controls.

Recommended distinction:

| Metadata kind | Purpose |
|---|---|
| Field metadata | What data exists and how it validates. |
| Form layout metadata | How fields are grouped, ordered, explained, and prioritized. |
| Runtime state | What is editable, invalid, saving, synced, or read-only right now. |

Without grouping, even correct metadata-driven forms will feel like scaffolding.

### 5.5 Add dashboard and report renderers

Core should provide reusable dashboard and report renderers so host apps do not create one-off UI for common platform concepts.

Recommended components:

- `GenericDashboardView`
- `GenericReportView`
- native `Table` renderer for report rows
- metric cards
- filter chips
- empty/loading/error states

Report and dashboard rendering should stay declarative: Hub and other apps provide definitions and data sources; Core provides the native presentation.

### 5.6 Make Visual Builder a first-class macOS window

The Visual Builder should evolve as a production-grade macOS tool, not a modal form sequence.

Recommended direction:

- separate window;
- sidebar or palette;
- central canvas;
- inspector;
- toolbar actions for Save, Preview, Validate, and Publish;
- minimal modal editing;
- visible validation and publish readiness;
- preview modes for form, list, dashboard, and report layouts over time.

The right metaphor is closer to Xcode or Numbers than a web admin wizard.

### 5.7 Strengthen design tokens

`MercantisTheme` should expand from a compact style helper into a clearer design token layer:

- spacing;
- typography;
- materials;
- semantic tones;
- domain/module tones.

Color should be subtle and semantic, not decorative. Recommended uses include badge fills, icon backgrounds, selected indicators, dashboard accents, and validation states. Avoid using domain color as a full-screen or fully colored sidebar treatment.

## 6. macOS Best Practice Guardrails

Use native macOS and SwiftUI conventions wherever they fit:

- `NavigationSplitView`
- `Table`
- `Inspector`
- native toolbar placements
- `ContentUnavailableView`
- `Menu`
- `Picker`
- `DisclosureGroup`
- SF Symbols
- system accent color
- system materials

Avoid patterns that make Mercantis feel like a web dashboard port:

- web-dashboard layout conventions;
- heavy gradients;
- custom title bars unless necessary;
- excessive saturated color;
- modal-heavy builder workflows;
- color-only status indication;
- overusing cards everywhere.

Cards are useful for grouping, dashboards, and summaries. They should not replace every native list, table, form section, or inspector surface.

## 7. Suggested Core UX Roadmap

### Phase UX-1 — Documentation and design tokens

- Create this UX direction doc.
- Add architecture and roadmap links.
- Define the design token direction.

### Phase UX-2 — Component extraction

- Extract selected design-lab components from `LiquidGlassShellView`.
- Introduce reusable workspace headers, status badges, cards, and metric cards.
- Keep extraction incremental and production-led.

### Phase UX-3 — Record/form polish

- Native table list view.
- Grouped form rendering.
- Inline validation and save status.
- Improved browse/detail mode.

### Phase UX-4 — Dashboard/report renderers

- Add `GenericDashboardView`.
- Add `GenericReportView`.
- Standardize loading, empty, error, and no-results states.

### Phase UX-5 — Visual Builder productionisation

- Separate window.
- Palette/canvas/inspector.
- Preview/validate/publish workflow.
- Builder-specific empty, invalid, and publish-ready states.

## 8. Non-goals

- Do not make Core ERP-domain-specific.
- Do not force Hub's exact navigation into Core.
- Do not replace native macOS controls with custom web-like controls.
- Do not implement a large UI rewrite in one pass.
- Do not copy the design-lab shell wholesale into production.
- Do not claim recommended dashboard/report/builder features are shipped until they are implemented.

Core should remain a reusable platform layer: native, metadata-driven, domain-agnostic, and suitable for sophisticated business applications.