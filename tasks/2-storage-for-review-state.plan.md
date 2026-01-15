---
# yaml-language-server: $schema=https://raw.githubusercontent.com/dimfeld/llmutils/main/schema/rmplan-plan-schema.json
title: Storage for review state
goal: ""
id: 2
uuid: aae1042d-6942-47bc-8470-5d7ac9ca8bc6
status: pending
priority: medium
parent: 1
createdAt: 2026-01-15T00:25:49.542Z
updatedAt: 2026-01-15T00:25:49.544Z
tasks: []
tags: []
---

Create a system for storing entries about when a file was reviewed. Here we want to include something like:
- The repository directory
- The branch name
- The path to each file marked reviewed
- The hash of each file marked reviewed
- The last Git hash or jj change when the file was edited (if feasible)

The idea is that when a file is marked reviewed, we have a good idea of what its state was at that time.

This should be stored under ~/.cache/diffview.nvim/, and can use sqlite if that's convenient in Lua/neovim or just a set of files otherwise.
