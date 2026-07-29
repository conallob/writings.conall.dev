---
title: "Automating Myself Out of a Job (Again): Introducing o11y-analysis-tools"
date: 2026-07-29T09:00:00+01:00
draft: false
description: "A collection of static analysis and testing tools for PromQL-compatible monitoring stacks, built from a few thousand PromQL/Borgmon code reviews."
tags: ["SRE", "Observability", "PromQL", "Prometheus", "Golang", "Open Source"]
categories: ["Engineering"]
---

There's a lot of anxiety right now about AI taking jobs. But SREs have been automating themselves
out of their own jobs for decades — the reward for good work, inevitably, is yet more work.

My latest example: Over my career, I've personally performed a few thousand code reviews of PromQL
(neé Borgmon). Any issues I catch can be distilled down into a handful of categories, none of which
I consider exotic.

**[o11y-analysis-tools](https://github.com/conallob/o11y-analysis-tools)** is a collection of
static analysis and testing tools for PromQL-compatible monitoring stacks — formatters, label
enforcement, test generation, Alertmanager testing, and alert hygiene analysis. Full details,
interactive and CI pipeline usage, and install options are in the
[README](https://github.com/conallob/o11y-analysis-tools).

The part I'm most excited about: each tool also ships as an installable Agent Skill, so an
LLM coding agent can run the same checks I used to run by eye, before a human reviewer ever
sees the diff. Or there's the Agent definition that combines them all together, named after
my mentor in this area, the late [Cody Smith](https://supah.green).

If you've ever guessed/sparred with `for: duration`, forgotten a `job` label, or reviewed a
PromQL diff that made you pause — I built this for you, for past-me, and ideally for future
me, to add more novelty into my review queue.
