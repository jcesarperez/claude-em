#!/usr/bin/env bash

set -euo pipefail

GITHUB_USER=$1
JIRA_EMAIL_USER=$2
FROM=$3
TO=$4

# Load credentials
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../../../../.env.local"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
export GH_TOKEN=${GITHUB_TOKEN:-${GH_TOKEN:-}}
export JIRA_API_TOKEN=${JIRA_TOKEN:-${JIRA_API_TOKEN:-}}

# Compute period_days from FROM and TO
if date -v-1d +"%Y-%m-%d" &>/dev/null 2>&1; then
  # macOS
  FROM_TS=$(date -j -f "%Y-%m-%d" "$FROM" +%s)
  TO_TS=$(date -j -f "%Y-%m-%d" "$TO" +%s)
else
  # Linux
  FROM_TS=$(date -d "$FROM" +%s)
  TO_TS=$(date -d "$TO" +%s)
fi
DAYS=$(( (TO_TS - FROM_TS) / 86400 + 1 ))

TS=$(date +%s)
OUT_DIR="/tmp/ic_activity_${GITHUB_USER}_${TS}"
mkdir -p "$OUT_DIR"

# --- GitHub PRs merged ---
gh search prs \
  --author "$GITHUB_USER" \
  --merged \
  --created "$FROM..$TO" \
  --json number,createdAt,closedAt,title,repository \
  > "$OUT_DIR/prs.json"

# --- GitHub PRs closed (not merged) ---
gh search prs \
  --author "$GITHUB_USER" \
  --state closed \
  --created "$FROM..$TO" \
  --json number,repository,state \
  > "$OUT_DIR/prs_closed.json"

# --- GitHub PRs open ---
gh search prs \
  --author "$GITHUB_USER" \
  --state open \
  --json number \
  > "$OUT_DIR/prs_open.json"

# --- GitHub Reviews given ---
gh search prs \
  --reviewed-by "$GITHUB_USER" \
  --created "$FROM..$TO" \
  --json number,repository \
  > "$OUT_DIR/reviews.json"

# --- GitHub Commits ---
gh search commits \
  --author "$GITHUB_USER" \
  --committer-date "$FROM..$TO" \
  --json commit \
  > "$OUT_DIR/commits.json"

# --- Jira issues completed (cross-project via REST API) ---
curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  -X POST "${JIRA_URL}/rest/api/3/search/jql" \
  -H "Content-Type: application/json" \
  --data-binary "{
    \"jql\": \"assignee = \\\"$JIRA_EMAIL_USER\\\" AND status = Done AND resolutiondate >= \\\"$FROM\\\" AND resolutiondate <= \\\"$TO\\\" AND issuetype != Epic\",
    \"maxResults\": 100,
    \"fields\": [\"key\",\"issuetype\",\"resolutiondate\",\"status\"]
  }" \
  | jq '.issues // []' > "$OUT_DIR/issues.json" 2>/dev/null || echo "[]" > "$OUT_DIR/issues.json"

# --- Jira issues in progress / WIP (cross-project, all non-Done statuses) ---
curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  -X POST "${JIRA_URL}/rest/api/3/search/jql" \
  -H "Content-Type: application/json" \
  --data-binary "{
    \"jql\": \"assignee = \\\"$JIRA_EMAIL_USER\\\" AND statusCategory = 'In Progress' AND issuetype != Epic\",
    \"maxResults\": 100,
    \"fields\": [\"key\",\"issuetype\",\"status\"]
  }" \
  | jq '.issues // []' > "$OUT_DIR/issues_wip.json" 2>/dev/null || echo "[]" > "$OUT_DIR/issues_wip.json"

# --- Metrics ---
PRS=$(jq length "$OUT_DIR/prs.json")
COMMITS=$(jq length "$OUT_DIR/commits.json")
REVIEWS=$(jq length "$OUT_DIR/reviews.json")
ISSUES=$(jq 'if type == "array" then length else 0 end' "$OUT_DIR/issues.json")

