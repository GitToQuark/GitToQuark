---
name: GitToQuark
version: 0.0.1
description: GitToQuark - Automated assistant for saving GitHub repository contents to Quark Cloud Drive. Supports Release asset download and source code archive download with automatic geolocation-based proxy routing for CN users. Trigger when user wants to save/download GitHub repo files, releases, or source code to Quark Cloud Drive.
---

# GitToQuark Skill

Automated assistant for saving GitHub repository contents to Quark Cloud Drive. Supports both Release asset download and source code archive download with automatic geolocation-based proxy routing for CN users.

## Global Execution Order (Must Not Be Reordered)

IP Detection → Auth Health Check (skip install if authorized) → Parse Input → Determine Mode → Download → Upload → Cleanup

## Prerequisites

This skill bundles its own Quark Cloud Drive CLI wrapper under `scripts/` (`quark-drive.cjs`, `hash-worker.cjs`, `install.sh`, `uninstall.sh`). It is a thin wrapper around the official Quark Cloud Drive API; **no runtime download is required** — the wrapper ships with the skill. Credentials are stored locally under `~/.quarkclouddrive/` after authorization.

- The helper files `scripts/quark-drive.cjs` and `scripts/install.sh` are included in this repository. They are NOT fetched at runtime.
- `bash scripts/install.sh` performs an environment + CLI availability check ONLY (Node.js >= 16, `scripts/quark-drive.cjs` present). It never downloads files and never modifies `SKILL.md` / `references/`. Safe to run repeatedly; it no-ops when everything is already in place.
- Run `bash scripts/install.sh` once before first use, or whenever you see a "scripts missing / CLI unavailable" error. Do NOT run it before every command.

## Step 1: Geolocation Detection (Highest Priority, Must Execute First)

At the start of every session, immediately execute:

```bash
curl -s --max-time 10 https://ipinfo.io/json || curl -s --max-time 10 https://ipapi.co/json
```

Set the global `USE_PROXY` flag:
- `country == "CN"` → `USE_PROXY=true`. Prefix **file/archive downloads** (e.g. `github.com/.../archive/...`, asset `browser_download_url`) with proxy nodes in order: `https://gh-proxy.com/`, fallback `https://ghproxy.net/`, fallback `https://v6.gh-proxy.org/`. **API requests to `api.github.com` MUST be direct (no proxy prefix)** — proxying them triggers GitHub rate limiting.
- `country != "CN"` → `USE_PROXY=false`. Use direct original addresses.
- Detection failure (both sources fail) → Default to `true` and warn: "IP detection failed, proxy conservatively enabled."

Critical: Geolocation MUST be determined before any GitHub request. Never curl github.com before detection.

## Step 2: Check Quark Cloud Drive Skill Auth Status

Run health check:

```bash
node scripts/quark-drive.cjs get-user-info --session-input "<user's original question>" --session-id "<timestamp>-<random>"
```

- Returns `code:0`: Already authorized. Credentials valid. Proceed to Step 3.
- Returns `code:-103` (not logged in) / file missing: Not authorized or wrapper missing. Enter installation flow.

### Installation Flow (Only When Unauthorized)

The Quark CLI wrapper (`scripts/quark-drive.cjs`) is bundled with this skill, so there is no download step. Just verify the environment, then authorize.

1. Environment check (safe, no download, never overwrites docs):
```bash
bash scripts/install.sh
```
   Confirm it prints "Environment ready" and `node scripts/quark-drive.cjs --version` succeeds.

2. Authorize via the authorization-code flow (no cookie-based login):
   a. Run `node scripts/quark-drive.cjs login --session-input "<user's original question>" --session-id "<timestamp>-<random>"` to start the flow.
   b. Open the returned authorization link in a browser and complete login to obtain the code/token.
   c. Run `node scripts/quark-drive.cjs login --token <token> --session-input "<user's original question>" --session-id "<timestamp>-<random>"` to finish.
   Credentials persist to `~/.quarkclouddrive/`. Agent MUST NOT read, print, or cache plaintext tokens/cookies.

3. After authorization, run `get-user-info` again to confirm `code:0`. Never repeat this flow thereafter.

## Step 3: Parse User Input

Supports direct GitHub URL paste. Auto-extract `owner` and `repo`:
- `https://github.com/owner/repo` (sub-paths like `/tree/`, `/issues/`, `/releases` are truncated automatically)
- `owner/repo` short format

Parse failure → Prompt: "Cannot identify repository. Please provide \"owner/repo\" or a full github.com URL."

### Mode Determination

User Expression Mode Behavior
- Contains "software/package/release/installer/executable/download latest" → Release Mode: Fetch latest Release assets, match installer
- Contains "source code/zip/tar.gz/entire project" → Source Mode: Download repository source archive
- Only URL, no additional description → Source Mode (Default)

## Step 4: Release Mode

1. GET `https://api.github.com/repos/{owner}/{repo}/releases/latest` (API request — DIRECT, no proxy prefix).
2. Use "tag_name" as version. Iterate "assets" and match by OS:
   - Windows: `-windows-`, `-win-`, `.exe`, `.msi`
   - macOS: `-mac-`, `-darwin-`, `.dmg`, `.pkg`
   - Linux: `-linux-`, `.AppImage`, `.deb`, `.rpm`
