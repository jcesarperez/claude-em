---
name: check-board
description: >
  Evaluate the daily health of a Jira Kanban board: flow, people load, and bugs at risk.
  Use whenever the user wants a daily-standup-ready view of a board — what's stuck, who's
  overloaded, who can pull, what's blocked, what bugs are about to breach SLA.
---

## Tool

Run this script using the Bash tool:

```
bash .claude/skills/check-board/scripts/fetch_board.sh <BOARD_ID_OR_URL> --json
```

- `BOARD_ID_OR_URL`: numeric board id (e.g. `5289`) or full board URL.
- The script trims Done to the last 36h. To Do, In Progress and Done<36h all show up in the snapshot.

The script outputs JSON with this structure:
```json
{
  "fetched_at": "2026-05-09T12:00:00Z",
  "board": {
    "id": "5289",
    "name": "...",
    "type": "kanban",
    "project": "OPS",
    "columns": [{ "name": "In Progress", "status_ids": ["10001", "10002"] }]
  },
  "flagged_field_supported": true,
  "metrics": {
    "total": 0,
    "in_progress": 0,
    "todo": 0,
    "done_last_36h": 0,
    "blocked_count": 0,
    "blocked": [{ "key": "...", "summary": "...", "status": "...", "statusCategory": "...", "column": "...", "assignee": "Name", "time_in_status": "Xd Yh Zm" }],
    "stuck": [{ "key": "...", "summary": "...", "status": "...", "column": "...", "assignee": "Name", "is_blocked": false, "time_in_status": "Xd Yh Zm", "seconds": 0, "severity": "warning|critical" }],
    "unassigned_in_progress": [{ "key": "...", "summary": "...", "status": "...", "column": "...", "time_in_status": "..." }],
    "regressions_last_7d": [{ "key": "...", "summary": "...", "at": "...", "from": "...", "to": "..." }],
    "throughput_7d": 0,
    "throughput_14d": 0,
    "median_cycle_time_days": 0.0,
    "columns": [{ "name": "...", "count": 0, "in_progress_count": 0, "stuck_count": 0 }],
    "assignees": [{ "assignee": "Name or null", "count": 0, "keys": ["..."], "max_time_in_status_seconds": 0, "stuck_count": 0, "blocked_count": 0 }],
    "idle_assignees": ["Name"],
    "bugs_at_risk": [{ "key": "...", "summary": "...", "status": "...", "column": "...", "assignee": "Name", "priority": "High", "duedate": "YYYY-MM-DD or null", "days_until_due": 0, "risk": "red|yellow", "reason": "due date|Highest priority, no due date" }],
    "bugs_other_count": 0,
    "epics": [{ "key": "EPIC-1", "summary": "...", "status": "...", "active_count": 0, "in_progress_count": 0, "stuck_count": 0, "blocked_count": 0, "red_bug_count": 0, "yellow_bug_count": 0, "issue_keys": ["..."] }],
    "issues_without_epic": 0
  },
  "issues": [/* full snapshot, same per-issue shape as inside metrics + changelog-derived fields */]
}
```

---

## Instructions

### Resolving the input

The skill accepts either:
- A **team name** (e.g. `events`, `floor`) → read `data/team_{name}.md`, take the `Default board` and the team roster (full names of all `### member` sections). Use that board id; keep the roster for filtering.
- A **board id or URL** → use it directly. No roster available; skip roster-based filters and say so.

If the team file is missing or has no `Default board`, ask the user for the board id before continuing.

### Analysis steps

1. Resolve the input as above. If a team file was loaded, build `team_roster = [full names from every "### name" section]`.
2. Run the script with `--json`. Stop and report the error if it fails.
3. Use the pre-computed `metrics` for all rubric checks. Do not recompute from `issues` unless you need a specific issue's detail (e.g. parent epic, blocked_by links).
4. Produce the structured report below.
5. If `flagged_field_supported == false`, mention in the output that blocked detection is unavailable for this tenant.

