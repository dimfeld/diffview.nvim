---
# yaml-language-server: $schema=https://raw.githubusercontent.com/dimfeld/llmutils/main/schema/rmplan-plan-schema.json
title: improve performance
goal: ""
id: 10
uuid: dca45387-91d3-4317-aacc-04ffc5128ec2
generatedBy: agent
status: done
priority: medium
planGeneratedAt: 2026-01-18T18:30:59.573Z
promptsGeneratedAt: 2026-01-18T18:30:59.573Z
createdAt: 2026-01-16T20:45:24.179Z
updatedAt: 2026-01-18T19:08:05.278Z
tasks:
  - title: Add review performance instrumentation
    done: false
    description: Add lightweight profiling around review status computation so we
      can confirm where time is spent (git calls vs Lua loops vs panel render).
      Reuse PerfTimer (lua/diffview/perf.lua) and existing logger patterns.
      Prefer an opt-in flag (e.g. config.review.perf_debug) or high log level
      gating; avoid noisy default output.
  - title: Implement batch blob-hash lookup in GitAdapter
    done: true
    description: 'In lua/diffview/vcs/adapters/git/init.lua, add a helper to resolve
      many file blob hashes in one process (review use-case: rev_arg="HEAD" +
      list of file paths). Prefer stdin-driven batching via utils.job(..., {
      writer = {...} }) (see lua/diffview/utils.lua + lua/diffview/job.lua).
      Chunk large inputs to avoid limits. Return a path->hash|nil map and
      preserve existing semantics for missing paths. Add automated coverage in
      lua/diffview/tests/functional/git_adapter_spec.lua (batch matches per-file
      file_blob_hash(), missing paths handled).'
  - title: Add DiffView review status cache with invalidation
    done: true
    description: In lua/diffview/scene/views/diff/diff_view.lua, introduce a
      per-view cache mapping path->status plus the HEAD commit used to compute
      it. Add invalidate/rebuild helpers, and invalidate on files updates
      (DiffView.update_files), review events (init_review_event_listeners), and
      relevant mode toggles (toggle_review_filter / toggle_since_review_mode).
      Ensure status reads are O(1) after rebuild.
  - title: Use commit_hash short-circuit in status computation
    done: true
    description: When computing status for reviewed files, skip blob-hash lookups if
      ReviewEntry.commit_hash exists and equals the current HEAD commit (treat
      as reviewed). This can live in the cache rebuild path or in
      review.get_file_status if it delegates to DiffView cache helpers. Add
      tests in lua/diffview/tests/functional/review_api_spec.lua that assert
      adapter:file_blob_hash is not called when commit_hash matches, and that
      legacy entries (no commit_hash) still use blob-hash comparison.
  - title: Reduce redundant review status scans in navigation and filtering
    done: true
    description: Refactor the review navigation helpers in
      lua/diffview/scene/views/diff/diff_view.lua to avoid scanning the file
      list multiple times per keypress (ordered_file_list filtering + a second
      pass). Prefer a single pass using cached status reads. When
      review_filter_enabled is active and navigating "pending" files, avoid
      recomputing statuses for files already filtered. Extend existing
      navigation specs or add targeted tests to cover correctness and guard
      against regressions.
  - title: (Optional) Avoid full panel render on pure navigation
    done: false
    description: If profiling shows panel:render/panel:redraw is still a bottleneck
      after caching/batching, reduce work in DiffView._set_file by avoiding full
      file panel re-render when only selection changes. Consider moving
      "selected" highlighting to a dedicated highlight namespace so navigation
      can update highlights without rebuilding render_data. Keep UX identical
      (selection visible even when panel not focused). Add automated coverage
      for selection highlight correctness and ensure review indicators remain
      accurate.
changedFiles:
  - lua/diffview/review.lua
  - lua/diffview/scene/views/diff/diff_view.lua
  - lua/diffview/scene/views/diff/file_panel.lua
  - lua/diffview/tests/functional/git_adapter_spec.lua
  - lua/diffview/tests/functional/review_api_spec.lua
  - lua/diffview/tests/functional/review_filter_spec.lua
  - lua/diffview/tests/functional/review_navigation_spec.lua
  - lua/diffview/tests/functional/since_review_diff_spec.lua
  - lua/diffview/vcs/adapters/git/init.lua
tags: []
---

The new review feature is fairly slow at some points. Need to do some profiling to see if that's related to a lot of Git operations or the JSON handling or just a lot of spawning processes. Then probably batch things where possible to speed it up and make it more responsive.

