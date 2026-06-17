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

Deploys are handled by Cloudflare Pages directly, triggered on push to `main`. No GitHub Actions workflow is needed.

`wrangler.jsonc` is the deploy config — it points Wrangler at Hugo's `public/` output and is designed to be reusable across multiple Hugo sites.

### Cloudflare Pages dashboard settings

| Setting | Value |
|---|---|
| Build command | `hugo --minify` |
| Build output directory | `public` |
| Root directory | `/` |

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