---

## Scoring Rubrics

### Flow Health

Evaluate four signals:

**Stuck** (use `metrics.stuck`):
- 🟢 None
- 🟡 1–2 warnings (≥5d), no critical
- 🔴 Any critical (≥10d), or ≥3 warnings

**Regressions last 7d** (use `metrics.regressions_last_7d`):
- 🟢 0
- 🟡 1–2
- 🔴 ≥3, or ≥1 transition into a To Do category from In Progress/Done

**Blocked** (use `metrics.blocked_count` and `metrics.blocked`):
- 🟢 0
- 🟡 1–2
- 🔴 ≥3, or any blocked item also stuck ≥10d
- If `flagged_field_supported == false`: skip this signal and say so explicitly.

**Throughput / Cycle time**:
- Cite `throughput_7d`, `throughput_14d`, and `median_cycle_time_days`.
- These are descriptive — flag only as 🟡/🔴 if you spot an obvious anomaly (e.g. `throughput_7d == 0` while `in_progress > 5`, or `median_cycle_time_days > 15`). Otherwise 🟢.

**Overall Flow state**:
- 🟢 Moving — all four 🟢
- 🟡 At Risk — any 🟡, no 🔴
- 🔴 Stalled — any 🔴

### People Health

Evaluate three signals:

**WIP balance** (use `metrics.assignees`):
- Overloaded: assignee with `count ≥ 4` in In Progress, or `count ≥ 3` AND `stuck_count ≥ 3`
- Heavy stuck: assignee with `stuck_count ≥ 3` regardless of count
- Cite each by name.

**Unassigned in In Progress** (use `metrics.unassigned_in_progress`):
- 🟢 None
- 🔴 Any — active work without an owner is a delivery risk.
- Do NOT flag unassigned issues in To Do — that's normal in this team.

**Idle / can-pull** (use `metrics.idle_assignees`):
- Assignees with items elsewhere on the board but 0 in In Progress. Useful daily signal: who can pick something up.
- **Filter to the team roster**: only include names that match `team_roster` (full names from the team file). This excludes PMs, designers, cross-team contributors and anyone else who shows up on the board but isn't an engineer on the team.
- If no team file was loaded (board id passed directly), skip this signal and write "Idle filter unavailable — no team file resolved."
- Note: people not assigned to anything on the board are invisible to this signal.

**Overall People state**:
- 🟢 Healthy — no overload, no unassigned in progress
- 🟡 At Risk — 1 overloaded person, or any single 🟡 signal
- 🔴 Stretched — multiple overloaded, or any unassigned in progress, or someone with `stuck_count ≥ 4`

### Epic Health

Use `metrics.epics`. Each epic groups all active (non-Done) issues whose `parent.issuetype == "Epic"`. Sub-tasks whose parent is a Story are grouped under their Story key (treated as "(no epic)" in the listing) — their epic is unknown without an extra fetch.

For each epic, classify state:
- 🔴 Stalled — `stuck_count ≥ 3` OR `blocked_count ≥ 2` OR `red_bug_count ≥ 1`
- 🟡 At Risk — `stuck_count ≥ 1` OR `blocked_count ≥ 1` OR `yellow_bug_count ≥ 1` OR `in_progress_count ≥ 5` (high WIP)
- 🟢 OK — none of the above

In the output, list only 🔴 and 🟡 epics (those that need attention). If all epics are 🟢, say "All epics OK". Always cite the epic's key + summary and the specific signals (e.g. "3 stuck, 1 blocked, 1 red bug").

If `issues_without_epic > 0`, mention the count at the end so the EM knows that group exists.

### Bugs at Risk

Already classified by the script. Output them as-is, sorted (the script already orders red before yellow, then by `days_until_due` ascending).

- 🔴 Red bugs: SLA imminent (`days_until_due ≤ 3`, including overdue) OR `priority == Highest` with no due date.
- 🟡 Yellow bugs: due in 4–10d.
- The `bugs_other_count` is informational ("Bugs without SLA: N") — do not flag.

