# Claude EM

**Claude EM turns Claude into an Engineering Manager operating system.**

Not a generic AI. Not a blank prompt.

A context-aware, opinionated system that understands:
- your team
- your context
- how you run engineering

## Why Claude EM

It comes with:
1. Persistent context → **your team** + **your way of working**
2. Reusable workflows → **skills** that support real EM tasks

Claude EM is built for **day-to-day EM work**:
- Plan initiatives with clear scope and trade-offs
- Write epics and stories that engineers can actually build
- Analyze IC performance using real data (Jira + GitHub)
- Prepare 1:1s with context and intent
- Think through org and leadership decisions

It is intentionally **CLI-first**: faster, more predictable, and more cost-efficient (tokens).

Works out of the box with **Jira** and **GitHub**. Other tools can be added via CLI scripts or MCP servers.

---

## Quick start (2 minutes)

1. Click on **[Use this template](https://github.com/new?template_name=claude-em&template_owner=jcesarperez)** and create your own repository

2. Install Claude Code:

```bash
npm install -g @anthropic-ai/claude-code
```

3. Add your team context:

* Copy `data/team_example.md` → `data/team_myteam.md`.
* Fill in your team context and members

4. Open Claude in your workspace:

```bash
claude
```

5. Try your first prompt:

> I want to write a discovery epic to assess frontend performance issues

6. Complete the full setup to unlock data-driven workflows (Jira, GitHub, and more)

---

## Example use cases

* Plan an initiative
  > We have recurring CI flakiness slowing down delivery. Plan an initiative to reduce it

* Analyze IC activity
  > Analyze Maria's last 30 days

* Prepare a 1:1
  > Prepare a 1:1 with Ana. She’s delivering less lately and seems disengaged. I want to understand what's going on

* Write a strategy
  > Write a strategy to reduce operational load on the team while maintaining reliability

* Mentor
  > I'm considering reorganizing the team into two squads. Help me think through trade-offs and risks

* Prepare the daily meeting
  > Give me a daily-ready view of the team's board

* Generate a user story map
  > Generate a user story map from this PRD: [paste PRD]

* Check an epic
  > Check this epic

* Write a delivery epic
  > Write an epic to implement rate limiting in our API. Include scope, risks, and definition of done

* Write a discovery epic
  > We have performance issues in the frontend. Write a discovery epic to understand root causes and options
 
 ---

## How it works

* **CLAUDE.md** defines your personal EM style and how Claude should behave
* **Skills** (`.claude/skills/`) are reusable prompts for real EM tasks
* **Team context** (`data/team_*.md`) defines your team
* **Data** (`data/`) stores shared information (Jira, GitHub, etc.)
* **Initiatives** are folders where work, analysis, and outputs live
* **CLI-first approach**: prefers CLI tools over MCP servers to stay fast, predictable, and low-cost in terms of tokens

---

## Skills

| Skill | What it does |
|---|---|
| `/check-board` | Daily health check of a Jira Kanban board: flow, people load, stuck/blocked issues, and bugs at risk of breaching SLA |
| `/check-epic` | Analyze an Epic's definition, decomposition, and execution using Jira data |
| `/check-ic-activity` | Analyze an IC's delivery, quality, and collaboration using Jira + GitHub data |
| `/jira` | Create and query Jira issues — epics, stories, bugs, and tasks |
| `/mentor-me` | Think through a leadership situation with an Engineering Director mindset |
| `/one-on-one` | Prepare for a 1:1 — situation read, key questions, risks, and opening line |
| `/plan-initiative` | Structure a rough idea into a scoped initiative with epics and next steps |
| `/us-mapping` | Generate a User Story Map from a PRD or Figma design |
| `/write-epic-build` | Write a delivery epic with scope, risks, and definition of done |
| `/write-epic-technical-discovery` | Write a discovery epic focused on reducing uncertainty and enabling a decision |
| `/write-strategy` | Draft a strategy doc (Rumelt + Larson) with diagnosis, policies, and actions |
| `/write-us` | Draft a user story following INVEST and vertical slicing |
| `/write-vision` | Draft a vision doc with value proposition, capabilities, and constraints |

---

## Workspace structure

```
claude-em/
├── data/                       # Shared data across initiatives
│   ├── team_{name}.md          # Team context files
│   ├── [source]/               # One folder per data source (jira, github, etc.)
│   └── tmp/                    # Temporary files
└── [initiative-name]/          # One folder per initiative
    ├── data/                   # Initiative-specific data
    ├── tmp/                    # Temporary files
    ├── scripts/                # Analysis and processing
    └── output/                 # Results and reports
```

---

## Setup (full)

### 1. Create your workspace

Click on **[Use this template](https://github.com/new?template_name=claude-em&template_owner=jcesarperez)** and create your own repository.

This gives you a fully independent workspace you can customize.

---

### 2. Install Claude Code

```bash
npm install -g @anthropic-ai/claude-code
```

> Docs: https://docs.anthropic.com/claude-code

---

### 3. Configure your EM profile

Edit `CLAUDE.md` and define:

* Your EM style
* Your expectations from Claude
* Your way of working

Then create your team context:

* Copy `data/team_example.md`
* Rename it to `data/team_{your-team}.md`
* Fill in your team context and members

---

### 4. (Optional) Install CLI tools

Claude EM is designed to work primarily with CLI tools instead of MCP, as they are faster and more cost-efficient.

**Jira CLI (`jira`)**

```bash
brew install ankitpokhrel/jira-cli/jira
jira init
```

> Docs: https://github.com/ankitpokhrel/jira-cli

**GitHub CLI (`gh`)**

```bash
brew install gh
gh auth login
```

> Docs: https://cli.github.com

---

### 5. (Optional) Configure credentials

Create a `.env.local` file at the workspace root (git-ignored):

```bash
# Jira
JIRA_URL="https://your-domain.atlassian.net"
JIRA_EMAIL="your-email@company.com"
JIRA_API_TOKEN="your-api-token"

# GitHub
GITHUB_TOKEN="your-github-token"

# Figma
FIGMA_TOKEN="your-figma-token"
```

Getting credentials:
- **Jira API token**: https://id.atlassian.com/manage-profile/security/api-tokens
- **GitHub token**: https://github.com/settings/tokens (scopes: `repo`, `read:org`, `read:user`)
- **Figma token**: https://www.figma.com/settings → Personal access tokens

---

### 6. (Optional) Configure the Jira skill for your project(s)

The `/jira` skill works with any Jira project, but you need to point it at yours. When you invoke it for the first time, Claude will ask for the missing values and offer to save them permanently.

If you manage **more than one project**, create one skill file per project:

```bash
# Copy the base skill for each project
cp .claude/skills/jira-project/SKILL.md .claude/skills/jira-myproject/SKILL.md
cp .claude/skills/jira-project/SKILL.md .claude/skills/jira-otherproject/SKILL.md
```

Then open each copy and update:

1. **Folder name** — already done by the `cp` command above
2. **`name:` in the frontmatter** — must match the folder name (e.g. `jira-myproject`)
3. **`description:` in the frontmatter** — replace "any Jira project" with your project name so Claude picks the right skill when you have multiple
4. **The three configuration placeholders:**

| Placeholder | Example |
|---|---|
| `{{PROJECT_KEY}}` | `PLAT` |
| `{{CLOUD_ID}}` | `abc123-...` (from `jira config list`) |
| `{{BASE_URL}}` | `yourcompany.atlassian.net` |

Each copy becomes its own skill. Claude will pick the right one based on context, or you can invoke them explicitly.

---

### 7. (Optional) Configure MCP servers

MCP servers give Claude direct access to Jira, GitHub, and Figma without CLI or scripts.

```bash
claude mcp add --plugin atlassian
claude mcp add --plugin github
claude mcp add --plugin figma
```

---

## Notes

* You don’t need full setup to start — Quick Start is enough
* CLI tools and MCP improve automation but are optional
* The system works best when your team context is accurate and up to date

---

## Updating

Your workspace is yours.

Check the repository releases to see:
- New skills
- Improvements
- Bug fixes

Pull improvements when they’re useful.

---

## Contributing

Contributions are welcome:

* Feedback from real usage
* Suggestions
* New skills
* Support for additional tools

---

## License

MIT
