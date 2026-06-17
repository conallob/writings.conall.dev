# portfolio.conall.dev

Hugo-powered personal portfolio and blog, served via Cloudflare Pages.

## Tech Stack

- **Static site generator:** [Hugo](https://gohugo.io/) v0.147.2+ (extended)
- **Theme:** [PaperMod](https://github.com/adityatelange/hugo-PaperMod) (git submodule)
- **Hosting:** [Cloudflare Pages](https://pages.cloudflare.com/)
- **Domain:** portfolio.conall.dev

## Local Development

```bash
# Serve with live reload (includes drafts)
hugo server --buildDrafts

# Production build
hugo --minify
```

## Content

| Section | Path | Purpose |
|---|---|---|
| Posts | `content/posts/` | Articles and writing |
| Projects | `content/projects/` | Project showcases |
| About | `content/about.md` | About page |
| Search | `content/search.md` | Client-side search |

New content uses front matter with `draft: true` by default — set to `false` to publish.

```bash
# Scaffold a new post
hugo new content posts/my-post.md

# Scaffold a new project
hugo new content projects/my-project.md
```

## Deployment

Deploys are handled by Cloudflare Workers Builds, triggered on push to `main`. No GitHub Actions workflow is needed — `wrangler.jsonc` is the only deploy config.

### How it works

Cloudflare Workers Builds clones the repo and runs the `build.command` from `wrangler.jsonc` before deploying. The command:
1. Initialises git submodules (theme)
2. Downloads Hugo extended and puts it in `/tmp`
3. Runs `hugo --minify` to produce `public/`

Wrangler then deploys `public/` as a static asset Worker.

### Reusable wrangler.jsonc pattern for other Hugo sites

```jsonc
{
  "name": "<site-slug>",
  "compatibility_date": "<today>",
  "assets": {
    "directory": "./public"
  },
  "build": {
    "command": "git submodule update --init --recursive && curl -fsSL https://github.com/gohugoio/hugo/releases/download/v0.147.2/hugo_extended_0.147.2_linux-amd64.tar.gz | tar -xz -C /tmp hugo && /tmp/hugo --minify"
  }
}
```

Only `name` and the Hugo version in the download URL need to change per site.

### Cleanup checklist for migrating other Hugo sites

- [ ] Delete `.github/workflows/` (any deploy workflow)
- [ ] Delete `build.sh` (or equivalent build script)
- [ ] Ensure `wrangler.jsonc` has the `build.command` above
- [ ] Ensure the theme is a git submodule (not a vendor copy) — the command initialises it automatically
- [ ] Confirm Cloudflare Workers Builds is connected to the repo in the Cloudflare dashboard

## Theme Updates

PaperMod is pinned as a git submodule at `themes/PaperMod`.

```bash
git submodule update --remote themes/PaperMod
```

## Repository Structure

```
.
├── archetypes/       # Content templates
├── content/          # Site content (Markdown)
├── layouts/          # Custom layout overrides (empty by default)
├── static/           # Static assets copied verbatim to public/
│   └── _headers      # Cloudflare Pages HTTP security headers
├── themes/
│   └── PaperMod/     # Theme (git submodule)
└── hugo.toml         # Site configuration
```
