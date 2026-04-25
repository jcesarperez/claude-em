---
name: jira
description: >
  General-purpose Jira skill for any Jira project. Use for any Jira-related request: creating issues (Epic, Story, Bug, Task, Sub-task), querying issues (in progress, completed, by type/status, bugs by due date), or updating issues.
  Triggers include: "create an epic", "create a bug", "show me bugs", "epics in progress", "issues completed last N days", "bugs due in N days", or any request involving Jira.
  Also triggers when any other skill (e.g. write-us, write-epic-build) reaches a "create in Jira" confirmation step or similar.
---

# Skill: Jira — Project

## Manual Setup

Before using this skill, replace the following placeholders throughout this file — **including the `name:` and `description:` in the frontmatter above**:

- `name:` → use a short identifier for your project (e.g. `jira-platform`, `jira-core`)
- `description:` → update "any Jira project" to mention your actual project name, so Claude picks the right skill when you have multiple

Then replace the configuration placeholders:

| Placeholder | Description | How to find it |
|---|---|---|
| `{{PROJECT_KEY}}` | Your Jira project key | Visible in any issue key (e.g. `PLAT-123` → key is `PLAT`) |
| `{{CLOUD_ID}}` | Your Atlassian Cloud ID | Run `jira config list` or extract from your Atlassian URL |
| `{{BASE_URL}}` | Your Jira domain | e.g. `yourcompany.atlassian.net` |

Delete this section and the "Auto-detection" section below once you've replaced the placeholders.

---

## Auto-detection (always run this first)

**Before doing anything else**, check if any placeholder is still unconfigured:

- If `{{PROJECT_KEY}}` appears literally in this file → ask: *"What is your Jira project key? (e.g. PLAT, ENG, CORE)"*
- If `{{CLOUD_ID}}` appears literally in this file → ask: *"What is your Atlassian Cloud ID? You can find it by running `jira config list` or from your Atlassian admin URL."*
- If `{{BASE_URL}}` appears literally in this file → ask: *"What is your Jira domain? (e.g. yourcompany.atlassian.net)"*

Once the user provides the values, use them for the rest of the conversation **without asking again**.

Then ask: *"Should I save these values in the skill so you don't have to enter them again in future conversations?"*
- If yes → edit this SKILL.md file, replacing each `{{PLACEHOLDER}}` with the value the user provided, and confirm when done.
- If no → keep them only for this conversation.

---

## Configuration

| Field | Value |
|---|---|
| Project | {{PROJECT_KEY}} |
| cloudId | {{CLOUD_ID}} |
| Base URL | {{BASE_URL}} |
| Assignee | None (unless user specifies) |
| Reporter | Current user |
| Priority | Medium (unless user specifies) |
| Components | None by default |
| Labels | None by default |

**Supported issue types:** Epic, Story, Bug, Task, Sub-task

---

## Tool usage

**Always prefer the `jira` CLI.** Only fall back to MCP (`searchJiraIssuesUsingJql`, `createJiraIssue`, etc.) if the CLI is not available or a specific operation isn't supported by it.

### Jira CLI quick reference

```bash
# Search / query — using native flags (preferred for simple filters)
jira issue list -p {{PROJECT_KEY}} -a "<email>" -s "<status>" -t <IssueType> \
  --created-after "YYYY-MM-DD" --created-before "YYYY-MM-DD" \
  --plain --columns KEY,SUMMARY,STATUS,ASSIGNEE,PRIORITY \
  --paginate 0:100

# Search / query — using raw JQL (for complex filters)
# ⚠️ Do NOT include ORDER BY in the JQL string — the CLI adds it automatically and will return a 400 error if you include it
jira issue list -p {{PROJECT_KEY}} --jql "<JQL without ORDER BY>"

# Create issue
jira issue create -p {{PROJECT_KEY}} -t <IssueType> -s "<summary>" [flags]

# View issue
jira issue view <ISSUE-KEY>
```

**Prefer native flags over `--jql` when the filter maps cleanly** (assignee, status, type, date range). Use `--jql` only for filters that have no native flag equivalent (e.g. `resolutiondate`, custom fields).

---

## A. Querying issues

Identify the query intent and build the appropriate query. Always scope to `project = {{PROJECT_KEY}}`.

### Common queries

