---
# yaml-language-server: $schema=https://raw.githubusercontent.com/dimfeld/llmutils/main/schema/rmplan-plan-schema.json
title: Clear all review state for a branch
goal: ""
id: 9
uuid: 5c9e18fb-157d-4000-b111-45d034aedd0b
status: pending
priority: medium
dependencies:
  - 5
parent: 1
references:
  "1": 6d222e2b-71b2-42ca-9e26-231b4726a946
  "5": 409b88c6-22c0-43f9-97ec-ff6a12b9b0df
createdAt: 2026-01-15T01:45:15.566Z
updatedAt: 2026-01-15T01:45:15.570Z
tasks: []
tags: []
---

Implement the ability to clear all review state for a branch, allowing the user to start a fresh review.

## Use Cases
- Starting over on a review after significant changes
- Clearing state when the previous review is no longer relevant
- Resetting when the blob hashes are stale (garbage collected)

## Actions Required

### Clear All Review State for Current Branch
- Remove all review entries for the current repository + branch combination
- All files will appear as "unreviewed" after this action
- Should prompt for confirmation before clearing

### Optional: Clear Review State for Specific Repository
- Remove all review entries for a specific repository (all branches)
- Useful when a repository is removed or relocated

## Integration
- Should be available as a command that can be bound to a key
- Consider adding to a menu or command palette if diffview has one