Specific opportunities observed while navigating review mode (esp. review_next_pending and Tab):
- Avoid per-file `git rev-parse` on every navigation. `review.get_file_status` calls `adapter:file_blob_hash()` for each file, and that maps to `git rev-parse`. This happens in navigation and panel list building.
- Short-circuit for reviewed files using stored `commit_hash`: if current HEAD matches the stored commit hash, the file can be treated as reviewed without resolving the blob hash.
- Cache review status (path -> status) in the view and invalidate on review events, file list updates, or HEAD changes to avoid recomputing statuses on every keypress.
- Batch blob hash fetches for the file list (e.g., `git ls-tree -r HEAD -- <paths>` or `git cat-file --batch`) and reuse results rather than per-file `rev-parse`.
- Reduce panel rendering work on pure navigation: `_set_file` always `panel:render()`/`panel:redraw()`; only highlight updates should be needed when the file list hasn’t changed.

## Research

### Expected Behavior/Outcome

Review mode should feel responsive even on large diffs (hundreds/thousands of files), especially for:
- Navigation commands like `review_next_pending` / `review_prev_pending`.
- Toggling/filtering in the file panel when review filter / since-review is enabled.

There should be no user-facing behavior changes in *what* gets marked `"unreviewed"|"reviewed"|"changed"`; only performance should improve.

#### Relevant States (definitions)

**Per-view feature state**
- **Review disabled**: `config.review.enabled=false` → `review.get_file_status()` returns `nil` and file panel should not show review indicators.
- **Review enabled but not active for this view**: `view.review_state=nil` (e.g. non-git adapter / view didn’t load review state) → `review.get_file_status()` returns `nil`.
- **Review enabled and active**: `view.review_state` exists (only for Git views today) → review status is computed.

**Per-file review status**
- **`"unreviewed"`**: no entry exists in `ReviewState.files[path]`.
- **`"reviewed"`**:
  - entry exists and current HEAD blob hash matches `entry.blob_hash`, OR
  - current HEAD blob hash is unavailable (`nil`), which `ReviewState:get_file_status()` treats as reviewed today (keep semantics), OR
  - (new optimization) entry has `commit_hash` and it equals the current HEAD commit.
- **`"changed"`**: entry exists and current HEAD blob hash differs from `entry.blob_hash`.

**Cache state (new, internal)**
- **Valid cache**: status map was computed for a specific HEAD commit and specific file list generation.
- **Invalid cache**: needs recomputation due to review events, file list updates, or detected HEAD changes.

### Key Findings

#### Product & User Story
- Review mode currently “feels slow” during common workflows (navigating pending files, using panel filter). The pain is interaction latency, not correctness.
- The intent of review state is stable: compare stored reviewed content (blob hash) vs current HEAD’s blob hash to detect `"changed"`.
- `commit_hash` is already stored in review entries and is a strong optimization opportunity when HEAD hasn’t moved since review.

#### Design & UX Approach
- Primary goal: reduce lag spikes on keypress.
- Keep UI output identical (same indicators/counts) while improving performance.
- Prefer caching and batching over incremental micro-optimizations first; then address panel rendering if still a hotspot.

#### Technical Plan & Risks
- **Main hotspot**: repeated spawning of `git rev-parse` processes through `adapter:file_blob_hash()` during navigation and panel rendering.
- **Risk (staleness)**: if HEAD changes while a view is open, a cached status map could become stale. Mitigate by:
  - recomputing on known triggers (`files_updated`, review events), and
  - optionally re-checking HEAD at a low frequency when status is requested (rate-limited).
- **Risk (batch command correctness)**: batch hash queries must preserve current behavior for missing paths, odd filenames, and index-style revspecs (`:path`).
- **Risk (over-caching)**: cached statuses must be invalidated when review state changes (mark/clear/all clear) and when file list changes.

#### Pragmatic Effort Estimate
- **Likely win**: large (order-of-magnitude reduction in git process spawns during navigation).
- **Engineering effort**: medium (touches git adapter, review status logic, and view/panel integration).
- **Test effort**: medium (add unit-ish functional tests around call counts / bypass paths).

### What I inspected in the codebase (hot paths & patterns)

#### Review status computation
- `lua/diffview/review.lua`
  - `review.get_file_status(view, file_entry)` always calls `view.adapter:file_blob_hash(file_entry.path, "HEAD")`.
  - `get_head_commit_hash()` exists (via `adapter:head_rev()`), but is only used when *marking* reviewed files — not when *checking* status.
