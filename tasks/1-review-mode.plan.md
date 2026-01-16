---
# yaml-language-server: $schema=https://raw.githubusercontent.com/dimfeld/llmutils/main/schema/rmplan-plan-schema.json
title: Review mode
goal: ""
id: 1
uuid: 6d222e2b-71b2-42ca-9e26-231b4726a946
status: done
priority: medium
epic: true
dependencies:
  - 2
  - 3
  - 4
  - 5
  - 6
  - 7
  - 8
  - 9
references:
  "2": aae1042d-6942-47bc-8470-5d7ac9ca8bc6
  "3": 2445aa72-8e05-43bf-afdb-3c1e4b508db8
  "4": 0b764a53-420b-410c-8e39-5e5688e97542
  "5": 409b88c6-22c0-43f9-97ec-ff6a12b9b0df
  "6": 7b6950a9-0254-43a1-9590-9d8a0e509bd4
  "7": 9ce60301-7529-43d4-a46d-27c75a43f4d8
  "8": 23bead4b-525b-482d-bf0c-51757bee0793
  "9": 5c9e18fb-157d-4000-b111-45d034aedd0b
createdAt: 2026-01-14T23:39:33.523Z
updatedAt: 2026-01-16T10:57:52.388Z
tasks: []
changedFiles:
  - .rmfilter/config/rmplan.yml
  - AGENTS.md
  - CLAUDE.md
  - lua/diffview/config.lua
  - lua/diffview/init.lua
  - lua/diffview/review.lua
  - lua/diffview/review_store.lua
  - lua/diffview/scene/views/diff/diff_view.lua
  - lua/diffview/tests/functional/git_adapter_spec.lua
  - lua/diffview/tests/functional/review_api_spec.lua
  - lua/diffview/tests/functional/review_store_spec.lua
  - lua/diffview/vcs/adapters/git/init.lua
  - README.md
  - USAGE.md
  - doc/diffview.txt
  - doc/diffview_defaults.txt
  - lua/diffview/actions.lua
  - lua/diffview/hl.lua
  - lua/diffview/scene/views/diff/file_panel.lua
  - lua/diffview/scene/views/diff/listeners.lua
  - lua/diffview/scene/views/diff/render.lua
  - lua/diffview/tests/functional/render_review_indicator_spec.lua
  - lua/diffview/tests/functional/review_actions_spec.lua
  - lua/diffview/tests/functional/review_cleanup_spec.lua
  - lua/diffview/tests/functional/review_clear_spec.lua
  - lua/diffview/tests/functional/review_filter_spec.lua
  - lua/diffview/tests/functional/review_navigation_spec.lua
  - lua/diffview/tests/functional/since_review_diff_spec.lua
  - lua/diffview/ui/models/file_tree/file_tree.lua
  - plugin/diffview.lua
tags: []
---

We want to have a review mode which works similarly to the GitHub review for a pull request. It allows you to mark files as reviewed, tracks when a file has been changed since the last review, and can optionally show you only the changes since the last time the file was marked as reviewed.
