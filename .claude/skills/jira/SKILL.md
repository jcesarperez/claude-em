---
name: jira
description: >
  General-purpose Jira skill for any Jira project. Use for any Jira-related request:
  creating issues (Epic, Story, Bug, Task, Sub-task), querying issues (in progress,
  completed, by type/status, bugs by due date), or updating issues.
  Triggers include: "create an epic", "create a bug", "show me bugs", "epics in progress",
  "issues completed last N days", "bugs due in N days", or any request involving Jira.
---

# Skill: Jira — Project

## Setup

Before using this skill, replace the following placeholders throughout this file — **including the `name:` and `description:` in the frontmatter above**:

- `name:` → use a short identifier for your project (e.g. `jira-platform`, `jira-core`)
- `description:` → update "any Jira project" to mention your actual project name, so Claude picks the right skill when you have multiple

Then replace the configuration placeholders:

| Placeholder | Description | How to find it |
|---|---|---|
| `{{PROJECT_KEY}}` | Your Jira project key | Visible in any issue key (e.g. `PLAT-123` → key is `PLAT`) |
| `{{CLOUD_ID}}` | Your Atlassian Cloud ID | Run `jira config list` or extract from your Atlassian URL |
| `{{BASE_URL}}` | Your Jira domain | e.g. `yourcompany.atlassian.net` |

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
# Search / query
jira issue list -p {{PROJECT_KEY}} --jql "<JQL>"

# Create issue
jira issue create -p {{PROJECT_KEY}} -t <IssueType> -s "<summary>" [flags]

# View issue
jira issue view <ISSUE-KEY>
```

---

## A. Querying issues

Identify the query intent and build the appropriate JQL. Always scope to `project = {{PROJECT_KEY}}`.

### Common queries

| User request | JQL |
|---|---|
| Epics in progress | `project = {{PROJECT_KEY}} AND issuetype = Epic AND status = "In Progress" ORDER BY updated DESC` |
| Bugs open / in progress | `project = {{PROJECT_KEY}} AND issuetype = Bug AND status != Done ORDER BY priority ASC, duedate ASC` |
| Issues completed last N days | `project = {{PROJECT_KEY}} AND status = Done AND resolutiondate >= -Nd ORDER BY resolutiondate DESC` |
| Issues of type X in status Y | `project = {{PROJECT_KEY}} AND issuetype = X AND status = "Y" ORDER BY updated DESC` |
| Bugs due in ≤ N days | `project = {{PROJECT_KEY}} AND issuetype = Bug AND duedate <= Nd AND status != Done ORDER BY duedate ASC` |
| All open issues | `project = {{PROJECT_KEY}} AND status != Done ORDER BY updated DESC` |

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
