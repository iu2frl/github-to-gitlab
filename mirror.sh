#!/bin/bash

# Exit on error
set -e

# Config from environment
GITHUB_TOKEN=${GITHUB_TOKEN:?Missing GITHUB_TOKEN}
GITLAB_TOKEN=${GITLAB_TOKEN:?Missing GITLAB_TOKEN}
GITLAB_NAMESPACE=${GITLAB_NAMESPACE:?Missing GITLAB_NAMESPACE}
GITLAB_API="https://gitlab.com/api/v4"

# Fetch GitHub repositories with pagination
REPOS=""
PAGE=1

echo "[*] Fetching repositories from GitHub..."

while : ; do
  PAGE_DATA=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/user/repos?per_page=100&page=$PAGE")

  COUNT=$(echo "$PAGE_DATA" | jq length)

  REPOS+=$(echo "$PAGE_DATA" | jq -r '.[] | .name + " " + .clone_url')$'\n'

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
while read -r NAME URL; do
  [ -z "$NAME" ] && continue
  echo "[*] Processing $NAME"

  # Check if GitLab repo exists
  EXISTS=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "$GITLAB_API/projects/$GITLAB_NAMESPACE%2F$NAME" | jq -r '.id // empty')

  if [ -z "$EXISTS" ]; then
    echo "  [+] Creating $NAME on GitLab..."
    curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
      --data "name=$NAME&namespace_id=$NAMESPACE_ID" \
      "$GITLAB_API/projects" > /dev/null
  else
    echo "  [=] Repo $NAME already exists on GitLab"
  fi

  # Clone and push mirror
  git clone --mirror "$URL"
  cd "$NAME.git" || continue
  git remote add gitlab "https://oauth2:$GITLAB_TOKEN@gitlab.com/$GITLAB_NAMESPACE/$NAME.git"
  git push --mirror gitlab
  cd ..
  rm -rf "$NAME.git"
done <<< "$REPOS"