# issues by type
ISSUES_BY_TYPE=$(jq '
  if type == "array" then
    group_by(.fields.issuetype.name)
    | map({ (.[0].fields.issuetype.name): length })
    | add // {}
  else {} end
' "$OUT_DIR/issues.json")

# wip_count: issues currently in progress
WIP=$(jq 'if type == "array" then length else 0 end' "$OUT_DIR/issues_wip.json")

# open_prs: PRs currently open
OPEN_PRS=$(jq length "$OUT_DIR/prs_open.json")

# prs_cancelled: closed PRs minus merged PRs
PRS_CLOSED_TOTAL=$(jq 'length' "$OUT_DIR/prs_closed.json")
PRS_CANCELLED=$((PRS_CLOSED_TOTAL - PRS))

# --- Issue cycle time: In Progress → Done via Jira changelog ---
mkdir -p "$OUT_DIR/issue_details"
jq -r 'if type == "array" then .[].key else empty end' "$OUT_DIR/issues.json" | \
while read -r key; do
  curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
    "${JIRA_URL}/rest/api/3/issue/${key}?expand=changelog&fields=changelog" \
    | jq '
        def parse_jira_date: gsub("\\.[0-9]+"; "") | gsub("([+-][0-9]{2}):?([0-9]{2})$"; "Z") | fromdateiso8601;
        .changelog.histories
        | map(select(.items[] | .field == "status"))
        | {
            in_progress: (map(select(.items[] | .toString == "In Progress")) | first | .created // null),
            done:        (map(select(.items[] | .toString == "Done"))        | last  | .created // null)
          }
      ' \
    > "$OUT_DIR/issue_details/${key}.json" 2>/dev/null || true
done

ISSUE_CYCLE_TIME_DAYS=$(
  find "$OUT_DIR/issue_details" -name '*.json' -exec cat {} \; 2>/dev/null \
  | jq -s '
    def parse_jira_date: gsub("\\.[0-9]+"; "") | gsub("([+-][0-9]{2}):?([0-9]{2})$"; "Z") | fromdateiso8601;
    [ .[] | select(.in_progress != null and .done != null) |
      ((.done | parse_jira_date) - (.in_progress | parse_jira_date)) / 86400
    ] |
    if length > 0 then add / length | . * 10 | round / 10 else null end
  '
)

# --- Per-PR details via API (size, comments, cycle time) ---
mkdir -p "$OUT_DIR/pr_details"
jq -r '.[] | .repository.nameWithOwner + " " + (.number | tostring)' "$OUT_DIR/prs.json" | \
while read -r repo number; do
  gh api "repos/$repo/pulls/$number" \
    --jq '{additions, deletions, comments, review_comments, created_at, merged_at,
           pr_author: .user.login}' \
    > "$OUT_DIR/pr_details/${number}.json" 2>/dev/null || true
done

# aggregate PR details
PR_DETAILS_AGG=$(
  find "$OUT_DIR/pr_details" -name '*.json' -exec cat {} \; 2>/dev/null \
  | jq -s '
    if length == 0 then
      { avg_pr_size: null, total_loc: null, comments_per_pr: null, pr_cycle_time_days: null }
    else
      {
        avg_pr_size: (map(.additions + .deletions) | add / length | . * 10 | round / 10),
        total_loc: (map(.additions + .deletions) | add),
        comments_per_pr: (map(.comments + .review_comments) | add / length | . * 10 | round / 10),
        pr_cycle_time_days: (
          map(
            select(.merged_at != null) |
            ((.merged_at | fromdateiso8601) - (.created_at | fromdateiso8601)) / 86400
          ) | if length > 0 then add / length | . * 10 | round / 10 else null end
        )
      }
    end
  '
)

AVG_PR_SIZE=$(echo "$PR_DETAILS_AGG" | jq '.avg_pr_size')
TOTAL_LOC=$(echo "$PR_DETAILS_AGG" | jq '.total_loc')
COMMENTS_PER_PR=$(echo "$PR_DETAILS_AGG" | jq '.comments_per_pr')
PR_CYCLE_TIME_DAYS=$(echo "$PR_DETAILS_AGG" | jq '.pr_cycle_time_days')

# avg time for the IC to submit their first review on PRs assigned to them
# For each PR the user reviewed, fetch PR details (created_at) and their first review (submitted_at)
mkdir -p "$OUT_DIR/reviewed_pr_details"
mkdir -p "$OUT_DIR/reviewed_pr_reviews"
jq -r '.[] | .repository.nameWithOwner + " " + (.number | tostring)' "$OUT_DIR/reviews.json" | \
while read -r repo number; do
  gh api "repos/$repo/pulls/$number" \
    --jq '{created_at, pr_author: .user.login}' \
    > "$OUT_DIR/reviewed_pr_details/${number}.json" 2>/dev/null || true
  gh api "repos/$repo/pulls/$number/reviews" \
    --jq "[.[] | select(.user.login == \"$GITHUB_USER\" and .state != \"PENDING\")]" \
    > "$OUT_DIR/reviewed_pr_reviews/${number}.json" 2>/dev/null || true
done

AVG_TIME_TO_FIRST_REVIEW=$(
  for f in "$OUT_DIR/reviewed_pr_details"/*.json; do
    number=$(basename "$f" .json)
    reviews_file="$OUT_DIR/reviewed_pr_reviews/${number}.json"
    [ -f "$reviews_file" ] || continue
    jq -n \
      --slurpfile detail "$f" \
      --slurpfile reviews "$reviews_file" \
      '{
        created_at: $detail[0].created_at,
        first_review: ($reviews[0] | sort_by(.submitted_at) | first)
      }'
  done | jq -s '
    [ .[] | select(.first_review != null) |
      ((.first_review.submitted_at | fromdateiso8601) - (.created_at | fromdateiso8601)) / 3600
    ] |
    if length > 0 then add / length * 10 | round / 10 else null end
  '
)

# commits_per_pr
if [[ "$PRS" -gt 0 ]]; then
  COMMITS_PER_PR=$(echo "scale=1; $COMMITS / $PRS" | bc)
else
  COMMITS_PER_PR="null"
fi

# per-week metrics
ISSUES_PER_WEEK=$(echo "scale=2; $ISSUES / $DAYS * 7" | bc)
PRS_PER_WEEK=$(echo "scale=2; $PRS / $DAYS * 7" | bc)
REVIEWS_PER_WEEK=$(echo "scale=2; $REVIEWS / $DAYS * 7" | bc)

cat <<EOF
{
  "col_avg_time_to_first_review_as_reviewer_hours": $AVG_TIME_TO_FIRST_REVIEW,
  "col_reviews": $REVIEWS,
  "col_reviews_per_week": $REVIEWS_PER_WEEK,
  "del_pr_cycle_time_days": $PR_CYCLE_TIME_DAYS,
  "del_commits": $COMMITS,
  "del_commits_per_pr": $COMMITS_PER_PR,
  "del_issues_by_type": $ISSUES_BY_TYPE,
  "del_issue_cycle_time_days": $ISSUE_CYCLE_TIME_DAYS,
  "del_issues_completed": $ISSUES,
  "del_issues_per_week": $ISSUES_PER_WEEK,
  "del_prs_merged": $PRS,
  "del_prs_per_week": $PRS_PER_WEEK,
  "del_total_loc": $TOTAL_LOC,
  "foc_open_prs": $OPEN_PRS,
  "foc_wip_count": $WIP,
  "period_days": $DAYS,
  "qua_avg_pr_size": $AVG_PR_SIZE,
  "qua_comments_per_pr": $COMMENTS_PER_PR,
  "qua_prs_cancelled": $PRS_CANCELLED
}
EOF