- `lua/diffview/review_store.lua`
  - `ReviewEntry` includes optional `commit_hash` (already stored/serialized for backward compatibility).
  - `ReviewState:get_file_status(path, current_blob_hash)` is pure/fast; the expensive part is fetching `current_blob_hash`.

#### Git adapter cost center
- `lua/diffview/vcs/adapters/git/init.lua`
  - `GitAdapter:file_blob_hash(path, rev_arg)` runs `git rev-parse --revs-only <rev:path>` via `exec_sync()` (spawns a process per call).
  - `GitAdapter:head_rev()` is also a `git rev-parse HEAD` call — expensive but acceptable if called once per interaction, not per file.
- `lua/diffview/utils.lua` + `lua/diffview/job.lua`
  - `utils.job()` supports `writer` (stdin), enabling batch git commands without spawning per-file processes.

#### Where status checks happen a lot
- `lua/diffview/scene/views/diff/diff_view.lua`
  - Navigation helpers (`:_navigate_review_file*`) build lists by calling `review.get_file_status(self, file)` for each file on every navigation keypress.
  - `_set_file` currently calls `self.panel:render(); self.panel:redraw(); vim.cmd("redraw")` on every file open, even on simple navigation.
- `lua/diffview/scene/views/diff/file_panel.lua`
  - `FilePanel:should_show_file()` calls `review.get_file_status()` for filtering.
  - `FilePanel:update_components()` may call `should_show_file()` for every file when filter enabled.
- `lua/diffview/scene/views/diff/render.lua`
  - Panel render uses `review.get_file_status()` in several loops (review indicator per file, pending counts, visible counts).

#### Existing performance instrumentation
- `lua/diffview/perf.lua` provides a `PerfTimer` used in a few places (e.g. `DiffView.update_files`, `Panel:redraw`).
  - This can be reused to add targeted instrumentation around review status computation and git batch calls without introducing new dependencies.

### Files likely to change (implementation scope)
- `lua/diffview/review.lua` (status logic, entry short-circuit, caching entrypoint)
- `lua/diffview/scene/views/diff/diff_view.lua` (view-level cache storage + invalidation, navigation loops, `_set_file` panel work)
- `lua/diffview/scene/views/diff/file_panel.lua` (optional: avoid redundant status checks when filter enabled; selection highlight work if done here)
- `lua/diffview/scene/views/diff/render.lua` (optional: avoid redundant loops / integrate cached pending counts)
- `lua/diffview/vcs/adapters/git/init.lua` (batch blob hash retrieval helper)
- Tests:
  - `lua/diffview/tests/functional/review_api_spec.lua` (add bypass/caching tests)
  - `lua/diffview/tests/functional/git_adapter_spec.lua` (add batch helper tests)
  - possibly new/extended specs for navigation/panel behavior if needed

### Acceptance Criteria
- [ ] Functional: Navigating in review mode (`review_next_pending` / `review_prev_pending`) no longer triggers per-file git processes; the commands stay responsive on large file lists.
- [ ] UX: Review indicator symbols and filter counts remain correct and update immediately when marking/clearing review state.
- [ ] Technical: `adapter:head_rev()` and `adapter:file_blob_hash()` are not called O(N) times per navigation keypress; status computation is cached and/or batched.
- [ ] Tests: All new code paths (batch hash retrieval, cache invalidation, commit-hash bypass) are covered by automated tests.

Note: reducing file panel render/redraw work on pure navigation is explicitly **optional** for this plan; only do it if profiling shows it’s still a hotspot after caching/batching.

### Dependencies & Constraints
- **Dependencies**
  - Relies on existing `GitAdapter` (`lua/diffview/vcs/adapters/git/init.lua`) and `utils.job(..., { writer = ... })` support for stdin-driven batch commands.
  - Review feature is currently guarded to Git (`DiffView:post_open()` only loads review state for `GitAdapter`), so optimizations can be Git-specific.
- **Technical constraints**
  - Must handle large diffs efficiently (hundreds to thousands of files; ideally still reasonable at >10k).
  - Must preserve current semantics for missing blob hashes (`nil` treated as `"reviewed"` by `ReviewState:get_file_status()`).
  - Must remain safe under rapid repeated calls (navigation loops, repeated renders).

### Implementation Notes
- **Recommended approach**
  - Prefer view-level caching keyed by `(HEAD commit, file list generation)` so repeated status queries during a render/navigation are O(1) Lua table lookups.
  - Prefer batching git queries (one process per chunk) over per-file spawns; chunk input to avoid command length / memory spikes.
