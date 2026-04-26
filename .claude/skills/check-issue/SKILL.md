---
name: check-issue
description: >
  Evaluate whether a Jira issue (Story, Bug, Task) is stuck. Analyzes execution health
  (time in status, ping pong, PR state, subtask movement), with lighter definition and
  decomposition checks adapted per issue type. Use whenever the user wants to know if an
  issue is blocked, stuck, or at risk.
---

## Tool

Run this script using the Bash tool:

```
bash .claude/skills/check-issue/scripts/fetch_issue.sh <ISSUE_KEY> --json
```

- `ISSUE_KEY`: any issue key (Story, Bug, Task, Sub-task)
- If the issue is not found, the script exits with an error. Report it and stop.

The script outputs JSON with this structure:
```json
{
  "fetched_at": "2026-04-20T10:00:00Z",
  "issue": {
    "key": "FBX-1234",
    "issuetype": "Story",
    "summary": "...",
    "status": "In Review",
    "statusCategory": "In Progress",
    "description": "plain text",
    "assignee": "Name or null",
    "priority": "High",
    "duedate": "YYYY-MM-DD or null",
    "created": "...",
    "updated": "...",
    "comments": [{ "author": "Name", "created": "...", "body": "plain text" }],
    "time_in_current_status": { "formatted": "Xd Yh Zm", "seconds": 0, "since": "..." },
    "first_in_progress_at": "YYYY-MM-DDTHH:MM:SSZ or null",
    "cycle_time": { "formatted": "Xd Yh Zm", "seconds": 0 }, // Done issues only, or null
    "time_in_progress": { "formatted": "Xd Yh Zm", "seconds": 0 }, // In Progress issues only, or null
    "status_transitions": [{ "from": "...", "to": "...", "at": "...", "author": "Name" }],
    "assignee_changes": [{ "from": "...", "to": "...", "at": "...", "changed_by": "Name" }],
    "pr": {
      "count": 2,
      "open_count": 1,
      "draft_count": 0,
      "items": [                              // null if only aggregate data is available
        {
          "id": "#123",
          "title": "fix: FBX-1234 ...",
          "status": "OPEN",                   // OPEN | DRAFT | MERGED | DECLINED | CLOSED
          "open": true,                       // true only when status == OPEN (ready for review)
          "author": "Name",
          "branch": "FBX-1234-my-branch",
          "last_updated": "YYYY-MM-DDTHH:MM:SS.000+0000",
          "url": "https://github.com/..."
        }
      ]
    } // or null if no PRs found
    "pr_merge_gap": { "formatted": "Xd Yh Zm", "seconds": 0 } // gap between first and last MERGED PR; null if < 2 merged PRs
  },
  "parent_epic": { "key": "FBX-1000", "summary": "...", "status": "In Development" }, // or null
  "subtasks": [
    {
      "key": "FBX-1235",
      "summary": "...",
      "status": "In Progress",
      "statusCategory": "In Progress",
      "assignee": "Name or null",
      "time_in_current_status": { "formatted": "Xd Yh Zm", "seconds": 0, "since": "..." }
    }
  ],
  "pingpong": {
    "status_bounces": 0,
    "assignee_change_count": 0,
    "pingpong_comment_count": 0,
    "comment_author_count": 0,
    "detected": false
  }
}
```

---

## Instructions

### Issue Key Resolution

- If the argument matches `[A-Z]+-\d+`, use it directly.
- Otherwise, treat it as a search phrase and search Jira using JQL:
  `summary ~ "<phrase>" ORDER BY updated DESC`
  Use the jira skill, then CLI, then REST API.
- If multiple matches, list them and ask the user to confirm.

### Analysis Steps

1. Run the script; stop and report error if it fails
2. Run the three health analyses using the fetched data
3. Produce the structured report

---

## Scoring Rubrics

### Definition Health (lightweight, type-specific)

Evaluate `issue.description` and `issue.comments`. Assess each criterion for the issue type:

**Story:**
| # | Criterion | ✅ |
|---|---|---|
| 1 | User value / goal | Clear description of what the user can do or what changes |
| 2 | Acceptance criteria | Explicit AC, "done when", or testable conditions present |
| 3 | Dependencies flagged | Named blockers, teams, or linked issues if applicable |

**Bug:**
| # | Criterion | ✅ |
|---|---|---|
| 1 | Steps to reproduce | Clear steps or scenario that triggers the bug |
| 2 | Expected vs actual | Both states described |
| 3 | Severity/priority set | Priority field is not null/default |

**Task / Sub-task:**
| # | Criterion | ✅ |
|---|---|---|
| 1 | Clear goal | Description states what needs to be done |
| 2 | Scope defined | What is in scope; not ambiguous |

