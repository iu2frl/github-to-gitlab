#!/bin/bash

# Exit on error (but continue on individual repo errors)
set -e

# Load environment variables if file exists (for cron usage in Alpine)
[ -f /root/container_env.sh ] && source /root/container_env.sh

cd /root/repos

# Config from environment
FORCE_SYNC_ON_START=${FORCE_SYNC_ON_START:-false}
SKIP_REPOS=${SKIP_REPOS:-""}
GITHUB_TOKEN=${GITHUB_TOKEN:?Missing GITHUB_TOKEN}
GITLAB_TOKEN=${GITLAB_TOKEN:?Missing GITLAB_TOKEN}
GITLAB_NAMESPACE=${GITLAB_NAMESPACE:?Missing GITLAB_NAMESPACE}
GITLAB_API="https://gitlab.com/api/v4"

# Configure git to help with large repositories and low memory environments
# Lower buffer to prevent OOM (10MB)
git config --global http.postBuffer 10485760
git config --global pack.windowMemory 256m
git config --global pack.threads 1
git config --global core.compression 0
git config --global gc.auto 0
git config --global http.version HTTP/1.1
git config --global core.packedGitLimit 128m
git config --global core.packedGitWindowSize 128m
git config --global advice.ignoredHook false
git config --global lfs.locksverify false

# Fetch GitHub repositories with pagination
REPOS=""
PAGE=1

echo "[*] Fetching repositories from GitHub..."

while : ; do
  PAGE_DATA=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/user/repos?per_page=100&page=$PAGE")

  COUNT=$(echo "$PAGE_DATA" | jq length)
  REPO=$(echo "$PAGE_DATA" | jq -r '.[] | .name + " https://'"$GITHUB_TOKEN"'@github.com/" + (.full_name) + ".git"')$'\n'
  REPOS+="$REPO"

  [ "$COUNT" -lt 100 ] && break
  PAGE=$((PAGE + 1))
done

# Print all repositories found
echo "[*] Repositories found:"
echo "$REPOS"

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

  # Check if repo is in skip list
  if [[ ",$SKIP_REPOS," == *",$NAME,"* ]]; then
    echo "[!] Skipping $NAME (defined in SKIP_REPOS)"
    continue
  fi

  echo "[*] Processing $NAME"

  # Check if GitLab repo exists (retrieve project ID)
  PROJECT_ID=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "$GITLAB_API/projects/$GITLAB_NAMESPACE%2F$NAME" | jq -r '.id // empty')

  if [ -z "$PROJECT_ID" ]; then
    echo "  [+] Creating $NAME on GitLab..."
    CREATE_RESP=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
      --data "name=$NAME&namespace_id=$NAMESPACE_ID" \
      "$GITLAB_API/projects")
    PROJECT_ID=$(echo "$CREATE_RESP" | jq -r '.id // empty')
    if [ -z "$PROJECT_ID" ]; then
      echo "  [!] Failed to create project $NAME on GitLab"
      continue
    fi
  else
    echo "  [=] Repo $NAME already exists on GitLab"
  fi

  # Helper: URL-encode a string (uses jq present earlier)
  urlencode() {
    echo -n "$1" | jq -sRr @uri
  }

  # Attempt clone with retries and a fallback fetch if index-pack fails
  clone_with_retries() {
    local attempts=0
    local max=3
    while [ $attempts -lt $max ]; do
      attempts=$((attempts + 1))
      echo "  [+] Cloning repo $NAME from GitHub (attempt $attempts)..."
      if git clone --mirror "$URL"; then
         if [ -d "$NAME.git" ]; then
            cd "$NAME.git"
            # Attempt LFS fetch (ignore errors if lfs not installed or not used)
            if git lfs install --local >/dev/null 2>&1; then
                echo "  [*] Fetching LFS objects..."
                git lfs fetch --all 2>/dev/null || echo "  [!] LFS fetch failed or not needed"
            fi
            cd ..
         fi
        return 0
      fi

      # Detect invalid index-pack output and try alternative fetch
      if [ -d "$NAME.git" ]; then
        echo "  [*] Clone created $NAME.git directory but failed; cleaning up before retry"
        rm -rf "$NAME.git"
      fi

      sleep $((attempts * 2))
    done

    # Fallback: try a bare init + fetch (may avoid some transfer issues)
    echo "  [*] Fallback: trying bare init + fetch for $NAME"
    git init --bare "$NAME.git" || return 1
    cd "$NAME.git" || return 1
    git remote add origin "$URL"
    if git fetch --prune origin "+refs/*:refs/*"; then
      # LFS fetch for fallback
      if git lfs install --local >/dev/null 2>&1; then
          echo "  [*] Fetching LFS objects (fallback)..."
          git lfs fetch --all 2>/dev/null || true
      fi

      git remote remove origin
      cd ..
      return 0
    else
      cd ..
      rm -rf "$NAME.git"
      return 1
    fi
  }

  # Attempt push: aggressively remove protections and force-push (ignore unprotect failures)
  push_with_fallback() {
    cd "$NAME.git" || return 1
    git remote add gitlab "https://oauth2:$GITLAB_TOKEN@gitlab.com/$GITLAB_NAMESPACE/$NAME.git"

    # Try to remove any protected branches first (ignore any errors)
    echo "  [*] Removing any protected branches (ignoring failures)..."
    PROTECTED=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API/projects/$PROJECT_ID/protected_branches" | jq -r '.[].name' 2>/dev/null || true)
    if [ -n "$PROTECTED" ]; then
      for b in $PROTECTED; do
        echo "  [*] Removing protection for branch '$b' (ignoring errors)"
        curl -s -X DELETE --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API/projects/$PROJECT_ID/protected_branches/$(urlencode "$b")" >/dev/null 2>&1 || true
      done
    fi

    # Attempt forced mirror push with retries
    echo "  [+] Force pushing mirror to GitLab..."

    # Push LFS objects first
    echo "  [*] Pushing LFS objects..."
    git lfs push --all gitlab || echo "  [!] LFS push warning (might not be an LFS repo or LFS not installed)"

    attempts=0
    max=3
    while [ $attempts -lt $max ]; do
      attempts=$((attempts + 1))
      echo "  [+] Force push attempt $attempts..."
      if git push --mirror --force gitlab 2> push.err; then
        rm -f push.err
        cd ..
        return 0
      else
        echo "  [!] Force push failed (attempt $attempts): $(tr '\n' ' ' < push.err)"
        sleep $((attempts * 2))
      fi
    done

    # Final fallback: try forcing branches and tags separately
    echo "  [*] Final try: force push branches + tags separately"
    if git push --all --force gitlab && git push --tags --force gitlab; then
      rm -f push.err
      cd ..
      return 0
    fi

    cd ..
    return 1
  }

  # Clone and push with handling (continue on failure)
  if ! clone_with_retries; then
    echo "  [!] Failed to clone $NAME from GitHub"
    continue
  fi

  if ! push_with_fallback; then
    echo "  [!] Failed to push $NAME to GitLab"
    rm -rf "$NAME.git"
    continue
  fi

  rm -rf "$NAME.git"

done <<< "$REPOS"
