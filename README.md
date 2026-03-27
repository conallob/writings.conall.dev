# portfolio.conall.dev

Personal portfolio and blog, powered by [Hugo](https://gohugo.io/) with the [PaperMod](https://github.com/adityatelange/hugo-PaperMod) theme.

Served via [Cloudflare Pages](https://pages.cloudflare.com/).

## Development

```bash
hugo server --buildDrafts
```

## Cloudflare Pages Build Settings

| Setting | Value |
|---|---|
| Build command | `hugo --minify` |
| Build output directory | `public` |
| Environment variable | `HUGO_VERSION=0.147.2` |

> Set `HUGO_VERSION` in the Cloudflare Pages dashboard under **Settings → Environment variables**.

## New Content

```bash
# New post
hugo new content posts/my-post.md

# New project
hugo new content projects/my-project.md
```