3. Multiple hits → pick largest by "size". No match → list all asset names for user selection.
4. Default path: `GitHub Software/{repo}/{tag_name}/{targetOs}/{filename}`. If "customPath" given → `{customPath}/{repo}/{tag_name}/{targetOs}/{filename}`.

## Step 5: Source Mode

1. GET `https://api.github.com/repos/{owner}/{repo}` to get "default_branch" (main/master) (API request — DIRECT, no proxy prefix).
2. Download: `{prefix}https://github.com/{owner}/{repo}/archive/refs/heads/{default_branch}.zip`, filename `{repo}-{default_branch}.zip`.
3. Default path: `GitHub Project/{repo}/Source Code/{repo}-{default_branch}.zip`. If "customPath" given → `{customPath}/{repo}/Source Code/...`
4. Only use `git clone --mirror` + `tar` when user explicitly requests "full history / complete repo". Default is OFF.

## Step 6: Download

```bash
curl -L -o "{temp_dir}/{filename}" "{full_download_URL}"
```

- When `USE_PROXY=true`, prefix the **file download URL** (source archive or release asset `browser_download_url`) with the proxy node. API requests (`api.github.com`) must stay direct.

- Pre-check disk space with `df` ≥ size*1.2 before download.
- Large files (>100MB): output progress. After completion, compare actual size with API "size" field.
- Download failure: CN environment → check proxy first, then origin link.

## Step 7: Upload

- Create remote directory if missing. Do NOT pass "--parent-fid 0"; let CLI use default behavior.
- Upload completion summary: Mode / Repo / Version or Branch / Filename / Full Remote Path.
- If "keep_temp_files=false" (default), remove temp file after upload. Deletion failure → warn only.

## Error Table

| Scenario | Handling |
|----------|----------|
| Repo not found (404) | Check spelling |
| No Release Inform | none available (Release Mode only) |
| No matching OS | List all assets for selection |
| Download failure | Network/proxy issue |
| Upload failure | Check CLI login status and cloud drive space |
| API 403 | Rate limit, retry later |
| Proxy 503 | Switch to fallback node |
| default_branch unavailable | Try "main", then "master" |
| Skill install failure | Check proxy and version resolution |
| Unrecognized Agent environment (-104) | The CLI auto-detects the agent channel (e.g. WorkBuddy → `QK_AGENT_ID=workbuddy`). If -104 occurs, ensure the agent runtime exposes its channel id; OpenClaw-based agents inject `OPENCLAW_SERVICE_MARKER=openclaw`. Then run `resolve-agent` self-check to confirm `QK_AGENT_ID` is recognized |

## Scope

Currently supports latest Release and default branch source only. No support for: specific version / batch / private repo / submodule recursion. When user requests out-of-scope features, clearly state unsupported and mention roadmap.

## CLI Invocation Rules

When invoking the Quark Cloud Drive CLI (`node scripts/quark-drive.cjs`):

- Must include `--session-input` parameter with the user's original question text (verbatim, no rewriting)
- Must include `--session-id` parameter in format `{timestamp}-{random}` (e.g., `1784035443-a1b2c3`), generated on first CLI call and reused throughout the conversation
- Run `bash scripts/install.sh` only on first use or when a "scripts missing / CLI unavailable" error appears. Do NOT run it before every command.
- If the CLI returns an Agent whitelist error (-104, "cannot identify Agent environment"), the agent channel was not recognized. The CLI auto-detects the agent channel (e.g. WorkBuddy → `QK_AGENT_ID=workbuddy`); OpenClaw-based agents should inject `OPENCLAW_SERVICE_MARKER=openclaw`. Then run `resolve-agent` self-check to confirm `QK_AGENT_ID` is recognized. Example: `OPENCLAW_SERVICE_MARKER=openclaw node scripts/quark-drive.cjs resolve-agent --session-input "<user's original question>" --session-id "<timestamp>-<random>"`
- When user has not specified a target directory, do NOT pass `--parent-fid` or `--to-pdir-fid` parameters; let CLI use default behavior
- Do NOT pass `--parent-fid 0` unless user explicitly requests upload to root directory
- Agent MUST NOT read, print, or cache plaintext tokens/cookies from config files

### CLI Commands Used by This Skill

| Command | Purpose |
|---------|---------|
| `login` | Authorize Quark Cloud Drive (OAuth in browser); `login --token <token>` to finish |
| `get-user-info` | Auth health check — `code:0` when authorized, `code:-103` when not logged in |
| `upload` | Upload local file/folder; `--parent-fid <fid>` sets the target directory |
| `create-folder` | Create remote folder; `--dir-path <path>` (supports nested), `--parent-fid <fid>` |
| `resolve-agent` | Output the current agent channel id (`QK_AGENT_ID`), e.g. `workbuddy` |
| `search` / `share` / `saveas` / `summary` / `qa` | Other available commands — see `node scripts/quark-drive.cjs --help` |
