#!/usr/bin/env bash
# fetch_board.sh — Fetch a Jira Kanban board snapshot with daily-focused metrics
#
# Usage:
#   ./fetch_board.sh BOARD_ID_OR_URL          # human-readable output
#   ./fetch_board.sh BOARD_ID_OR_URL --json   # raw JSON output
#
# Examples:
#   ./fetch_board.sh 5289
#   ./fetch_board.sh https://mews.atlassian.net/jira/software/c/projects/OPS/boards/5289 --json

set -euo pipefail

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 BOARD_ID_OR_URL [--json]" >&2
  exit 1
fi

BOARD_INPUT=$1
JSON_MODE=false
[[ "${2:-}" == "--json" ]] && JSON_MODE=true

# Parse board id (numeric or URL)
if [[ "$BOARD_INPUT" =~ ^[0-9]+$ ]]; then
  BOARD_ID="$BOARD_INPUT"
elif [[ "$BOARD_INPUT" =~ /boards/([0-9]+) ]]; then
  BOARD_ID="${BASH_REMATCH[1]}"
elif [[ "$BOARD_INPUT" =~ rapidView=([0-9]+) ]]; then
  BOARD_ID="${BASH_REMATCH[1]}"
else
  echo "Error: could not parse board id from '$BOARD_INPUT'" >&2
  exit 1
fi

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

jira_get() {
  curl -s -f -u "${JIRA_EMAIL}:${JIRA_TOKEN}" -H "Accept: application/json" "${JIRA_URL}$1"
}

# ---------------------------------------------------------------------------
# Discover Flagged custom field id (varies per tenant)
# ---------------------------------------------------------------------------
echo "Discovering Flagged field..." >&2
FLAGGED_FIELD_ID=$(jira_get "/rest/api/3/field" 2>/dev/null \
  | jq -r '[.[] | select(.name == "Flagged") | .id] | first // ""' || echo "")

# ---------------------------------------------------------------------------
# Fetch board metadata + configuration
# ---------------------------------------------------------------------------
echo "Fetching board ${BOARD_ID}..." >&2
BOARD_RAW=$(jira_get "/rest/agile/1.0/board/${BOARD_ID}")
BOARD_CONFIG_RAW=$(jira_get "/rest/agile/1.0/board/${BOARD_ID}/configuration")

BOARD_TYPE=$(echo "$BOARD_RAW" | jq -r '.type // ""')
BOARD_NAME=$(echo "$BOARD_RAW" | jq -r '.name // ""')
PROJECT_KEY=$(echo "$BOARD_RAW" | jq -r '.location.projectKey // empty')

if [[ -z "$PROJECT_KEY" ]]; then
  echo "Error: could not determine project key for board ${BOARD_ID}" >&2
  exit 1
fi

# Status category map (status name → category name) for the project
STATUS_CATEGORIES_RAW=$(jira_get "/rest/api/3/project/${PROJECT_KEY}/statuses" 2>/dev/null || echo "[]")
STATUS_CATEGORIES=$(echo "$STATUS_CATEGORIES_RAW" \
  | jq '[.[] | .statuses[] | {(.name): .statusCategory.name}] | add // {}')

