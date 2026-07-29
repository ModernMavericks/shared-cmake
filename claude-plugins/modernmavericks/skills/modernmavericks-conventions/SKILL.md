---
name: modernmavericks-conventions
description: Use when creating or modifying a ModernMavericks (mavericks-*) project — its release workflow, Renovate/automerge config, versioning, shared-cmake usage, or Sparkle updater — or when deciding whether a deviation from the family conventions is warranted.
---

# ModernMavericks project conventions

ModernMavericks repos (`mavericks-*`) each cross-build one upstream thing into a **Mac OS X 10.9
(Mavericks)**-compatible `.pkg` with a **Sparkle** auto-updater, on a modern Apple-Silicon runner,
with **no 10.9 build runner anywhere**. They share a CMake/Renovate helper (`ModernMavericks/shared-cmake`)
and a common release/versioning shape. This skill is the family's conventions plus the judgment calls
that copying one repo can't teach.

**Core rule: match the family unless the upstream or product genuinely differs — and when you deviate,
say so in a comment or PR describing why.** A silent deviation reads as a mistake; a documented one reads
as a decision.

## Canonical templates (copy these, not the others)

The family has an older/simpler variant and a current/mature variant. **Start from the mature one.**

| Copy from | For | Notes |
|---|---|---|
| **mavericks-golang** | the whole modern shape: `UPSTREAM_VERSION` + `build/version.sh`, green-gated `release.yml`, `renovate.json` | most complete reference |
| **mavericks-legacysupport** | the `version.sh`/`lib.sh`/`release-notes-file.sh` scripts verbatim | origin of the auto-cut pattern |
| swift-toolchain, swift-runtime | the **tag-only-publish** release model (see below) | when you don't auto-cut on main |

Older repos (`ed25519` on `@v4` actions + deprecated `fileMatch`; the pre-green-gate workflows) are being
brought forward — don't copy their lag.

## shared-cmake: consume, never vendor

- Install via its **action**: `uses: ModernMavericks/shared-cmake/.github/actions/install@v1`. It
  self-registers in the CMake user package registry; consume it downstream with `find_package` — **no
  `CMAKE_PREFIX_PATH`, no vendored copy, no hand-run `cmake --install`.**
- `@v1` is the **moving major tag**; Renovate's native github-actions manager tracks it — **no custom
  manager, no SHA pin, no marker comment** for it.
- Resolve its scripts dir at runtime from the registry:
  `SH="$(cat "$HOME/.cmake/packages/MavericksSharedCMake/"* | head -1)/scripts"`.
- Reuse a sibling checkout of shared-cmake locally; don't duplicate its logic.

## Renovate & automerge

Consumer `renovate.json` is `{"$schema", "extends": ["github>ModernMavericks/shared-cmake"]}` plus
your upstream manager and rules. The shared preset provides `config:recommended` + `automerge: true`.

**The `ignoreTests` policy (load-bearing):** the preset now defaults **`ignoreTests: false`** — automerge
waits for a green build. That only works if **your repo produces a CI status check on Renovate PRs**:

- Give `release.yml` a `pull_request: branches: [main]` trigger (or `push: branches: ['**']`) so the
  build runs on the bump PR. This is what Renovate's automerge waits on.
- A repo with **no build to gate** must set `ignoreTests: true` locally (opt back into blind automerge)
  — this is the one legitimate use; shared-cmake itself does it.
- Setting `ignoreTests: false` explicitly in a consumer is redundant with the default but harmless
  (defense-in-depth); fine to keep or omit.

**Rules** — automate patch, gate minor/major on a human:

```json
"customManagers": [{
  "customType": "regex",
  "managerFilePatterns": ["/^UPSTREAM_VERSION$/"],
  "matchStrings": ["^(?<currentValue>.+?)\\s*$"],
  "depNameTemplate": "acme/foo",
  "datasourceTemplate": "github-tags",
  "extractVersionTemplate": "^v(?<version>.+)$"
}],
"packageRules": [
  {"matchDepNames": ["acme/foo"], "matchUpdateTypes": ["patch"], "automerge": true},
  {"matchDepNames": ["acme/foo"], "matchUpdateTypes": ["minor","major"], "automerge": false}
]
```

