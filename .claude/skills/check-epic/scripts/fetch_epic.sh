#!/usr/bin/env bash
# fetch_epic.sh — Fetch Jira Epic details and all its child issues (via JQL)
#
# Usage:
#   ./fetch_epic.sh EPIC_KEY          # human-readable output
#   ./fetch_epic.sh EPIC_KEY --json   # raw JSON output
#
# Examples:
#   ./fetch_epic.sh FBX-1234
#   ./fetch_epic.sh FBX-1234 --json > /tmp/epic_report.json

set -euo pipefail

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 EPIC_KEY [--json]" >&2
  exit 1
fi

EPIC_KEY=$1
JSON_MODE=false
[[ "${2:-}" == "--json" ]] && JSON_MODE=true

# ---------------------------------------------------------------------------
# Auth — load .env.local, fall back to existing env vars
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

# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------
fetch_issue() {
  local key=$1
  local fields="summary,status,issuetype,created,updated,duedate,assignee,description,comment"
  curl -s -f \
    -u "${JIRA_EMAIL}:${JIRA_TOKEN}" \
    -H "Accept: application/json" \
    "${JIRA_URL}/rest/api/3/issue/${key}?expand=changelog&fields=${fields}"
}

# Fetch all child issues of an epic via JQL with pagination.
# Returns a JSON array of issues (each with changelog expanded).
fetch_children() {
  local epic_key=$1
  local fields="summary,status,issuetype,created,updated,duedate,assignee,subtasks"
  local jql="parent = ${epic_key} ORDER BY created ASC"
  local all_issues='[]'
  local next_page_token=""

  while true; do
    local params="jql=$(jq -rn --arg q "$jql" '$q | @uri')&fields=${fields}&expand=changelog&maxResults=100"
    if [[ -n "$next_page_token" ]]; then
      params="${params}&nextPageToken=${next_page_token}"
    fi

    local page
    page=$(curl -s -f \
      -u "${JIRA_EMAIL}:${JIRA_TOKEN}" \
      -H "Accept: application/json" \
      "${JIRA_URL}/rest/api/3/search/jql?${params}")

    local count
    count=$(echo "$page" | jq '.issues | length')
    echo "  Fetched ${count} child issues..." >&2

    all_issues=$(jq -n \
      --argjson acc "$all_issues" \
      --argjson page "$page" \
      '$acc + $page.issues')

    local is_last
    is_last=$(echo "$page" | jq '.isLast // true')
    next_page_token=$(echo "$page" | jq -r '.nextPageToken // empty')

    if [[ "$is_last" == "true" || -z "$next_page_token" ]]; then
      break
    fi
  done

  echo "$all_issues"
}

# ---------------------------------------------------------------------------
# jq filter library (shared between epic and subtask extraction)
# ---------------------------------------------------------------------------
read -r -d '' JQ_LIB << 'JQLIB' || true

# Parse Jira ISO-8601 date to Unix timestamp
def parse_jira_date:
  gsub("\\.[0-9]+"; "")
  | gsub("([+-][0-9]{2}):?([0-9]{2})$"; "Z")
  | fromdateiso8601;

# Format seconds to "Xd Yh Zm"
def format_duration:
  (if . < 0 then 0 else . end) as $s |
  ($s / 86400 | floor) as $d |
  (($s % 86400) / 3600 | floor) as $h |
  (($s % 3600) / 60 | floor) as $m |
  if $d > 0 then "\($d)d \($h)h \($m)m"
  elif $h > 0 then "\($h)h \($m)m"
  else "\($m)m"
  end;

# Recursively extract plain text from Atlassian Document Format
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

# How long has the issue been in its current status?
# Input: full issue JSON (with changelog at top level)
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

