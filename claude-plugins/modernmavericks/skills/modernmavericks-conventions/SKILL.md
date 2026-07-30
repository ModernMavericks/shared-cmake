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

## shared-cmake: consume its facilities, never hand-roll them

- Install via its **action**: `uses: ModernMavericks/shared-cmake/.github/actions/install@v1`. It
  self-registers in the CMake user package registry; consume it downstream with `find_package` — **no
  `CMAKE_PREFIX_PATH`, no vendored copy, no hand-run `cmake --install`.**
- `@v1` is the **moving major tag**; Renovate's native github-actions manager tracks it — **no custom
  manager, no SHA pin, no marker comment** for it.
- Resolve its scripts dir at runtime from the registry:
  `SH="$(cat "$HOME/.cmake/packages/MavericksSharedCMake/"* | head -1)/scripts"`.
- Reuse a sibling checkout of shared-cmake locally; don't duplicate its logic.

**Use its facilities for 10.9-correctness — do NOT reinvent SDK fetching, floors, build-mode handling,
updaters, signing, or compat checks:**

| Facility (CMake fn · script) | Does | Don't hand-roll |
|---|---|---|
| `mavericks_build_mode` · `MavericksMode` · `mavericks_mode.sh` | selects/asserts the build MODE: native-on-10.9 vs cross-on-modern | arch/host detection |
| `mavericks_fetch_sdk` · `fetch_sdk.sh` | the pinned, integrity-checked MacOSX10.9 SDK | fetching an SDK yourself |
| `RequireAppleClang` | enforces Apple `/usr/bin/clang` (cgo/ObjC) | assuming the toolchain |
| `mavericks_assert_binary_compatible` · `MavericksCompatGuard` · `assert_binary_compatible.sh` | proves a built binary is 10.9-safe (floor + symbol set) | a bespoke compat check |
| `mavericks_add_updater_app` · `MavericksSparkle` · `stage_updater.sh` | builds/stages the Sparkle updater (self-fetches the framework) | wiring Sparkle by hand |
| `set_install_floor.sh` | stamps the 10.9.5 install floor on the `.pkg` | editing the pkg Distribution |
| `sign_and_appcast.sh` · `gen_appcast.sh` | EdDSA-signs + renders the appcast (fetches `ed25519-sign` via `gh`) | rolling your own signing |
| `mavericks_fetch` · `mavericks_locate` | fetch / locate helpers | ad-hoc `curl` / paths |

## Build equivalence: native-10.9 ≡ modern-cross (core invariant)

The product must run on **10.9**, but **there is no 10.9 build runner in CI** — every project cross-builds
on a modern Mac. So each project MUST establish that its cross-build equals a native-10.9 build, via
shared-cmake's facilities rather than trusting the runner:

- Drive the build through the **mode** machinery (`mavericks_build_mode`) so native and cross are the same
  recipe against the same pinned 10.9 SDK and floor — not two divergent paths.
- **Gate on the compat guard** (`mavericks_assert_binary_compatible`): fail the build if any shipped binary
  declares a floor above 10.9 or links a symbol 10.9 lacks. This is the in-CI equivalence proof — every
  project needs it (or an equivalent gate), since no 10.9 runner validates the output.