**Score:**
- 🟢 All ✅ or at most 1 ⚠️
- 🟡 1–2 ⚠️, no ❌
- 🔴 Any ❌, or description is empty

### Decomposition Health (lightweight)

Evaluate `subtasks` array. Skip this section entirely if `issuetype == "Sub-task"`.

| # | Criterion | ✅ |
|---|---|---|
| 1 | Appropriate decomposition | Complex issue has subtasks; simple issue may not need them |
| 2 | Not oversized | `subtasks.length ≤ 5`; no single subtask has been stuck significantly longer than others |
| 3 | All subtasks have clear summaries | Summaries are descriptive, not placeholders |

**Signals to flag:**
- No subtasks but description implies multiple distinct pieces of work → ⚠️ may be oversized
- `subtasks.length > 5` → ⚠️ may be over-decomposed or should be an epic
- All subtasks Done but issue still open → inconsistency, flag it

**Score:**
- 🟢 All ✅ or at most 1 ⚠️
- 🟡 1 ⚠️
- 🔴 Any ❌

### Execution Health (primary focus)

This is the core of the analysis. Evaluate all signals, then derive overall state.

#### Status Stuck Signal

Use `issue.status` (exact name, not category) and `issue.time_in_current_status.seconds`:

| Status | Stuck threshold | Critical threshold |
|---|---|---|
| Statuses containing "Review", "QA", "Testing" | 3 days (259200s) | 5 days |
| All other In Progress category statuses | 5 days (432000s) | 10 days |

Only apply this to issues in `statusCategory == "In Progress"`. Ignore To Do and Done.

#### Ping Pong (primary signal for Bugs, applies to all types)

Use `pingpong` pre-computed object AND read `issue.comments` directly to assess context.

**Pre-computed signals:**
- `status_bounces ≥ 2`: issue moved back and forth between in-progress category statuses
- `assignee_change_count ≥ 3`: passed between people multiple times
- `pingpong_comment_count ≥ 3` AND `comment_author_count ≥ 2`: back-and-forth in comments

**Manual comment analysis** (always do this):
Read `issue.comments` and look for:
- Open questions directed at another person ("@name can you...", "waiting for X to...")
- Unanswered questions (question asked, no reply author after it, or reply is another question)
- Comments that pass the ball ("handing back to", "assigned to you", "please check", "any update?")
- Long gaps between comment threads that suggest waiting

Report specific evidence: quote or paraphrase the comment and its author/date.

**Ping pong severity:**
- 🔴 Critical: `pingpong.detected == true` OR clear evidence of unanswered blocking question older than 3 days
- 🟡 At Risk: 1–2 signals, or recent back-and-forth with open question
- 🟢 None: no signals

#### PR Health

Use `issue.pr` and `issue.pr.items` (sorted by `last_updated` desc). Read the PR list to understand what happened: how many attempts, rework, drafts that never progressed, etc.

| Situation | Signal |
|---|---|
| `status` contains "Review" AND `pr == null` | ⚠️ In review but no PR — status may be wrong |
| `pr.open_count > 0` AND most recent open PR `last_updated` > 3 days ago | 🟡 PR open but stale |
| `pr.open_count > 0` AND most recent open PR `last_updated` > 7 days ago | 🔴 PR open and very stale |
| `pr.draft_count > 0` AND `statusCategory == "In Progress"` AND most recent draft `last_updated` > 5 days ago | 🟡 Draft stale — engineer may be blocked |
| `pr.draft_count > 0` AND all other PRs are MERGED | ℹ️ Drafts never promoted — note but do not flag |
| all PRs MERGED AND `statusCategory != "Done"` | ⚠️ All PRs merged but issue still open — status stale |
| `pr.count > 2` AND multiple DECLINED or many attempts | ⚠️ Rework signal — investigate why |
| `statusCategory == "In Progress"` AND `pr == null` | ℹ️ No PR yet — expected if early in-progress |

Skip PR analysis if `pr == null` and status is not review-related.

#### Cycle Time Signal

Use `issue.cycle_time.seconds` (Done issues) or `issue.time_in_progress.seconds` (In Progress issues). Apply to both Done and In Progress; ignore To Do.

| Elapsed | Signal |
|---|---|
| > 30 days (2,592,000s) | 🔴 Very long cycle time — investigate delivery pace |
| > 15 days (1,296,000s) | 🟡 Getting long — monitor |
| ≤ 15 days | 🟢 OK |

#### PR Merge Gap Signal

Use `issue.pr_merge_gap.seconds`. Skip if `pr_merge_gap == null` (fewer than 2 merged PRs).

