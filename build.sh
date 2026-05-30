#!/usr/bin/env bash

set -euo pipefail

HUGO_VERSION="0.147.2"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

archive="hugo_extended_${HUGO_VERSION}_linux-amd64.tar.gz"
curl -fsSL "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/${archive}" \
  -o "${tmpdir}/${archive}"
tar -xzf "${tmpdir}/${archive}" -C "${tmpdir}"
mkdir -p ~/.local/bin
mv "${tmpdir}/hugo" ~/.local/bin/hugo
export PATH="$HOME/.local/bin:$PATH"

hugo version
hugo --minify
