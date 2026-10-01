---
title: "Alerts as a State Machine: Promote, Demote, Repeat"
date: 2026-10-01T09:00:00+01:00
draft: false
description: "Use a single routing label in Alertmanager to turn alert lifecycle (new, stable, noisy, urgent) into a state machine where promotion and demotion are one-line changes."
tags: ["SRE", "Observability", "Alertmanager", "Prometheus", "PromQL", "On-call"]
categories: ["Engineering"]
showToc: true
TocOpen: true
---

Most alerting treats an alert as static: you write a rule, it pages someone, and it keeps doing
so until somebody deletes it. But alerts have a lifecycle. They start unproven, become
trustworthy, get noisy as the system underneath them changes, and sometimes need different
handling at 11am on a Tuesday than at 3am on a Sunday.

Model that lifecycle explicitly and a lot of painful, ad-hoc process becomes a one-line change.
Treat **one routing label** as the alert's *state*, and Alertmanager as the machine that maps
each state to a destination.

## The states

I use a label called `target`. (`severity` works too. The point is that it says *where an alert
should go*, not just how bad it is.)

| `target` | Meaning | Destination | Expectation |
|---|---|---|---|
| `testing` | Untrusted. New, or demoted for cleanup. | Email or a Slack channel | None. Cheap to send to, fine to ignore. |
| `ticket` | Needs an owner or follow-up, not time sensitive. | Ticket queue | Triaged within days. |
| `page` | Time sensitive, needs a response within a defined window. | Pager | A human responds within the rotation's SLO. |

Each destination has a different *cost of being wrong*. A noisy `testing` alert costs a few
ignored Slack messages. A noisy `page` costs sleep, trust, and eventually attrition. An alert
earns its way up the cost ladder, and can be pushed back down when it stops earning its keep.

Alongside these, define one more destination, but note that it is **not a state**. `uncaught` is
the backstop for alerts that match none of the states above because their `target` is missing or
misspelled. It sits explicitly *outside* the state machine: nobody sets it, nothing promotes or
demotes into or out of it, and an alert only gets there by mistake. Send it somewhere cheap and
low-urgency, such as an email address or a ticket queue.

## Alertmanager config

The rule author sets the state in the rule:

```yaml
- alert: FrontendHighErrorRatio
  expr: |
    sum(rate(http_requests_total{job="frontend", code=~"5.."}[5m]))
      / sum(rate(http_requests_total{job="frontend"}[5m])) > 0.02
  for: 10m
  labels:
    target: testing
```

Alertmanager routes purely on that label:

```yaml
route:
  receiver: uncaught         # root route: matched no state
  group_by: [alertname, job]
  routes:
    - matchers: [target="page"]
      receiver: pager
      group_wait: 30s
      repeat_interval: 1h
    - matchers: [target="ticket"]
      receiver: ticket-queue
      group_wait: 5m
      repeat_interval: 3d
    - matchers: [target="testing"]
      receiver: testing
      group_interval: 1h
      repeat_interval: 24h

receivers:
  - name: uncaught
    email_configs: [{to: alert-routing-owners@example.com}]
  - name: pager
    pagerduty_configs: [{routing_key_file: /etc/alertmanager/secrets/pagerduty}]
  - name: ticket-queue
    webhook_configs: [{url: http://ticket-bridge.internal/alerts}]
  - name: testing
    slack_configs: [{channel: "#alerts-testing", send_resolved: true}]
```

Adding, promoting, demoting or deleting an alert never touches this file. That's much of the
appeal: Alertmanager config bugs have a large blast radius, so the less often it changes, the
better.

Details that matter:

* **Failing safe means failing quiet.** An alert with a bad `target` falls through to the root
  receiver, which must never be `page`.
* **`uncaught` is distinct from `testing`.** `testing` is a deliberate state people expect to be
  noisy. `uncaught` means "this alert is misrouted" and needs an owner. Use email for a small
  routing team, or a ticket if you want someone accountable for clearing it.
* **Treat anything `uncaught` as a bug.** Set a valid `target` on the rule. Add a CI lint that
  rejects rules whose `target` isn't a known value, so `uncaught` doesn't become a permanent home.
* **Timing belongs to the state, not the alert.** `group_wait` and `repeat_interval` describe how
  you want to be interrupted: a `page` re-notifies hourly, a `ticket` every few days.

## Transitions

### Promotion: new alert to production

* Write the alert with `target: testing`.
* Let it fire into `#alerts-testing` for a soak period spanning at least one daily and one weekly
  traffic cycle.
* Ask: how often did it fire, was each firing actionable, would I have wanted to be woken?
* If yes, change one line: `testing` becomes `ticket` or `page`.

Review is a one-line diff with a clear question attached. Nobody reasons about Alertmanager
config at promotion time.

### Demotion: stop the bleeding

A noisy alert normally leaves you three bad options: delete it (losing the signal), silence it
(and forget to un-silence it), or leave it noisy until someone has time to refactor it.

**Demote it one state** instead: `page` to `ticket`, or `ticket` to `testing`.

* The noise stops immediately.
* The signal is preserved where you can still see it.
* The refactor happens on your schedule, not the schedule of whoever was just woken up.
* Once fixed, the alert goes back through promotion like any new alert.

Make demotion socially cheap: "demote first, ask questions later". If it feels like admitting
failure, noisy pages will live far too long.

Demote by changing the rule's `target`, not by adding an Alertmanager route that matches on
`alertname`. That reintroduces the config churn and blast radius this pattern avoids, and state
in the rule is easier to review and audit than state hidden in routing.