| Gap between first and last MERGED PR | Signal |
|---|---|
| > 14 days (1,209,600s) | 🔴 Large gap — delivery stretched, likely paused or blocked mid-way |
| > 7 days (604,800s) | 🟡 Noticeable gap — work spread across multiple cycles |
| ≤ 7 days | 🟢 OK |

#### Subtask Execution

Use `subtasks` array:
- Any subtask stuck by the same thresholds → flag with key + time
- All subtasks Done but parent issue not Done → inconsistency
- No subtasks started (`statusCategory == "To Do"` for all) → nothing moving

#### Assignee

- `assignee == null` AND `statusCategory == "In Progress"` → 🔴 active work with no owner

#### Overall Execution State

- 🟢 Moving: within stuck threshold, no ping pong, PR healthy (or not applicable), subtasks progressing, cycle time ≤ 15d, PR merge gap ≤ 7d
- 🟡 At Risk: approaching threshold (>50% of limit), minor ping pong signs, PR open but not stale, 1 subtask stuck, cycle time > 15d, OR PR merge gap > 7d
- 🔴 Stuck: exceeded stuck threshold, OR `pingpong.detected == true` OR clear unanswered blocking question, OR `assignee == null` in progress, OR PR very stale, OR all subtasks blocked, OR cycle time > 30d, OR PR merge gap > 14d

---

## Output Format

Return ONLY this structure:

---

🎫 Issue Snapshot — KEY: Summary

- Type: Story / Bug / Task / Sub-task
- Status: "Status name" [statusCategory] — in this status for Xd Yh Zm (since YYYY-MM-DD)
- Progress: First in progress YYYY-MM-DD · Cycle time Xd Yh (Done) | In progress Xd Yh total (In Progress) | — (To Do / never started)
- Assignee: Name  |  ⚠️ Unassigned
- Priority: High / Medium / Low / —
- PRs: 3 total · 1 OPEN · 1 DRAFT · 1 MERGED (last activity YYYY-MM-DD)  |  No PRs
  (list each PR on its own line if ≤ 4 total: "  · #123 MERGED — branch-name — author (YYYY-MM-DD)")
- Parent: KEY — Epic Summary [Epic Status]  |  No parent
- Subtasks: X total (X Done · X In Progress · X To Do)  |  None
- Comments: X

🧠 Definition Health — 🟢 / 🟡 / 🔴

(Use type-specific criteria from the rubric)
- ✅/⚠️/❌ Criterion: one-line assessment

🧩 Decomposition Health — 🟢 / 🟡 / 🔴  |  N/A (Sub-task)

- ✅/⚠️/❌ Criterion: one-line assessment
- (Flag inconsistencies: all subtasks Done but issue open, etc.)

⚙️ Execution Health — 🟢 Moving / 🟡 At Risk / 🔴 Stuck

- Status time: Xd in "Status" — 🟢 OK / 🟡 Approaching / 🔴 Stuck (threshold: Xd)
- Ping pong: 🔴 Detected / 🟡 Signals present / 🟢 None
  - Evidence: "[quote or paraphrase]" — Author (date)  |  None
- Cycle time: Xd total — 🟢 OK / 🟡 Long (>15d) / 🔴 Very long (>30d)  |  — (To Do)
- PR merge gap: Xd between first and last merge — 🟢 OK / 🟡 Spread (>7d) / 🔴 Large (>14d)  |  N/A
- PR: state — assessment  |  No PR
- Subtasks: X moving / KEY stuck Xd / all Done but issue open  |  None
- Assignee: ✅ Assigned / 🔴 Unassigned while In Progress
- Key risks: bullet list

🧭 Summary

Overall: 🟢/🟡/🔴  ·  Definition: 🟢/🟡/🔴  ·  Decomposition: 🟢/🟡/🔴  ·  Execution: 🟢/🟡/🔴

- 3–5 bullets: current state · main risk · main blocker

🎯 Recommendations

1. [Verb] Specific concrete action
2. ...
(2–5 items, ordered by urgency)

---

## Style Guidelines

- Cite status names, durations, dates, and comment authors — no vague observations
- For ping pong: quote or paraphrase actual evidence from comments; never say "ping pong detected" without backing it up
- Bugs: pay extra attention to ping pong and blocking questions — this is the most common reason bugs stall
- If definition is empty, state it explicitly; don't skip the section
- Be concise and direct — EM tone, no fluff

## Constraints

- DO NOT invent data not present in the input
- DO NOT flag Decomposition for Sub-tasks
- DO NOT flag unassigned issues that are in "To Do" status category — only flag unassigned in "In Progress"
- DO NOT apply stuck thresholds to issues in "Done" or "To Do" status categories
- If `pr.last_updated` is null, omit the staleness assessment for PRs
