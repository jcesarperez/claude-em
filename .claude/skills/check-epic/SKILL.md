---
name: check-epic
description: >
  Evaluate the health of a Jira epic: definition quality, issue decomposition, and execution
  dynamics. Use whenever the user wants to assess epic health, identify risks, or get
  prioritized recommendations.
---

## Tool

Run this script using the Bash tool:

```
bash .claude/skills/check-epic/scripts/fetch_epic.sh <EPIC_KEY> --json
```

- `EPIC_KEY`: the Jira epic key (e.g. `FBX-1234`) — may be resolved from a phrase; see **Epic Key Resolution** below
- If `EPIC_KEY` is not an Epic, the script exits with an error. Report the error to the user and stop.

The script outputs JSON with this structure:
```json
{
  "fetched_at": "2026-04-14T10:00:00Z",
  "epic": {
    "key": "FBX-1234",
    "summary": "...",
    "status": "In Development",
    "statusCategory": "In Progress",
    "description": "plain text",
    "duedate": "YYYY-MM-DD or null",
    "created": "...",
    "updated": "...",
    "comments": [
      { "author": "Name", "created": "...", "body": "plain text" }
    ],
    "time_in_current_status": { "formatted": "Xd Yh Zm", "seconds": 0, "since": "..." }
  },
  "metrics": {
    "total": 0,
    "done": 0,
    "in_progress": 0,
    "todo": 0,
    "blocked": 0,
    "pct_done": 0.0,
    "assignees": ["Name"],
    "assignee_count": 0,
    "closed_last_7d": 0,
    "created_last_7d": 0,
    "stale_in_progress": [{ "key": "FBX-X", "summary": "...", "time_in_status": "Xd Yh Zm" }],
    "unassigned_in_progress": ["FBX-X"],
    "days_until_due": 0,
    "epic_status_stale": false,
    "median_cycle_time_days": 0.0,
    "high_cycle_time_issues": [{ "key": "FBX-X", "summary": "...", "cycle_time_days": 0.0, "cycle_time_formatted": "Xd Yh Zm" }]
  },
  "child_issues": [
    {
      "key": "FBX-1235",
      "issuetype": "Story",
      "summary": "...",
      "status": "In Progress",
      "statusCategory": "In Progress",
      "assignee": "Name or null",
      "num_subtasks": 0,
      "duedate": "YYYY-MM-DD or null",
      "created": "...",
      "updated": "...",
      "time_in_current_status": { "formatted": "Xd Yh Zm", "seconds": 0, "since": "..." },
      "cycle_time": { "in_progress_at": "...", "done_at": "...", "seconds": 0, "days": 0.0, "formatted": "Xd Yh Zm" }
    }
  ]
}
```

---

## Instructions

### Epic Key Resolution

Before running the script, resolve the epic key:

- If the argument matches the pattern `[A-Z]+-\d+` (e.g. `FBX-1234`), use it directly.
- Otherwise, treat it as a search phrase and search Jira for epics with a matching summary. Use this tool priority:
  1. **jira skill** — invoke `/jira` with JQL: `issuetype = Epic AND summary ~ "<phrase>" ORDER BY created DESC`
  2. **CLI** — `jira issue list --jql 'issuetype = Epic AND summary ~ "<phrase>"'`
  3. **Batch** — REST API calls via bash
  4. **MCP** — `searchJiraIssuesUsingJql` as last resort
- If multiple matches are found, list them and ask the user to confirm which one to use.
- If no match is found, report it and stop.

### Analysis steps

1. Run the script with the resolved epic key; stop and report the error if it fails
2. Run the three health analyses using the pre-computed `metrics` and the `epic` + `child_issues` data
3. Produce the structured report

---

## Scoring Rubrics

### Definition Health

Evaluate epic `description` + `comments`. Assess each criterion:
- ✅ clearly present and specific
- ⚠️ present but vague or incomplete
- ❌ absent

