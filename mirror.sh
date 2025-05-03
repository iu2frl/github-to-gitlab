#!/bin/bash

# Config from environment
GITHUB_TOKEN=${GITHUB_TOKEN:?Missing GITHUB_TOKEN}
GITLAB_TOKEN=${GITLAB_TOKEN:?Missing GITLAB_TOKEN}
GITLAB_NAMESPACE=${GITLAB_NAMESPACE:?Missing GITLAB_NAMESPACE}
GITLAB_API="https://gitlab.com/api/v4"

REPOS=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/user/repos?per_page=100 | jq -r '.[] | .name + " " + .clone_url')

while read -r NAME URL; do
  echo "Processing $NAME"

  EXISTS=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "$GITLAB_API/projects/$GITLAB_NAMESPACE%2F$NAME" | jq -r '.id // empty')

  if [ -z "$EXISTS" ]; then
    echo "  -> Creating repo $NAME on GitLab..."
    curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
      --data "name=$NAME&namespace_id=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API/namespaces?search=$GITLAB_NAMESPACE" | jq -r '.[0].id')" \
      "$GITLAB_API/projects" > /dev/null
  else
    echo "  -> Repo $NAME already exists on GitLab."
  fi

  git clone --mirror "$URL"
  cd "$NAME.git" || continue
  git remote add gitlab "https://oauth2:$GITLAB_TOKEN@gitlab.com/$GITLAB_NAMESPACE/$NAME.git"
  git push --mirror gitlab
  cd ..
  rm -rf "$NAME.git"
done <<< "$REPOS"