| User request | Preferred command |
|---|---|
| Epics in progress | `jira issue list -p {{PROJECT_KEY}} -t Epic -s "In Progress" --plain --columns KEY,SUMMARY,STATUS,ASSIGNEE --paginate 0:100` |
| Bugs open / in progress | `jira issue list -p {{PROJECT_KEY}} -t Bug --jql 'project = {{PROJECT_KEY}} AND "customfield_10001" = "82dc66a2-af52-404a-8663-a25bb3c10093" AND issuetype = Bug AND status != Done' --plain --paginate 0:100` |
| Issues completed last N days | `jira issue list -p {{PROJECT_KEY}} --jql 'project = {{PROJECT_KEY}} AND "customfield_10001" = "82dc66a2-af52-404a-8663-a25bb3c10093" AND status = Done AND resolutiondate >= -Nd' --plain --paginate 0:100` |
| Issues of type X in status Y | `jira issue list -p {{PROJECT_KEY}} -t X -s "Y" --plain --paginate 0:100` |
| Bugs due in ≤ N days | `jira issue list -p {{PROJECT_KEY}} -t Bug --jql 'project = {{PROJECT_KEY}} AND "customfield_10001" = "82dc66a2-af52-404a-8663-a25bb3c10093" AND issuetype = Bug AND duedate <= Nd AND status != Done' --plain --paginate 0:100` |
| All open issues | `jira issue list -p {{PROJECT_KEY}} --jql 'project = {{PROJECT_KEY}} AND "customfield_10001" = "82dc66a2-af52-404a-8663-a25bb3c10093" AND status != Done' --plain --paginate 0:100` |
| Issues by assignee in date range | `jira issue list -p {{PROJECT_KEY}} -a "<email>" --created-after "YYYY-MM-DD" --plain --columns KEY,SUMMARY,STATUS,PRIORITY --paginate 0:100` |

### Output format for queries

Show results as a markdown table with columns:
`Key | Type | Summary | Status | Priority | Due Date | Assignee`

Omit columns that are empty for all results. Include a total count at the end.

---

## B. Creating issues

### Step 1 — Determine issue type

If not stated, ask. Options: **Epic, Story, Bug, Task, Sub-task**.

### Step 2 — Gather required fields by type

#### Epic
| Field | Required | Notes |
|---|---|---|
| Summary | Yes | Concise title |
| Description | Recommended | Context and goals |
| Start Date | Ask | `customfield_10015` (YYYY-MM-DD) |
| Due Date | Ask | `duedate` (YYYY-MM-DD) |
| Parent | No | Epics are top-level by default |

#### Story
| Field | Required | Notes |
|---|---|---|
| Summary | Yes | Concise title, start with verb |
| Description | Yes | Use Story format (see §C) |
| Parent Epic | Ask | Query recent epics if not given; allow null |

#### Bug
| Field | Required | Notes |
|---|---|---|
| Summary | Yes | Describe the defect clearly |
| Description | Yes | Steps to reproduce, expected vs actual |
| Priority | Ask | Default Medium; consider High/Critical if user hints urgency |
| Due Date | Ask | Especially relevant for bugs |
| Parent Epic | Ask | Optional |

#### Task
| Field | Required | Notes |
|---|---|---|
| Summary | Yes | Action-oriented title |
| Description | Recommended | What needs to be done and why |
| Parent | Ask | Can be Epic or Story |

#### Sub-task
| Field | Required | Notes |
|---|---|---|
| Summary | Yes | |
| Description | Recommended | |
| Parent | **Required** | Must have a parent issue key |

### Step 3 — Draft and confirm

Present the issue draft before creating. Ask the user to confirm or edit.

**Do not create in Jira until explicit confirmation.**

### Step 4 — Create via CLI

**Always try the CLI first.** Do not skip to MCP because the description is long or structured — use `--body` or pass the description via stdin. Only fall back to MCP if the CLI command fails or explicitly does not support a required field.

```bash
jira issue create \
  -p {{PROJECT_KEY}} \
  -t "<IssueType>" \
  -s "<summary>" \
  [--priority "Medium"] \
  [--custom "duedate=YYYY-MM-DD"] \
  [--parent "<PARENT-KEY>"]
```

If CLI flags don't support a field, fall back to `createJiraIssue` MCP with:

```json
{
  "cloudId": "{{CLOUD_ID}}",
  "projectKey": "{{PROJECT_KEY}}",
  "issueType": "<IssueType>",
  "summary": "<summary>",
  "description": "<ADF description>",
  "priority": "Medium",
  "duedate": "YYYY-MM-DD",
  "parent": { "key": "<PARENT-KEY>" }
}
```

> **ADF note**: When using MCP, description must be in Atlassian Document Format (`type: "doc"`). Use level-2 headings for sections and paragraphs for content.

### Step 5 — Output after creation

Share:
- Direct link: `https://{{BASE_URL}}/browse/{{PROJECT_KEY}}-XXXX`
- Brief summary: type, title, parent (if any), due date (if set)

---

## General rules

- Always scope queries to `project = {{PROJECT_KEY}}` — never query without the team filter
- Never invent issue keys, user IDs, or field values
- If a field value is unknown, ask — don't guess
- If the user says "N days", substitute the number directly into the JQL (e.g. `-7d`)
- For date fields use ISO format: `YYYY-MM-DD`
