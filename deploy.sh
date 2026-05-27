#!/bin/sh
set -e

BRANCH="${1:-branch}"

hugo --minify

if [ "$BRANCH" = "main" ]; then
  npx wrangler deploy
else
  npx wrangler versions upload
fi
