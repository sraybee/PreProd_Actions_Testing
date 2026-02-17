#!/usr/bin/env bash

# Fail fast
set -euo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
  echo "Run with bash: bash $0" >&2
  exit 2
fi

usage(){
  cat <<EOF
Usage: $0 -a owner/repo -s <service-repo-git-url> [-t <TICKET>]
EOF
}

ACTION=""
SERVICE_URL=""
TICKET=""

while getopts "a:s:t:h" opt; do
  case "$opt" in
    a) ACTION="$OPTARG";;
    s) SERVICE_URL="$OPTARG";;
    t) TICKET="$OPTARG";;
    h) usage; exit 0;;
    *) usage; exit 1;;
  esac
done

if [[ -z "$ACTION" || -z "$SERVICE_URL" ]]; then
  usage; exit 1
fi

if [[ -z "$TICKET" ]]; then TICKET="CBP_Not_Provided"; fi

NEW_USES="${ACTION}/.cloudbees/testing@main"
SANITIZED_TICKET=$(echo "$TICKET" | sed -E 's/[^A-Za-z0-9]+/_/g')
ACTION_NAME=$(basename "$ACTION" | sed 's/-/_/g' | awk 'BEGIN{FS=OFS="_"}{for(i=1;i<=NF;i++)sub(/./,toupper(substr($i,1,1)),$i)}1')
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
FOLDER="${SANITIZED_TICKET}_Test_${ACTION_NAME}_${TIMESTAMP}"
BRANCH="${SANITIZED_TICKET}_Test_${ACTION_NAME}_${TIMESTAMP}"

mkdir -p "$FOLDER" && cd "$FOLDER"

echo "Cloning service: $SERVICE_URL"
git clone "$SERVICE_URL"
REPO_DIR=$(basename "$SERVICE_URL" .git)
cd "$REPO_DIR"

echo "Creating branch: $BRANCH"
git checkout -b "$BRANCH"

TMPFILE=$(mktemp)
git grep -Il "uses:[[:space:]]*${ACTION}@v1" > "$TMPFILE" 2>/dev/null || true
FILES=()
while IFS= read -r l; do [[ -z "$l" ]] && continue; FILES+=("$l"); done < "$TMPFILE"
rm -f "$TMPFILE"

if [[ ${#FILES[@]} -eq 0 ]]; then echo "No files to change"; exit 0; fi

echo "Updating files"
for f in "${FILES[@]}"; do
  echo " - $f"
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -E -i "" "s|(^[[:space:]]*uses:[[:space:]]*)${ACTION}@v1([[:space:]]*)$|\\1${NEW_USES}\\2|" "$f"
  else
    sed -E -i "s|(^[[:space:]]*uses:[[:space:]]*)${ACTION}@v1([[:space:]]*)$|\\1${NEW_USES}\\2|" "$f"
  fi
  git add "$f"
done

if git diff --cached --quiet; then echo "No changes after replacement"; exit 0; fi

git commit -m "${TICKET}: update action references to ${NEW_USES}"
git push -u origin "$BRANCH"

echo "Done. Branch: $BRANCH"
exit 0
