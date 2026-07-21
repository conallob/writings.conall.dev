#!/usr/bin/env bash
set -euo pipefail

# Regenerates content/projects/portfolio/ from every public GitHub repo
# tagged with the "conall-portfolio" topic (https://github.com/topics/conall-portfolio).
# The directory is fully owned by this script: every run wipes and
# rebuilds the generated pages (aside from _index.md) so repos that drop
# the topic are removed automatically.

TOPIC="conall-portfolio"
CONTENT_DIR="content/projects/portfolio"
API_URL="https://api.github.com/search/repositories"
PER_PAGE=100

mkdir -p "$CONTENT_DIR"

find "$CONTENT_DIR" -maxdepth 1 -name '*.md' ! -name '_index.md' -delete

if [ ! -f "$CONTENT_DIR/_index.md" ]; then
  cat > "$CONTENT_DIR/_index.md" <<'EOF'
---
title: "Portfolio"
description: "Projects tagged with the conall-portfolio topic on GitHub"
---
EOF
fi

auth_header=()
if [ -n "${GH_TOKEN:-}" ]; then
  auth_header=(-H "Authorization: Bearer ${GH_TOKEN}")
fi

page=1
total_repos=0

while :; do
  response=$(curl -fsSL \
    "${auth_header[@]}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${API_URL}?q=topic:${TOPIC}&per_page=${PER_PAGE}&page=${page}")

  count=$(echo "$response" | jq '.items | length')
  if [ "$count" -eq 0 ]; then
    break
  fi

  echo "$response" | jq -c '.items[]' | while IFS= read -r repo; do
    name=$(echo "$repo" | jq -r '.name')
    description=$(echo "$repo" | jq -r '.description // ""')
    html_url=$(echo "$repo" | jq -r '.html_url')
    homepage=$(echo "$repo" | jq -r '.homepage // ""')
    language=$(echo "$repo" | jq -r '.language // ""')
    stars=$(echo "$repo" | jq -r '.stargazers_count')
    created_at=$(echo "$repo" | jq -r '.created_at')
    pushed_at=$(echo "$repo" | jq -r '.pushed_at')

    slug=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
    file="${CONTENT_DIR}/${slug}.md"
    esc_description=$(echo "$description" | sed 's/\\/\\\\/g; s/"/\\"/g')

    {
      echo "---"
      echo "title: \"${name}\""
      echo "date: ${created_at}"
      echo "lastmod: ${pushed_at}"
      echo "draft: false"
      echo "description: \"${esc_description}\""
      echo "params:"
      echo "  githubUrl: \"${html_url}\""
      [ -n "$homepage" ] && echo "  homepage: \"${homepage}\""
      [ -n "$language" ] && echo "  language: \"${language}\""
      echo "  stars: ${stars}"
      echo "---"
      echo
      if [ -n "$description" ]; then
        echo "${description}"
        echo
      fi
      echo "[View on GitHub →](${html_url})"
      if [ -n "$homepage" ]; then
        echo
        echo "[Visit project →](${homepage})"
      fi
    } > "$file"
  done

  total_repos=$((total_repos + count))
  if [ "$count" -lt "$PER_PAGE" ]; then
    break
  fi
  page=$((page + 1))
done

echo "Synced ${total_repos} repositories tagged '${TOPIC}' into ${CONTENT_DIR}"