- Use **`managerFilePatterns`** (regex-delimited `"/^UPSTREAM_VERSION$/"`), not the deprecated `fileMatch`.
- Pick the datasource for how upstream ships: `github-tags` (+`extractVersionTemplate` to strip `v`),
  `golang-version`, `git-refs`/`currentDigest` for a raw commit, etc.
- Track the pin in a dedicated bare file (`UPSTREAM_VERSION` = `1.4.2`) matched whole-file, **or** an
  inline value carrying a marker comment (`… # mavericks-legacysupport`) when it lives in a shared file.

## Versioning

- **`UPSTREAM_VERSION`** — committed, bare (`1.4.2`, no `v`), Renovate-edits it. Read by `build/lib.sh`'s
  `upstream_version()`.
- **`VERSION`** — `<upstream>-mavericks.N`, **gitignored (`/VERSION`) and written by the workflow** (the
  `ver` step) or a local test. Read by CMake (`file(STRINGS VERSION …)`). Don't commit it.
- **`build/version.sh <auto|local>`** computes the full version + release decision (copy verbatim):
  `auto` → N=1/`RELEASE=yes` for a new upstream (no tag yet), else current N/`RELEASE=no`;
  `local` → N=max+1/`RELEASE=yes` (a packaging-only repackage). N resets to 1 whenever `UPSTREAM_VERSION`
  changes. Emits `FULL=`/`TAG=`/`RELEASE=` lines.
- Scripts derive `REPO_ROOT` themselves and source `lib.sh`; `versions.sh` reads `GO_VERSION`-equivalent
  from `UPSTREAM_VERSION` and falls back to `version.sh auto` when `VERSION` is absent (so a fresh checkout
  builds without a committed `VERSION`).
- **A test that encodes the upstream version MUST read it from `UPSTREAM_VERSION`, never hardcode** — a
  hardcoded version fails its own CI on the next Renovate bump and blocks the automerge.

## Release workflow

Two release models — **pick by how you publish**:

- **Auto-cut on main** (golang, legacysupport, ed25519): a push to `main` with a not-yet-released upstream
  cuts `<upstream>-mavericks.1` automatically. Publish decision lives in the build job via
  `steps.ver.outputs.release`. Use this when Renovate merging the bump should *itself* release.
- **Tag-only publish** (swift-toolchain, container-tools, magic-trackpad2): build+gate on every push/PR,
  but publish only on an explicit tag (separate `publish` job `if: github.ref_type == 'tag'`). Use this
  when a human decides when to cut, or the build is too heavy/risky to auto-release.

**Shared shape (both models):**

- Three entry points: `push: branches:[main] + tags:['*-mavericks.*']`, `pull_request: branches:[main]`
  (the automerge gate), `workflow_dispatch` with a `local_release` boolean (repackage escape hatch).
- `checkout` with `fetch-depth: 0` (version.sh counts tags).
- A **`ver` step** (id `ver`) that: on a tag, takes `full=tag=$GITHUB_REF_NAME`, `rel=yes`; else runs
  `version.sh auto|local`, then **forces `rel=no` when `$GITHUB_REF_NAME != main`** (so PRs and non-main
  branches never publish); writes `VERSION`; sets outputs `full`/`tag`/`release`.
- **`gh release create "$TAG" dist/* …` mints the tag itself** — no `git tag`/push, **no PAT**. A
  `GITHUB_TOKEN`-created tag can't retrigger the workflow, so no second-hop/loop. (Don't reach for
  `softprops/action-gh-release` + a PAT; `gh release create` is the family way.)
- **`concurrency: cancel-in-progress: false`** whenever you auto-cut on main — a superseding push must not
  cancel an in-flight `gh release create`. (Tag-only-publish repos can use `true`; their publish ref is
  unique.)
