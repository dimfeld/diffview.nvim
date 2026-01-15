---
# yaml-language-server: $schema=https://raw.githubusercontent.com/dimfeld/llmutils/main/schema/rmplan-plan-schema.json
title: Actions for marking review state
goal: ""
id: 6
uuid: 7b6950a9-0254-43a1-9590-9d8a0e509bd4
status: pending
priority: medium
dependencies:
  - 2
parent: 1
references:
  "1": 6d222e2b-71b2-42ca-9e26-231b4726a946
  "2": aae1042d-6942-47bc-8470-5d7ac9ca8bc6
createdAt: 2026-01-15T01:45:08.558Z
updatedAt: 2026-01-15T01:45:08.561Z
tasks: []
tags: []
---

Implement the core actions for managing review state on files.

## Actions Required

### Mark File as Reviewed
- Mark the currently selected/viewed file as reviewed
- Store the file path and its current git blob hash in the review storage
- Update the file panel to reflect the new reviewed state

### Mark All Files as Reviewed
- Mark all files in the current diff view as reviewed
- Useful when you've gone through everything and want to mark it all at once

### Clear File Review State
- Remove the review state for a specific file
- The file will appear as "unreviewed" again

## Integration Points
- These actions should be available as commands that can be bound to keys (see plan 5)
- They should update the file panel display (see plan 3)
- They interact with the storage system (see plan 2)
