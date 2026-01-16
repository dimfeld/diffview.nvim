---
# yaml-language-server: $schema=https://raw.githubusercontent.com/dimfeld/llmutils/main/schema/rmplan-plan-schema.json
title: improve performance
goal: ""
id: 10
uuid: dca45387-91d3-4317-aacc-04ffc5128ec2
status: pending
priority: medium
createdAt: 2026-01-16T20:45:24.179Z
updatedAt: 2026-01-16T20:45:24.179Z
tasks: []
tags: []
---

The new review feature is fairly slow at some points. Need to do some profiling to see if that's related to a lot of Git operations or the JSON handling or just a lot of spawning processes. Then probably batch things where possible to speed it up and make it more responsive.
