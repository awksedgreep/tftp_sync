# tftp_sync Project Plan

Standalone Elixir project `tftp_sync` providing a directory-to-DDNet TFTP API sync agent, similar to the existing Python `tools/tftp_sync.py`, but implemented as an OTP application and escript.

- **App name:** `tftp_sync`
- **Main module:** `TftpSync`
- **Deployment model:** escript binary run under `systemd` (or similar)
- **Primary responsibility:** Keep a local directory of TFTP firmware/config files in sync with the DDNet TFTP API (`/api/tftp/files` + `/api/tftp/stats`).

---

## TFTP File Management API (DDNet)

This section documents the DDNet TFTP API surface that the external `tftp_sync` project is expected to call. It is self-contained so the external project does **not** need a checkout of this repository.

All endpoints are relative to the DDNet base URL, e.g. `http://ddnet-host:4000`.

### 1. Service Stats / Connectivity Check

**Endpoint**

```text
GET /api/tftp/stats
```

**Purpose**

- Verify that the DDNet TFTP service is reachable.
- Retrieve high-level statistics about stored files.

**Successful response (200)**

Example JSON (fields may be extended over time; existing ones are stable):

```json
{
  "total_files": 123,
  "active_files": 120,
  "inactive_files": 3,
  "total_size_bytes": 123456789,
  "total_size_mb": 117.77,
  "large_files_count": 4,
  "content_type_distribution": {
    "application/octet-stream": 80,
    "text/plain": 40
  },
  "tag_distribution": {
    "firmware": 30,
    "config": 10
  },
  "database_direct_access": true,
  "service_type": "database_direct"
}
```

The external `tftp_sync` tool generally only needs `total_files` to log a friendly message.

### 2. List Files

**Endpoint**

```text
GET /api/tftp/files
```

**Purpose**

- Obtain the current set of files in the TFTP store with metadata.
- Used by sync tools to compute differences between local directory and server state.

**Query parameters (optional)**

- `active` – `true` or `false` to filter by active status.
- `tag` – filter by tag string.
- `search` – case-insensitive search in filename/description.

**Successful response (200)**

```json
{
  "files": [
    {
      "filename": "firmware/modem-x/v1.2.3.bin",
      "size": 12345678,
      "content_type": "application/octet-stream",
      "description": "Optional human description",
      "tags": ["firmware", "modem-x"],
      "is_active": true,
      "uploaded_at": "2025-07-24T17:42:34.000000Z",
      "updated_at": "2025-07-24T17:42:34.000000Z"
    }
    // ... more files
  ],
  "total": 42
}
```

External tools typically use `files[*].filename` and `files[*].size`, and may read `is_active` for reporting.

### 3. Get File Details

**Endpoint**

```text
GET /api/tftp/files/:filename
```

Where `:filename` is URL-encoded and matches the stored filename (e.g. `firmware/modem-x/v1.2.3.bin`).

**Successful response (200)**

```json
{
  "file": {
    "filename": "firmware/modem-x/v1.2.3.bin",
    "size": 12345678,
    "content_type": "application/octet-stream",
    "description": "Optional human description",
    "tags": ["firmware", "modem-x"],
    "is_active": true,
    "uploaded_at": "2025-07-24T17:42:34.000000Z",
    "updated_at": "2025-07-24T17:42:34.000000Z"
  }
}
```

**Not found (404)**

```json
{"error": "File not found"}
```

### 4. Upload / Upsert File

**Endpoint**

```text
POST /api/tftp/files
```

**Content-Type**

- `multipart/form-data`

**Form fields**

- `file` (required)
  - Binary file upload part.
- `filename` (optional)
  - Override for stored filename.
  - If omitted, the uploaded filename is used.
- `description` (optional)
  - String description.
- `tags` (optional)
  - Comma-separated list, e.g. `"firmware,modem-x"`.
- `content_type` (optional)
  - MIME type override. If omitted, server detects from filename/content.
- `is_active` (optional)
  - String `"true"` or `"false"`. If omitted, defaults to `true`.

**Successful response (201 Created)**

```json
{
  "success": true,
  "message": "File uploaded successfully",
  "file": {
    "filename": "firmware/modem-x/v1.2.3.bin",
    "size": 12345678,
    "content_type": "application/octet-stream",
    "description": "Optional human description",
    "tags": ["firmware", "modem-x"],
    "is_active": true,
    "uploaded_at": "2025-07-24T17:42:34.000000Z"
  }
}
```

**Validation error (400)**

- Missing file:

  ```json
  {"error": "No file provided in upload"}
  ```

- Invalid filename or other input errors:

  ```json
  {"error": "Upload error: ..."}
  ```

