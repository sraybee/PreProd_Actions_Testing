#!/usr/bin/env bash

# Fail fast, catch unset vars and pipeline failures
set -euo pipefail

# Ensure script is run with Bash (do not invoke with `sh`)
if [ -z "${BASH_VERSION:-}" ]; then
  echo "This script must be run with bash. Use: bash $0 [args]" >&2
  exit 2
fi

usage() {
  cat <<EOF
Usage: $0 -a owner/repo [-t TICKET]

Options:
  -a  Action identifier (owner/repo), e.g. cloudbees-io/helm-package
  -t  (Optional) Ticket number, e.g. CBP-24963 (default: CBP_Not_Provided)

Description:
  Replaces occurrences of "uses: <action>@v1" with
  "uses: <action>/.cloudbees/testing@main" in the current repository
  (assumes the repo has already been checked out), commits the change on
  a new branch, and pushes the branch to origin.
EOF
}

ACTION=""
TICKET=""

while getopts "a:t:h" opt; do
  case "$opt" in
    a) ACTION="$OPTARG" ;;
    t) TICKET="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

# Allow ACTION to be provided via env var ACTION_ID
if [[ -z "$ACTION" ]]; then
  ACTION="${ACTION_ID:-}"
fi

if [[ -z "$ACTION" ]]; then
  echo "Missing required -a ACTION or ACTION_ID env" >&2
  usage
  exit 1
fi

if [[ -z "$TICKET" ]]; then
  TICKET="CBP_Not_Provided"
fi

# sanitize ticket for branch name
SANITIZED_TICKET=$(echo "$TICKET" | sed -E 's/[^A-Za-z0-9]+/_/g')

# Extract action name (e.g., helm-package -> Helm_Package)
ACTION_NAME=$(basename "$ACTION" | sed 's/-/_/g' | awk 'BEGIN{FS=OFS="_"}{for(i=1;i<=NF;i++)sub(/./,toupper(substr($i,1,1)),$i)}1')

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BRANCH="${SANITIZED_TICKET}_Test_${ACTION_NAME}_${TIMESTAMP}"

echo "Running in repo: $(pwd)"
echo "Creating branch: $BRANCH"
git checkout -b "$BRANCH"

NEW_USES="${ACTION}/.cloudbees/testing@main"

# Find files that reference the action via "uses: <action>"
GREP_PATTERN="uses:[[:space:]]*${ACTION}"
TMPFILE=$(mktemp)
git grep -Il "$GREP_PATTERN" > "$TMPFILE" 2>/dev/null || true
FILES=()
while IFS= read -r line; do
  [ -z "$line" ] && continue
  FILES+=("$line")
done < "$TMPFILE"
rm -f "$TMPFILE"

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No workflow files reference action '$ACTION'. Nothing to change."
  exit 0
fi

echo "Updating ${#FILES[@]} file(s) that reference '$ACTION'"
for f in "${FILES[@]}"; do
  echo " - $f"
  # Replace lines like: uses: cloudbees-io/helm-package@v1
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -E -i "" "s|(^[[:space:]]*uses:[[:space:]]*)${ACTION}@v1([[:space:]]*)$|\\1${NEW_USES}\\2|" "$f"
  else
    sed -E -i "s|(^[[:space:]]*uses:[[:space:]]*)${ACTION}@v1([[:space:]]*)$|\\1${NEW_USES}\\2|" "$f"
  fi
  git add "$f"
done

COMMIT_MSG="${TICKET}: update action references to ${NEW_USES}"

if git diff --cached --quiet; then
  echo "No changes after replacement. Exiting."
  exit 0
fi

echo "Committing changes"
git commit -m "$COMMIT_MSG"

echo "Pushing branch to origin: $BRANCH"
git push -u origin "$BRANCH"

echo "Done. Branch: $BRANCH"
exit 0
