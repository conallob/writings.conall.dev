# writings.conall.dev

Personal writings and blog, powered by [Hugo](https://gohugo.io/) with the [PaperMod](https://github.com/adityatelange/hugo-PaperMod) theme.

Served via [Cloudflare Pages](https://pages.cloudflare.com/).

## Development

```bash
hugo server --buildDrafts
```

## Cloudflare Pages Build Settings

| Setting | Value |
|---|---|
| Build command | *(leave blank)* |
| Deploy command | `sh deploy.sh` |
| Environment variable | `HUGO_VERSION=0.147.2` |

> Set `HUGO_VERSION` in the Cloudflare Pages dashboard under **Settings → Environment variables**.
> `deploy.sh` runs `hugo --minify` then `npx wrangler versions upload` so `public/` exists when Wrangler runs.

## New Content

```bash
# New post
hugo new content posts/my-post.md

# New project
hugo new content projects/my-project.md
```
