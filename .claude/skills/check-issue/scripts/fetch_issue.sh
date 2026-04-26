#!/usr/bin/env bash
# fetch_issue.sh — Fetch a Jira issue with changelog, subtasks, and parent epic
#
# Usage:
#   ./fetch_issue.sh ISSUE_KEY          # human-readable output
#   ./fetch_issue.sh ISSUE_KEY --json   # raw JSON output

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 ISSUE_KEY [--json]" >&2
  exit 1
fi

ISSUE_KEY=$1
JSON_MODE=false
[[ "${2:-}" == "--json" ]] && JSON_MODE=true

# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../../../../.env.local"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

JIRA_TOKEN="${JIRA_TOKEN:-${JIRA_API_TOKEN:-}}"
JIRA_URL="${JIRA_URL:-https://mews.atlassian.net}"

if [[ -z "${JIRA_EMAIL:-}" || -z "$JIRA_TOKEN" ]]; then
  echo "Error: JIRA_EMAIL and JIRA_TOKEN must be set" >&2
  exit 1
fi

AUTH="-u ${JIRA_EMAIL}:${JIRA_TOKEN}"
HEADERS='-H "Accept: application/json"'

jira_get() {
  local path=$1
  curl -s -f \
    -u "${JIRA_EMAIL}:${JIRA_TOKEN}" \
    -H "Accept: application/json" \
    "${JIRA_URL}${path}"
}

# ---------------------------------------------------------------------------
# jq lib (shared)
# ---------------------------------------------------------------------------
read -r -d '' JQ_LIB << 'JQLIB' || true

def parse_jira_date:
  gsub("\\.[0-9]+"; "")
  | gsub("([+-][0-9]{2}):?([0-9]{2})$"; "Z")
  | fromdateiso8601;

def format_duration:
  (if . < 0 then 0 else . end) as $s |
  ($s / 86400 | floor) as $d |
  (($s % 86400) / 3600 | floor) as $h |
  (($s % 3600) / 60 | floor) as $m |
  if $d > 0 then "\($d)d \($h)h \($m)m"
  elif $h > 0 then "\($h)h \($m)m"
  else "\($m)m"
  end;