**Overall Bugs state**:
- 🟢 No red, no yellow
- 🟡 Any yellow, no red
- 🔴 Any red

---

## Output Format

Return ONLY this structure:

---

📋 Board Snapshot — BOARD_ID: Name [type]

- Total (snapshot): X · In Progress: X · To Do: X · Done last 36h: X
- Blocked (Flagged): X  |  Flagged field not available on this tenant
- Throughput: X (7d) · X (14d)
- Median cycle time (last 14d): X.Xd  |  Not enough data
- Columns: name (count), name (count), ...

🌊 Flow Health — 🟢 Moving / 🟡 At Risk / 🔴 Stalled

- Stuck: 🟢/🟡/🔴 — X warnings, X critical
  - KEY — summary (Xd in "Status", assignee)[ · BLOCKED]
  - ...up to ~6, prioritize critical
- Regressions last 7d: 🟢/🟡/🔴 — X transitions
  - KEY — summary: from → to (date)
  - ...
- Blocked: 🟢/🟡/🔴 — X items
  - KEY — summary (status, assignee, Xd in status)
  - ...
- Throughput: X / 7d, X / 14d — 🟢/🟡 (note anomaly if any)
- Cycle time: X.Xd median — 🟢/🟡/🔴

👥 People Health — 🟢 Healthy / 🟡 At Risk / 🔴 Stretched

- Overloaded: Name (X WIP, X stuck), ...  |  None
- Heavy stuck: Name (X stuck), ...  |  None
- Unassigned in In Progress: KEY — summary, KEY — summary  |  None
- Can pull (idle): Name, Name  |  None visible

🛤️ Epic Health

- 🔴 KEY — epic summary
  X active · X WIP · X stuck · X blocked · X 🔴 / X 🟡 bugs
- 🟡 KEY — ...
- All epics OK  |  (only when no epic is 🔴/🟡)
- Issues not under an epic on the board: X (informational)  |  (skip if 0)

🐞 Bugs at Risk — 🟢 / 🟡 / 🔴

- 🔴 KEY — summary
  priority · due YYYY-MM-DD (Xd) · assignee — reason
- 🟡 KEY — summary
  priority · ...
- ...
- Bugs without SLA on the board: X (informational)

🧭 Summary

- 3–5 bullets max. The actionable story for today's standup. Focus on:
  - The 1–2 issues most likely to slip today
  - Who needs help (overloaded, heavy stuck)
  - Who can pull (idle)
  - Top blocker to unblock
  - Any SLA bug due today/overdue

🎯 Recommendations

1. [Verb] Specific concrete action — cite KEY or Name
2. ...
(2–5 items, ordered by urgency)

---

## Style Guidelines

- Always cite issue keys, durations, dates, and people by name — no vague observations.
- Mention assignee on every stuck/blocked/at-risk item so the EM knows who to talk to.
- For overdue bugs, lead with the overdue magnitude ("Xd overdue").
- Be concise and direct — EM tone, no fluff.
- Prioritize signal over completeness: if there are 20 stuck items, list the top ~6 most severe and say "and N more".

## Constraints

- DO NOT flag unassigned issues in To Do — only in In Progress.
- DO NOT list as idle anyone outside `team_roster` when a team file was loaded (PMs, designers, cross-team contributors stay off the line).
- DO NOT recompute metrics from `issues`; trust the pre-computed `metrics`.
- DO NOT show Done items older than 36h (the script already trims them).
- DO NOT use sprint/velocity language — this skill is Kanban-only.
- If `flagged_field_supported == false`, say "Blocked detection unavailable" once and skip the Blocked block entirely.
- Avoid generic recommendations like "improve communication". Be specific: "ping <name> on KEY-X — stuck Xd in Review with no assignee".

## Goal

Help an Engineering Manager walk into the daily knowing:

"What's slipping, who's overloaded, who can pull, what's blocked, and which bug is about to breach SLA?"
