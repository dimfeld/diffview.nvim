---
# yaml-language-server: $schema=https://raw.githubusercontent.com/dimfeld/llmutils/main/schema/rmplan-plan-schema.json
title: Cleanup stale review data
goal: ""
id: 8
uuid: 23bead4b-525b-482d-bf0c-51757bee0793
status: pending
priority: medium
dependencies:
  - 9
parent: 1
references:
  "1": 6d222e2b-71b2-42ca-9e26-231b4726a946
  "9": 5c9e18fb-157d-4000-b111-45d034aedd0b
createdAt: 2026-01-15T01:45:14.898Z
updatedAt: 2026-01-15T01:45:14.901Z
tasks: []
tags: []
---

Implement cleanup functionality to remove review data for branches that no longer exist.

## Why Cleanup is Needed
- Review state is stored per branch
- When branches are deleted (after merging PRs, etc.), the review data becomes stale
- Over time this can accumulate and waste storage space

## Cleanup Approach

### Automatic Cleanup (on startup or periodic)
- When diffview loads, check stored review data against existing branches
- Remove review entries for branches that no longer exist in the repository
- Should be efficient and not slow down normal operations

### Manual Cleanup Command
- Provide a command to manually trigger cleanup
- Could show what will be removed before doing it

## Considerations
- Need to handle multiple repositories (each repo has its own branches)
- Should be resilient to temporary branch unavailability (e.g., during fetch)
- Consider age-based cleanup as an additional strategy (remove reviews older than X days)
