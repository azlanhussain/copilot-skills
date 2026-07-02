---
name: openqc-prepare
description: >-
    Prepare an OpenQC test plan in Markdown format. Queries the database for real test data,
    validates record states, and writes openqc/qc-<timestamp>/task.md with structured test
    cases ready for openqc-run to execute. Use when the user wants to prepare QC test cases
    for a feature or task. Accepts inline context e.g. "openqc-prepare ~/Desktop/task.txt"
    or "openqc-prepare read from branch changes and PR description".
user-invocable: true
---

# OpenQC — Prepare

When invoked, follow these steps exactly.

---

## Step 0 — Parse invocation context

Read the user's invocation message for inline instructions. Extract:

- **File path(s)** — any path like `~/Desktop/xxx.txt`, `./task.txt` etc. → read as ticket requirement
- **Keywords:**
  - `branch` / `diff` / `code changes` → include git diff as a source
  - `PR` / `pull request` → include PR description as a source
  - `ticket` + path → read that file as requirement source

If **nothing is provided**, auto-discover all available sources (see Step 1).

Examples of valid invocations:
```
openqc-prepare
openqc-prepare ~/Desktop/task-112662.txt
openqc-prepare read from branch code changes and PR description
openqc-prepare read from this branch code changes, PR description and ticket at ~/Desktop/task-112662.txt
```

---

## Step 1 — Gather QC scope from all available sources

Collect context from every source that is available or was specified. Use all that apply:

### Source A — Git diff (always run)
```
git diff main...HEAD --name-only
git diff main...HEAD --stat
```
From the changed files, infer:
- Which routes/pages are affected (changed controllers → test those URLs)
- Which UI elements changed (changed templates → test rendering)
- Which calculations changed (changed services/models → test output values)
- Which config changed (changed routes/middleware → test access control)

### Source B — PR description (if PR exists)
```
gh pr view --json title,body,number 2>/dev/null
```
If a PR exists, read `title` and `body` for feature summary and acceptance criteria.

### Source C — Ticket/task file (if path provided or auto-found)
If a path was provided in the invocation → read that file.
If no path provided → check common locations:
```
ls ~/Desktop/task-*.txt ~/Desktop/task-*.md 2>/dev/null | head -5
```
If found, ask user: "I found `<filename>` on the Desktop. Should I use this as the ticket requirement?"

Read and parse the task file for:
- Feature description
- Acceptance criteria
- Edge cases mentioned

### Source D — Existing PHPUnit tests (hints for edge cases)
```
git diff main...HEAD --name-only | grep -i "Controller\|Service\|Table" | sed 's|src/||;s|.php||'
```
For each changed class, check if a corresponding test exists in `tests/TestCase/`. If so, read it for edge case hints.

---

After gathering all sources, synthesise into a **QC scope summary**:
> "Based on the diff/PR/ticket, I will test: [list of pages/features/scenarios]"

Present this to the user before proceeding. If scope is unclear, ask one focused clarifying question.

---

## Step 2 — Pre-flight checks

### 2.1 Detect environment mode
```
git worktree list
```
- 1 entry → **single-folder mode**: `CONTAINER_FOLDER = WORKTREE_FOLDER = cwd`
- 2+ entries → **worktree mode**: ask user for `CONTAINER_FOLDER`

### 2.2 Playwright local install + Chromium
```
ls /tmp/openqc-playwright/node_modules/playwright 2>/dev/null || echo "NOT_FOUND"
```
If not found:
```
mkdir -p /tmp/openqc-playwright
echo '{"name":"openqc-runner","version":"1.0.0","dependencies":{"playwright":"latest"}}' > /tmp/openqc-playwright/package.json
cd /tmp/openqc-playwright && npm install --silent
```
Check Chromium:
```
cd /tmp/openqc-playwright && node -e "const {chromium}=require('playwright'); console.log(chromium.executablePath())" 2>/dev/null || echo "NOT_FOUND"
```
If not found: `cd /tmp/openqc-playwright && npx playwright install chromium`

### 2.3 pdfplumber
```
python3 -c "import pdfplumber; print('ok')" 2>/dev/null || echo "NOT_FOUND"
```
If not found: `pip3 install pdfplumber`. **Stop and wait.**

### 2.4 Vagrant VM reachable
```
curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://<VM_IP>
```
If not 200/302: ask user to run `vagrant up`. **Stop and wait.**

### 2.5 DB accessible

> **Discover credentials:** Check `docker/docker-compose.yml` or `.env` in the project for `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DATABASE`. Replace `<DB_USER>`, `<DB_PASS>`, `<DB_NAME>` accordingly. For `<VM_IP>`, check `Vagrantfile` or ask the user.

```
cd <CONTAINER_FOLDER> && vagrant ssh -c 'cd /vagrant/docker && docker-compose exec -T mysql mysql -u <DB_USER> -p<DB_PASS> <DB_NAME> -e "SELECT 1"' 2>/dev/null | grep -v Warning
```