> **Tip: test the transitions, not just the alert.** State is just a label, so tooling you
> probably already have covers it:
>
> * A `promtool` unit test asserts the alert fires *with the right `target`* via `exp_labels`,
>   so a promotion or demotion is a two-line diff: the rule and its test.
> * [`e2e-alertmanager-test`](https://github.com/conallob/o11y-analysis-tools), part of
>   [o11y-analysis-tools](https://github.com/conallob/o11y-analysis-tools), replays those same
>   `exp_alerts` fixtures through an ephemeral Alertmanager running your real routing tree and
>   renders the notification (email, Slack, webhook JSON). A promotion shows up in review as
>   "this now renders as a page", and a typo'd `target` as a notification landing in the wrong
>   place.
> * It renders output for you to diff rather than asserting on it, so diff its output in CI.
>   Point the ephemeral Alertmanager at a skeleton config with the same routes but no-op
>   receivers, so nothing real is ever sent.
>
> ```bash
> docker run -d -p 9093:9093 prom/alertmanager   # skeleton config, receivers stubbed
> e2e-alertmanager-test --tests=./alerts_test.yml \
>   --alertmanager-config=./alertmanager.yml --output=full > notifications.txt
> ```

## The advanced case: time-sensitive tickets

Some issues are urgent only if nobody notices them soon, and what counts as *soon* depends on
whether people are at their desks. Add a fourth state, `target: p0-ticket`:

* Alertmanager routes it to the ticketing system unconditionally, like `ticket` with a different
  receiver.
* Ticketing automation flags the ticket and assigns it to a dedicated **p0 on-call queue**.
* That queue's **escalation policy** redirects an unacknowledged ticket to the real on-call
  queue after N minutes.

```yaml
    - matchers: [target="p0-ticket"]
      receiver: p0-ticket
      group_wait: 1m
      repeat_interval: 1d
```

Alertmanager deliberately has **no notion of time** here. It's tempting to use `time_intervals`
to send the alert to the p0 queue by day and the pager by night, but the routing decision is
made once, when the alert fires. A ticket filed at 16:55 goes to the p0 queue, nobody is
looking at it by 17:30, and Alertmanager never revisits the decision, so it languishes.

An escalation policy is a timer on the *ticket*, not a window on the clock:

* It escalates N minutes after creation, whether that's 10:00 Tuesday or 16:55 Friday.
* In working hours, the p0 queue's watchers usually catch it first and nobody is paged.
* Otherwise it reaches the real on-call queue with no human deciding that.
* "Who gets interrupted when" stays in one place, the rota and escalation policy, where those
  changes already happen.

`p0-ticket` is *just another state*. It slots into the same ladder (`testing`, `ticket`,
`p0-ticket`, `page`) with no new Alertmanager logic beyond one more `target` route.

## Scaling across teams

The state machine scales to many teams by cloning it, once per team, under a nested `team` route:

```yaml
route:
  receiver: uncaught            # the only uncaught stanza in the tree
  group_by: [alertname, job]
  routes:
    - matchers: [team="payments"]
      routes:
        - matchers: [target="page"]
          receiver: payments-pager
          repeat_interval: 1h
        - matchers: [target="ticket"]
          receiver: payments-tickets
          repeat_interval: 3d
        - matchers: [target="testing"]
          receiver: payments-testing
          repeat_interval: 24h
    - matchers: [team="search"]
      routes:
        # same three states, search's receivers
```

* **One `uncaught` for the whole tree.** Team routes set no `receiver`, so they inherit the
  root's. A bad `target` on a valid team matches no state in that team's clone and falls to
  `uncaught`; an unknown `team` matches no team route and falls to `uncaught`. Don't give each
  team its own backstop.
* **Each team owns its destinations.** The states and their meaning are shared. Receivers
  (pager service, ticket queue, Slack channel) and timing are per team.
* **Onboarding a team is the only config change.** Adding a team adds one stanza. Adding or
  changing an alert is still a rule change.
* **Subdivide the config if it grows.** Alertmanager loads a single file, so keep one file per
  team in your repo and assemble them into the final config at build time. A shared template
  keeps the clones identical, so promotion means the same thing for every team.

## Things to watch out for

* **Keep the state space small.** Each state needs a distinct destination and expectation. If
  two states route to the same place, merge them.
* **Keep `uncaught` quiet but visible.** If it fires on every deploy, people will filter it.
  Keep its volume near zero.
* **Never route on `alertname`.** Per-alert routes put you back to editing Alertmanager config
  whenever an alert changes. Route on `target` (and `team` for ownership); keep per-alert
  decisions in the rules.
* **One label, one meaning.** Don't overload `target` with team, environment or severity. Route
  ownership with a separate `team` label in a nested route, as above.
* **Use `continue` deliberately.** To mirror everything into a firehose or archive, put that
  route first with `continue: true`.
* **Consider inhibition.** A firing `page` can inhibit the `ticket` and `testing` versions of
  related alerts, so one incident doesn't create five notifications.
* **Record transitions.** State lives in a version-controlled rule file, so `git log` is a free
  audit trail of who promoted or demoted an alert, and why.

## Why this works

It's the same idea behind feature flags and canary rollouts: separate *deploying* a change from
*exposing* it. A rule that is merged and firing into `testing` is deployed. It only becomes
exposed when someone makes the deliberate, reviewable choice to promote it.
