---
name: swap-deps
description: Use when switching app.json dependencies between ForNAV e4 development mode and normal release mode in a Business Central AL extension project.
---

# swap-deps — ForNAV dependency switcher

Swap the `dependencies` array in `app.json` between **e4 development** and **normal release** mode.

## Steps

1. Read `app.json` from the current directory.
2. Detect current mode: if a dependency with id `d6978c22-4a2f-452a-8f12-efdcf158d7e4` is present → currently **e4**.
3. Replace the entire `dependencies` array with the target set (see below).
4. Write the updated `app.json`.
5. Report which mode you switched to.

## Dependency sets

**e4 (development):**
```json
[
  {
    "id": "d6978c22-4a2f-452a-8f12-efdcf158d7e4",
    "name": "ForNAV Core Development e4",
    "publisher": "ForNAV",
    "version": "8.2.0.0"
  }
]
```

**Normal (release):**
```json
[
  {
    "id": "f94c6dff-0118-4c1d-a7d4-382033529ed3",
    "name": "ForNAV Language Module",
    "publisher": "ForNAV",
    "version": "8.2.0.0"
  },
  {
    "id": "6f0293d3-86fc-4ff8-9632-54a580be6546",
    "name": "ForNAV Core",
    "publisher": "ForNAV",
    "version": "8.2.0.0"
  },
  {
    "id": "83326d6d-11f8-49fd-981a-6f266a7c8d81",
    "name": "Customizable Report Pack",
    "publisher": "ForNAV",
    "version": "8.2.0.0"
  }
]
```
