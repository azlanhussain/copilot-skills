---
name: fix-review
description: >-
    Skill for handling GitHub Copilot review comments on a PR. Investigates each comment,
    assesses validity, applies fixes with individual commits, replies in-thread with commit
    SHA, and resolves the conversation. Use when the user asks to check or fix GitHub Copilot
    review comments.
user-invocable: true
---

# Fix GitHub Copilot Review Comments

When invoked, follow these steps exactly.

---

## Step 1 — Auto-detect the PR

Detect the current branch from the working directory:
```
git branch --show-current
```

Find the open PR for this branch:
```
gh pr list --repo <owner>/<repo> --head <branch> --json number,title,url
```

Present the detected PR to the user:
> "I detected PR #<number>: <title>. Is this the correct PR?"

**Wait for the user to confirm** before proceeding.

---

## Step 2 — Fetch GitHub Copilot review comments

Fetch all review comments on the PR:
```
gh api repos/<owner>/<repo>/pulls/<PR>/comments \
  --jq '[.[] | select(.user.login == "Copilot") | {id, body, path, line, pull_request_review_id}]'
```

Also check top-level review bodies (not inline):
```
gh api repos/<owner>/<repo>/pulls/<PR>/reviews \
  --jq '[.[] | select(.user.login == "Copilot") | {id, body, state}]'
```

List all comments found, numbered, with a one-line summary each.

---

## Step 3 — Investigate each comment

For every Copilot comment:

1. **Read the flagged code** — open the file at the indicated path and line using `view` or `grep`.
2. **Assess validity:**
   - **Valid** — genuine bug, security risk, incorrect usage, or missed edge case.
   - **Invalid** — already fixed by another commit, stylistic preference only, lacks business context, or is a false positive given the system design.
3. **State reasoning** clearly for each.

---

## Step 4 — Present investigation table

Show the full assessment **before doing any fixes**:

| # | Comment ID | File:Line | Summary | Valid? | Reasoning | Action |
|---|-----------|-----------|---------|--------|-----------|--------|
| 1 | `35xxxxxxx` | `src/Foo.php:42` | ... | ✅ Yes | ... | Fix |
| 2 | `35xxxxxxx` | `src/Bar.php:10` | ... | ❌ No | Already fixed in `abc1234` | Reply only |

**Do NOT wait for user approval — proceed immediately after presenting the table.**

---

## Step 5 — Process each comment (fix or reply)

Handle comments one at a time in order.

### For VALID comments (fix needed):

1. **Make the minimal, surgical code change** — do not refactor unrelated code.
2. **Run checks** using the project's existing check mechanism:
   - If `~/run-checks.sh` exists: `~/run-checks.sh <worktree-path> <target-path>`
   - Otherwise: run `composer cs-check`, `composer stan`, `composer test` inside the container.
3. If checks pass, **commit with a specific message**:
   ```
   Refs #<ticket> <Short description of what was fixed>

   <Root cause explanation>
   <What the fix does and why it is safe>

   Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
   ```
4. **Push the commit.**
5. **Reply in-thread** directly on the review comment:
   ```
   gh api repos/<owner>/<repo>/pulls/<PR>/comments/<comment_id>/replies \
     -X POST \
     --field body="Fixed in commit \`<full-sha>\`. <Brief explanation of what was changed and why.>"
   ```
6. **Resolve the conversation thread** (mark as resolved):
   ```
   gh api repos/<owner>/<repo>/pulls/comments/<comment_id>/replies \
     -X POST \
     --field body="..."
   ```
   Then resolve via GraphQL:
   ```
   gh api graphql -f query='
     mutation {
       resolveReviewThread(input: {threadId: "<thread_node_id>"}) {
         thread { isResolved }
       }
     }
   '
   ```
   To get the thread node ID:
   ```
   gh api repos/<owner>/<repo>/pulls/<PR>/comments/<comment_id> --jq '.pull_request_review_id'
   ```
   Or use the REST approach: after replying, the thread is considered addressed — optionally skip GraphQL resolution if the API is not available.

### For INVALID comments (no fix needed):

1. **Reply in-thread** explaining why no change is made:
   ```
   gh api repos/<owner>/<repo>/pulls/<PR>/comments/<comment_id>/replies \
     -X POST \
     --field body="No code change needed. <Clear explanation of why this is not a valid concern: e.g., already fixed, intentional design, no business impact, etc.>"
   ```
2. **Resolve the conversation thread** (same GraphQL approach as above).

---

## Step 6 — Summary

After processing all comments, present a final summary table:

| # | Comment | Action Taken | Commit / Note |
|---|---------|-------------|---------------|
| 1 | Filename not sanitized | Fixed | `e1dab2f3f` |
| 2 | Already fixed by team | Replied (no fix) | N/A |

---

## Important rules

- **One commit per review comment fix.** Never combine fixes from multiple comments into one commit.
- **Never modify files under `/vendor`.**
- **Reply must be in the review comment thread** using `/replies` endpoint — never create a top-level PR comment as a substitute.
- **Do not fix warnings** from PHPCS (errors only). Do not fix pre-existing issues unrelated to the review comment.
- **Ticket number:** Extract from branch name (e.g. `ticket_112662` → `#112662`) or from existing commit messages on the branch.
- **Run checks before every commit.** Never commit code that fails cs-check or stan.
- **Be critical of Copilot reviews** — the reviewer has no knowledge of business requirements. Assess validity honestly; do not blindly implement every suggestion.