- **Potential gotchas**
  - HEAD changes while view is open: cache must be invalidated/recomputed, ideally without calling `head_rev()` on every per-file status read.
  - Missing/renamed paths: batch query parsing should tolerate paths that no longer exist at HEAD and map them to `nil`.
  - Path edge cases: whitespace/special chars should be handled via stdin or `-z` parsing (avoid shell-escaped path lists).
  - Test determinism: tests that assert “adapter call counts” should use mocks to avoid flakiness and avoid tying to real git performance.
  - UI sensitivity: any attempt to reduce panel re-rendering must preserve selection highlighting and review indicator correctness.

## Implementation Guide

### Recommended Approach (high level)
1. Add lightweight instrumentation to confirm where time is spent (git calls vs render vs Lua loops).
2. Stop doing per-file git calls on navigation/panel render:
   - Use `commit_hash` short-circuit when possible.
   - Cache `(path -> status)` per view, invalidated on known events and HEAD changes.
   - Batch fetch blob hashes for many files at once when needed.
3. If navigation is still sluggish after removing git overhead, reduce file panel work on pure navigation:
   - Avoid full `panel:render()/panel:redraw()` on every `_set_file` call when file list and review indicators haven’t changed.

### Step-by-step guide

#### 1) Add profiling hooks (no behavioral change)
- Add a `PerfTimer` around whichever new “rebuild status cache” function is introduced.
- Add a counter/log for:
  - number of paths whose blob hash was fetched,
  - number of git processes spawned (should go down to ~1 per rebuild, instead of N),
  - time spent in batch git query and time spent in pure Lua status mapping.
- Keep logs behind an opt-in flag (e.g. `config.get_config().review.perf_debug`) or a high logger level to avoid noisy defaults.

#### 2) Introduce a batch blob-hash query in the git adapter
- Add a helper on `GitAdapter` for resolving many `rev:path` specs in one process, leveraging `utils.job(..., { writer = {...} })`.
  - Start with the review use-case: `rev_arg="HEAD"` and a list of file paths.
  - Recommended implementation strategy:
    - Use `git rev-parse --revs-only --stdin` and write one `<rev:path>` per line (matches existing `file_blob_hash` semantics).
    - Parse `stdout` lines back into a `path -> hash|nil` map.
    - Handle missing paths/errors by returning `nil` hash for those paths (preserve current behavior where missing hash is treated as reviewed).
    - Chunk the input list to avoid command limits (e.g. 200–500 paths per batch).
  - Alternative if `rev-parse --stdin` proves too error-prone: `git ls-tree -z <rev> -- <paths...>` (HEAD-only) with robust parsing.
- Add tests in `lua/diffview/tests/functional/git_adapter_spec.lua`:
  - Batch results match per-file `file_blob_hash()` for a handful of known files.
  - Missing file paths return `nil` without failing the whole batch.

#### 3) Add a view-level review status cache (+ invalidation)
- Add cache fields on `DiffView` (or attach them dynamically):
  - `review_status_cache: table<string, "unreviewed"|"reviewed"|"changed">`
  - `review_status_cache_head: string|nil` (the HEAD commit hash used to compute cache)
  - `review_status_cache_valid: boolean` (or derive from presence of head + map)
- Add methods:
  - `DiffView:invalidate_review_status_cache(reason?)`
  - `DiffView:rebuild_review_status_cache()` (uses `head_rev()` once + batch blob hashes where needed)
  - `DiffView:get_review_status(file_entry)` (returns cached status; rebuilds if invalid)
- Invalidation triggers (minimum set):
  - `DiffView.update_files()` end: invalidate and rebuild (or rebuild lazily on first read after update).
  - Review events in `DiffView:init_review_event_listeners()`:
    - `review_file_marked`, `review_file_cleared`, `review_all_cleared`, `review_repo_cleared`
    - At minimum: invalidate cache; optionally patch-update single path on per-file events.
  - `toggle_review_filter()` / `toggle_since_review_mode()`:
    - ensure cache is valid before computing visible counts / filtering to avoid repeated work.
- HEAD change detection:
  - Preferred: rebuild cache whenever `head_rev().commit` differs from `review_status_cache_head`.
  - Keep `head_rev()` calls rate-limited (e.g. only check when cache is invalid or when a small “staleness window” expires).