| # | Criterion | What counts as ✅ |
|---|---|---|
| 1 | Clear and testable goal | Describes what will be true when done, not just what will be built |
| 2 | Success metrics / acceptance criteria | Measurable outcomes or explicit done conditions |
| 3 | Scope boundaries | Explicit in-scope / out-of-scope statements |
| 4 | Dependencies identified | Named teams, systems, or issues that are external blockers |
| 5 | Rollout strategy | Feature flags, phased rollout, migration plan |
| 6 | Observability | Dashboards, alerts, logs, or metrics named |

**Score**:
- 🟢 ≥4 criteria ✅
- 🟡 2–3 ✅, or majority ⚠️
- 🔴 ≤1 ✅, or description is empty

### Decomposition Health

Evaluate issue list structure using summaries, types, and counts. Do NOT analyze issue descriptions.

| # | Criterion | What counts as ✅ |
|---|---|---|
| 1 | Coverage | Issue summaries collectively address all stated scope items; no major scope items untracked |
| 2 | Granularity | Issues are roughly similar in scope; no oversized items (`num_subtasks > 5`); `median_cycle_time_days ≤ 7` when available |
| 3 | Issue count | At least one issue per major scope item; not zero, not a single monolithic issue |

**Score**:
- 🟢 All ✅ or at most 1 ⚠️, no ❌
- 🟡 1–2 ⚠️, no ❌
- 🔴 Any ❌, or `metrics.total == 0`

### Execution Health

Evaluate four signals, then derive overall state:

**Velocity** (use `metrics.closed_last_7d`):
- Active: `closed_last_7d > 0`
- Slow: `closed_last_7d == 0` AND `in_progress > 0`
- Stalled: `closed_last_7d == 0` AND `in_progress == 0`

**WIP pressure** (use `metrics.in_progress` / `metrics.total`):
- Healthy: `in_progress / total ≤ 0.30` OR `in_progress ≤ 2`
- High: `in_progress / total > 0.30` AND `in_progress > 2`

**Bottlenecks** (use `metrics.stale_in_progress` and `metrics.blocked`):
- Flag each issue in `stale_in_progress` (stuck ≥ 7d); issues ≥ 14d are critical
- Flag each issue in `blocked`

**Unassigned in-progress** (use `metrics.unassigned_in_progress`):
- Flag any in-progress issue with no owner — active work without an assignee is a delivery risk

**Cycle time** (use `metrics.median_cycle_time_days` and `metrics.high_cycle_time_issues`; skip entirely if null — not enough completed issues):
- Healthy: `median_cycle_time_days ≤ 5`
- At Risk: `5 < median_cycle_time_days ≤ 10`, or any `high_cycle_time_issues` (> 2× avg and > 5d)
- Critical: `median_cycle_time_days > 10`

**Due date** (use `metrics.days_until_due` and `metrics.pct_done`):
- Evaluate overdue cases first (`days_until_due < 0`):
  - 🔴 `days_until_due < 0` AND `pct_done < 100` — overdue with open work remaining
  - ⚠️ `days_until_due < 0` AND `pct_done == 100` — past due date but all issues done; delivery timing unknown (epic may have finished on time but date was never updated)
- Then evaluate upcoming deadline risk:
  - 🔴 `days_until_due < 14` AND `pct_done < 70`
  - 🟡 `days_until_due < 30` AND `pct_done < 50`
  - 🟢 otherwise, or `days_until_due` is null

**Epic status staleness** (use `metrics.epic_status_stale`):
- If true, flag it in the snapshot — the epic status contradicts the child issue data

**Overall execution state**:
- 🟢 Healthy: velocity Active, WIP Healthy, no bottlenecks or unassigned in-progress, due date 🟢, cycle time Healthy or null
- 🟡 At Risk: any of — Slow velocity, High WIP, ≥1 stale in-progress, any unassigned in-progress, due date 🟡, due date ⚠️ (overdue but complete), cycle time At Risk
- 🔴 Stalled: velocity Stalled, OR ≥2 issues stuck > 14d, OR due date 🔴 (overdue with open work, or upcoming with `pct_done < 50`), OR cycle time Critical