**File too large (413)**

If file exceeds the server-side maximum size (currently 200 MB), the server returns:

```json
{"error": "File too large (max 100MB)"}
```

> Note: the error message mentions 100MB, but the effective limit enforced by the service is 200 MB. Clients should treat any 413 as "file too large" regardless of message text.

### 5. Delete File

**Endpoint**

```text
DELETE /api/tftp/files/:filename
```

**Successful response (200)**

```json
{
  "success": true,
  "message": "File deleted successfully"
}
```

**Not found (404)**

```json
{"error": "File not found"}
```

### 6. Activate / Deactivate File

These endpoints toggle `is_active` for a given file.

**Activate**

```text
PUT /api/tftp/files/:filename/activate
```

**Deactivate**

```text
PUT /api/tftp/files/:filename/deactivate
```

**Successful response (200)**

```json
{
  "success": true,
  "message": "File activated"
}
```

or

```json
{
  "success": true,
  "message": "File deactivated"
}
```

**Not found (404)**

```json
{"error": "File not found"}
```

External `tftp_sync` tools do not *need* to call activate/deactivate for basic mirroring, but they may choose to expose this as a management operation or policy decision (e.g. marking certain files inactive instead of deleting them).

---

## Phase 1: Minimal Escript with One-shot Sync

**Goal:** Reproduce the basic behavior of the Python script's initial sync in Elixir, without directory watching.

### Scope

- Create a new Mix project `tftp_sync` (outside ddnet repo):
  - `mix new tftp_sync --sup`
  - Application module: `TftpSync.Application` (standard supervision tree).
- Configure **escript** support:
  - In `mix.exs`:
    - `escript: [main_module: TftpSync.CLI]`.
- Implement `TftpSync.CLI`:
  - `main/1` parses CLI args:
    - `source_dir` (local directory to sync).
    - `api_url` (e.g. `http://ddnet-host:4000`).
    - Flags similar to Python version:
      - `--once` (do initial sync and exit).
      - `--no-initial-sync` (watch only, for later phases).
      - `--exclude` patterns (optional, for later phases).
  - Validates arguments and prints helpful usage on error.
- Implement **HTTP client** abstraction:
  - Simple wrapper module, e.g. `TftpSync.Http` using `:req` or `Finch`:
    - `get_files/1` → `GET /api/tftp/files` (returns list of `%{"filename" => ...}` maps).
    - `upload_file/3` → `POST /api/tftp/files` (multipart).
    - `delete_file/2` → `DELETE /api/tftp/files/:filename`.
    - `test_connection/1` → `GET /api/tftp/stats` (for startup check).
- Implement **one-shot sync** module, e.g. `TftpSync.Sync`:
  - Reads local directory tree (recursive) from `source_dir`.
  - Applies exclusion patterns (basic glob or substring match).
  - Builds set of local filenames in DDNet format (slashes, relative to root).
  - Fetches existing files from server via `get_files/1`.
  - Computes:
    - Files that are new/changed → upload.
    - Files that exist on server but not locally → delete (optional, configurable).
  - For Phase 1, "changed" detection can be **simplified** to "always upload" (idempotent upserts on the server side) for correctness over optimization.
- Logging:
  - Use `Logger` to log actions (uploaded, deleted, errors) in a similar style to Python tool.

### Deliverables

- `tftp_sync` Mix project with:
  - `TftpSync.CLI` (escript entrypoint).
  - `TftpSync.Http` (API client).
  - `TftpSync.Sync` (one-shot sync logic).
- Working escript:
  - `MIX_ENV=prod mix escript.build`
  - Usage:

    ```bash
    ./tftp_sync /var/tftpboot http://localhost:4000 --once
    ```

- Verified manually against DDNet dev instance.

---

## Phase 2: Directory Watching and Continuous Sync

**Goal:** Add file system watching so the agent can run as a long-lived process, reacting to file changes in near real time.

### Scope

- Add dependency on `:file_system` for cross-platform directory watching.
- Implement `TftpSync.Watcher` as a GenServer:
  - Starts `FileSystem` watcher in `init/1`:

    ```elixir
    {:ok, watcher_pid} = FileSystem.start_link(dirs: [source_dir])
    FileSystem.subscribe(watcher_pid)
    ```

  - Handles messages:

    ```elixir
    def handle_info({_pid, {:fs, :file_event}, {path, events}}, state) do
      # Ignore directories and excluded patterns
      # Normalize to relative filename
      # Delegate to TftpSync.Sync for single-file upload/delete
    end
    ```

  - Maintains configuration in state:
    - `source_dir`
    - `api_url`
    - `excluded_patterns`
