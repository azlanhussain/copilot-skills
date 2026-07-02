---
name: openqc-run
description: >-
    Execute an OpenQC test plan automatically using Playwright (UI), MySQL (DB checks),
    and pdfplumber (PDF content). Fills in PASS/FAIL results and embeds screenshots into
    openqc/qc-<timestamp>/task.md. Automatically re-runs PENDING and FAILED tests — skips
    PASS. Use when the user wants to run or re-run QC tests from a prepared task.md file.
user-invocable: true
---

# OpenQC — Run

When invoked, follow these steps exactly.

---

## Step 0 — Pre-flight checks

### 0.1 Locate QC run folder and read environment mode

Find most recent QC run:
```
ls -dt <project-root>/openqc/qc-*/ | head -1
```

Read `task.md` and extract:
- `**Login Password:**` → store as `DEV_PASSWORD`
- `**Branch:**` → store as `QC_BRANCH`
- `**Environment:**` → determine mode:
  - If `single-folder` → `CONTAINER_FOLDER = WORKTREE_FOLDER = project-root`
  - If `worktree — <path>` → `CONTAINER_FOLDER = <path>`, `WORKTREE_FOLDER = project-root`

If `**Environment:**` line is missing, run:
```
git worktree list
```
- 1 entry → single-folder mode
- 2+ entries → ask user for `CONTAINER_FOLDER`

---

### 0.2 Playwright local install + Chromium

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

---

### 0.3 pdfplumber
```
python3 -c "import pdfplumber; print('ok')" 2>/dev/null || echo "NOT_FOUND"
```
If not found: `pip3 install pdfplumber`. **Stop and wait.**

---

### 0.4 Vagrant VM reachable
```
curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://<VM_IP>
```
If not 200/302: ask user to run `vagrant up`. **Stop and wait.**

---

### 0.5 DB accessible

> **Discover credentials:** Check `docker/docker-compose.yml` or `.env` in the project for `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DATABASE`. Replace `<DB_USER>`, `<DB_PASS>`, `<DB_NAME>` accordingly. For `<VM_IP>`, check `Vagrantfile` or ask the user.

```
cd <CONTAINER_FOLDER> && vagrant ssh -c 'cd /vagrant/docker && docker-compose exec -T mysql mysql -u <DB_USER> -p<DB_PASS> <DB_NAME> -e "SELECT 1"' 2>/dev/null | grep -v Warning
```

---

### 0.6 Worktree mode only — branch sync + code deploy

*Skip entirely in single-folder mode.*

**Step A — Branch check:**
```
cd <CONTAINER_FOLDER> && git branch --show-current
```
If differs from `QC_BRANCH`:
> ⚠️ Container folder is on branch `<X>` but QC was prepared on `<QC_BRANCH>`. Allow me to run `git checkout . && git checkout <QC_BRANCH>` in `<CONTAINER_FOLDER>`?

Wait for approval before continuing.

**Step B — Sync worktree code to container (always, not just on mismatch):**

This guarantees the test environment serves the latest worktree code.

First check if `~/run-checks.sh` exists:
```
ls ~/run-checks.sh 2>/dev/null || echo "NOT_FOUND"
```

- **If found:** use it — it syncs files, runs cs-check, stan, and npm build in one step:
  ```
  ~/run-checks.sh <WORKTREE_FOLDER> <CONTAINER_FOLDER>
  ```
  If it exits with `__BRANCH_MISMATCH__`, fix the branch (Step A) and re-run.

- **If not found:** sync manually using rsync (copy changed PHP/template/config files):
  ```
  rsync -av --delete \
    --exclude='.git' \
    --exclude='vendor/' \
    --exclude='node_modules/' \
    --exclude='tmp/' \
    --exclude='logs/' \
    <WORKTREE_FOLDER>/app/ <CONTAINER_FOLDER>/app/
  ```
  Then build frontend manually:
  ```
  cd <WORKTREE_FOLDER>/frontend && npm run build
  ```
  If `rsync` is also not available, ask the user:
  > ⚠️ Neither `~/run-checks.sh` nor `rsync` is available. How would you like to sync the code to the container folder before testing?

**Step C — Verify container has the latest code:**
```
curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://<VM_IP>/login
```
Should return 200. If 500/404, the sync may have failed — inspect and retry.

---

### 0.7 CSRF cookie check (critical for login over HTTP)

Check CSRF middleware config:
```
grep -A5 "CsrfProtectionMiddleware" <CONTAINER_FOLDER>/app/config/routes.php 2>/dev/null || \
grep -rA5 "CsrfProtectionMiddleware" <CONTAINER_FOLDER>/app/config/ 2>/dev/null | head -10
```

If `'secure' => true` found:
> ⚠️ CSRF middleware has `secure => true`. This prevents Playwright from logging in over HTTP — the browser won't send back the cookie set with the `Secure` flag.
>
> Please change it to `'secure' => false` in the CSRF middleware config, then:
> - **Worktree mode:** sync the file to `<CONTAINER_FOLDER>`
> - **Single-folder mode:** the change takes effect immediately

Verify fix:
```
curl -sv http://<VM_IP>/login 2>&1 | grep -i "set-cookie.*csrfToken"
```
Confirm `csrfToken` cookie does NOT contain `; secure`.

In worktree mode, also confirm the container folder has the updated file:
```
grep "secure" <CONTAINER_FOLDER>/app/config/routes.php
```
If still `secure => true`, copy it:
```
cp <WORKTREE_FOLDER>/app/config/routes.php <CONTAINER_FOLDER>/app/config/routes.php
```