---

## Output Format

Return ONLY this structure:

---

📊 Epic Snapshot — KEY: Summary

- Total: X issues (X Done · X In Progress · X To Do[· X Blocked])
- Completion: X% (X/X)
- Assignees: X
- Epic status: "Status" — in this status for Xd (since YYYY-MM-DD)[⚠️ Likely stale: X issues in progress/done but epic is "To Do"]
- Closed last 7 days: X  |  Created last 7 days: X
- Median cycle time: X.Xd (N done issues)  |  Not enough data
- Due date: YYYY-MM-DD (X days remaining)  |  No due date set

🧠 Definition Health — 🟢 / 🟡 / 🔴

- ✅/⚠️/❌ Clear goal: one-line assessment
- ✅/⚠️/❌ Success criteria: one-line assessment
- ✅/⚠️/❌ Scope boundaries: one-line assessment
- ✅/⚠️/❌ Dependencies: one-line assessment
- ✅/⚠️/❌ Rollout strategy: one-line assessment
- ✅/⚠️/❌ Observability: one-line assessment

🧩 Decomposition Health — 🟢 / 🟡 / 🔴

- ✅/⚠️/❌ Coverage: one-line assessment (cite missing scope items if ⚠️/❌)
- ✅/⚠️/❌ Granularity: one-line assessment
- ✅/⚠️/❌ Issue count: one-line assessment

⚙️ Execution Health — 🟢 Healthy / 🟡 At Risk / 🔴 Stalled

- Velocity: Active / Slow / Stalled (X closed last 7d)
- WIP: X in progress / X total (XX%)
- Bottlenecks: KEY stuck Xd, KEY stuck Xd (critical: KEY stuck Xd)  |  None
- Blocked: X issues  |  None
- Unassigned in-progress: KEY, KEY  |  None
- Cycle time: X.Xd median — 🟢 Healthy / 🟡 At Risk / 🔴 Critical  |  Not enough data
- Cycle time outliers: KEY Xd (Xx median), KEY Xd  |  None
- Due date: YYYY-MM-DD (X days remaining) — 🟢 On Track / 🟡 At Risk / 🔴 Critical  |  YYYY-MM-DD (Xd overdue, work still open) — 🔴 Overdue  |  YYYY-MM-DD (Xd overdue, all issues done) — ⚠️ Past due, delivery timing unknown  |  No due date set
- Key risks: bullet list
- Likely causes: bullet list

🧭 Summary

Overall: 🟢/🟡/🔴  ·  Definition: 🟢/🟡/🔴  ·  Decomposition: 🟢/🟡/🔴  ·  Execution: 🟢/🟡/🔴

- 3–6 bullets: current state · main risk · main blocker

🎯 Recommendations

1. [Verb] Specific concrete action
2. ...
(3–6 items, ordered by impact and urgency)

---

## Style Guidelines

- Cite issue keys, percentages, and durations — no vague observations
- Trust child issue data over epic status when they conflict (`metrics.epic_status_stale`)
- Mine epic comments for blockers, decisions, and context not visible in the issue list
- Child issue summaries are fair game; issue descriptions are not
- Be concise and direct — EM tone, no fluff
- Prioritize signal over completeness

## Constraints

- DO NOT analyze child issue descriptions
- DO NOT invent data not present in the input
- If data is missing (no due date, empty description), state it explicitly rather than skipping
- Avoid generic statements like "improve communication" or "ensure alignment"
- DO NOT flag or recommend assigning issues that are not yet in progress — it is the expected workflow for issues to remain unassigned until they move to the "In Progress" status category

## Goal

Help an Engineering Manager quickly answer:

"Is this epic under control, what are the risks, and what should I do next?"
