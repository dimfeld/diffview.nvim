---
# yaml-language-server: $schema=https://raw.githubusercontent.com/dimfeld/llmutils/main/schema/rmplan-plan-schema.json
title: render reviewed state in file panel
goal: ""
id: 3
uuid: 2445aa72-8e05-43bf-afdb-3c1e4b508db8
status: pending
priority: medium
dependencies:
  - 6
parent: 1
references:
  "1": 6d222e2b-71b2-42ca-9e26-231b4726a946
  "6": 7b6950a9-0254-43a1-9590-9d8a0e509bd4
createdAt: 2026-01-15T00:26:07.713Z
updatedAt: 2026-01-15T00:26:07.715Z
tasks: []
tags: []
---

In the File panel on the left, we want to be able to mark a file as:
- Unreviewed
- Changed since last review
- Reviewed

This should be just a single colored character or icon to indicate the state.
