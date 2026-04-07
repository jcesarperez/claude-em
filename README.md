# Claude EM

Claude EM turns Claude into a practical, opinionated **assistant** that understands **your team, your context, and how you run engineering**.

Instead of starting from a blank prompt, Claude already knows:
- your team
- your context
- how you like to work

It comes with **reusable skills** to support your initiatives and your day-to-day tasks, like planning, writing epics and stories, analyzing IC activity, preparing 1:1s, working with Jira, or drafting strategies.

It is intentionally **CLI-first**: faster, more predictable, and more cost-efficient in terms of tokens than relying on MCP servers.

Built for teams using **Jira** and **GitHub**. Other tools can be added via CLI scripts or MCP servers.

---

## Quick start (2 minutes)

1. Click on **"Use this template"** and create your own repository

2. Install Claude Code:

```bash
npm install -g @anthropic-ai/claude-code
```

3. Add your team context:

* Copy `data/team_example.md` → `data/team_myteam.md`
* Fill in your team context and members

4. Open Claude in your workspace:

```bash
claude
```

5. Try your first prompt:

> I want to write a discovery epic to assess frontend performance issues

6. Complete the full setup to unlock data-driven workflows (Jira, GitHub, and more)

---

## How it works

* **CLAUDE.md** defines your personal EM style and how Claude should behave
* **Skills** (`.claude/skills/`) are reusable prompts for specific EM tasks
* **Team context** (`data/team_*.md`) defines your team
* **Data** (`data/`) stores shared information (Jira, GitHub, etc.)
* **Initiatives** are folders where work, analysis, and outputs live
* **CLI-first approach**: prefers CLI tools over MCP servers to stay fast, predictable, and low-cost in terms of tokens

---

## Skills

| Skill | What it does |
|---|---|
| `/ic-activity` | Analyze an IC's delivery, quality, and collaboration using Jira + GitHub data |
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

## Example use cases

* Plan an initiative  
  > Plan an initiative to reduce CI flakiness using our current setup  

* Analyze IC activity  
  > Analyze Javier's last 30 days activity

* Prepare a 1:1  
  > Prepare a 1:1 with ana who is delivering less lately and seems a bit disconnected

* Write a strategy  
  > Write a strategy to reduce operational load on the team  

* Mentor me 
  > I'm thinking of reorganizing the team, help me think this through

---

## Setup (full)

### 1. Create your workspace

Click on **"Use this template"** and create your own repository.

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

Your workspace is independent from the template.

Check the repository releases to see:
- New skills
- Improvements
- Bug fixes

There is no need to stay fully in sync — adopt changes only when they are useful.

---

## Contributing

Contributions are welcome, especially:

* Feedback
* Suggestions
* New skills
* Support for additional tools


