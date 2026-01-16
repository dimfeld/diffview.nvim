# Repository Guidelines

## Project Structure & Module Organization
- `lua/diffview/` contains the core plugin logic (views, VCS adapters, UI, utils).
- `plugin/diffview.lua` is the Neovim entrypoint that sets up the plugin.
- `doc/` holds user-facing Vim help (`doc/diffview.txt`, defaults, changelog).
- `lua/diffview/tests/` contains Plenary/Busted tests, with helpers in
  `lua/diffview/tests/helpers.lua`.
- `scripts/` includes local dev/test bootstrapping (notably `scripts/test_init.lua`).
- `tasks/` stores planning notes and task docs (not runtime code).

## Build, Test, and Development Commands
- `make test`: Runs the full test suite with headless Neovim and Plenary.
- `TEST_PATH=lua/diffview/tests/functional make test`: Run a subset of tests.
- `make dev`: Fetches Neodev types into `.dev/` for improved Lua tooling.
- `make clean`: Removes local `.tests` and `.dev` artifacts.

## Coding Style & Naming Conventions
- Lua is the primary language; source is in `lua/diffview/`.
- Format with Stylua using `stylua.toml` (2-space indent, 100 columns, Unix
  line endings, prefer double quotes).
- Keep module names and paths aligned (e.g., `lua/diffview/vcs/adapters/git/`).
- Tests follow `*_spec.lua` naming under `lua/diffview/tests/`.

## Testing Guidelines
- Tests use Plenary’s Busted runner (invoked via `make test`).
- Place new specs in `lua/diffview/tests/functional/` when behavior crosses
  module boundaries; helpers live in `lua/diffview/tests/helpers.lua`.
- Keep test cases isolated; the test runner sets up a dedicated `.tests/`
  runtime path via `scripts/test_init.lua`.

## Commit & Pull Request Guidelines
- Recent commits use short, imperative summaries (e.g., “Add unit tests for …”).
- Keep commit messages focused on a single change; split refactors/tests where
  it improves reviewability.
- PRs should include: a concise summary, test coverage notes (commands run),
  and any doc updates if user-facing behavior changes (update `doc/` and
  `README.md`/`USAGE.md` as appropriate).

## Configuration & Docs Notes
- Help docs live in `doc/diffview.txt`; keep them in sync with behavior.
- User workflow guidance is in `README.md` and `USAGE.md`—update alongside
  feature or UX changes.