### 2.6 Worktree mode only — branch sync
*Skip in single-folder mode.*

Check branch:
```
cd <CONTAINER_FOLDER> && git branch --show-current
```
If differs from current branch: offer `git checkout . && git checkout <branch>` in `CONTAINER_FOLDER`.

Then sync (always, not just on mismatch):
```
ls ~/run-checks.sh 2>/dev/null || echo "NOT_FOUND"
```
- If found: `~/run-checks.sh <WORKTREE_FOLDER> <CONTAINER_FOLDER>`
- If not found: use `rsync`:
  ```
  rsync -av --delete --exclude='.git' --exclude='vendor/' --exclude='node_modules/' --exclude='tmp/' --exclude='logs/' <WORKTREE_FOLDER>/app/ <CONTAINER_FOLDER>/app/
  cd <WORKTREE_FOLDER>/frontend && npm run build
  ```
- If neither available: ask user how to sync before proceeding.

### 2.7 openqc/ folder and .gitignore
```
mkdir -p <WORKTREE_FOLDER>/openqc
grep -q '^openqc/' <WORKTREE_FOLDER>/.gitignore || echo 'openqc/' >> <WORKTREE_FOLDER>/.gitignore
```

### 2.8 Login credentials

First, query the DB to identify which accounts will be used as test accounts for this feature.
Show the user the discovered accounts clearly:

> "I found the following accounts that will be used for testing:
> - `<email1>` (e.g. doctor with approved data)
> - `<email2>` (e.g. doctor with no data)
>
> What is the password for these accounts in your local environment?
> (If accounts have different passwords, please provide them one by one.)"

For each unique account, ask for its password if they differ.
Store as `DEV_PASSWORD` (or per-account if they differ).

---

## Step 3 — Query the DB for real test data

For each scenario identified in Step 1, query the DB to find real matching records.

**Never invent IDs or assume field values.**

DB command pattern:
```
cd <CONTAINER_FOLDER> && vagrant ssh -c 'cd /vagrant/docker && docker-compose exec -T mysql mysql -u <DB_USER> -p<DB_PASS> <DB_NAME> -e "YOUR SQL"' 2>/dev/null | grep -v Warning
```

For each record: confirm field values and locked/approved state.

---

## Step 4 — Create the QC run folder
```
TIMESTAMP=$(date +%Y%m%d%H%M%S)
BRANCH=$(git branch --show-current)
mkdir -p <WORKTREE_FOLDER>/openqc/qc-$TIMESTAMP/screenshot
```

---

## Step 5 — Write task.md

Write `<WORKTREE_FOLDER>/openqc/qc-<timestamp>/task.md`:

```markdown
# QC Test Plan — <Feature Name>

**Generated:** <YYYY-MM-DD HH:MM:SS>
**Branch:** <branch name>
**Ticket:** #<number> (or N/A)
**Base URL:** http://<VM_IP>
**Login Password:** `<DEV_PASSWORD>` (all dev accounts)
**Environment:** <single-folder | worktree — CONTAINER_FOLDER path>
**Sources:** <git diff | PR #N | ~/Desktop/task-xxx.txt>
**DB Query:** `cd <CONTAINER_FOLDER> && vagrant ssh -c '...'`

---

## Reference Data

| Entity | ID | Email | Type | Status |
|--------|----|-------|------|--------|

---

## Pre-conditions

> ⚠️ (setup steps if needed, otherwise "No setup required.")

---

## Group A — UI / Display

### A-1 · <Title>

**URL:** http://<VM_IP>/...
**Login:** <email>

> <Record ID> current state: field=value (confirmed from DB)

**Actions:**
1. ...

**Expected:**
- ✅ ...

**Result:** ⬜ PENDING

**Notes:**
<!-- screenshot will be inserted here by openqc-run -->
```

### Rules:
- Result: `⬜ PENDING` always
- Notes: `<!-- screenshot will be inserted here by openqc-run -->` always
- Test IDs: `A-1`, `B-2`, `C-3`
- Dropdown counts: non-blank options only
- PDF tests: list expected cell values explicitly

---

## Step 6 — Cross-check before saving

- URLs confirmed real from DB
- Current state matches DB values
- Actions make sense for the state
- Expected values consistent with scenario

---

## Step 7 — Confirm to user

> ✅ QC plan created at `openqc/qc-<timestamp>/task.md`
> - N test cases across X groups
> - Branch: <branch>
> - Sources used: <list>
> - Run `openqc-run` to execute all tests automatically

---

## Important rules

- **Never invent test data** — all confirmed from DB
- **All test cases in English**
- **Login password and environment recorded in task.md**
- **Non-blank options only** when counting dropdowns
- **Sources used recorded in task.md** — for traceability
