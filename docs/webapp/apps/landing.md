# landing

**Workspace:** `@metalex-web/landing` · **Type:** Next.js

The MetaLeX marketing landing site. It is a standard Next.js app in the
monorepo, sharing the [design system](../design-system.md) with the other
apps.

## Run it

```bash
bun dev:landing
```

## Notes

* Uses typed routing (`_next-typesafe-url_.d.ts` is present).
* Content/marketing-focused: it does not carry protocol logic and has no
  database package.
* Shares Tailwind configuration and design-system components with the rest
  of the monorepo.

> For page structure, browse `apps/landing/src` in the repository.
