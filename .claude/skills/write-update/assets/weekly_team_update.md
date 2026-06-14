# Template: Weekly Team Update

## Purpose
Weekly update for the whole organisation, primarily for the Engineering Manager's manager.
Covers one engineering team's last 7 days: shipped work, problems, feedback, pipeline, metrics, allocation.

## Tone & style
- Direct, outcome-first. No "we are pleased to announce" language.
- Tone is warm and narrative.
- Every achievement should be quantified where possible (%, counts, latency ms, cost €/day).
- Lowlights are honest — don't bury risks. When the team responded well, say so — honesty includes recognising good execution under pressure.
- Links to Jira or Atlas are optional. Prioritise readability for a leadership audience over traceability.
- If there is no collected data or evidence, don't include the metric. Don't invent.

---

## Structure

### Header
`📰 Week ending [YYYY-MM-DD] [Team Name] Update`

---

### 🌤️ Highlights
3–8 bullet points. Each covers one shipped item or significant achievement:
- Name the feature/initiative
- One sentence of context or impact — focus on outcomes visible to customers or the organisation, not implementation details
- A metric or customer-visible outcome where available
- Use sub-bullets when there are multiple details (e.g. steps an agent performs, several perf numbers)
- Omit execution details (specific PRs, test counts, internal refactors) unless they have a clear org-level impact

---

### ⛈️ Lowlights
2–6 bullet points. Each covers a delay, incident, or risk:
- Name the specific issue
- Brief factual description of the problem
- Mitigation or next step — if the team responded well, say so
- For incidents: include root cause and current status in sub-bullets (2–4 sub-bullets)
- Keep the list focused on what matters at org level; not every bug or blocker needs to appear

---

### ✨ Feedback Loop & Content of the Week
1–3 bullets mixing:
- Customer feedback quotes (bold customer name + quote)
- Narrative summaries of achievements told as a story for a broader audience (warmer tone, 2–3 sentences)
- Links to videos, offsite summaries, articles, or notable Slack threads
- Screenshots or images if relevant

#### 🤖 AI Acceleration across the teams (sub-section, include if applicable)
1-2 bullets points:
- Describe a specific AI-assisted achievement or experiment
- Narrative summaries of achievements told as a story for a broader audience (warmer tone, 2–3 sentences)
- Include concrete efficiency metrics if they exist (%, counts, time saved)

---

### 🔭 Looking Ahead
2–6 items, each a project link followed by:
`[release stage] | [timeframe] | Tier [N]`

No prose. Pure pipeline list. Carry over items from previous weeks; update stage/dates as things ship.

---

### 📸 Metrics Snapshot
- Incidents: Critical: N / Major: N / Minor: N
- CCTs: Open: N / Resolved: N

No prose. Pure data.

---

### 💰 Team Allocation (past 7 days, Jira-based, by ticket count)
Total completed Jira items: N
- Strategy: X% (N items)
- Scale: X% (N items)
- KTLO: X% (N items)

No prose. Pure data.