- Where a stronger proof fits, keep a **characterization reference**: commit a trusted native-10.9 artifact
  and compare the cross-build against it (magic-trackpad2's kext characterization), and/or an emulated
  smoke (golang's best-effort Rosetta self-test).
- Back it with **out-of-band re-validation on real 10.9 hardware** before trusting a release.

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
- **For a green-gated PR to merge *promptly*, native auto-merge needs BOTH** (either alone is inert):
  1. the repo's **"Allow auto-merge"** enabled — off by GitHub default:
     `gh api -X PATCH repos/OWNER/REPO -f allow_auto_merge=true`; and
  2. **branch protection on `main` requiring the PR build check** — GitHub only *arms* auto-merge when a
     required check is pending. Set `strict:false` (no forced rebases) + `enforce_admins:false`
     (maintainers keep direct-push):
     ```sh
     printf '{"required_status_checks":{"strict":false,"contexts":["build"]},"enforce_admins":false,"required_pull_request_reviews":null,"restrictions":null}' \
       | gh api -X PUT repos/OWNER/REPO/branches/main/protection --input -
     ```
  The context is the build **job name** (`build`, `build-macos`, or a job's `name:` string like
  `Cross-build + compat gate (macos-26)`) — read the exact string from a real check-run first
  (`gh api repos/OWNER/REPO/commits/main/check-runs --jq '[.check_runs[].name]|unique'`); a typo requires a
  check that never reports and **blocks every merge**. Without the required check, `allow_auto_merge` is
  inert and the PR merges only on Renovate's next scan (still gated, just not instant).

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

**This customManager is the release trigger** — it's how the package auto-updates when upstream does:
Renovate bumps the pin → the green-gated build merges → the workflow cuts the release. Author it to fit how
upstream publishes; if no standard datasource fits (a versioned download URL, a components file), write a
custom regex manager + the closest datasource (`git-refs`, a `custom.regex` match) — container-tools tracks
a `components/*/version` file this way. **GitHub Actions pins** (`uses: …@vN`, including `shared-cmake/…@v1`)
need no custom config: Renovate's built-in github-actions manager updates them through the same green-gate +
patch-automerge — that's the intended auto-update for the workflow's actions.

## Versioning

**Two independent bump axes.** The **upstream component** moves when upstream releases: Renovate edits
`UPSTREAM_VERSION`, and `version.sh auto` cuts `<new>-mavericks.1` (N resets to 1). The **`-mavericks.N`
suffix** moves for a packaging-only re-release (recipe/patch/updater/CA change, upstream unchanged): via
`workflow_dispatch local_release=true`, which cuts N+1. Never hand-edit `VERSION` for either — it's computed.

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

## Consuming a ModernMavericks toolchain + auto-propagation

A repo built WITH another MM product (e.g. the go126 toolchain) pins it in a **file** (not workflow env),
e.g. `components/golang/version`, tracked by a Renovate customManager (`github-releases` on
`ModernMavericks/golang`). Renovate bumps the pin; the green-gated build rebuilds the product with the new
toolchain and automerges. Two things to wire deliberately:

- **Download the toolchain asset prefix-tolerantly.** golang's cross `.pkg` was renamed `go126-` →
  `golang-` at 1.26.5-mavericks.1. Read the pinned release's `SHA256SUMS` and accept EITHER prefix (try
  `golang-…`, fall back to `go126-…`) so a pin bump across the rename never 404s.
- **Auto-propagation via the shared reusable workflow (dispatch, NOT tag).** A toolchain bump alone does
  NOT auto-cut a consumer release: the consumer's own auto-cut is driven by ITS upstream (N=1), not a
  dependency. To ship the rebuilt product automatically, add a ~10-line caller:
  ```yaml
  on: { push: { branches: [main], paths: [ <ingredient pin files, e.g. components/golang/version> ] } }
  jobs:
    repackage:
      permissions: { actions: write }   # dispatch release.yml — reusable perms can't be elevated by the callee
      uses: ModernMavericks/shared-cmake/.github/workflows/repackage-on-ingredient-bump.yml@v1
      with: { own-upstream-paths: <path(s) meaning a NEW own upstream → N=1, excluded; omit if none> }
  ```
  The reusable workflow decides "ingredient changed and not the own upstream?" and, if so, **dispatches**
  the consumer's `release.yml` via `gh workflow run … -f local_release=true`. It does NOT push a tag: a
  `GITHUB_TOKEN`-pushed tag can't trigger `release.yml` (GitHub's recursion guard), whereas
  `workflow_dispatch` IS `GITHUB_TOKEN`-triggerable. So the consumer's `release.yml` needs a
  `workflow_dispatch` `local_release` input that computes `-mavericks.(N+1)` and **publishes inline** in
  that same run (golang/legacysupport have it via `version.sh local`; tag-only repos must add it — the same
  fix repairs any `release-on-bump.yml` that relies on a pushed tag). CI-only bumps (`.github/**` action
  `uses:`) aren't in the caller's `paths:`, so they never repackage. This automates the `-mavericks.N` axis,
  driven by a dependency instead of a hand-run `local_release`.
- **In a committed-`VERSION` repo, derive the repackage's N from TAGS, not from `VERSION`.** A
  dispatch-cut version is published without being committed back (the tag is minted by
  `action-gh-release` via `tag_name` + `target_commitish`), so reading N from the file recomputes the
  same N+1 on the next ingredient bump and **overwrites that release** instead of cutting the next one.
  Take the highest existing `<upstream>-mavericks.*` tag (needs `fetch-depth: 0`) — idempotent, no
  commit-back. Repos deriving from tags already (`version.sh local`) are fine by construction.
- **Track every trackable ingredient; document the ones you can't.** An ingredient with neither a
  Renovate customManager nor a written reason is a silent staleness hole — the product ships built from
  an input nobody is watching. Give each repo an `INGREDIENTS.md`: every input baked into the artifact,
  where it's pinned, its Renovate status, and what a bump does. Where no clean datasource exists (a
  rolling URL with no version, a moving `@v1` tag), say so and say what compensates — vendoring plus a
  hash pin keeps builds reproducible even when nothing is watching upstream. Don't invent a fragile
  tracker (scraping a download page for a date) just to fill a cell.

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
   PR check exists (or set `ignoreTests: true` if no build). For *prompt* automerge, enable **Allow
   auto-merge** AND add **branch protection requiring the build check** — both are needed (see the
   Renovate section for the exact commands and the typo-blocks-all-merges caveat).
2. `UPSTREAM_VERSION` (bare); `/VERSION` in `.gitignore`.
3. `build/lib.sh` (`upstream_version()`), `build/version.sh`, `build/release-notes-file.sh` — copy from
   legacysupport/golang.
4. `release.yml`: pick a release model; three triggers; `ver` step with the non-main guard; `gh release
   create`; `cancel-in-progress: false` if auto-cutting.
5. `release-notes/README.md`; Sparkle updater target; `SPARKLE_PRIVATE_KEY` secret.
6. Choose the upstream-verification method; note it if it deviates from a sibling.
7. If the repo bakes in build ingredients (anything it's built WITH, not the upstream it ports): make
   each pin a **file**, give each a Renovate customManager, add the `repackage-on-ingredient-bump`
   caller, and record the lot in `INGREDIENTS.md` — including any ingredient you deliberately left
   untracked and why. No file-based ingredient pins → no caller (say that in `INGREDIENTS.md` too).
8. Check in `.claude/settings.json` pointing at the `modernmavericks` marketplace (hosted in
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