---

### 0.8 Verify app serves correctly

```
curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://<VM_IP>/login
```
Should return 200. If 500/404 → container likely missing latest code. Re-run sync.

Only continue when **all checks pass**.

---

## Step 1 — Parse task.md

Extract all test cases with status `⬜ PENDING` or `❌ FAIL`. For each:
- Test ID, URL, login email, actions, expected values (UI, DB columns, PDF cells, filename patterns)

Skip tests already marked `✅ PASS` or `⚠️ SKIP`.

> ℹ️ `❌ FAIL` tests are **automatically re-run** — no need to manually reset them to `⬜ PENDING`.
> This means after fixing a bug, just run `openqc-run` again and it will re-test all failed cases.

Tell user: `"Running N tests (X pending + Y failed) from openqc/qc-<timestamp>/..."`

---

## Step 2 — Write Playwright runner

Write `/tmp/openqc-playwright/runner.js` tailored to parsed test cases.

### Critical rules:
- **`headless: true` always** — terminal has no display
- **`waitUntil: 'domcontentloaded'`** for all `page.goto()` — `networkidle` can hang
- **Login with `waitForURL`**:
  ```javascript
  async function login(page, email, password) {
    await page.goto(BASE_URL + '/login', { waitUntil: 'domcontentloaded' });
    await page.waitForSelector('input[name="email"]', { timeout: 10000 });
    await page.fill('input[name="email"]', email);
    await page.fill('input[name="password"]', password);
    await Promise.all([
      page.waitForURL(url => !url.toString().includes('/login'), { timeout: 15000 }),
      page.click('button[type="submit"]')
    ]);
  }
  ```
- **One browser context per unique login** — reuse sessions across tests
- **Count only non-blank dropdown options**:
  ```javascript
  const options = await page.locator('select option[value]:not([value=""])').allTextContents();
  ```
- **Screenshots always** (even on failure):
  ```javascript
  await page.screenshot({ path: SCREENSHOT_DIR + '/<id>.png', fullPage: true });
  ```
- **Download pattern**:
  ```javascript
  const [dl] = await Promise.all([
    page.waitForEvent('download', { timeout: 30000 }),
    page.click('button[type="submit"]')
  ]);
  const dlPath = DOWNLOAD_DIR + '/<id>-' + Date.now() + '.pdf';
  await dl.saveAs(dlPath);
  ```
- **Wrap each test in try/catch** — one failure must not stop others
- **Output JSON array to stdout** at end only

---

## Step 3 — Run Playwright

```
mkdir -p /tmp/openqc-downloads
cd /tmp/openqc-playwright && node runner.js 2>/tmp/openqc-runner.log
```

If non-zero exit, read log. Common causes:
- Login failed → CSRF `secure` flag (Step 0.7)
- Browser not found → `npx playwright install chromium`
- 404/500 → container missing latest code, re-sync

---

## Step 4 — DB checks

For tests with **Expected DB** sections:
```
cd <CONTAINER_FOLDER> && vagrant ssh -c 'cd /vagrant/docker && docker-compose exec -T mysql mysql -u <DB_USER> -p<DB_PASS> <DB_NAME> -e "SELECT ..."' 2>/dev/null | grep -v Warning
```
Compare actual vs expected. Record pass/fail.

---

## Step 5 — PDF checks

For each downloaded PDF, write `/tmp/openqc-pdf-check.py`:

```python
import pdfplumber, json, sys

def find_near(words, x0_range, top_range):
    return ' '.join(w['text'] for w in words
                    if x0_range[0] <= w['x0'] <= x0_range[1]
                    and top_range[0] <= w['top'] <= top_range[1])
```

**On first run for a new template** — calibrate positions by dumping all words:
```python
with pdfplumber.open(pdf_path) as pdf:
    for w in pdf.pages[0].extract_words():
        print(f"x0={w['x0']:.1f} top={w['top']:.1f}  {w['text']}")
```
Identify x0/top ranges from output. Store calibrated ranges for reuse.

**For this project's payment statement template:**
- B2 (year label): x0=(50,130), top=(35,48)
- H3 (address): x0=(130,280), top=(60,70)
- H4 (name): x0=(130,280), top=(80,92)
- P7 (total amount): x0=(360,430), top=(125,135)
- Y7 (withholding): x0=(490,580), top=(125,135)

If positions cannot be reliably matched → mark `⚠️ MANUAL`.

---

## Step 6 — Update task.md

For each test:
- Replace `⬜ PENDING` → `✅ PASS`, `❌ FAIL`, or `⚠️ SKIP`
- Replace `<!-- screenshot will be inserted here by openqc-run -->` with:
  ```markdown
  ![<id>](screenshot/<id>.png)
  ```
- For FAIL append:
  ```markdown
  > ❌ **Failure:** expected X, got Y
  ```
- For PDF tests append:
  ```markdown
  > 📄 **Filename:** `<filename>`
  > **PDF cells:** B2=令和7年分 ✅ | P7=2,727 ✅ | Y7=92 ✅
  ```

**Never mark PASS unless all sub-checks passed. Never modify Expected sections.**

---

## Step 7 — Final summary

Print summary table. List any failures with suggested next steps.

---

## Important rules

- **headless: true** always in CLI context
- **CSRF `secure` flag** is the most common login blocker — check it proactively
- **Worktree sync** only needed in worktree mode — skip in single-folder mode
- **Screenshots always taken** even on failure
- **Blank options excluded** from dropdown counts
- **PDF positions are template-specific** — calibrate once, reuse
- **Login password read from task.md** — never hardcode or guess