def extract_adf:
  if . == null then ""
  elif type == "string" then .
  elif type == "object" then
    if .type == "hardBreak" then "\n"
    elif .text != null then .text
    else ((.content // []) | map(extract_adf) | join(""))
    end
  elif type == "array" then (map(extract_adf) | join(""))
  else ""
  end;

def time_in_current_status($current_status; $created; $now):
  (
    (.changelog.histories // [])
    | map(select(any(.items[]?; .field == "status" and .toString == $current_status)))
    | sort_by(.created)
    | last
    | .created // $created
  ) as $since |
  ($now - ($since | parse_jira_date)) as $secs |
  {
    formatted: ($secs | format_duration),
    seconds:   ($secs | floor),
    since:     $since
  };

JQLIB

# ---------------------------------------------------------------------------
# Fetch main issue (changelog expanded for transitions + assignee history)
# ---------------------------------------------------------------------------
echo "Fetching ${ISSUE_KEY}..." >&2
FIELDS="summary,status,issuetype,description,assignee,priority,duedate,created,updated,comment,subtasks,parent,customfield_10000,customfield_10014"
ISSUE_RAW=$(jira_get "/rest/api/3/issue/${ISSUE_KEY}?expand=changelog&fields=${FIELDS}")

ISSUETYPE=$(echo "$ISSUE_RAW" | jq -r '.fields.issuetype.name // ""')
if [[ -z "$ISSUETYPE" ]]; then
  echo "Error: issue ${ISSUE_KEY} not found" >&2
  exit 1
fi

NOW=$(date -u +%s)

# Fetch status category lookup for this project (one lightweight call)
PROJECT_KEY="${ISSUE_KEY%%-*}"
STATUS_CATEGORIES_RAW=$(jira_get "/rest/api/3/project/${PROJECT_KEY}/statuses" 2>/dev/null || echo "[]")
STATUS_CATEGORIES=$(echo "$STATUS_CATEGORIES_RAW" | jq '[.[] | .statuses[] | {(.name): .statusCategory.name}] | add // {}' 2>/dev/null || echo '{}')

# Extract PR data via dev-status API (primary), customfield_10000 as aggregate fallback
ISSUE_ID=$(echo "$ISSUE_RAW" | jq -r '.id // ""')
PR_DATA="null"

if [[ -n "$ISSUE_ID" && "$ISSUE_ID" != "null" ]]; then
  DEV_STATUS=$(jira_get "/rest/dev-status/1.0/issue/detail?issueId=${ISSUE_ID}&applicationType=GitHub&dataType=pullrequest" 2>/dev/null || echo "{}")
  PR_DATA=$(echo "$DEV_STATUS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
except Exception:
    print('null')
    sys.exit(0)
prs = [pr for detail in data.get('detail', []) for pr in detail.get('pullRequests', [])]
if not prs:
    print('null')
    sys.exit(0)
items = []
for pr in prs:
    status = pr.get('status', '').upper()
    items.append({
        'id':           pr.get('id', ''),
        'title':        pr.get('name', ''),
        'status':       status,
        'open':         status == 'OPEN',
        'author':       pr.get('author', {}).get('name', ''),
        'branch':       pr.get('source', {}).get('branch', ''),
        'last_updated': pr.get('lastUpdate'),
        'url':          pr.get('url', ''),
    })
items.sort(key=lambda p: p.get('last_updated') or '', reverse=True)
print(json.dumps({
    'count':       len(items),
    'open_count':  sum(1 for p in items if p['status'] == 'OPEN'),
    'draft_count': sum(1 for p in items if p['status'] == 'DRAFT'),
    'items':       items,
}))
" 2>/dev/null || echo "null")
fi

# Fallback: customfield_10000 aggregate (no individual PR data available)
if [[ "$PR_DATA" == "null" ]]; then
  PR_DATA=$(echo "$ISSUE_RAW" | jq -r '.fields.customfield_10000 // ""' | python3 -c "
import sys, re, json
raw = sys.stdin.read()
state_m = re.search(r'\bpullrequest=\{[^}]*\bstate=([A-Z_]+)', raw)
count_m = re.search(r'\bpullrequest=\{[^}]*\bstateCount=(\d+)', raw)
if not state_m:
    print('null')
    sys.exit(0)
state = state_m.group(1)
count = int(count_m.group(1)) if count_m else 1
print(json.dumps({
    'count':       count,
    'open_count':  count if state == 'OPEN' else 0,
    'draft_count': 0,
    'items':       None,
}))
" 2>/dev/null || echo "null")
fi

# ---------------------------------------------------------------------------
# Fetch subtasks (via JQL search with changelog, same pattern as fetch_epic.sh)
# ---------------------------------------------------------------------------
SUBTASKS_RAW='[]'
NUM_SUBTASKS=$(echo "$ISSUE_RAW" | jq '.fields.subtasks | length')
if [[ "$NUM_SUBTASKS" -gt 0 ]]; then
  echo "Fetching ${NUM_SUBTASKS} subtasks..." >&2
  SUB_FIELDS="summary,status,assignee,created,updated"
  SUB_JQL="parent = ${ISSUE_KEY} ORDER BY created ASC"
  SUB_PAGE=$(jira_get "/rest/api/3/search/jql?jql=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$SUB_JQL")&fields=${SUB_FIELDS}&expand=changelog&maxResults=50")
  SUBTASKS_RAW=$(echo "$SUB_PAGE" | jq '.issues // []')
fi

# ---------------------------------------------------------------------------
# Fetch parent epic (lightweight — key, summary, status only)
# ---------------------------------------------------------------------------
PARENT_EPIC='null'
PARENT_KEY=$(echo "$ISSUE_RAW" | jq -r '
  .fields.parent.fields.issuetype.name as $t |
  if $t == "Epic" then .fields.parent.key
  elif (.fields.customfield_10014 // "") != "" then .fields.customfield_10014
  else ""
  end // ""
')
if [[ -n "$PARENT_KEY" && "$PARENT_KEY" != "null" ]]; then
  echo "Fetching parent epic ${PARENT_KEY}..." >&2
  PARENT_RAW=$(jira_get "/rest/api/3/issue/${PARENT_KEY}?fields=summary,status")
  PARENT_EPIC=$(echo "$PARENT_RAW" | jq '{
    key: .key,
    summary: (.fields.summary // ""),
    status: (.fields.status.name // ""),
    statusCategory: ((.fields.status.statusCategory // {}).name // "")
  }')
fi

# ---------------------------------------------------------------------------
# Extract issue data
# ---------------------------------------------------------------------------
ISSUE_FILTER="${JQ_LIB}"'
. as $raw |
$raw.fields as $f |
($f.status.name // "") as $status |

# Status transitions from changelog
([
  ($raw.changelog.histories // [])[] |
  .created as $at |
  (.author.displayName // "Unknown") as $author |
  (.items[] | select(.field == "status")) |
  { from: .fromString, to: .toString, at: $at, author: $author }
] | sort_by(.at)) as $status_transitions |

# Assignee changes from changelog
([
  ($raw.changelog.histories // [])[] |
  .created as $at |
  (.author.displayName // "Unknown") as $changer |
  (.items[] | select(.field == "assignee")) |
  { from: .fromString, to: .toString, at: $at, changed_by: $changer }
] | sort_by(.at)) as $assignee_changes |

(($f.status.statusCategory // {}).name // "") as $status_category |

# First date the issue entered any "In Progress" category status
(
  $status_transitions
  | map(select($status_categories[.to] == "In Progress"))
  | if length > 0 then .[0].at
    elif $status_category == "In Progress" then ($f.created // null)
    else null
    end
) as $first_in_progress_at |

# First date the issue entered any "Done" category status
(
  $status_transitions
  | map(select($status_categories[.to] == "Done"))
  | if length > 0 then .[0].at else null end
) as $first_done_at |

{
  key: $raw.key,
  issuetype: ($f.issuetype.name // ""),
  summary: ($f.summary // ""),
  status: $status,
  statusCategory: $status_category,
  description: ($f.description | extract_adf | gsub("^\\n+|\\n+$"; "")),
  assignee: (($f.assignee // {}).displayName),
  priority: (($f.priority // {}).name),
  duedate: $f.duedate,
  created: ($f.created // ""),
  updated: ($f.updated // ""),
  comments: [
    (($f.comment.comments) // []) | .[] |
    {
      author: (.author.displayName // "Unknown"),
      created: .created,
      body: (.body | extract_adf | gsub("^\\n+|\\n+$"; ""))
    }
  ],
  time_in_current_status: (. | time_in_current_status($status; $f.created; $now)),
  first_in_progress_at: $first_in_progress_at,
  cycle_time: (
    if $status_category == "Done" and $first_in_progress_at != null and $first_done_at != null then
      (($first_done_at | parse_jira_date) - ($first_in_progress_at | parse_jira_date)) as $secs |
      { formatted: ($secs | format_duration), seconds: ($secs | floor) }
    else null
    end
  ),
  time_in_progress: (
    if $status_category == "In Progress" and $first_in_progress_at != null then
      ($now - ($first_in_progress_at | parse_jira_date)) as $secs |
      { formatted: ($secs | format_duration), seconds: ($secs | floor) }
    else null
    end
  ),
  status_transitions: $status_transitions,
  assignee_changes: $assignee_changes,
  pr: $pr,
  pr_merge_gap: (
    if $pr != null then
      ([$pr.items[]? | select(.status == "MERGED" and .last_updated != null) | .last_updated | parse_jira_date] | sort) as $merge_dates |
      if ($merge_dates | length) >= 2 then
        (($merge_dates[-1]) - ($merge_dates[0])) as $secs |
        { seconds: ($secs | floor), formatted: ($secs | floor | format_duration) }
      else null
      end
    else null
    end
  )
}
'

ISSUE=$(echo "$ISSUE_RAW" | jq --argjson now "$NOW" --argjson pr "$PR_DATA" --argjson status_categories "$STATUS_CATEGORIES" "$ISSUE_FILTER")

# ---------------------------------------------------------------------------
# Extract subtasks
# ---------------------------------------------------------------------------
SUBTASK_FILTER="${JQ_LIB}"'
. as $raw |
$raw.fields as $f |
($f.status.name // "") as $status |
{
  key: $raw.key,
  summary: ($f.summary // ""),
  status: $status,
  statusCategory: (($f.status.statusCategory // {}).name // ""),
  assignee: (($f.assignee // {}).displayName),
  created: ($f.created // ""),
  updated: ($f.updated // ""),
  time_in_current_status: (. | time_in_current_status($status; $f.created; $now))
}
'

SUBTASKS=$(echo "$SUBTASKS_RAW" | jq --argjson now "$NOW" \
  "[.[] | ${SUBTASK_FILTER}]")

# ---------------------------------------------------------------------------
# Compute ping pong signals
# ---------------------------------------------------------------------------
PINGPONG_FILTER="${JQ_LIB}"'
. as $issue |

# Status bounce: In Progress ↔ In Review cycles
(
  [.status_transitions[] | select(
    (.from | ascii_downcase | test("progress|review|review|qa")) and
    (.to   | ascii_downcase | test("progress|review|review|qa"))
  )] | length
) as $status_bounces |

# Assignee ping pong: reassigned more than twice
(.assignee_changes | length) as $assignee_change_count |

# Comment ping pong signals: look for questions, waits, passes
(
  [.comments[] | select(
    (.body | ascii_downcase | test(
      "waiting|blocked by|any update|can you|please|\\?|assigned to|over to|@"
    ))
  )] | length
) as $pingpong_comment_count |

# Unique comment authors (signals back-and-forth threads)
([.comments[] | .author] | unique | length) as $comment_author_count |

{
  status_bounces: $status_bounces,
  assignee_change_count: $assignee_change_count,
  pingpong_comment_count: $pingpong_comment_count,
  comment_author_count: $comment_author_count,
  # Ping pong detected if multiple signals align
  detected: (
    ($status_bounces >= 2) or
    ($assignee_change_count >= 3) or
    ($pingpong_comment_count >= 3 and $comment_author_count >= 2)
  )
}
'

PINGPONG=$(echo "$ISSUE" | jq "$PINGPONG_FILTER")

# ---------------------------------------------------------------------------
# JSON output
# ---------------------------------------------------------------------------
if [[ "$JSON_MODE" == true ]]; then
  jq -n \
    --argjson issue "$ISSUE" \
    --argjson parent_epic "$PARENT_EPIC" \
    --argjson subtasks "$SUBTASKS" \
    --argjson pingpong "$PINGPONG" \
    --arg fetched_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      fetched_at: $fetched_at,
      issue: $issue,
      parent_epic: $parent_epic,
      subtasks: $subtasks,
      pingpong: $pingpong
    }'
  exit 0
fi

# ---------------------------------------------------------------------------
# Human-readable output
# ---------------------------------------------------------------------------
SEP="========================================================================"
echo ""
echo "$SEP"
echo "$ISSUE" | jq -r '"ISSUE  \(.key)  [\(.issuetype)]"'
echo "$SEP"
echo "$ISSUE" | jq -r '
  "  Summary    : \(.summary)",
  "  Status     : \(.status)  [\(.statusCategory)]",
  "  Assignee   : \(.assignee // "Unassigned")",
  "  Priority   : \(.priority // "—")",
  "  Due date   : \(.duedate // "—")",
  "  In status  : \(.time_in_current_status.formatted)  (since \(.time_in_current_status.since[:10]))",
  "  1st in prog: \(if .first_in_progress_at != null then .first_in_progress_at[:10] else "—" end)",
  (if .statusCategory == "Done" then
    "  Cycle time : \(if .cycle_time != null then .cycle_time.formatted else "—" end)"
  elif .statusCategory == "In Progress" then
    "  In progress: \(if .time_in_progress != null then .time_in_progress.formatted else "—" end)"
  else empty end),
  "  Created    : \(.created[:10])  Updated: \(.updated[:10])"
'
echo ""
echo "$ISSUE" | jq -r '
  if .pr != null then "  PR         : \(.pr.state) (\(.pr.count)) — last updated \(.pr.last_updated // "unknown")"
  else "  PR         : none"
  end
'
if [[ "$PARENT_EPIC" != "null" ]]; then
  echo "$PARENT_EPIC" | jq -r '"  Parent     : \(.key) — \(.summary) [\(.status)]"'
fi

NSUB=$(echo "$SUBTASKS" | jq 'length')
if [[ "$NSUB" -gt 0 ]]; then
  echo ""
  echo "  Subtasks ($NSUB):"
  echo "$SUBTASKS" | jq -r '.[] | "    \(.key)  [\(.status)]  \(.assignee // "Unassigned")  (\(.time_in_current_status.formatted))  \(.summary)"'
fi

echo ""
echo "  Comments: $(echo "$ISSUE" | jq '.comments | length')"
echo "$ISSUE" | jq -r '
  if (.comments | length) > 0 then
    .comments[] |
    "    [\(.created[:10])] \(.author): \(.body[:160] | gsub("\n"; " "))"
  else empty end
'

echo ""
echo "  Ping Pong signals:"
echo "$PINGPONG" | jq -r '
  "    Status bounces     : \(.status_bounces)",
  "    Assignee changes   : \(.assignee_change_count)",
  "    Pingpong comments  : \(.pingpong_comment_count)",
  "    Detected           : \(.detected)"
'
echo "$SEP"
