---
# yaml-language-server: $schema=https://raw.githubusercontent.com/dimfeld/llmutils/main/schema/rmplan-plan-schema.json
title: Navigation commands for review mode
goal: ""
id: 7
uuid: 9ce60301-7529-43d4-a46d-27c75a43f4d8
status: pending
priority: medium
dependencies:
  - 3
parent: 1
references:
  "1": 6d222e2b-71b2-42ca-9e26-231b4726a946
  "3": 2445aa72-8e05-43bf-afdb-3c1e4b508db8
createdAt: 2026-01-15T01:45:14.237Z
updatedAt: 2026-01-15T01:45:14.240Z
tasks: []
tags: []
---

Implement navigation commands to quickly move between files based on their review state.

## Navigation Commands

### Jump to Next/Previous Unreviewed File
- Navigate to the next file that has not been marked as reviewed
- Navigate to the previous file that has not been marked as reviewed
- Should wrap around at the end/beginning of the file list

### Jump to Next/Previous Changed-Since-Review File
- Navigate to the next file that was previously reviewed but has changed since
- Navigate to the previous file that was previously reviewed but has changed since
- These files have a different status than "unreviewed" (see plan 3)

## Behavior Notes
- Navigation should select the file in the file panel and open it in the diff view
- Should follow existing diffview navigation patterns for consistency
- Consider what happens when there are no matching files (show message? stay in place?)
