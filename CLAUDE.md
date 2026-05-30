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

Deploys run via GitHub Actions on push to `main`, using the reusable workflow at [`conallob/.github/.github/workflows/hugo-deploy.yml`](https://github.com/conallob/.github/blob/main/.github/workflows/hugo-deploy.yml).

The workflow checks out the repo (including submodules), builds with Hugo, and deploys via Wrangler. `wrangler.jsonc` points Wrangler at Hugo's `public/` output.

### Required GitHub secret

| Secret | Value |
|---|---|
| `CLOUDFLARE_API_TOKEN` | Cloudflare API token with Workers edit permission |

### Cloudflare Workers dashboard

Set all build/deploy commands to blank — GitHub Actions owns the deploy.

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
