---
name: check-ic-activity
description: >
  Use this skill whenever the user wants to analyze the activity of an IC or engineer.
  You have access to a CLI tool that retrieves activity data for an IC from Jira and GitHub.

---

## Tool

Run this script using the Bash tool:

```
bash .claude/skills/check-ic-activity/scripts/run_ic_activity.sh <github_username> <jira_email> <from_date> <to_date>
```

- `github_username`: the user's GitHub handle (e.g. `jcesarperez-mews`)
- `jira_email`: the user's Jira email (e.g. `julio.perez@mews.com`)
- `from_date`: start date in `YYYY-MM-DD` format (e.g. `2026-02-01`)
- `to_date`: end date in `YYYY-MM-DD` format (e.g. `2026-02-28`)

To resolve `github_username` and `jira_email` for a team member, check `data/team_*.csv` files first.

**Date resolution** — convert user expressions to `from_date` and `to_date` before calling the script. If no time range is specified, default to the last 14 days:
- (no date specified) → FROM = today - 14 days, TO = today
- "last 14 days" → FROM = today - 14 days, TO = today
- "last month" → FROM = first day of previous month, TO = last day of previous month
- "February 2026" → FROM = 2026-02-01, TO = 2026-02-28
- "this week" → FROM = Monday of current week, TO = today

The script outputs JSON metrics (alphabetically sorted, prefixed by category):
```json
{
  "col_avg_time_to_first_review_as_reviewer_hours": number,
  "col_reviews": number,
  "col_reviews_per_week": number,
  "del_issue_cycle_time_days": number,
  "del_pr_cycle_time_days": number,
  "del_commits": number,
  "del_commits_per_pr": number,
  "del_issues_by_type": { "Bug": number, "Story": number, "Task": number, ... },
  "del_issues_completed": number,
  "del_issues_per_week": number,
  "del_prs_merged": number,
  "del_prs_per_week": number,
  "del_total_loc": number,
  "foc_open_prs": number,
  "foc_wip_count": number,
  "period_days": number,
  "qua_avg_pr_size": number,
  "qua_comments_per_pr": number,
  "qua_prs_cancelled": number
}
```

---

## Instructions

1. Look up the user's `github_username` and `jira_email` from `data/team_*.csv`
2. Run the script with the Bash tool
3. Analyze the returned metrics
4. Produce a structured report with scoring and recommendations

---

## Scoring Logic

### Delivery
Single metric — score directly:
- del_issues_per_week: High ≥ 6 | Medium 3–5 | Low < 3

### Focus
Single metric — score directly:
- foc_wip_count: High ≤ 2 | Medium 3–4 | Low > 4
- **Special case:** foc_wip_count = 0 is a red flag (⚠️), not a High score. It likely indicates work is not being tracked in Jira. Do not assign a score — flag it instead.

### Quality
Score each metric independently, then average (round down to nearest tier):
- qua_avg_pr_size: High < 500 | Medium 500–1000 | Low > 1000
- qua_comments_per_pr: High < 6 | Medium 6–12 | Low > 12

If the individual scores differ, show each metric's score inline next to its value in the report.

### Collaboration
Score each metric independently, then average (round down to nearest tier):
- col_reviews_per_week: High ≥ 8 | Medium 4–8 | Low < 4
- col_avg_time_to_first_review_as_reviewer_hours: High < 24h | Medium 24–48h | Low > 48h

If the individual scores differ, show each metric's score inline next to its value in the report.

---

Return ONLY this format:

IC Activity Report (FROM to TO)

Delivery
- X issues completed (~X.X issues/week)
  - X Stories, X Tasks, X Bugs, X Sub-tasks, ...
- Issue cycle time: Xd
- Y PRs merged (~Y.Y PRs/week) — X LOC total
- PR cycle time: Xd
- Score: High | Medium | Low

Current Focus
- Issues in progress (WIP): X  ← if 0, show ⚠️ Red flag: no WIP tracked — work may not be linked to Jira issues
- Open PRs: X
- Score: High | Medium | Low  ← omit score and show ⚠️ Red flag instead when WIP = 0

Quality
- Avg PR size: X LOC
- Comments per PR: X
- Cancelled PRs: X
- Score: High | Medium | Low

Collaboration
- Reviews given: X (~X.X/week)
- Avg time to first review as reviewer: Xh
- Score: High | Medium | Low

Summary
- 2–3 concise insights about behavior and patterns

Recommendations
- 2–4 actionable, practical suggestions
- Focus on trade-offs (speed vs quality, focus vs multitasking, etc.)

---

## Style Guidelines

- Be concise and direct (engineering manager tone)
- Avoid fluff
- Prefer interpretation over raw data repetition
- Highlight trade-offs, not just metrics
- Do not hallucinate missing data

---

## Example Summary (style reference)

- Consistent delivery with solid throughput
- Slightly high parallel work impacting focus
- Good collaboration habits, responsive to feedback

## Example Recommendations (style reference)

- Reduce WIP to improve cycle time
- Aim for smaller PRs to lower rework
- Maintain strong review participation