#### 4) Add the `commit_hash` short-circuit
- During cache rebuild:
  - For each file with a review entry:
    - If `entry.commit_hash` exists and equals current HEAD commit → status `"reviewed"` without blob hash lookup.
    - Otherwise include the path in the batch blob-hash query and compare `entry.blob_hash` with the result.
- This directly addresses the “reviewed in current HEAD” hot path, which should be the most common case during a single review session.
- Add tests in `lua/diffview/tests/functional/review_api_spec.lua`:
  - When `ReviewEntry.commit_hash == HEAD`, `review.get_file_status()` does not call `adapter:file_blob_hash()` and returns `"reviewed"`.
  - When `commit_hash` is missing (legacy), behavior matches existing blob-hash comparison.

#### 5) Reduce redundant status scans in navigation/filtering (cheap wins)
- Navigation helpers currently do:
  - `panel:ordered_file_list()` (may filter using status checks),
  - then re-scan those files calling `review.get_file_status()` again.
- Once a cache exists, this becomes cheaper, but it’s still unnecessary work.
- Suggested refactors (in `lua/diffview/scene/views/diff/diff_view.lua`):
  - If `review_filter_enabled` and the command is “pending review”, treat `ordered_file_list()` as already filtered and skip re-checking statuses.
  - For other navigation modes, scan once and build `matching_files` using cached status reads only.

#### 6) Reduce file panel rendering work on pure navigation (optional, if still needed)
- Current `_set_file` eagerly re-renders the file panel on every navigation.
- Recommended incremental strategy:
  - First ship caching + batch git calls (should remove the biggest spikes).
  - If navigation still feels slow due to panel render/redraw cost:
    - avoid full `panel:render()/panel:redraw()` in `_set_file` when:
      - file list didn’t change,
      - review state didn’t change,
      - only the selected file changed.
    - Implement a “selection highlight” update path:
      - render uses a stable highlight for file names,
      - a dedicated namespace highlights the currently selected file name range,
      - moving selection only clears/adds highlights (no full render).
  - This is more complex than caching and should be gated behind performance validation.

### Manual testing (for humans; do not convert into rmplan tasks)
- Open a diff view with a large change set (hundreds+ files), enable review mode, and:
  - press `]r` repeatedly; observe whether latency spikes disappear,
  - toggle review filter and since-review mode; ensure counts/visibility are correct and responsive,
  - mark/clear review state and verify indicators update immediately,
  - change HEAD (checkout/rebase) while view is open and ensure statuses refresh after `update_files()` or next interaction.

### Why this approach
- Biggest win comes from reducing process spawns: batching and caching are multiplicative improvements.
- `commit_hash` short-circuit avoids unnecessary work in the common case where HEAD is unchanged during a review session.
- Panel render optimizations are valuable but should be second-pass, because they're more invasive and UI-sensitive.

## Current Progress

### Current State
- All core performance optimizations are implemented and tested. The main performance bottlenecks (per-file git process spawns during navigation/filtering) have been addressed.

### Completed (So Far)
- Task 2: Batch blob-hash lookup in GitAdapter using `git ls-tree -z` with chunking (300 paths per batch)
- Task 3: DiffView review status cache with invalidation on files_updated and review events
- Task 4: commit_hash short-circuit skips blob lookups when entry.commit_hash matches HEAD
- Task 5: Reduced redundant review status scans in navigation and filtering
  - Navigation helpers now use `skip_filter_when_panel_filtered` optimization
  - When `review_filter_enabled=true` and navigating "pending" files, uses panel's pre-filtered list directly
  - `FilePanel:should_show_file` uses `get_cached_review_status` when available
  - Added tests for the skip-filter optimization and cached status paths

### Remaining
- Task 1: Add review performance instrumentation (optional profiling hooks)
- Task 6: (Optional) Avoid full panel render on pure navigation

### Next Iteration Guidance
- Task 1 (instrumentation) can be added anytime to validate performance improvements
- Task 6 should only be done if profiling shows panel render is still a bottleneck after the caching/batching work

### Decisions / Changes
- Used `git ls-tree -z` for batch lookups instead of `git rev-parse --stdin` (more reliable parsing)
- commit_hash short-circuit is implemented in cache rebuild path (not in review.get_file_status)
- toggle_review_filter/toggle_since_review_mode don't invalidate cache (filters affect visibility, not status)
- Added debug logging for cache miss fallback path to detect if per-file git lookups still occur
- Navigation helpers call `ensure_review_status_cache()` at the start, then use cached lookups throughout
- `skip_filter_when_panel_filtered` parameter allows skipping redundant status checks when panel already filtered

### Risks / Blockers
- None