# Cycle time for completed issues: first transition to "In Progress" category → last transition to "Done" category
# Input: full issue JSON (with changelog at top level). Returns null if not yet Done.
def cycle_time_of_issue($status_categories):
  (.changelog.histories // []) as $h |
  ($h | map(select(any(.items[]?; .field == "status" and ($status_categories[.toString] == "In Progress"))))
      | sort_by(.created) | .[0] | .created) as $ip |
  ($h | map(select(any(.items[]?; .field == "status" and ($status_categories[.toString] == "Done"))))
      | sort_by(.created) | .[-1] | .created) as $done |
  if ($ip != null and $done != null) then
    (($done | parse_jira_date) - ($ip | parse_jira_date)) as $secs |
    if $secs > 0 then {
      in_progress_at: $ip,
      done_at:        $done,
      seconds:        ($secs | floor),
      days:           ($secs / 86400 * 10 | round / 10),
      formatted:      ($secs | format_duration)
    } else null end
  else null end;

JQLIB

# ---------------------------------------------------------------------------
# jq extraction filters
# ---------------------------------------------------------------------------
EPIC_FILTER="${JQ_LIB}"'
. as $issue |
$issue.fields as $f |
{
  key: $issue.key,
  summary: ($f.summary // ""),
  status: ($f.status.name // ""),
  statusCategory: (($f.status.statusCategory // {}).name // ""),
  description: ($f.description | extract_adf | gsub("^\\n+|\\n+$"; "")),
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
  time_in_current_status: (. | time_in_current_status($f.status.name; $f.created; $now))
}
'

# Applied to each element of the issues array returned by the search API.
# Input: single issue object (with .changelog at top level, as search API returns it).
CHILD_FILTER="${JQ_LIB}"'
. as $issue |
$issue.fields as $f |
{
  key: $issue.key,
  issuetype: (($f.issuetype // {}).name // ""),
  summary: ($f.summary // ""),
  status: ($f.status.name // ""),
  statusCategory: (($f.status.statusCategory // {}).name // ""),
  assignee: (($f.assignee // {}).displayName),
  num_subtasks: (($f.subtasks // []) | length),
  duedate: $f.duedate,
  created: ($f.created // ""),
  updated: ($f.updated // ""),
  time_in_current_status: (. | time_in_current_status($f.status.name; $f.created; $now)),
  cycle_time: cycle_time_of_issue($status_categories)
}
'

# Computes aggregate metrics from the extracted children array.
# Uses --argjson issues, --argjson now, --argjson epic (already filtered).
METRICS_FILTER="${JQ_LIB}"'
($now - 604800) as $cutoff_7d |
($issues | length) as $total |
($issues | map(select(.statusCategory == "Done"))        | length) as $done |
($issues | map(select(.statusCategory == "In Progress")) | length) as $in_progress |
($issues | map(select(.statusCategory == "To Do"))       | length) as $todo |
($issues | map(select(.status | ascii_downcase | test("block"))) | length) as $blocked |
(if $total > 0 then ($done * 1000 / $total | round / 10) else 0 end) as $pct_done |
($issues | map(select(.assignee != null)) | map(.assignee) | unique) as $assignees |
($issues | map(select(
    .statusCategory == "Done" and ((.updated | parse_jira_date) >= $cutoff_7d)
  )) | length) as $closed_last_7d |
($issues | map(select((.created | parse_jira_date) >= $cutoff_7d)) | length) as $created_last_7d |
($issues | map(select(
    .statusCategory == "In Progress" and .time_in_current_status.seconds >= 604800
  )) | map({key, summary, time_in_status: .time_in_current_status.formatted})) as $stale_in_progress |
($issues | map(select(
    .statusCategory == "In Progress" and .assignee == null
  )) | map(.key)) as $unassigned_in_progress |
(if $epic.duedate != null then
  (($epic.duedate + "T00:00:00Z" | fromdateiso8601) - $now) / 86400 | floor
 else null end) as $days_until_due |
((($epic.statusCategory == "To Do") and ($in_progress > 0 or $done > 0)) or
 (($epic.statusCategory == "Done") and ($in_progress > 0 or $todo > 0))) as $epic_status_stale |
($issues | map(select(.cycle_time != null) | .cycle_time.days)) as $cycle_time_vals |
(if ($cycle_time_vals | length) > 0 then
  ($cycle_time_vals | sort) as $sorted |
  ($sorted | length) as $n |
  (if ($n % 2) == 1 then $sorted[($n / 2 | floor)]
   else (($sorted[($n / 2) - 1] + $sorted[$n / 2]) / 2)
   end) * 10 | round / 10
else null end) as $median_cycle_time_days |
($issues | map(select(
    .cycle_time != null and
    $median_cycle_time_days != null and
    .cycle_time.days > ($median_cycle_time_days * 2) and
    .cycle_time.days > 5
  )) | map({key, summary, cycle_time_days: .cycle_time.days, cycle_time_formatted: .cycle_time.formatted})) as $high_cycle_time_issues |
{
  total:                   $total,
  done:                    $done,
  in_progress:             $in_progress,
  todo:                    $todo,
  blocked:                 $blocked,
  pct_done:                $pct_done,
  assignees:               $assignees,
  assignee_count:          ($assignees | length),
  closed_last_7d:          $closed_last_7d,
  created_last_7d:         $created_last_7d,
  stale_in_progress:       $stale_in_progress,
  unassigned_in_progress:  $unassigned_in_progress,
  days_until_due:          $days_until_due,
  epic_status_stale:       $epic_status_stale,
  median_cycle_time_days:  $median_cycle_time_days,
  high_cycle_time_issues:  $high_cycle_time_issues
}
'

# ---------------------------------------------------------------------------
# Fetch epic
# ---------------------------------------------------------------------------
echo "Fetching ${EPIC_KEY}..." >&2
EPIC_RAW=$(fetch_issue "$EPIC_KEY")

# Validate that the key is an Epic
ISSUETYPE=$(echo "$EPIC_RAW" | jq -r '.fields.issuetype.name // empty')
if [[ "$ISSUETYPE" != "Epic" ]]; then
  echo "Error: ${EPIC_KEY} is not an Epic (issuetype: ${ISSUETYPE:-unknown})" >&2
  exit 1
fi

# Fetch status category map for this project: { "status name": "category name", ... }
PROJECT_KEY="${EPIC_KEY%%-*}"
STATUS_CATEGORIES_RAW=$(curl -s -f \
  -u "${JIRA_EMAIL}:${JIRA_TOKEN}" \
  -H "Accept: application/json" \
  "${JIRA_URL}/rest/api/3/project/${PROJECT_KEY}/statuses" 2>/dev/null || echo "[]")
STATUS_CATEGORIES=$(echo "$STATUS_CATEGORIES_RAW" | jq '[.[] | .statuses[] | {(.name): .statusCategory.name}] | add // {}' 2>/dev/null || echo '{}')

NOW=$(date -u +%s)

EPIC=$(echo "$EPIC_RAW" | jq --argjson now "$NOW" "$EPIC_FILTER")

# ---------------------------------------------------------------------------
# Fetch all child issues via JQL (paginated, changelog included in search)
# ---------------------------------------------------------------------------
echo "Fetching child issues for ${EPIC_KEY}..." >&2
CHILDREN_RAW=$(fetch_children "$EPIC_KEY")

CHILDREN_JSON=$(echo "$CHILDREN_RAW" | jq --argjson now "$NOW" --argjson status_categories "$STATUS_CATEGORIES" \
  "[.[] | ${CHILD_FILTER}]")

METRICS=$(jq -n \
  --argjson issues "$CHILDREN_JSON" \
  --argjson now "$NOW" \
  --argjson epic "$EPIC" \
  "$METRICS_FILTER")

# ---------------------------------------------------------------------------
# JSON output mode
# ---------------------------------------------------------------------------
if [[ "$JSON_MODE" == true ]]; then
  jq -n \
    --argjson epic "$EPIC" \
    --argjson metrics "$METRICS" \
    --argjson children "$CHILDREN_JSON" \
    --arg fetched_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{fetched_at: $fetched_at, epic: $epic, metrics: $metrics, child_issues: $children}'
  exit 0
fi

# ---------------------------------------------------------------------------
# Human-readable output
# ---------------------------------------------------------------------------
SEP="========================================================================"
THIN="------------------------------------------------------------------------"

echo ""
echo "$SEP"
echo "$EPIC" | jq -r '"EPIC  \(.key)"'
echo "$SEP"
echo "$EPIC" | jq -r '
  "  Summary        : \(.summary)",
  "  Status         : \(.status)  [\(.statusCategory)]",
  "  Due Date       : \(.duedate // "—")",
  "  Created        : \(.created[:10])",
  "  Updated        : \(.updated[:10])",
  "  In status for  : \(.time_in_current_status.formatted)  (since \(.time_in_current_status.since[:10]))"
'

# Description
DESC=$(echo "$EPIC" | jq -r '.description // ""')
if [[ -n "$DESC" ]]; then
  echo ""
  echo "  Description:"
  echo "$DESC" | head -20 | sed 's/^/    /'
  TOTAL_LINES=$(echo "$DESC" | wc -l | tr -d ' ')
  if [[ "$TOTAL_LINES" -gt 20 ]]; then
    echo "    ... ($(( TOTAL_LINES - 20 )) more lines)"
  fi
fi

# Comments
echo "$EPIC" | jq -r '
  if (.comments | length) > 0 then
    "\n  Comments (\(.comments | length)):",
    (
      .comments[] |
      "    [\(.created[:10])] \(.author): \(.body[:200] | gsub("\n"; " "))"
    )
  else empty end
'

# Child issues table
NUM_CHILDREN=$(echo "$CHILDREN_JSON" | jq 'length')
echo ""
echo "  Child Issues (${NUM_CHILDREN}):"
echo ""

if [[ "$NUM_CHILDREN" -gt 0 ]]; then
  printf "  %-15s %-14s %-22s %-14s %-22s %4s  %-12s %s\n" \
    "KEY" "TYPE" "STATUS" "CATEGORY" "ASSIGNEE" "SUBS" "DUE" "IN STATUS"
  echo "  $THIN"

  echo "$CHILDREN_JSON" | jq -r '.[] | [
    .key,
    .issuetype,
    .status,
    .statusCategory,
    (.assignee // "Unassigned"),
    (.num_subtasks | tostring),
    (.duedate // "—"),
    .time_in_current_status.formatted,
    .summary,
    .created[:10],
    .updated[:10],
    (.cycle_time.formatted // "—")
  ] | @tsv' | while IFS=$'\t' read -r key issuetype status category assignee nsubs due instatus summary created updated cycletime; do
    printf "  %-15s %-14s %-22s %-14s %-22s %4s  %-12s %s\n" \
      "$key" "$issuetype" "${status:0:21}" "$category" "${assignee:0:21}" "$nsubs" "$due" "$instatus"
    printf "    %s\n" "${summary:0:68}"
    printf "    Created %s  Updated %s  Cycle time: %s\n" "$created" "$updated" "$cycletime"
  done
else
  echo "    (none)"
fi

echo "$SEP"
