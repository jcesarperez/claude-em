# Changelog

## [v1.4.0] - 2026-05-10

### Added
- `check-board` skill — Evaluate the daily health of a Jira Kanban board: flow, people load, blocked/stuck issues, idle assignees, and bugs at risk of breaching SLA.

### Changed
- `CLAUDE.md` — Team context file trigger broadened: team files are now read whenever the team itself is referenced or a skill needs team-specific context (default Jira project, default board, repos, conventions), not only when a team member is mentioned
- `data/team_example.md` — Restructured Jira section: replaced the thin `## Jira Projects` block with a `## Jira` section that captures default project key, default board (id + URL), Jira skill to use, and a list of team-specific conventions; optional `Other projects` subsection for additional keys

### Fixed
- `check-ic-activity` skill — Jira queries now use the REST API (`POST /rest/api/3/search/jql`) instead of the `jira` CLI, which was defaulting to the configured project (FBX) and silently excluding issues from other projects (e.g. OPS)
- `check-ic-activity` skill — Fixed Jira issues completed query: replaced `resolved` with `resolutiondate` (correct field name in Jira API)
- `check-ic-activity` skill — WIP query now uses `statusCategory = 'In Progress'` instead of `status = 'In Progress'`, capturing all active statuses (Testing, Preparation, etc.) across projects
- `check-epic` skill — Cycle time now uses status categories instead of hardcoded status names ("In Progress", "Done"), fixing incorrect `null` cycle times for issues in projects with custom status names

---

## [v1.3.0] - 2026-04-26

### Added
- `check-issue` skill — Evaluate whether a Jira issue (Story, Bug, Task): execution health, ping pong detection, PR state, subtask movement
- `README.md` — Example use cases

### Changed
- `check-epic` skill — Issue cycle time now uses median instead of average (`median_cycle_time_days`)
- `ic-activity` skill renamed to `check-ic-activity` for consistency with other `check-*` skills

### Fixed
- `README.md` - `Check-epic` skill added to the skill list
- `jira-fbx` skill — Removed `ORDER BY` from JQL examples (CLI adds it automatically; including it returns 400). Added native CLI flags (`-a`, `--created-after`, `--created-before`, `--paginate`) as preferred alternative to `--jql` for simple filters

---

## [v1.2.0] - 2026-04-19

### Added
- `check-epic` skill — Evaluate the health of a Jira epic: definition quality, issue decomposition, and execution dynamics
- `README.md` — "Use this template" now links directly to the GitHub template URL

---

## [v1.1.0] - 2026-04-12

### Added
- MIT license

### Changed
- `ic-activity` skill — Issue cycle time now calculated as `In Progress → Done` using Jira REST API changelog
- `ic-activity` skill — In Focus, WIP = 0 is a red flag
- `ic-activity` skill — Default time range is now 14 days when no date is specified
- `ic-activity` skill — Quality and Collaboration sections now show individual metric scores inline when they differ from each other
- Improved README for clarity and structure

### Fixed
- `CLAUDE.md` — Tool priority order now puts project-specific Jira skills (e.g. `jira-xxx` or `jira`) first, before CLI and MCP tools
- `write-us`, `write-epic-build`, `write-epic-technical-discovery` skills — Added explicit rule to invoke the appropriate Jira skill (`jira-xxx` or `jira`) for any Jira action (create, edit, update); MCP tools must not be called directly
- `jira` skill — Added rule in Step 4 to always try the CLI first before falling back to MCP, even for structured descriptions
- `jira` skill — Added explicit rule that this skill is the preferred entry point for any Jira action, including when triggered from another skill (e.g. `write-us`, `write-epic-build`)

---

## [v1.0.1] - 2026-04-08

### Fixed
- CLAUDE.md: Initial EM's style is EMPTY and Claude EM will ask the user for a value

---

## [v1.0.0] - 2026-04-07

### Added
- Initial release with 11 skills:
  - `/ic-activity` — Analyze an IC's delivery, quality, and collaboration using Jira + GitHub data
  - `/jira` — Create and query Jira issues — epics, stories, bugs, and tasks
  - `/mentor-me` — Think through a leadership situation with an Engineering Director mindset
  - `/one-on-one` — Prepare for a 1:1 — situation read, key questions, risks, and opening line
  - `/plan-initiative` — Structure a rough idea into a scoped initiative with epics and next steps
  - `/us-mapping` — Generate a User Story Map from a PRD or Figma design
  - `/write-epic-build` — Write a delivery epic with scope, risks, and definition of done
  - `/write-epic-technical-discovery` — Write a discovery epic focused on reducing uncertainty and enabling a decision
  - `/write-strategy` — Draft a strategy doc (Rumelt + Larson) with diagnosis, policies, and actions
  - `/write-us` — Draft a user story following INVEST and vertical slicing
  - `/write-vision` — Draft a vision doc with value proposition, capabilities, and constraints
