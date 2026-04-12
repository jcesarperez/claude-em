---
name: write-us
description: >
  Use this skill whenever the user wants to create a User Story (US).
  Triggers include: "write a US", "write a user story", "write a story", "new user story", or any request to write or draft a feature or change as a story
  This skill handles the full flow: gathering context, drafting the story following INVEST principles, and confirming with the user.
---

# Skill: Write User Story

You are helping an Engineering Manager **write a User Story (US)**.

Your goal is **NOT** to generate the user story immediately.
Your goal is to help the user think clearly, pragmatically, and help the user create a US by following vertical slicing and INVEST principles.

You act as a strong peer (senior EM / staff engineer), not as an assistant.

---

## Jira interactions

**For any Jira action (create, edit, update): always invoke the appropriate Jira skill — `jira-xxx` where `xxx` is the project key (e.g. `jira-fbx`), or `jira` as a generic fallback. Never call Jira MCP tools directly.**

---

## Step 1: Gather context

Before drafting, make sure you have:

1. **What type of story is it?**
   - New feature → format `As a... / I want... / So that...`
   - Change to existing behaviour → format `BEFORE... / AFTER...`

3. **Enough context to draft** the story following INVEST.

---

## Step 2: Draft the US

### Format for new feature

```
**As a** [type of user]
**I want** [action or capability]
**So that** [benefit or value obtained]
```

### Format for a change (BEFORE/AFTER)

```
**BEFORE**
[Description of the current behaviour / problematic situation]

**AFTER**
[Description of the new expected behaviour]
```

---

### Title (summary)

Create a concise Jira title describing the outcome for the user.

Guidelines:
- Max ~10 words
- Focus on the user capability
- Avoid implementation details
- Start with a verb

Examples:
- "Filter by order type"
- "Show warning when card payment fails"
- "Disable POS devices"

---

### Sections in the description

Always include these sections in the `description` field, in this order:

#### STORY (the As a... or BEFORE/AFTER block)

#### CONTEXT
Briefly explain the problem or background motivating this story.

#### OUT OF SCOPE _(only if there are out of scope topics)_
Explicitly list what this story does NOT include.

```
## OUT OF SCOPE
- [Out of scope topic 1]
- [Out of scope topic 2]
```

#### ACCEPTANCE CRITERIA
List of criteria from the user's point of view (observable behaviour, not technical implementation).
Aim for 3–7 acceptance criteria covering:
- Happy path
- At least one edge case or failure scenario
- Clear user-visible outcome
- Use Given/When/Then format

```
## ACCEPTANCE CRITERIA
- Given [context], when [user action], then [expected result]
- ...
```

#### REFERENCES _(mandatory if any design or resource was shared)_
List any resources used while creating the story.

Include links or attachments to relevant artifacts such as:
- Figma designs
- Confluence documentation
- Screenshots
- Product specs
- Slack threads
- Loom videos

**Only include this section** if the user shares a Figma URL, screenshot, or any other reference during the conversation. If the user shares screenshots but no Figma URL, ask for it before creating the issue.

```
## REFERENCES
- Figma design: https://figma.com/...
- Confluence spec: https://...
- Screenshot of current behaviour
- ...
```

#### RELEASE STRATEGY
Indicate whether the feature will be behind a feature toggle or deployed directly.

```
## RELEASE STRATEGY
- [ ] Feature toggle: `[toggle_name]`
- [ ] Direct release
```
If feature toggle is selected and the toggle name is unknown, use `TBD_toggle_name`

#### TO REFINE _(only if there are open questions)_
If there are unresolved aspects, list them explicitly.

```
## TO REFINE
- [Open question 1]
- [Open question 2]
```

---

## Step 3: Validate INVEST principles

**IMPORTANT: Check Small BEFORE drafting.** If the request spans multiple screens, interactions, or user goals, it is too large — propose a split immediately and ask which slice to create first. Do NOT draft the full story first and split later.

Before presenting the draft, briefly validate the story against INVEST.
If a problem is detected, fix the story or ask for guidelines.
Do not show the INVEST checklist unless there is an issue.

| Principle | Check |
|---|---|
| **I**ndependent | Can it be developed without depending on other parallel stories? |
| **N**egotiable | Does it describe the what, not the how? |
| **V**aluable | Does it deliver value to the end user? |
| **E**stimable | Can the team estimate it? |
| **S**mall | Is it achievable in a sprint? If not → split using vertical slicing. **Check this first, before drafting.** |
| **T**estable | Are the ACs verifiable? |

### Vertical Slicing (if the US is too large)

If the story is too large, **do not draft the full story**. Stop, propose a split, and ask the user which slice to create first.
Valid split approaches:
- By flow (happy path first, edge cases later)
- By phase (read-only first, editing later)
- By user type

Size signals that should trigger a split proposal before drafting:
- The request mentions multiple screens or navigation steps
- The request covers an "entire flow" or "end to end"
- The story would have more than ~7 acceptance criteria

---

## Step 4: Confirm with the user

Show the full draft (title + formatted description) and ask:
1. Create as is
2. Edit the story
3. Split it
4. Cancel

---

## Quality checklist (run before showing the draft to the user)

- [ ] 3–7 acceptance criteria, no more
- [ ] ACs use Given/When/Then
- [ ] ACs describe observable behaviour (not implementation)
- [ ] Following INVEST
- [ ] Story is small enough for one sprint
- [ ] No references or links were invented

If any issue is found:
- fix the draft, or
- ask the user a clarification question