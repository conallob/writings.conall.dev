#!/bin/sh
set -e
hugo --minify
npx wrangler versions upload
