# Mercantis CLI

The `mercantis` CLI is the developer tool for managing Mercantis app manifests, installations, and data patches.

## Prerequisites

- macOS 14+
- Swift 5.9+

## Installation

From the repository root:

```bash
swift build -c release
cp .build/release/mercantis /usr/local/bin/mercantis
```

## Commands

### `mercantis new-app`

Interactively scaffold a new app manifest and app folder structure.

```bash
mercantis new-app
```

### `mercantis install-app`

Install a manifest into a Mercantis SQLite database.

```bash
mercantis install-app manifest.json --db-path ./mercantis.sqlite
```

### `mercantis migrate`

Run all pending patches from `patches.json`.

```bash
mercantis migrate --db-path ./mercantis.sqlite --patches-dir ./patches
```

### `mercantis create-patch`

Interactively scaffold a new patch descriptor and append it to `patches.json`.

```bash
mercantis create-patch
```

### `mercantis run-patch`

Run one patch by name.

```bash
mercantis run-patch 001_initial_seed --db-path ./mercantis.sqlite
```

### `mercantis list-apps`

List all installed apps from the database.

```bash
mercantis list-apps --db-path ./mercantis.sqlite
```