- Extend `TftpSync.CLI`:
  - `--once` → do Phase 1 one-shot sync then stop.
  - Default mode:
    - Optionally run initial sync.
    - Start supervision tree with `TftpSync.Watcher` + HTTP client resources.
    - Block until process receives SIGTERM/SIGINT (from systemd or Ctrl+C).
- Implement **single-file operations** in `TftpSync.Sync`:
  - `sync_file(path)` → upload one file based on relative path.
  - `delete_file(path)` → delete one file on server.
- Ensure **debounce/backoff** behavior:
  - Avoid thrashing when editors write temp files.
  - Simple approach: ignore hidden files and common temp extensions by default (`.swp`, `.tmp`, etc.).

### Deliverables

- `TftpSync.Watcher` GenServer wired into the supervision tree.
- CLI behavior:
  - `./tftp_sync /var/tftpboot http://ddnet:4000` → initial sync + continuous watching.
  - `./tftp_sync /var/tftpboot http://ddnet:4000 --once` → one-shot only.

---

## Phase 3: Robustness, Observability, and Config

**Goal:** Make the agent production-friendly: safe error handling, retries, logging, and tuning knobs.

### Scope

- **Error handling and retries**:
  - Wrap HTTP calls with retry/backoff on transient errors.
  - Distinguish between client errors (400/404) and server/network errors.
  - Ensure watchers never crash on a single failure; log and continue.
- **Logging & metrics**:
  - Structured `Logger` metadata (filename, operation, status).
  - Optional stats endpoint (if later embedded into an OTP app) or logs only for now.
- **Configuration**:
  - Support environment variables in addition to CLI flags:
    - `TFTP_SYNC_SOURCE_DIR`
    - `TFTP_SYNC_API_URL`
    - `TFTP_SYNC_EXCLUDES`
  - Clarify precedence: CLI > env > defaults.
- **Safety features**:
  - Option flag to disable deletions (`--no-delete-remote`), so initial deployments cannot accidentally wipe server state.
  - Dry-run mode (`--dry-run`) to log intended actions without modifying server.

### Deliverables

- Hardened escript suitable for long-running use.
- Documented config behaviors and failure modes.

---

## Phase 4: Systemd Integration and Operations Guide

**Goal:** Provide a clean way for operators to run `tftp_sync` as a managed service alongside DDNet.

### Scope

- Write `systemd` unit template, e.g. `tftp_sync.service`:

  ```ini
  [Unit]
  Description=DDNet TFTP Sync Agent
  After=network-online.target

  [Service]
  ExecStart=/usr/local/bin/tftp_sync /var/tftpboot http://ddnet-host:4000
  WorkingDirectory=/var/tftpboot
  Restart=always
  RestartSec=5
  User=ddnet
  Group=ddnet

  [Install]
  WantedBy=multi-user.target
  ```

- Document rollout steps:
  - Build and install escript to `/usr/local/bin/tftp_sync`.
  - Create systemd unit and enable:

    ```bash
    systemctl daemon-reload
    systemctl enable tftp_sync
    systemctl start tftp_sync
    ```

  - How to view logs:

    ```bash
    journalctl -u tftp_sync -f
    ```

- Operational guidance:
  - Expected behavior on restart (no special state; re-syncs as needed).
  - How to safely change source dir or API URL.

### Deliverables

- `tftp_sync.service` example.
- Short operations guide (can live in the `tftp_sync` repo README).

---

## Phase 5: Future Enhancements (Optional)

Not required for initial deployment, but worth tracking:

- **Direct DB/Ash integration** (if ever desired):
  - Instead of calling the HTTP API, talk directly to `Tftp.FileService` or the underlying DB in a trusted environment.
  - Would require running inside the same BEAM cluster or with direct DB credentials.
- **Bidirectional sync / reconciliation**:
  - Today the model is "local dir is source of truth".
  - Could add modes where server changes (e.g. via UI) are synced back to filesystem.
- **Advanced filtering and rules**:
  - Tagging based on directory structure (e.g. auto-tag `firmware`, `config`).
  - Per-subtree configuration (different behaviors for different directories).

These can be added incrementally without changing the basic CLI and watcher structure.

---

## Notes on Alignment with Existing Python Tool

- The Elixir `tftp_sync` escript mirrors the current Python `tools/tftp_sync.py` behavior:
  - Initial full sync of a directory.
  - Continuous watch for add/modify/delete.
  - Interaction with DDNet strictly via the TFTP API.
- Key differences/benefits:
  - OTP-supervised watcher processes (resilience).
  - Single-beam deployment with strong observability/logging patterns.
  - Easier integration with other Elixir-based tooling in the future.
