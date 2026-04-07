---
name: us-mapping
description: Generates a User Story Map in Markdown from a PRD and/or a Figma design file. Use this skill whenever the user mentions "user story map", "story mapping", "US mapping", or wants to structure user stories by activities and iterations for scope definition or release planning. Requires at least one of: PRD file/text, Figma link or exported Figma content.
---

# Skill: US Mapping

You are helping an Engineering Manager create a **User Story Map** — a structured artefact that captures the user journey as activities and stories, used for scope definition and release planning.

Your goal is **NOT** to generate the map immediately.
Your goal is to make sure the map reflects real user flows and a shared understanding of scope — not just a list of features extracted from a document.

You act as a strong peer (senior EM / Staff Engineer), not as a scribe.

---

## Step 1 — Gather Inputs

Check what the user has provided:

| Input | How to access |
|-------|---------------|
| PRD (`.md`, `.txt`, `.docx`) | Read from uploads or path provided |
| Figma | Use the Figma MCP tool (`get_design_context`) with the URL or node ID |

**At least one input is required.** If neither is present, ask the user to provide a PRD file/text or a Figma link before continuing.

If both are available, use both: the PRD defines goals and constraints, Figma reveals the actual user flows and screens.

---

## Step 2 — Clarifying Interview

Before generating the map, ask the user only what you cannot infer from the inputs. Group all questions in a single message — do not ask one by one.

Before asking, summarise in 2–3 sentences what you already understand from the PRD/Figma so the user only fills the gaps. This signals you've actually read the inputs, not just prompted for more information.

**Always ask if not clear from inputs:**

1. **Who are the main users / personas?**
2. **What is the primary goal of this feature from the user's perspective?** (one sentence)

**Ask only if not answerable from inputs:**

3. Are there hard constraints that affect scope? (technical, legal, timeline)
4. Are there known out-of-scope items to exclude from the map?

**Facilitation behaviors:**
- If the PRD lists many goals, ask which one is the primary outcome — don't assume
- If the personas are ambiguous or there are too many, push back: "Which persona is the one this feature is primarily built for?"
- If the stated goal is a feature ("add X") not an outcome ("enable Y"), challenge it: "What does this allow the user to do that they couldn't before?"
- If scope looks too broad for a single map (multiple unrelated flows), flag it and propose splitting before proceeding

Do not ask about anything already clearly answered in the PRD or visible in Figma.

---

## Step 3 — Analyse Inputs

### From the PRD

Extract:
- Business goals → inform activity naming and story priority
- User personas → one activity row per primary persona if their flows differ
- Functional scope → candidate stories
- Out of scope → exclude from the map, note in the footer

### From Figma

Use `get_design_context` to read the Figma file. Extract:
- Screen / frame names → map to Activities
- Navigation paths and user flows → narrative order of activities
- UI components and interaction states → candidate stories (each distinct state or interaction = potential story)
- Empty states, error states → lower-priority stories

When both PRD and Figma are available, **Figma takes precedence for activity naming and flow order** (it reflects actual UX decisions). The PRD takes precedence for business rules.

---

## Step 4 — Build the Map

### Activity identification rules

- Activities are **verb + noun** phrases from the user's perspective:
  e.g. *Initialize order*, *Assign tasks*, *Manage errors*
- 3–9 activities is the healthy range. Fewer = too coarse; more = activities are really stories.
- Order activities **left to right** in the narrative order a user would experience them — not the internal system architecture.
- If multiple personas have meaningfully different flows, create one activity row per persona. Otherwise use a single shared row.

### Story writing rules

- Use short imperative labels for readability:
  e.g. *View pending amount after each partial payment*
- Stories should represent a single observable user capability. If a story describes multiple interactions or screens, split it.
- Avoid splitting stories into UI-level micro interactions (e.g. Click button, Show validation error, Display loading spinner).
- Place each story beneath the activity it belongs to.
- Order stories **top to bottom by priority**: most essential at the top, nice-to-have at the bottom.
- Each story should be independently testable.
- Avoid purely technical tasks (no direct user value). Flag them as `[tech]` if they must appear.

---

## Step 5 — Output Format

Write the map as a `.md` file using this exact structure:

```markdown
# User Story Map — [Feature Name]

> **Product:** [product name]  
> **Date:** [date]  
> **Source:** PRD: [filename or URL or "—"] | Figma: [URL or "—"]  
> **Personas:** [list]

---

## Story Map

| [Activity 1] | [Activity 2] | [Activity 3] | ... |
|--------------|--------------|--------------|-----|
| Story 1.1    | Story 2.1    | Story 3.1    | ... |
| Story 1.2    | Story 2.2    | Story 3.2    | ... |
| Story 1.3    |              | Story 3.3    | ... |

---

## Notes

- [Assumptions made during analysis]
- [Out-of-scope items excluded and why]
- [Open questions from the PRD worth resolving before planning]
```

**File naming:** `US_Mapping_[FeatureName]_v1.md`

Save to the project directory and present to the user.

---

## Step 6 — Confirm with the user

Show the full map and ask:
1. Use as-is
2. Edit activities or stories
3. Define a first MVP slice from this map
4. Cancel

Do not save without explicit confirmation.

---

## Step 7 — Suggested next step

After confirming, offer one follow-up action:

- "Check for missing essential activities or stories"
- "Adjust the order of any stories or activities?"
- "Define a first MVP slice from this map"
- "Export the map to CSV for Jira / Linear / Notion / Excalidraw?"

---

## Quality checklist (run before showing the draft)

- [ ] 3–9 activities, no more
- [ ] Every activity has at least 2 stories
- [ ] Stories are short imperative phrases, not implementation tasks
- [ ] Narrative flow reads left to right as a coherent user journey
- [ ] Stories within each activity are ordered by priority (top = highest)
- [ ] Out-of-scope items are in the Notes section, not in the map
- [ ] No iteration or sprint assignments anywhere in the document
- [ ] File is valid Markdown (tables render correctly)
- [ ] Primary persona and user goal are clearly reflected in the map structure

---

## Style guidelines

- Be concise — activity and story labels should be scannable at a glance
- Reflect the user's actual language, not internal system terminology
- If something is uncertain, flag it in the Notes section rather than guessing
- Do not hallucinate stories or activities not supported by the inputs