# Columns (with status ids) and status_id → column_name map
COLUMNS=$(echo "$BOARD_CONFIG_RAW" | jq '
  [.columnConfig.columns[] | {name: .name, status_ids: [.statuses[].id]}]
')
STATUS_TO_COLUMN=$(echo "$BOARD_CONFIG_RAW" | jq '
  [.columnConfig.columns[] as $c | $c.statuses[] | {(.id): $c.name}] | add // {}
')

# ---------------------------------------------------------------------------
# Fetch all board issues (paginated, with changelog)
# ---------------------------------------------------------------------------
FIELDS="summary,status,issuetype,priority,created,updated,duedate,assignee,issuelinks,subtasks,parent"
if [[ -n "$FLAGGED_FIELD_ID" ]]; then
  FIELDS="${FIELDS},${FLAGGED_FIELD_ID}"
fi

TMPDIR=$(mktemp -d -t check-board.XXXXXX)
trap "rm -rf $TMPDIR" EXIT

# Fetch backlog keys (to exclude — user only sees from TODO column onwards)
echo "Fetching backlog keys..." >&2
BACKLOG_KEYS_FILE="${TMPDIR}/backlog_keys.json"
START_AT=0
BL_PAGE_NUM=0
while true; do
  PAGE_FILE="${TMPDIR}/backlog-${BL_PAGE_NUM}.json"
  jira_get "/rest/agile/1.0/board/${BOARD_ID}/backlog?fields=summary&startAt=${START_AT}&maxResults=100" > "$PAGE_FILE"
  COUNT=$(jq '.issues | length' "$PAGE_FILE")
  echo "  Backlog page: ${COUNT}..." >&2
  if [[ "$COUNT" -eq 0 ]]; then
    rm -f "$PAGE_FILE"
    break
  fi
  jq '[.issues[].key]' "$PAGE_FILE" > "${TMPDIR}/backlog-keys-${BL_PAGE_NUM}.json"
  rm -f "$PAGE_FILE"
  BL_PAGE_NUM=$((BL_PAGE_NUM + 1))
  START_AT=$((START_AT + COUNT))
done
if ls "${TMPDIR}"/backlog-keys-*.json >/dev/null 2>&1; then
  jq -s 'add // []' "${TMPDIR}"/backlog-keys-*.json > "$BACKLOG_KEYS_FILE"
else
  echo '[]' > "$BACKLOG_KEYS_FILE"
fi

echo "Fetching board issues..." >&2
START_AT=0
MAX_RESULTS=100
PAGE_NUM=0

while true; do
  PAGE_FILE="${TMPDIR}/page-${PAGE_NUM}.json"
  jira_get "/rest/agile/1.0/board/${BOARD_ID}/issue?fields=${FIELDS}&expand=changelog&startAt=${START_AT}&maxResults=${MAX_RESULTS}" > "$PAGE_FILE"
  COUNT=$(jq '.issues | length' "$PAGE_FILE")
  TOTAL=$(jq '.total // 0' "$PAGE_FILE")
  echo "  Fetched ${COUNT} (startAt=${START_AT}, total=${TOTAL})..." >&2

  if [[ "$COUNT" -eq 0 ]]; then
    rm -f "$PAGE_FILE"
    break
  fi

  jq '.issues' "$PAGE_FILE" > "${TMPDIR}/issues-${PAGE_NUM}.json"
  rm -f "$PAGE_FILE"

  PAGE_NUM=$((PAGE_NUM + 1))
  START_AT=$((START_AT + COUNT))
  if [[ "$TOTAL" -gt 0 && "$START_AT" -ge "$TOTAL" ]]; then break; fi
done

ALL_ISSUES_FILE="${TMPDIR}/all_issues.json"
if ls "${TMPDIR}"/issues-*.json >/dev/null 2>&1; then
  jq -s 'add // []' "${TMPDIR}"/issues-*.json > "$ALL_ISSUES_FILE"
else
  echo '[]' > "$ALL_ISSUES_FILE"
fi

NOW=$(date -u +%s)

# ---------------------------------------------------------------------------
# jq lib
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

def cat_rank($cat):
  if $cat == "To Do" then 1
  elif $cat == "In Progress" then 2
  elif $cat == "Done" then 3
  else 0 end;

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
    seconds: ($secs | floor),
    since: $since
  };

def last_transition_to_done_at($status_categories):
  [
    (.changelog.histories // [])[] as $h
    | $h.items[]?
    | select(.field == "status" and ($status_categories[.toString] == "Done"))
    | $h.created
  ]
  | sort
  | (if length > 0 then .[-1] else null end);

def cycle_time_of_issue($status_categories):
  (.changelog.histories // []) as $h |
  ($h | map(select(any(.items[]?; .field == "status" and ($status_categories[.toString] == "In Progress"))))
      | sort_by(.created) | .[0] | .created) as $ip |
  ($h | map(select(any(.items[]?; .field == "status" and ($status_categories[.toString] == "Done"))))
      | sort_by(.created) | .[-1] | .created) as $done |
  if ($ip != null and $done != null) then
    (($done | parse_jira_date) - ($ip | parse_jira_date)) as $secs |
    if $secs > 0 then {
      seconds: ($secs | floor),
      days: ($secs / 86400 * 10 | round / 10),
      formatted: ($secs | format_duration)
    } else null end
  else null end;

def regressions_last_7d($status_categories; $cutoff):
  [
    (.changelog.histories // [])[] as $h
    | select(($h.created | parse_jira_date) >= $cutoff)
    | $h.items[]?
    | select(.field == "status")
    | select(cat_rank($status_categories[.fromString]) > cat_rank($status_categories[.toString])
          and cat_rank($status_categories[.toString]) > 0)
    | {at: $h.created, from: .fromString, to: .toString}
  ];

JQLIB

# ---------------------------------------------------------------------------
# Per-issue extraction
# ---------------------------------------------------------------------------
ISSUE_FILTER="${JQ_LIB}"'
. as $issue |
$issue.fields as $f |
($f.status.id // "") as $status_id |
($f.status.name // "") as $status_name |
($flagged_field // "") as $ff |
{
  key: $issue.key,
  issuetype: ($f.issuetype.name // ""),
  is_bug: (($f.issuetype.name // "") | ascii_downcase | test("bug")),
  summary: ($f.summary // ""),
  status: $status_name,
  statusCategory: (($f.status.statusCategory // {}).name // ""),
  status_id: $status_id,
  column: ($status_to_column[$status_id] // ""),
  priority: (($f.priority // {}).name // ""),
  assignee: (($f.assignee // {}).displayName),
  duedate: $f.duedate,
  created: ($f.created // ""),
  updated: ($f.updated // ""),
  parent: (
    if ($f.parent // null) == null then null
    else { key: $f.parent.key,
           summary: (($f.parent.fields // {}).summary // ""),
           status: ((($f.parent.fields // {}).status // {}).name // ""),
           issuetype: ((($f.parent.fields // {}).issuetype // {}).name // "") }
    end
  ),
  num_subtasks: (($f.subtasks // []) | length),
  is_blocked: (
    if $ff == "" then false
    else (($f[$ff] // null) | (. != null and (type == "array") and (length > 0)))
    end
  ),
  blocked_by: [
    ($f.issuelinks // [])[]
    | select(.type.inward == "is blocked by" and .inwardIssue != null)
    | { key: .inwardIssue.key,
        status: (.inwardIssue.fields.status.name // ""),
        statusCategory: ((.inwardIssue.fields.status.statusCategory.name) // "") }
  ],
  time_in_current_status: (. | time_in_current_status($status_name; $f.created; $now)),
  cycle_time: cycle_time_of_issue($status_categories),
  last_done_at: last_transition_to_done_at($status_categories),
  regressions_last_7d: regressions_last_7d($status_categories; ($now - 604800))
}
'

EXTRACTED_FILE="${TMPDIR}/extracted.json"
jq \
  --argjson now "$NOW" \
  --argjson status_categories "$STATUS_CATEGORIES" \
  --argjson status_to_column "$STATUS_TO_COLUMN" \
  --arg flagged_field "$FLAGGED_FIELD_ID" \
  "[.[] | ${ISSUE_FILTER}]" "$ALL_ISSUES_FILE" > "$EXTRACTED_FILE"

# ---------------------------------------------------------------------------
# Snapshot: drop backlog; keep all non-Done; keep Done only if within 36h
# ---------------------------------------------------------------------------
CUTOFF_36H=$((NOW - 36*3600))
SNAPSHOT_FILE="${TMPDIR}/snapshot.json"
jq --argjson cutoff "$CUTOFF_36H" --slurpfile backlog_keys "$BACKLOG_KEYS_FILE" '
  ($backlog_keys[0] // []) as $bk |
  [.[]
   | .key as $k
   | select(($bk | index($k)) == null)
   | select(
       .statusCategory != "Done"
       or (
         .last_done_at != null
         and ((.last_done_at | gsub("\\.[0-9]+"; "") | gsub("([+-][0-9]{2}):?([0-9]{2})$"; "Z") | fromdateiso8601) >= $cutoff)
       )
     )]
' "$EXTRACTED_FILE" > "$SNAPSHOT_FILE"

# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------
METRICS_FILTER="${JQ_LIB}"'
($now - 604800)  as $cutoff_7d |
($now - 1209600) as $cutoff_14d |

def to_epoch: gsub("\\.[0-9]+"; "") | gsub("([+-][0-9]{2}):?([0-9]{2})$"; "Z") | fromdateiso8601;

($issues | length)                                                as $total |
($issues | map(select(.statusCategory == "Done"))        | length) as $done_recent |
($issues | map(select(.statusCategory == "In Progress")) | length) as $in_progress |
($issues | map(select(.statusCategory == "To Do"))       | length) as $todo |

# WIP per assignee (In Progress only, including unassigned bucket)
([$issues[] | select(.statusCategory == "In Progress")]
  | group_by(.assignee // "(unassigned)")
  | map({
      assignee: (.[0].assignee // null),
      count: length,
      keys: [.[].key],
      max_time_in_status_seconds: ([.[].time_in_current_status.seconds] | max),
      stuck_count:   ([.[] | select(.time_in_current_status.seconds >= 432000)] | length),
      blocked_count: ([.[] | select(.is_blocked)] | length)
    })
  | sort_by(-.count)) as $assignees_wip |

# People who can pull: have something in To Do but 0 in In Progress (and are real assignees on this board)
([$issues[] | .assignee] | map(select(. != null)) | unique) as $all_assignees |
([$assignees_wip[] | select(.assignee != null) | .assignee]) as $busy_assignees |
($all_assignees - $busy_assignees) as $idle_assignees |

# Stuck (In Progress, ≥5d). Critical at ≥10d.
([$issues[] | select(.statusCategory == "In Progress" and .time_in_current_status.seconds >= 432000)
  | { key, summary, status, column, assignee, is_blocked,
      time_in_status: .time_in_current_status.formatted,
      seconds: .time_in_current_status.seconds,
      severity: (if .time_in_current_status.seconds >= 864000 then "critical" else "warning" end) }]
  | sort_by(-.seconds)) as $stuck |

# Unassigned in In Progress
([$issues[] | select(.statusCategory == "In Progress" and .assignee == null)
  | { key, summary, status, column, time_in_status: .time_in_current_status.formatted }]) as $unassigned_in_progress |

# Blocked (Flagged field)
([$issues[] | select(.is_blocked)
  | { key, summary, status, statusCategory, column, assignee,
      time_in_status: .time_in_current_status.formatted }]) as $blocked |

# Regressions in last 7d (one record per regression item)
([$issues[] as $i | $i.regressions_last_7d[]
  | { key: $i.key, summary: $i.summary, at, from, to }]
  | sort_by(.at) | reverse) as $regressions |

# Throughput (use the full extracted set — Done was trimmed only in snapshot)
([$all_issues[] | select(.last_done_at != null and ((.last_done_at | to_epoch) >= $cutoff_7d))]  | length) as $throughput_7d |
([$all_issues[] | select(.last_done_at != null and ((.last_done_at | to_epoch) >= $cutoff_14d))] | length) as $throughput_14d |

# Median cycle time (Done in last 14d with valid cycle_time)
([$all_issues[]
  | select(.statusCategory == "Done" and .cycle_time != null
        and .last_done_at != null and ((.last_done_at | to_epoch) >= $cutoff_14d))
  | .cycle_time.days]) as $ct_vals |
(if ($ct_vals | length) > 0 then
  ($ct_vals | sort) as $sorted |
  ($sorted | length) as $n |
  (if ($n % 2) == 1 then $sorted[($n / 2 | floor)]
   else (($sorted[($n / 2) - 1] + $sorted[$n / 2]) / 2)
   end) * 10 | round / 10
else null end) as $median_cycle_time |

# Per-column summary (snapshot — includes Done<36h)
([$columns[] | . as $col | {
  name: $col.name,
  count:             ([$issues[] | select(.status_id as $sid | $col.status_ids | any(. == $sid))] | length),
  in_progress_count: ([$issues[] | select(.statusCategory == "In Progress" and (.status_id as $sid | $col.status_ids | any(. == $sid)))] | length),
  stuck_count:       ([$issues[] | select(.statusCategory == "In Progress" and .time_in_current_status.seconds >= 432000 and (.status_id as $sid | $col.status_ids | any(. == $sid)))] | length)
}]) as $columns_summary |

# Bugs: classify each non-Done bug
($now - ($now % 86400)) as $today_start_utc |
([$issues[] | select(.is_bug and .statusCategory != "Done")
  | (if .duedate != null then
       ((((.duedate + "T00:00:00Z" | fromdateiso8601) - $today_start_utc) / 86400) | floor) as $days_left
       | (if $days_left <= 3 then "red"
          elif $days_left <= 10 then "yellow"
          else "green" end) as $risk
       | { key, summary, status, column, assignee, priority, duedate,
           days_until_due: $days_left, risk: $risk, reason: "due date" }
     else
       (if .priority == "Highest" then "red" else "none" end) as $risk
       | { key, summary, status, column, assignee, priority, duedate: null,
           days_until_due: null, risk: $risk,
           reason: (if $risk == "red" then "Highest priority, no due date" else "no SLA" end) }
     end)]) as $bug_classified |

([$bug_classified[] | select(.risk == "red" or .risk == "yellow")]
  | sort_by((if .risk == "red" then 0 else 1 end), (.days_until_due // -999999))) as $bugs_at_risk |
([$bug_classified[] | select(.risk == "green" or .risk == "none")]) as $bugs_other |

# key → risk lookup (for epic aggregation)
([$bug_classified[] | {(.key): .risk}] | add // {}) as $risk_by_key |

# Epics: group active issues by parent epic
([$issues[] | select(.parent != null and (.parent.issuetype // "") == "Epic")]
  | group_by(.parent.key)
  | map({
      key:               .[0].parent.key,
      summary:           .[0].parent.summary,
      status:            .[0].parent.status,
      active_count:      length,
      in_progress_count: ([.[] | select(.statusCategory == "In Progress")] | length),
      stuck_count:       ([.[] | select(.statusCategory == "In Progress" and .time_in_current_status.seconds >= 432000)] | length),
      blocked_count:     ([.[] | select(.is_blocked)] | length),
      red_bug_count:     ([.[] | select($risk_by_key[.key] == "red")] | length),
      yellow_bug_count:  ([.[] | select($risk_by_key[.key] == "yellow")] | length),
      issue_keys:        [.[].key]
    })
  | sort_by(-.stuck_count, -.blocked_count, -.red_bug_count, -.in_progress_count)) as $epics |
([$issues[] | select(.parent == null or (.parent.issuetype // "") != "Epic")] | length) as $issues_without_epic |

{
  total:                  $total,
  in_progress:            $in_progress,
  todo:                   $todo,
  done_last_36h:          $done_recent,
  blocked_count:          ($blocked | length),
  blocked:                $blocked,
  stuck:                  $stuck,
  unassigned_in_progress: $unassigned_in_progress,
  regressions_last_7d:    $regressions,
  throughput_7d:          $throughput_7d,
  throughput_14d:         $throughput_14d,
  median_cycle_time_days: $median_cycle_time,
  columns:                $columns_summary,
  assignees:              $assignees_wip,
  idle_assignees:         $idle_assignees,
  bugs_at_risk:           $bugs_at_risk,
  bugs_other_count:       ($bugs_other | length),
  epics:                  $epics,
  issues_without_epic:    $issues_without_epic
}
'

METRICS_FILE="${TMPDIR}/metrics.json"
jq -n \
  --slurpfile issues     "$SNAPSHOT_FILE" \
  --slurpfile all_issues "$EXTRACTED_FILE" \
  --argjson   columns    "$COLUMNS" \
  --argjson   now        "$NOW" \
  '($issues[0]) as $issues | ($all_issues[0]) as $all_issues |
  '"$METRICS_FILTER" > "$METRICS_FILE"
METRICS=$(cat "$METRICS_FILE")

# ---------------------------------------------------------------------------
# JSON output
# ---------------------------------------------------------------------------
if [[ "$JSON_MODE" == true ]]; then
  BOARD_OBJ=$(jq -n \
    --arg id "$BOARD_ID" --arg name "$BOARD_NAME" \
    --arg type "$BOARD_TYPE" --arg project "$PROJECT_KEY" \
    --argjson columns "$COLUMNS" \
    '{id: $id, name: $name, type: $type, project: $project, columns: $columns}')

  jq -n \
    --arg fetched_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson board "$BOARD_OBJ" \
    --slurpfile metrics "$METRICS_FILE" \
    --slurpfile issues  "$SNAPSHOT_FILE" \
    --arg flagged_field "$FLAGGED_FIELD_ID" \
    '{ fetched_at: $fetched_at, board: $board,
       flagged_field_supported: ($flagged_field != ""),
       metrics: $metrics[0], issues: $issues[0] }'
  exit 0
fi

# ---------------------------------------------------------------------------
# Human-readable output
# ---------------------------------------------------------------------------
SEP="========================================================================"
THIN="------------------------------------------------------------------------"

echo ""
echo "$SEP"
echo "BOARD ${BOARD_ID} — ${BOARD_NAME}  [${BOARD_TYPE}, project ${PROJECT_KEY}]"
echo "$SEP"

echo "$METRICS" | jq -r '
  "  Total on board (snapshot): \(.total)",
  "  In Progress: \(.in_progress)  ·  To Do: \(.todo)  ·  Done (last 36h): \(.done_last_36h)",
  "  Blocked (Flagged): \(.blocked_count)",
  "  Throughput: \(.throughput_7d) (7d) · \(.throughput_14d) (14d)",
  (if .median_cycle_time_days != null then "  Median cycle time (14d): \(.median_cycle_time_days)d" else "  Median cycle time: not enough data" end)
'

echo ""
echo "  Columns:"
echo "$METRICS" | jq -r '.columns[] | "    \(.name): \(.count)"'

echo ""
echo "  Stuck (≥5d in In Progress):"
STUCK_N=$(echo "$METRICS" | jq '.stuck | length')
if [[ "$STUCK_N" -eq 0 ]]; then
  echo "    (none)"
else
  echo "$METRICS" | jq -r '.stuck[] |
    "    [\(.severity | ascii_upcase)] \(.key) — \(.time_in_status) in \"\(.status)\" · \(.assignee // "Unassigned")\(if .is_blocked then " · BLOCKED" else "" end)\n      \(.summary[:80])"'
fi

echo ""
echo "  Unassigned in In Progress:"
UNAS_N=$(echo "$METRICS" | jq '.unassigned_in_progress | length')
if [[ "$UNAS_N" -eq 0 ]]; then
  echo "    (none)"
else
  echo "$METRICS" | jq -r '.unassigned_in_progress[] | "    \(.key) — \(.time_in_status) in \"\(.status)\"\n      \(.summary[:80])"'
fi

echo ""
echo "  Blocked (Flagged):"
BLK_N=$(echo "$METRICS" | jq '.blocked_count')
if [[ "$BLK_N" -eq 0 ]]; then
  echo "    (none)"
else
  echo "$METRICS" | jq -r '.blocked[] | "    \(.key) — \(.status) · \(.assignee // "Unassigned") · \(.time_in_status)\n      \(.summary[:80])"'
fi

echo ""
echo "  Regressions last 7d:"
REG_N=$(echo "$METRICS" | jq '.regressions_last_7d | length')
if [[ "$REG_N" -eq 0 ]]; then
  echo "    (none)"
else
  echo "$METRICS" | jq -r '.regressions_last_7d[] | "    \(.key) — \(.from) → \(.to) (\(.at[:10]))"'
fi

echo ""
echo "  Bugs at risk:"
BUG_N=$(echo "$METRICS" | jq '.bugs_at_risk | length')
if [[ "$BUG_N" -eq 0 ]]; then
  echo "    (none)"
else
  echo "$METRICS" | jq -r '.bugs_at_risk[] |
    "    [\(.risk | ascii_upcase)] \(.key) — \(.priority) · due \(.duedate // "—")\(if .days_until_due != null then " (\(.days_until_due)d)" else "" end) · \(.assignee // "Unassigned") — \(.reason)\n      \(.summary[:80])"'
fi

echo ""
echo "  WIP per assignee (In Progress):"
echo "$METRICS" | jq -r '.assignees[] |
  "    \(.assignee // "(unassigned)"): \(.count) WIP · \(.stuck_count) stuck · \(.blocked_count) blocked"'

echo ""
echo "  Epics on the board:"
EP_N=$(echo "$METRICS" | jq '.epics | length')
if [[ "$EP_N" -eq 0 ]]; then
  echo "    (none)"
else
  echo "$METRICS" | jq -r '.epics[] | "    \(.key) — \(.summary[:60])\n      active \(.active_count) · WIP \(.in_progress_count) · stuck \(.stuck_count) · blocked \(.blocked_count) · 🔴 \(.red_bug_count) 🟡 \(.yellow_bug_count) bugs"'
fi
NO_EPIC=$(echo "$METRICS" | jq '.issues_without_epic')
if [[ "$NO_EPIC" -gt 0 ]]; then
  echo "    (no epic: $NO_EPIC issues)"
fi

IDLE_N=$(echo "$METRICS" | jq '.idle_assignees | length')
if [[ "$IDLE_N" -gt 0 ]]; then
  echo ""
  echo "  Idle assignees (have items elsewhere on board, 0 in In Progress):"
  echo "$METRICS" | jq -r '.idle_assignees[] | "    \(.)"'
fi

echo ""
echo "$SEP"
