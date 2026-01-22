# Diffview.nvim

Single tabpage interface for easily cycling through diffs for all modified files
for any git rev.

This is a fork of [sindrets/diffview.nvim](https://github.com/sindrets/diffview.nvim), with extra support for
reviewing PRs and other diffs.

![preview](https://user-images.githubusercontent.com/2786478/131269942-e34100dd-cbb9-48fe-af31-6e518ce06e9e.png)


## Introduction

Vim's diff mode is pretty good, but there is no convenient way to quickly bring
up all modified files in a diffsplit. This plugin aims to provide a simple,
unified, single tabpage interface that lets you easily review all changed files
for any git rev.

## Requirements

- Git ≥ 2.31.0 (for Git support)
- Mercurial ≥ 5.4.0 (for Mercurial support)
- Neovim ≥ 0.7.0 (with LuaJIT)
- [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) (optional) For file icons

## Installation

Install the plugin with your package manager of choice.

```vim
" Plug
Plug 'sindrets/diffview.nvim'
```

```lua
-- Packer
use "sindrets/diffview.nvim" 
```

## Merge Tool

![merge tool showcase](https://user-images.githubusercontent.com/2786478/188286293-13bbf0ab-3595-425d-ba4a-12f514c17eb6.png)

Opening a diff view during a merge or a rebase will list the conflicted files in
their own section. When opening a conflicted file, it will open in a 3-way diff
allowing you to resolve the merge conflicts with the context of the target
branch's version, as well as the version from the branch which is being merged.

The 3-way diff is only the default layout for merge conflicts. There are
multiple variations on this layout, a 4-way diff layout, and a single window
layout available.

In addition to the normal `:h copy-diffs` mappings, there are default mappings
provided for jumping between conflict markers, obtaining a hunk directly from
any of the diff buffers, and accepting any one, all, or none of the versions of
a file given by a conflict region.

For more information on the merge tool, mappings, layouts and how to
configure them, see:

- `:h diffview-merge-tool`
- `:h diffview-config-view.x.layout`

## File History

![file history showcase](https://user-images.githubusercontent.com/2786478/188331057-f9ec9a0d-8cda-4ff8-ac98-febcc7aa4010.png)

The file history view allows you to list all the commits that affected a given
set of paths, and view the changes made in a diff split. This is a porcelain
interface for git-log, and supports a good number of its options. Things like:

- Filtering commits by grepping commit messages and commit authors.
- Tracing the line evolution of a given set of line ranges for multiple files.
- Only listing changes for a specific commit range, branch, or tag.
- Following file changes through renames.

Get started by opening file history for:

- The current branch: `:DiffviewFileHistory`
- The current file: `:DiffviewFileHistory %`

For more info, see `:h :DiffviewFileHistory`.

## JSON Grouped Views

You can open a diff view with files organized into custom named groups using a
JSON file. This is useful for:

- **Code review workflows**: Organize files by logical feature areas (frontend,
  backend, tests) rather than alphabetically
- **Automated tooling**: Generate curated file lists from external tools (e.g.,
  AI code analysis, dependency impact analysis)
- **Educational walkthroughs**: Show specific files in a specific order

### Basic Usage

Create a JSON file defining your groups:

```json
{
  "title": "PR #123: Add authentication",
  "groups": [
    {
      "name": "Frontend",
      "files": [
        { "path": "src/components/Login.tsx" },
        { "path": "src/components/Signup.tsx" }
      ]
    },
    {
      "name": "Backend",
      "files": [
        { "path": "src/api/auth.ts" }
      ]
    }
  ]
}
```

Then open it with:

```vim
:DiffviewOpenJson review.json HEAD~5
:DiffviewOpenJson review.json main..feature-branch
```

The command accepts the same revision arguments as `:DiffviewOpen`. File status
and diffs are computed from git based on the specified revisions.

### Filtering

- Files with no changes at the specified revisions are automatically filtered out
- Missing files show a warning, but the view continues with valid files
- Empty groups (after filtering) are hidden
- If all groups are empty, an error is shown

For more details, see `:h :DiffviewOpenJson`.

## Review Tracking

This fork adds review tracking functionality to help you keep track of which
files you've reviewed in a diff. This is particularly useful when reviewing
large PRs or diffs that span multiple sessions.

### How It Works

When you mark a file as reviewed, diffview stores the file's blob hash (the
content hash) along with a timestamp. This has several advantages:

- **Survives rebases and amends**: Since the blob hash is content-based, your
  review state persists even if commit hashes change (common when using tools
  like Jujutsu or when force-pushing).
- **Detects changes**: If a file is modified after you reviewed it, diffview
  detects this by comparing blob hashes and marks it as "changed".

### Review Statuses

Files in the file panel show indicators based on their review status:

- **Unreviewed** (blank): File has never been marked as reviewed
- **Reviewed** (●): File was marked as reviewed and hasn't changed
- **Changed** (◐): File was marked as reviewed but has been modified since

### Key Features

**Mark files as reviewed:**
- `<leader>rm` - Mark current file as reviewed
- `<leader>rM` - Mark all files as reviewed

**Navigate by review status:**
- `]r` / `[r` - Jump to next/previous file pending review (unreviewed or changed)
- `]R` / `[R` - Jump to next/previous unreviewed file

**Review filter:**
- `<leader>rf` - Toggle filter to show only files pending review

**Since-review diff mode:**
- `<leader>rs` - Toggle since-review mode. When enabled, files marked as
  "changed" show only the diff since your last review, not the full diff.
  This helps you focus on what changed since you last looked at a file.

**Clear review state:**
- `<leader>rc` - Clear review status for current file
- `<leader>rC` - Clear all review state for this branch
- `<leader>rX` - Clear all review state for this repository

### Configuration

```lua
review = {
  enabled = true,              -- Enable review tracking
  cache_dir = nil,             -- Storage location (default: ~/.cache/diffview.nvim/reviews/)
  auto_cleanup = false,        -- Auto-cleanup stale branch data on DiffView open
  cleanup_age_days = 30,       -- Age threshold for auto-cleanup (days)
  auto_advance = "stay",       -- "stay", "next", or "next_pending"
  symbols = {
    unreviewed = " ",          -- No indicator
    reviewed = "●",            -- Filled circle (green)
    changed = "◐",             -- Half-filled circle (yellow)
  },
}
```

### Cleanup

Review state is stored per-branch. Over time, you may accumulate review data
for branches that no longer exist. Use `:DiffviewReviewCleanup` to remove
stale data:

- `:DiffviewReviewCleanup` - Interactively clean up stale branch data
- `:DiffviewReviewCleanup!` - Preview what would be cleaned up (dry run)

You can also enable `auto_cleanup = true` in the config to automatically clean
up stale data when opening a DiffView.

## Usage

### `:DiffviewOpen [git rev] [options] [ -- {paths...}]`

Calling `:DiffviewOpen` with no args opens a new Diffview that compares against
the current index. You can also provide any valid git rev to view only changes
for that rev.

Examples:

- `:DiffviewOpen`
- `:DiffviewOpen HEAD~2`
- `:DiffviewOpen HEAD~4..HEAD~2`
- `:DiffviewOpen d4a7b0d`
- `:DiffviewOpen d4a7b0d^!`
- `:DiffviewOpen d4a7b0d..519b30e`
- `:DiffviewOpen origin/main...HEAD`

You can also provide additional paths to narrow down what files are shown:

- `:DiffviewOpen HEAD~2 -- lua/diffview plugin`

For information about additional `[options]`, visit the
[documentation](https://github.com/sindrets/diffview.nvim/blob/main/doc/diffview.txt).

Additional commands for convenience:

- `:DiffviewClose`: Close the current diffview. You can also use `:tabclose`.
- `:DiffviewToggleFiles`: Toggle the file panel.
- `:DiffviewFocusFiles`: Bring focus to the file panel.
- `:DiffviewRefresh`: Update stats and entries in the file list of the current
  Diffview.

With a Diffview open and the default key bindings, you can cycle through changed
files with `<tab>` and `<s-tab>` (see configuration to change the key bindings).

#### Staging

You can stage individual hunks by editing any buffer that represents the index
(after running `:DiffviewOpen` with no `[git-rev]` the entries under "Changes"
will have the index buffer on the left side, and the entries under "Staged
changes" will have it on the right side). Once you write to an index buffer the
index will be updated.

### `:[range]DiffviewFileHistory [paths] [options]`

Opens a new file history view that lists all commits that affected the given
paths. This is a porcelain interface for git-log. Both `[paths]` and
`[options]` may be specified in any order, even interchangeably.

If no `[paths]` are given, defaults to the top-level of the working tree. The
top-level will be inferred from the current buffer when possible, otherwise the
cwd is used. Multiple `[paths]` may be provided and git pathspec is supported.

If `[range]` is given, the file history view will trace the line evolution of the
given range in the current file (for more info, see the `-L` flag in the docs).

Examples:

- `:DiffviewFileHistory`
- `:DiffviewFileHistory %`
- `:DiffviewFileHistory path/to/some/file.txt`
- `:DiffviewFileHistory path/to/some/directory`
- `:DiffviewFileHistory include/this and/this :!but/not/this`
- `:DiffviewFileHistory --range=origin..HEAD`
- `:DiffviewFileHistory --range=feat/example-branch`
- `:'<,'>DiffviewFileHistory`

> [!IMPORTANT]
> ### Familiarize Yourself With `:h diff-mode`
>
> This plugin assumes you're familiar with all the features already provided by
> nvim's builtin diff-mode. These features include:
>
> - Jumping between hunks (`:h jumpto-diffs`).
> - Applying the changes of a diff hunk from any of the diffed buffers
>   (`:h copy-diffs`).
> - And more...
>
> Read the help page for more info.

---

<br>

> [!NOTE]
> Additionally check out [USAGE](USAGE.md) for examples of some more specific
> use-cases.

<br>

---

## Configuration

<p>
<details>
<summary style='cursor: pointer'><b>Example config with default values</b></summary>

```lua
-- Lua
local actions = require("diffview.actions")

require("diffview").setup({
  diff_binaries = false,    -- Show diffs for binaries
  enhanced_diff_hl = false, -- See |diffview-config-enhanced_diff_hl|
  git_cmd = { "git" },      -- The git executable followed by default args.
  hg_cmd = { "hg" },        -- The hg executable followed by default args.
  use_icons = true,         -- Requires nvim-web-devicons
  show_help_hints = true,   -- Show hints for how to open the help panel
  watch_index = true,       -- Update views and index buffers when the git index changes.
  icons = {                 -- Only applies when use_icons is true.
    folder_closed = "",
    folder_open = "",
  },
  signs = {
    fold_closed = "",
    fold_open = "",
    done = "✓",
  },
  view = {
    -- Configure the layout and behavior of different types of views.
    -- Available layouts:
    --  'diff1_plain'
    --    |'diff2_horizontal'
    --    |'diff2_vertical'
    --    |'diff3_horizontal'
    --    |'diff3_vertical'
    --    |'diff3_mixed'
    --    |'diff4_mixed'
    -- For more info, see |diffview-config-view.x.layout|.
    default = {
      -- Config for changed files, and staged files in diff views.
      layout = "diff2_horizontal",
      disable_diagnostics = false,  -- Temporarily disable diagnostics for diff buffers while in the view.
      winbar_info = false,          -- See |diffview-config-view.x.winbar_info|
    },
    merge_tool = {
      -- Config for conflicted files in diff views during a merge or rebase.
      layout = "diff3_horizontal",
      disable_diagnostics = true,   -- Temporarily disable diagnostics for diff buffers while in the view.
      winbar_info = true,           -- See |diffview-config-view.x.winbar_info|
    },
    file_history = {
      -- Config for changed files in file history views.
      layout = "diff2_horizontal",
      disable_diagnostics = false,  -- Temporarily disable diagnostics for diff buffers while in the view.
      winbar_info = false,          -- See |diffview-config-view.x.winbar_info|
    },
  },
  file_panel = {
    listing_style = "tree",             -- One of 'list' or 'tree'
    tree_options = {                    -- Only applies when listing_style is 'tree'
      flatten_dirs = true,              -- Flatten dirs that only contain one single dir
      folder_statuses = "only_folded",  -- One of 'never', 'only_folded' or 'always'.
    },
    win_config = {                      -- See |diffview-config-win_config|
      position = "left",
      width = 35,
      win_opts = {},
    },
  },
  file_history_panel = {
    log_options = {   -- See |diffview-config-log_options|
      git = {
        single_file = {
          diff_merges = "combined",
        },
        multi_file = {
          diff_merges = "first-parent",
        },
      },
      hg = {
        single_file = {},
        multi_file = {},
      },
    },
    win_config = {    -- See |diffview-config-win_config|
      position = "bottom",
      height = 16,
      win_opts = {},
    },
  },
  commit_log_panel = {
    win_config = {},  -- See |diffview-config-win_config|
  },
  default_args = {    -- Default args prepended to the arg-list for the listed commands
    DiffviewOpen = {},
    DiffviewFileHistory = {},
  },
  review = {          -- See |diffview-config-review|
    enabled = true,   -- Enable review tracking
    cache_dir = nil,  -- Review state storage (default: ~/.cache/diffview.nvim/reviews/)
    auto_cleanup = false,    -- Auto-cleanup stale branch review data on DiffView open
    cleanup_age_days = 30,   -- Age threshold for cleanup (days)
    auto_advance = "stay",   -- "stay", "next", or "next_pending"
    symbols = {       -- Symbols for review state indicator in file panel
      unreviewed = " ",  -- Blank space (no indicator)
      reviewed = "●",    -- Filled circle (green)
      changed = "◐",     -- Half-filled circle (yellow)
    },
  },
  hooks = {},         -- See |diffview-config-hooks|
  keymaps = {
    disable_defaults = false, -- Disable the default keymaps
    view = {
      -- The `view` bindings are active in the diff buffers, only when the current
      -- tabpage is a Diffview.
      { "n", "<tab>",       actions.select_next_entry,              { desc = "Open the diff for the next file" } },
      { "n", "<s-tab>",     actions.select_prev_entry,              { desc = "Open the diff for the previous file" } },
      { "n", "[F",          actions.select_first_entry,             { desc = "Open the diff for the first file" } },
      { "n", "]F",          actions.select_last_entry,              { desc = "Open the diff for the last file" } },
      { "n", "gf",          actions.goto_file_edit,                 { desc = "Open the file in the previous tabpage" } },
      { "n", "<C-w><C-f>",  actions.goto_file_split,                { desc = "Open the file in a new split" } },
      { "n", "<C-w>gf",     actions.goto_file_tab,                  { desc = "Open the file in a new tabpage" } },
      { "n", "<leader>e",   actions.focus_files,                    { desc = "Bring focus to the file panel" } },
      { "n", "<leader>b",   actions.toggle_files,                   { desc = "Toggle the file panel." } },
      { "n", "g<C-x>",      actions.cycle_layout,                   { desc = "Cycle through available layouts." } },
      { "n", "[x",          actions.prev_conflict,                  { desc = "In the merge-tool: jump to the previous conflict" } },
      { "n", "]x",          actions.next_conflict,                  { desc = "In the merge-tool: jump to the next conflict" } },
      { "n", "[r",          actions.review_prev_pending,            { desc = "Jump to the previous file pending review" } },
      { "n", "]r",          actions.review_next_pending,            { desc = "Jump to the next file pending review" } },
      { "n", "[R",          actions.review_prev_unreviewed,         { desc = "Jump to the previous unreviewed file" } },
      { "n", "]R",          actions.review_next_unreviewed,         { desc = "Jump to the next unreviewed file" } },
      { "n", "<leader>rf",  actions.review_toggle_filter,           { desc = "Toggle review filter (show only pending)" } },
      { "n", "<leader>rs",  actions.review_toggle_since_review,    { desc = "Toggle since-review diff mode" } },
      { "n", "<leader>rm",  actions.review_mark_file,              { desc = "Mark the current file as reviewed" } },
      { "n", "<leader>rM",  actions.review_mark_all,               { desc = "Mark all files as reviewed" } },
      { "n", "<leader>rc",  actions.review_clear_file,             { desc = "Clear review status for the current file" } },
      { "n", "<leader>rC",  actions.review_clear_all,              { desc = "Clear all review state for this branch" } },
      { "n", "<leader>rX",  actions.review_clear_repo,             { desc = "Clear all review state for this repository" } },
      { "n", "<leader>co",  actions.conflict_choose("ours"),        { desc = "Choose the OURS version of a conflict" } },
      { "n", "<leader>ct",  actions.conflict_choose("theirs"),      { desc = "Choose the THEIRS version of a conflict" } },
      { "n", "<leader>cb",  actions.conflict_choose("base"),        { desc = "Choose the BASE version of a conflict" } },
      { "n", "<leader>ca",  actions.conflict_choose("all"),         { desc = "Choose all the versions of a conflict" } },
      { "n", "dx",          actions.conflict_choose("none"),        { desc = "Delete the conflict region" } },
      { "n", "<leader>cO",  actions.conflict_choose_all("ours"),    { desc = "Choose the OURS version of a conflict for the whole file" } },
      { "n", "<leader>cT",  actions.conflict_choose_all("theirs"),  { desc = "Choose the THEIRS version of a conflict for the whole file" } },
      { "n", "<leader>cB",  actions.conflict_choose_all("base"),    { desc = "Choose the BASE version of a conflict for the whole file" } },
      { "n", "<leader>cA",  actions.conflict_choose_all("all"),     { desc = "Choose all the versions of a conflict for the whole file" } },
      { "n", "dX",          actions.conflict_choose_all("none"),    { desc = "Delete the conflict region for the whole file" } },
    },
    diff1 = {
      -- Mappings in single window diff layouts
      { "n", "g?", actions.help({ "view", "diff1" }), { desc = "Open the help panel" } },
    },
    diff2 = {
      -- Mappings in 2-way diff layouts
      { "n", "g?", actions.help({ "view", "diff2" }), { desc = "Open the help panel" } },
    },
    diff3 = {
      -- Mappings in 3-way diff layouts
      { { "n", "x" }, "2do",  actions.diffget("ours"),            { desc = "Obtain the diff hunk from the OURS version of the file" } },
      { { "n", "x" }, "3do",  actions.diffget("theirs"),          { desc = "Obtain the diff hunk from the THEIRS version of the file" } },
      { "n",          "g?",   actions.help({ "view", "diff3" }),  { desc = "Open the help panel" } },
    },
    diff4 = {
      -- Mappings in 4-way diff layouts
      { { "n", "x" }, "1do",  actions.diffget("base"),            { desc = "Obtain the diff hunk from the BASE version of the file" } },
      { { "n", "x" }, "2do",  actions.diffget("ours"),            { desc = "Obtain the diff hunk from the OURS version of the file" } },
      { { "n", "x" }, "3do",  actions.diffget("theirs"),          { desc = "Obtain the diff hunk from the THEIRS version of the file" } },
      { "n",          "g?",   actions.help({ "view", "diff4" }),  { desc = "Open the help panel" } },
    },
    file_panel = {
      { "n", "j",              actions.next_entry,                     { desc = "Bring the cursor to the next file entry" } },
      { "n", "<down>",         actions.next_entry,                     { desc = "Bring the cursor to the next file entry" } },
      { "n", "k",              actions.prev_entry,                     { desc = "Bring the cursor to the previous file entry" } },
      { "n", "<up>",           actions.prev_entry,                     { desc = "Bring the cursor to the previous file entry" } },
      { "n", "<cr>",           actions.select_entry,                   { desc = "Open the diff for the selected entry" } },
      { "n", "o",              actions.select_entry,                   { desc = "Open the diff for the selected entry" } },
      { "n", "l",              actions.select_entry,                   { desc = "Open the diff for the selected entry" } },
      { "n", "<2-LeftMouse>",  actions.select_entry,                   { desc = "Open the diff for the selected entry" } },
      { "n", "-",              actions.toggle_stage_entry,             { desc = "Stage / unstage the selected entry" } },
      { "n", "s",              actions.toggle_stage_entry,             { desc = "Stage / unstage the selected entry" } },
      { "n", "S",              actions.stage_all,                      { desc = "Stage all entries" } },
      { "n", "U",              actions.unstage_all,                    { desc = "Unstage all entries" } },
      { "n", "X",              actions.restore_entry,                  { desc = "Restore entry to the state on the left side" } },
      { "n", "L",              actions.open_commit_log,                { desc = "Open the commit log panel" } },
      { "n", "zo",             actions.open_fold,                      { desc = "Expand fold" } },
      { "n", "h",              actions.close_fold,                     { desc = "Collapse fold" } },
      { "n", "zc",             actions.close_fold,                     { desc = "Collapse fold" } },
      { "n", "za",             actions.toggle_fold,                    { desc = "Toggle fold" } },
      { "n", "zR",             actions.open_all_folds,                 { desc = "Expand all folds" } },
      { "n", "zM",             actions.close_all_folds,                { desc = "Collapse all folds" } },
      { "n", "<c-b>",          actions.scroll_view(-0.25),             { desc = "Scroll the view up" } },
      { "n", "<c-f>",          actions.scroll_view(0.25),              { desc = "Scroll the view down" } },
      { "n", "<tab>",          actions.select_next_entry,              { desc = "Open the diff for the next file" } },
      { "n", "<s-tab>",        actions.select_prev_entry,              { desc = "Open the diff for the previous file" } },
      { "n", "[F",             actions.select_first_entry,             { desc = "Open the diff for the first file" } },
      { "n", "]F",             actions.select_last_entry,              { desc = "Open the diff for the last file" } },
      { "n", "gf",             actions.goto_file_edit,                 { desc = "Open the file in the previous tabpage" } },
      { "n", "<C-w><C-f>",     actions.goto_file_split,                { desc = "Open the file in a new split" } },
      { "n", "<C-w>gf",        actions.goto_file_tab,                  { desc = "Open the file in a new tabpage" } },
      { "n", "i",              actions.listing_style,                  { desc = "Toggle between 'list' and 'tree' views" } },
      { "n", "f",              actions.toggle_flatten_dirs,            { desc = "Flatten empty subdirectories in tree listing style" } },
      { "n", "R",              actions.refresh_files,                  { desc = "Update stats and entries in the file list" } },
      { "n", "<leader>e",      actions.focus_files,                    { desc = "Bring focus to the file panel" } },
      { "n", "<leader>b",      actions.toggle_files,                   { desc = "Toggle the file panel" } },
      { "n", "g<C-x>",         actions.cycle_layout,                   { desc = "Cycle available layouts" } },
      { "n", "[x",             actions.prev_conflict,                  { desc = "Go to the previous conflict" } },
      { "n", "]x",             actions.next_conflict,                  { desc = "Go to the next conflict" } },
      { "n", "[r",             actions.review_prev_pending,            { desc = "Jump to the previous file pending review" } },
      { "n", "]r",             actions.review_next_pending,            { desc = "Jump to the next file pending review" } },
      { "n", "[R",             actions.review_prev_unreviewed,         { desc = "Jump to the previous unreviewed file" } },
      { "n", "]R",             actions.review_next_unreviewed,         { desc = "Jump to the next unreviewed file" } },
      { "n", "<leader>rf",     actions.review_toggle_filter,           { desc = "Toggle review filter (show only pending)" } },
      { "n", "<leader>rs",    actions.review_toggle_since_review,    { desc = "Toggle since-review diff mode" } },
      { "n", "<leader>rm",    actions.review_mark_file,              { desc = "Mark the current file as reviewed" } },
      { "n", "<leader>rM",    actions.review_mark_all,               { desc = "Mark all files as reviewed" } },
      { "n", "<leader>rc",    actions.review_clear_file,             { desc = "Clear review status for the current file" } },
      { "n", "<leader>rC",  actions.review_clear_all,              { desc = "Clear all review state for this branch" } },
      { "n", "<leader>rX",  actions.review_clear_repo,             { desc = "Clear all review state for this repository" } },
      { "n", "g?",             actions.help("file_panel"),             { desc = "Open the help panel" } },
      { "n", "<leader>cO",     actions.conflict_choose_all("ours"),    { desc = "Choose the OURS version of a conflict for the whole file" } },
      { "n", "<leader>cT",     actions.conflict_choose_all("theirs"),  { desc = "Choose the THEIRS version of a conflict for the whole file" } },
      { "n", "<leader>cB",     actions.conflict_choose_all("base"),    { desc = "Choose the BASE version of a conflict for the whole file" } },
      { "n", "<leader>cA",     actions.conflict_choose_all("all"),     { desc = "Choose all the versions of a conflict for the whole file" } },
      { "n", "dX",             actions.conflict_choose_all("none"),    { desc = "Delete the conflict region for the whole file" } },
    },
    file_history_panel = {
      { "n", "g!",            actions.options,                     { desc = "Open the option panel" } },
      { "n", "<C-A-d>",       actions.open_in_diffview,            { desc = "Open the entry under the cursor in a diffview" } },
      { "n", "y",             actions.copy_hash,                   { desc = "Copy the commit hash of the entry under the cursor" } },
      { "n", "L",             actions.open_commit_log,             { desc = "Show commit details" } },
      { "n", "X",             actions.restore_entry,               { desc = "Restore file to the state from the selected entry" } },
      { "n", "zo",            actions.open_fold,                   { desc = "Expand fold" } },
      { "n", "zc",            actions.close_fold,                  { desc = "Collapse fold" } },
      { "n", "h",             actions.close_fold,                  { desc = "Collapse fold" } },
      { "n", "za",            actions.toggle_fold,                 { desc = "Toggle fold" } },
      { "n", "zR",            actions.open_all_folds,              { desc = "Expand all folds" } },
      { "n", "zM",            actions.close_all_folds,             { desc = "Collapse all folds" } },
      { "n", "j",             actions.next_entry,                  { desc = "Bring the cursor to the next file entry" } },
      { "n", "<down>",        actions.next_entry,                  { desc = "Bring the cursor to the next file entry" } },
      { "n", "k",             actions.prev_entry,                  { desc = "Bring the cursor to the previous file entry" } },
      { "n", "<up>",          actions.prev_entry,                  { desc = "Bring the cursor to the previous file entry" } },
      { "n", "<cr>",          actions.select_entry,                { desc = "Open the diff for the selected entry" } },
      { "n", "o",             actions.select_entry,                { desc = "Open the diff for the selected entry" } },
      { "n", "l",             actions.select_entry,                { desc = "Open the diff for the selected entry" } },
      { "n", "<2-LeftMouse>", actions.select_entry,                { desc = "Open the diff for the selected entry" } },
      { "n", "<c-b>",         actions.scroll_view(-0.25),          { desc = "Scroll the view up" } },
      { "n", "<c-f>",         actions.scroll_view(0.25),           { desc = "Scroll the view down" } },
      { "n", "<tab>",         actions.select_next_entry,           { desc = "Open the diff for the next file" } },
      { "n", "<s-tab>",       actions.select_prev_entry,           { desc = "Open the diff for the previous file" } },
      { "n", "[F",            actions.select_first_entry,          { desc = "Open the diff for the first file" } },
      { "n", "]F",            actions.select_last_entry,           { desc = "Open the diff for the last file" } },
      { "n", "gf",            actions.goto_file_edit,              { desc = "Open the file in the previous tabpage" } },
      { "n", "<C-w><C-f>",    actions.goto_file_split,             { desc = "Open the file in a new split" } },
      { "n", "<C-w>gf",       actions.goto_file_tab,               { desc = "Open the file in a new tabpage" } },
      { "n", "<leader>e",     actions.focus_files,                 { desc = "Bring focus to the file panel" } },
      { "n", "<leader>b",     actions.toggle_files,                { desc = "Toggle the file panel" } },
      { "n", "g<C-x>",        actions.cycle_layout,                { desc = "Cycle available layouts" } },
      { "n", "g?",            actions.help("file_history_panel"),  { desc = "Open the help panel" } },
    },
    option_panel = {
      { "n", "<tab>", actions.select_entry,          { desc = "Change the current option" } },
      { "n", "q",     actions.close,                 { desc = "Close the panel" } },
      { "n", "g?",    actions.help("option_panel"),  { desc = "Open the help panel" } },
    },
    help_panel = {
      { "n", "q",     actions.close,  { desc = "Close help menu" } },
      { "n", "<esc>", actions.close,  { desc = "Close help menu" } },
    },
  },
})
```

</details>
</p>

### Hooks

The `hooks` table allows you to define callbacks for various events emitted from
Diffview. The available hooks are documented in detail in
`:h diffview-config-hooks`. The hook events are also available as User
autocommands. See `:h diffview-user-autocmds` for more details.

Examples:

```lua
hooks = {
  diff_buf_read = function(bufnr)
    -- Change local options in diff buffers
    vim.opt_local.wrap = false
    vim.opt_local.list = false
    vim.opt_local.colorcolumn = { 80 }
  end,
  view_opened = function(view)
    print(
      ("A new %s was opened on tab page %d!")
      :format(view.class:name(), view.tabpage)
    )
  end,
}
```

### Keymaps

The keymaps config is structured as a table with sub-tables for various
different contexts where mappings can be declared. In these sub-tables
key-value pairs are treated as the `{lhs}` and `{rhs}` of a normal mode
mapping. These mappings all use the `:map-arguments` `silent`, `nowait`, and
`noremap`. The implementation uses `vim.keymap.set()`, so the `{rhs}` can be
either a vim command in the form of a string, or it can be a lua function:

```lua
  view = {
    -- Vim command:
    ["a"] = "<Cmd>echom 'foo'<CR>",
    -- Lua function:
    ["b"] = function() print("bar") end,
  }
```

For more control (i.e. mappings for other modes), you can also define index
values as list-like tables containing the arguments for `vim.keymap.set()`.
This way you can also change all the `:map-arguments` with the only exception
being the `buffer` field, as this will be overridden with the target buffer
number:

```lua
view = {
  -- Normal and visual mode mapping to vim command:
  { { "n", "v" }, "<leader>a", "<Cmd>echom 'foo'<CR>", { silent = true } },
  -- Visual mode mapping to lua function:
  { "v", "<leader>b", function() print("bar") end, { nowait = true } },
}
```

To disable any single mapping without disabling them all, set its `{rhs}` to
`false`:

```lua
  view = {
    -- Disable the default normal mode mapping for `<tab>`:
    ["<tab>"] = false,
    -- Disable the default visual mode mapping for `gf`:
    { "x", "gf", false },
  }
```

Most of the mapped file panel actions also work from the view if they are added
to the view maps (and vice versa). The exception is for actions that only
really make sense specifically in the file panel, such as `next_entry`,
`prev_entry`. Actions such as `toggle_stage_entry` and `restore_entry` work
just fine from the view. When invoked from the view, these will target the file
currently open in the view rather than the file under the cursor in the file
panel.

**For more details on how to set mappings for other modes, actions, and more see:**
- `:h diffview-config-keymaps`
- `:h diffview-actions`

## Restoring Files

If the right side of the diff is showing the local state of a file, you can
restore the file to the state from the left side of the diff (key binding `X`
from the file panel by default). The current state of the file is stored in the
git object database, and a command is echoed that shows how to undo the change.

## Tips and FAQ

- **Hide untracked files:**
  - `DiffviewOpen -uno`
- **Exclude certain paths:**
  - `DiffviewOpen -- :!exclude/this :!and/this`
- **Run as if git was started in a specific directory:**
  - `DiffviewOpen -C/foo/bar/baz`
- **Diff the index against a git rev:**
  - `DiffviewOpen HEAD~2 --cached`
  - Defaults to `HEAD` if no rev is given.
- **Q: How do I get the diagonal lines in place of deleted lines in
  diff-mode?**
  - A: Change your `:h 'fillchars'`:
    - (vimscript): `set fillchars+=diff:╱`
    - (Lua): `vim.opt.fillchars:append { diff = "╱" }`
  - Note: whether or not the diagonal lines will line up nicely will depend on
    your terminal emulator. The terminal used in the screenshots is Kitty.
- **Q: How do I jump between hunks in the diff?**
  - A: Use `[c` and `]c`
  - `:h jumpto-diffs`

<!-- vim: set tw=80 -->
