---
name: write-update
description: Write a periodic update (weekly, monthly, etc.) for a team. Reads data from Jira, Slack, and configured URLs for the last N days and generates the update in the chosen template format.
---

# Skill: Write Update

You are helping an Engineering Manager write a periodic update for their team.

---

## Step 1 — Determine inputs

Check the user's prompt for:
- **Team** (required — e.g. "events"). If missing, ask.
- **Format** (optional — template name). If missing, list the `.md` files in this skill's `assets/` folder and ask the user to choose.
- **Date range** (optional — defaults to last 7 days inclusive from today). Accept natural language like "last week" or "from Monday to Sunday". Convert to absolute dates before passing to subagents.

Once you have the team, read `data/team_{name}.md` and extract:
- Jira project key, board ID, Jira skill name, and conventions
- Slack channels (under `## Slack`)
- Update source URLs (under `## Update Sources`)

Then read the chosen template file. If it contains an `## Instructions` section, follow those instructions now — before deciding which sources to query. The instructions may:
- Tell you to ask the user which project this update is for
- Restrict which Jira epics, Slack channels, and URLs to use
- Tell you to filter shared sources (e.g. meeting notes) by project name or epic keys

Resolve all source scoping decisions before launching subagents in Step 2.

---

## Step 2 — Collect data via parallel subagents

Launch one subagent per data source using the `Agent` tool, all in parallel (single message, multiple tool calls). Do not wait for one before launching the others.

Pass each subagent only what it needs. Each subagent must return a **structured summary** — never raw content.

### Subagent: Jira

Prompt template:
> You are collecting Jira data for a team update.
>
> Team: {team}
> Date range: {date_from} to {date_to}
> Jira project key: {project_key}
> Jira skill: {jira_skill}
> Jira conventions: {conventions}
>
> Use the `{jira_skill}` skill to query:
> - Epics updated or closed in this date range
> - Issues updated or closed in this date range
> - Apply all team-specific filters
>
> Return a structured summary with:
> - **Completed**: list of done items (title, Jira URL, epic they belong to, any metrics)
> - **In progress / updated**: notable items that moved but aren't done
> - **Incidents / bugs**: any incidents or customer cases
> - **Allocation**: counts by Strategy / Scale / KTLO if available
>
> If data is unavailable, return `{"error": "reason"}`.

### Subagent: Slack (one per channel)

Launch one subagent per Slack channel. Prompt template:
> You are extracting signal from a Slack channel for a team update.
>
> Channel: {channel_name}
> Date range: {date_from} to {date_to}
>
> **Important — use `mcp__claude_ai_Slack__slack_read_channel` as the primary tool.**
> The local `mcp__slack__*` tools (slack_list_channels, slack_get_channel_history, etc.) have broken authentication in this workspace and must NOT be used.
>
> Steps:
> 1. Compute Unix timestamps from the human-readable dates using Python or date CLI before calling Slack:
>    ```bash
>    python3 -c "import datetime; print(int(datetime.datetime(YYYY, MM, DD, tzinfo=datetime.timezone.utc).timestamp()))"
>    ```
>    Do NOT pre-calculate or hard-code Unix timestamps — always derive them from the date strings at runtime to avoid year-offset bugs.
> 2. Call `mcp__claude_ai_Slack__slack_read_channel` with the channel name (without the `#`).
>    - Pass the computed `oldest` and `latest` Unix timestamps to filter messages server-side.
>    - If the channel is private and the name doesn't resolve, try with the channel ID if known.
> 2. For individual threads with relevant signal, call `mcp__claude_ai_Slack__slack_read_thread` to fetch replies.
> 3. DM channels (IDs starting with `D`) are not accessible — return `{"error": "DM channel not accessible"}`.
>
> Extract only:
> - Shipped features or completed work mentioned
> - Decisions made
> - Risks, incidents, or blockers raised
> - Customer feedback quotes (verbatim if possible)
>
> Ignore: bot messages, standup check-ins, scheduling, reactions-only threads.
>
> Return a structured bullet list of findings, or `{"error": "reason"}` if the channel is unreachable.

### Subagent: URL (one per Update Source)

Launch one subagent per URL. Prompt template:
> You are extracting relevant information from a page for a team update.
>
> URL: {url}
> Date range: {date_from} to {date_to}
>
> **For Atlas URLs** (home.atlassian.com — project or goal update pages):
> Atlas is a separate Atlassian product; the MCP only covers Jira and Confluence, and WebFetch cannot authenticate. Use the bash script `data/atlassian/scripts/get_atlas_project_updates.sh`, which queries the Atlassian GraphQL API using credentials from `.env.local`:
> ```bash
> # Credentials are loaded automatically from .env.local by the script
> data/atlassian/scripts/get_atlas_project_updates.sh {project_key} {site_id} {date_from} {date_to}
> ```
> Extract the `project_key` from the URL (e.g. `MEWS-4494` from `.../project/MEWS-4494/updates`).
> The Mews site ID is `9cb80e14-6d83-4419-a743-3b8c78b0bf7f`.
>
> **For Confluence URLs** (mews.atlassian.net/wiki):
> 1. First try `mcp__claude_ai_Atlassian__fetch` with the full URL — this handles personal spaces and folders that the REST API cannot address by page ID.
> 2. If that fails, extract the space key from the URL path (e.g. `~71202020c7dda3e907495697c548dd58e509ff`) and search with CQL:
>    `space = "{space_key}" AND created >= "{date_from}" AND created <= "{date_to}"`
>    using `mcp__claude_ai_Atlassian__searchConfluenceUsingCql`.
> 3. Do NOT try to call the REST API directly using the numeric folder/page ID from the URL — personal space folders are not addressable this way and will return 404.
>
> **For other URLs:** fetch with WebFetch.
>
> Extract only content dated within the range. If dates are ambiguous, include the content and flag it.
>
> Return:
> - **Decisions / outcomes** from meetings or notes
> - **Risks or blockers** surfaced
> - **Notable context** relevant to a weekly team update
>
> Return `{"error": "reason"}` if the URL fails to load.

---

## Step 3 — Collect results and note gaps

Wait for all subagents to complete. Collect their outputs. For any subagent that returned an error, record it for the Data Gaps section — do not stop or retry.

---

## Step 4 — Synthesise

From all subagent outputs, build an internal fact list:
- Achievements with metrics
- Delays, incidents, risks
- Customer feedback quotes
- Pipeline / upcoming items
- Allocation data

Do not invent data. If a template section has no supporting facts, write `No data available this week.`

---

## Step 5 — Write the update

Read the chosen template file from this skill's `assets/` folder. Follow it exactly:
- Same section headings, order, and emoji
- Tone as described in the template
- Link every initiative/feature to its Jira or Atlas URL
- Quantify achievements wherever data supports it

---

## Step 6 — Report gaps

If any source failed, append after the update:

```
---
**Data gaps:**
- Slack #rnd-events-team: could not connect
- URL https://...: failed to load
```

Omit entirely if all sources returned data.

---

## Output

The full update, ready to review. No meta-commentary before or after.
The EM will review, edit, and publish manually.
