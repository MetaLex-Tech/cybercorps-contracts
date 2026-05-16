# The design system

Shared UI lives in `packages/design-system`. All four Next.js apps
(`cybercorps-web`, `web`, `lexchex-web`, `landing`) consume it so they share
components, tokens, and styling conventions.

## Styling stack

* **Tailwind CSS** — utility-first styling. The repo also uses
  `@tailwindcss/container-queries`.
* **Per-app Tailwind config** — each app has a thin `tailwind.config.ts`
  that extends shared configuration.
* **Biome** — formats and lints (no Prettier/ESLint).

## Conventions (from `AGENTS.md`)

* For UI work, follow the repo's `ui-design-system` agent skill at
  `.agents/skills/ui-design-system/SKILL.md` — it codifies page builds,
  component composition, styling updates, and responsive polish.
* Keep implementations aligned with **existing app patterns** and the shared
  design-system package rather than introducing new primitives.
* **Avoid over-abstraction.** A small, low-reuse component should stay whole.
  Extract subcomponents only when it clearly improves reuse, readability, or
  complexity management.
* Prefer plain function components; import React types directly
  (`ReactNode`); type props inline at the declaration when practical.

## Forms

* Reuse existing form components and patterns.
* Simple forms: local `useState` is fine.
* Larger forms with complex validation, error handling, or workflow logic:
  use [TanStack Form](https://tanstack.com/form).
* In `cybercorps-web` the `forms` feature module holds shared form building
  blocks.

## Markdown rendering

User- and template-facing rich text uses `react-markdown` with `remark-gfm`
(GitHub-flavoured markdown) — relevant for agreement templates and help
content.

## When adding UI

1. Check `packages/design-system` for an existing component.
2. Check the target app's `features/ui` module for an app-level pattern.
3. Only then build something new — and put it at the right level
   (design-system if cross-app, `features/ui` if app-specific).