- Sign/appcast and publish steps gate on `steps.ver.outputs.release == 'yes'`. Fork PRs never touch
  `SPARKLE_PRIVATE_KEY` (they resolve `release=no`).
- Runner `macos-26` (fallback `macos-15`); `actions/*@v7` on new repos.

## Release notes

- One committed file per release: `release-notes/<full-version>.md` (becomes the Sparkle appcast
  `<description>` and the GitHub Release body). A `release-notes/README.md` documents the convention.
- Missing note → the GitHub Release uses `gh release create … --generate-notes`; the appcast needs a
  **guaranteed non-empty** file, so use `build/release-notes-file.sh <TAG> <FULL>` which returns the
  committed note or generates a minimal default to a temp file (the appcast generator rejects empty notes).

## Verifying the fetched upstream (deviation axis)

Upstream source is **fetched by tag at build time, not vendored**. How you verify it depends on what
upstream publishes — pick the strongest available and note the choice:

| Upstream publishes… | Verify by | Example |
|---|---|---|
| a checksum feed/file | fetch that checksum, verify the download against it (frozen by the pinned version) | golang → go.dev `?mode=json` SHA256 |
| signed artifacts | signature/identity (verifies a version that doesn't exist yet) | swift-toolchain → Apple installer signer |
| only a git tag | the pinned tag itself (TOFU via `UPSTREAM_VERSION`); no in-repo hash | legacysupport → GitHub tag tarball |

Record the resulting digest in `SHA256SUMS` for the record even when the gate is a signature. **Don't
invent a hand-maintained pinned hash when upstream already publishes one** — that's a divergence to avoid.

## Sparkle updater

- Every product ships a Sparkle updater `.app` that **must not link the product it updates** (self-update
  circularity — assert with `otool -L`). EdDSA-signed; private key is the `SPARKLE_PRIVATE_KEY` secret.
- `mavericks_add_updater_app()` self-fetches the Sparkle framework at configure time; signing/appcast use
  the shared `sign_and_appcast.sh` (fetches `ed25519-sign` via `gh` → needs `GH_TOKEN`).

## New-project checklist

1. `renovate.json`: extend shared-cmake; add the upstream `customManager` + patch/minor rules; ensure a
   PR check exists (or set `ignoreTests: true` if no build).
2. `UPSTREAM_VERSION` (bare); `/VERSION` in `.gitignore`.
3. `build/lib.sh` (`upstream_version()`), `build/version.sh`, `build/release-notes-file.sh` — copy from
   legacysupport/golang.
4. `release.yml`: pick a release model; three triggers; `ver` step with the non-main guard; `gh release
   create`; `cancel-in-progress: false` if auto-cutting.
5. `release-notes/README.md`; Sparkle updater target; `SPARKLE_PRIVATE_KEY` secret.
6. Choose the upstream-verification method; note it if it deviates from a sibling.
7. Check in `.claude/settings.json` pointing at the `modernmavericks` marketplace (hosted in
   `mavericks-shared-cmake`) so contributors' agents load these conventions — do NOT copy the SKILL.md:
   ```json
   {"extraKnownMarketplaces": {"modernmavericks": {"source": {"source": "github", "repo": "ModernMavericks/shared-cmake"}}},
    "enabledPlugins": {"modernmavericks@modernmavericks": true}}
   ```

## Common mistakes

- Hardcoding the upstream version in a test → self-blocks the next Renovate automerge.
- `ignoreTests: false` (default) but no PR check → automerge **stalls forever**. Add the `pull_request`
  gate or set `ignoreTests: true`.
- Auto-cutting on main with `cancel-in-progress: true` → a rapid second push cancels the release mid-flight.
- Adding a PR trigger without the `rel=no unless main` guard → a PR build tries to publish.
- Committing `VERSION`, or building assuming it exists → it's gitignored/workflow-written.
- Reaching for a PAT to create the release tag → `gh release create` mints it under `GITHUB_TOKEN`.
- Vendoring shared-cmake or pinning its action to a SHA → consume `@v1` via the install action.
