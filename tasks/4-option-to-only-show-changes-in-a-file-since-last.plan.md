---
# yaml-language-server: $schema=https://raw.githubusercontent.com/dimfeld/llmutils/main/schema/rmplan-plan-schema.json
title: option to only show changes in a file since last marked reviewed
goal: ""
id: 4
uuid: 0b764a53-420b-410c-8e39-5e5688e97542
status: pending
priority: medium
dependencies:
  - 7
parent: 1
references:
  "1": 6d222e2b-71b2-42ca-9e26-231b4726a946
  "7": 9ce60301-7529-43d4-a46d-27c75a43f4d8
createdAt: 2026-01-15T00:26:26.637Z
updatedAt: 2026-01-15T00:26:26.640Z
tasks: []
tags: []
---

When viewing a diff, there should be an option to have the diff view show only:
1. Files that have changed since they were last marked reviewed
2. Files that have not been reviewed yet

At the same time, we should be able to toggle the view itself, so that if there is a previous review, we only show changes since the change where the file was last marked reviewed.
