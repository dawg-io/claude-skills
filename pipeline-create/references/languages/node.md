# Node / TypeScript / frontend

## Detect

`package.json`. The package manager comes from the lockfile, not from preference:
`package-lock.json` -> npm, `yarn.lock` -> Yarn, `pnpm-lock.yaml` -> pnpm, `bun.lockb` ->
Bun. A `packageManager` field in `package.json` is authoritative if present.

Read `scripts` in `package.json` - that is the real list of available commands, and it beats
any convention. Frameworks show up in `dependencies`: `next`, `react`, `vue`, `svelte`,
`vite`, `nest`, `express`.

## Healthy looks like

- Exactly one lockfile. Two is a red flag - ask which is authoritative.
- A `test` script that runs something real. A `test` script that is `echo "no tests"` will
  report green forever; treat it as no tests at all.
- `engines.node` in `package.json`, or `.nvmrc`. Without one, the Node version has to be
  asked for.
- Lint config: `eslint.config.js`, `.eslintrc*`, or `biome.json`.

## Commands

| Job | npm | Yarn | pnpm |
|---|---|---|---|
| Install | `npm ci` | `yarn install --immutable` | `pnpm install --frozen-lockfile` |
| Test | `npm test` | `yarn test` | `pnpm test` |
| Lint | `npm run lint` | `yarn lint` | `pnpm lint` |
| Types | `npx tsc --noEmit` | | |
| Build | `npm run build` | `yarn build` | `pnpm build` |

`npm ci` over `npm install` always - it is the reproducible one, and it fails loudly when
the lockfile and manifest disagree, which is exactly what CI should do.

## Setup and caching

```yaml
- uses: actions/setup-node@v4
  with:
    node-version: ${{ matrix.node }}
    cache: npm        # or yarn / pnpm
```

pnpm needs `pnpm/action-setup` before `setup-node`, or the cache resolution fails.

## Artifacts

| Artifact | When | Registry |
|---|---|---|
| **Container image** | a server, or a frontend served by nginx | GHCR |
| **Static bundle** (`dist/`, `build/`, `.next/`) | a SPA or static site | uploaded as an artifact, then deployed to Pages / S3 / a CDN |
| **npm package** | a library | npm registry, or GitHub Packages |

A frontend produces a static bundle *and* possibly an image wrapping it. Ask which is the
deployable - it changes the whole deploy job.

## Tagging

npm versions are semver, strictly - the registry enforces it. Prereleases are
`1.4.0-rc.1`, which npm treats as not-`latest` unless tagged so explicitly.

The version lives in `package.json`. If releases are cut by git tag, something has to keep
the two in sync - ask which is the source of truth.

## Notes

- **Publishing to npm should use provenance and a granular token**, or OIDC trusted
  publishing where available. `npm publish --provenance` needs `id-token: write`.
- A frontend build often needs build-time environment variables baked in (`VITE_*`,
  `NEXT_PUBLIC_*`). These end up in the shipped bundle and are therefore **public** - never
  put a secret in one. Ask which are needed and say plainly that they are not secret.
- Monorepos with workspaces: the workspace tool already handles the fan-out. Use
  `npm run build --workspaces` rather than a matrix over packages.
- Playwright and Cypress need browsers installed - `npx playwright install --with-deps`,
  which is slow and worth caching or running in the official container image.
