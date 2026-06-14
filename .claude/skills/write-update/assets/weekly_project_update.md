# Template: Weekly Project Update

## Purpose
Weekly status update for a specific project or initiative, primarily for stakeholders and leadership.
Covers the project's current health, key developments, and what's coming next.

## Tone & style
- Direct, outcome-first. No "we are pleased to announce" language.
- Use the status indicator to set the tone immediately.
- Main text must be concise — one status line plus the reason(s) for that status. No additional prose.
- All detail goes in the "More detail" section, not the main text.
- Don't invent. If there is no data for a section, omit the bullet rather than filling with filler.

---

## Instructions

These instructions tell the skill how to collect data for this template. They are read before any sources are fetched.

**Project identification**
- If the project is not clear from the user's prompt, ask: "Which project should this update cover?" and list the projects found in the team file's `## Slack` temporary/project channels and `## Update Sources`.
- Accept either a project name or an epic key. Resolve the project from the team file.

**Jira**
- Scope queries to the epic(s) associated with the project. Do not pull issues from other epics.
- If no epic is found for the project, flag it and ask the user before proceeding.

**Slack**
- If the team file lists a dedicated Slack channel for the project (e.g. under `Temporary / project channels`), read only that channel.
- Also read the main team channel, but instruct the subagent to extract only messages that mention the project name or its epic keys — ignore unrelated threads.

**URLs**
- Read only the URL(s) explicitly associated with the project in the team file's `## Update Sources`.
- For meeting notes URLs that are shared across topics, instruct the subagent to extract only content that mentions the project name or its epic keys.
- Do not read team-wide or unrelated URLs.

---

## Structure

### Status line
`🗞️ [STATUS] because:`

STATUS must be exactly one of:
- `ON TRACK`
- `AT RISK`
- `OFF TRACK`
- `COMPLETED`
- `PAUSED`

Followed by a brief reason list (1–N bullets). Each bullet is one concise sentence explaining why the project has that status. No additional context here — details belong in "More detail".

Example:
```
🗞️ AT RISK because:

- Backend migration is 2 weeks behind schedule due to unexpected schema complexity.
- Dependency on Platform team not yet unblocked.
```

---

### More detail

#### 🌤️ Highlights
2–5 bullets. Concrete progress made this period:
- Shipped items, decisions reached, milestones hit
- Quantify where possible (%, dates, counts)

#### ⛈️ Lowlights
1–4 bullets. Honest account of problems, delays, or risks:
- Name the issue and its impact
- Include mitigation or next step

#### 👉 Upcoming
1–4 bullets. What is planned for the next period:
- Specific deliverable or milestone
- Expected date or timeframe if known

#### ℹ️ FYI
0–4 bullets. Optional. Relevant project information that wasn't captured in the sections above, including any content shared this week related to the project:
- Links shared this week: recordings, presentations, Confluence pages, design docs, Figma files, videos — anything a reader might want to reference
- Related decisions or context that didn't rise to a highlight or lowlight but is still worth knowing
- Omit this section entirely if there is nothing relevant to add.