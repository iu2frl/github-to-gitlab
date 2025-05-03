#!/bin/bash

set -e

# Load config from environment
GITHUB_TOKEN=${GITHUB_TOKEN:?Missing GITHUB_TOKEN}
GITLAB_TOKEN=${GITLAB_TOKEN:?Missing GITLAB_TOKEN}
GITLAB_NAMESPACE=${GITLAB_NAMESPACE:?Missing GITLAB_NAMESPACE}
GITLAB_API="https://gitlab.com/api/v4"

# Prepare repo list
REPOS_TMP=$(mktemp)
PAGE=1

echo "[*] Fetching repositories from GitHub..."

while : ; do
  PAGE_DATA=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/user/repos?per_page=100&page=$PAGE")

  COUNT=$(echo "$PAGE_DATA" | jq length)
  echo "$PAGE_DATA" | jq -r '.[] | .name + " " + .clone_url' >> "$REPOS_TMP"

  [ "$COUNT" -lt 100 ] && break
  PAGE=$((PAGE + 1))
done

# Get GitLab namespace ID
NAMESPACE_ID=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "$GITLAB_API/namespaces?search=$GITLAB_NAMESPACE" | jq -r '.[0].id')

if [ -z "$NAMESPACE_ID" ]; then
  echo "[!] GitLab namespace '$GITLAB_NAMESPACE' not found"
  exit 1
fi

# Process each repo
while IFS= read -r LINE; do
  NAME=$(cut -d' ' -f1 <<< "$LINE")
  URL=$(cut -d' ' -f2- <<< "$LINE")
  [ -z "$NAME" ] && continue

  echo "[*] Processing $NAME"

  # Check if GitLab project exists
  EXISTS=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "$GITLAB_API/projects/$GITLAB_NAMESPACE%2F$NAME" | jq -r '.id // empty')

  if [ -z "$EXISTS" ]; then
    echo "  [+] Creating $NAME on GitLab..."
    curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
      --data "name=$NAME&namespace_id=$NAMESPACE_ID" \
      "$GITLAB_API/projects" > /dev/null
  fi

  # Clone and push
  git clone --mirror "$URL"
  cd "$NAME.git" || continue

  git remote add gitlab "https://oauth2:$GITLAB_TOKEN@gitlab.com/$GITLAB_NAMESPACE/$NAME.git"

  echo "  [>] Pushing branches..."
  git push gitlab --all

  echo "  [>] Pushing safe tags..."
  SAFE_TAGS=$(git tag -l | grep -vE '[:~^ ]')
  for TAG in $SAFE_TAGS; do
    git push gitlab "refs/tags/$TAG"
  done

  cd ..
  rm -rf "$NAME.git"

done < "$REPOS_TMP"

rm -f "$REPOS_TMP"
