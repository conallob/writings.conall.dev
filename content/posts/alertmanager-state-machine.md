---
title: "Alerts as a State Machine: Promote, Demote, Repeat"
date: 2026-10-01T09:00:00+01:00
draft: false
description: "Use a single routing label in Alertmanager to turn alert lifecycle (new, stable, noisy, urgent) into a state machine where promotion and demotion are one-line changes."
tags: ["SRE", "Observability", "Alertmanager", "Prometheus", "PromQL", "On-call"]
categories: ["Engineering"]
---

Most alerting setups treat an alert as a static thing: you write a rule, it pages someone, and
it does so until somebody deletes it. But alerts have a lifecycle. They start out unproven,
become trustworthy, get noisy as the system underneath them changes, and occasionally need to be
treated differently depending on whether it's 11am on a Tuesday or 3am on a Sunday.

If you model that lifecycle explicitly, a lot of painful, ad-hoc processes become a one-line
change. The trick is to treat **one routing label** as the alert's *state*, and Alertmanager as
the machine that maps each state to a destination.

## The states

I use a label called `target`. (`severity` works too, and you may already have one. The point is
that it describes *where an alert should go*, not merely how bad it is.)

| `target` | Meaning | Destination | Expectation |
|---|---|---|---|
| `testing` | Untrusted. New, or demoted for cleanup. | Email or a Slack channel | None. Cheap to send to, fine to ignore. |
| `ticket` | Needs an owner or follow-up, but isn't time sensitive. | Ticket queue | Someone triages it within days. |
| `page` | Time sensitive. Must be addressed within a defined window. | Pager | A human responds within the SLO of the rotation. |

Alongside these, define one more destination, but note that it is **not a state**. `uncaught` is
the backstop for alerts that match none of the states above, because their `target` is missing or
misspelled. It sits explicitly *outside* the state machine: nobody sets it, nothing promotes or
demotes into or out of it, and an alert only ever ends up there by mistake. Send it somewhere
cheap and low-urgency, such as an email address or a ticket queue. Every router needs a defined
answer for input it doesn't recognise, and this is that answer.

The important property is that each destination has a different *cost of being wrong*. A noisy
alert in `testing` costs nothing but a few ignored Slack messages. A noisy alert in `page` costs
sleep, trust, and eventually attrition. The state machine lets an alert earn its way up the cost
ladder, and lets you push it back down quickly when it stops earning its keep.

## Alertmanager config

The rule author sets the state in the alert rule:

```yaml
groups:
  - name: frontend
    rules:
      - alert: FrontendHighErrorRatio
        expr: |
          sum(rate(http_requests_total{job="frontend", code=~"5.."}[5m]))
            /
          sum(rate(http_requests_total{job="frontend"}[5m]))
            > 0.02
        for: 10m
        labels:
          target: testing
        annotations:
          summary: "Frontend 5xx ratio above 2% for 10m"
```

And Alertmanager routes purely on that label. Adding, promoting, demoting or deleting an alert
never touches this file, which is much of the appeal: Alertmanager config bugs have a large blast
radius, so the less often it changes, the better.

```yaml
route:
  receiver: uncaught         # default: anything matching no route below
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
    email_configs:
      - to: alert-routing-owners@example.com
        send_resolved: false
  - name: pager
    pagerduty_configs:
      - routing_key_file: /etc/alertmanager/secrets/pagerduty
  - name: ticket-queue
    webhook_configs:
      - url: http://ticket-bridge.internal/alerts
  - name: testing
    slack_configs:
      - channel: "#alerts-testing"
        send_resolved: true
```

A few details are doing real work here:

* **The root route is the `uncaught` backstop, and it is not `page`.** An alert with a missing or
  misspelled `target` matches none of the child routes and falls through to the root receiver.
  That receiver should be cheap and low-urgency, so failing means failing quiet, but it should
  also be *distinct* from `testing`. `testing` is a deliberate state that people choose and
  expect to be noisy; `uncaught` means "this alert is misrouted", and it needs an owner. Use
  email if you have a small routing team who'll see it, and a ticket if you want someone to be
  accountable for clearing it.
* **Treat anything `uncaught` as a bug.** The fix is almost always to set a valid `target`
  on the rule, which moves the alert into the state machine. Pair it with a
  lint check in CI that rejects rules whose `target` isn't one of the known values. That's the
  kind of thing a static analysis pass over rule files is very good at, and it stops
  `uncaught` from becoming a permanent home.
* **Timing parameters belong to the state, not the alert.** `repeat_interval` and `group_wait`
  are properties of how you want to be interrupted, so they live on the route for each state.
  A `page` should re-notify hourly; a `ticket` shouldn't re-notify for days.

## Transitions

With that in place, the processes people usually argue about become mechanical.

### Promotion: new alert to production

1. Write the alert with `target: testing`.
2. Let it fire into `#alerts-testing` for a defined soak period, long enough to span at least one
   daily and one weekly cycle of your traffic.
3. Ask the real questions: how often did it fire? Was each firing actionable? Would I have wanted
   to be woken for it?
4. If yes, change one line: `target: testing` becomes `target: ticket` or `target: page`.

The review is a one-line diff with a clear question attached to it. Nobody has to reason about
Alertmanager config at promotion time, because that was done once, up front.

### Demotion: stop the bleeding

An alert is generating too many unactionable tickets or pages. The usual options are all bad:
delete it (and lose the signal), silence it (and forget to un-silence it), or leave it noisy while
someone finds time to refactor it properly.

With a state machine you have a fourth option: **demote it one state**. `page` becomes `ticket`, or
`ticket` becomes `testing`. The noise stops immediately, the signal is preserved where you can
still see it, and the refactoring happens on a timescale that isn't dictated by the person who
was just woken up. Once the rule is fixed, it goes back through promotion like any new alert.

Demotion should be socially cheap. If demoting feels like admitting failure, people will hold on
to noisy pages for far too long. Make "demote first, ask questions later" the stated norm.

Resist the urge to demote by adding an Alertmanager route that matches on `alertname`. That
trades a one-line rule change for a change to shared routing config, which is exactly the churn
and blast radius this pattern exists to avoid. Demotion is a change to the rule's `target`, and
state kept in the rule is also easier to review and audit than state hidden in routing.

> **Tip: test the transitions, not just the alert.** Because state is just a label, it's easy
> to cover with the tooling you probably already have. A `promtool` unit test can assert that the
> alert fires *with the right `target`* by including it in `exp_labels`, so a promotion or
> demotion is a two-line diff: the rule and its test. Then replay those same `exp_alerts`
> fixtures through an ephemeral Alertmanager with
> [`e2e-alertmanager-test`](https://github.com/conallob/o11y-analysis-tools), part of
> [o11y-analysis-tools](https://github.com/conallob/o11y-analysis-tools):
>
> ```bash
> docker run -d -p 9093:9093 prom/alertmanager   # skeleton config, receivers stubbed
> e2e-alertmanager-test --tests=./alerts_test.yml \
>   --alertmanager-config=./alertmanager.yml --output=full > notifications.txt
> ```
>
> It renders what the notification would actually look like (email, Slack, webhook JSON)
> using your real routing tree, so a promotion shows up in review as "this now renders as a
> page", and a typo'd `target` shows up as a notification landing in the wrong place before it merges.
> It renders output for you to diff rather than asserting on it, so commit or diff
> `notifications.txt` in CI. Point the ephemeral Alertmanager at a skeleton config that keeps
> your routes but swaps receiver credentials for local no-ops, so nothing real is ever sent.

## The advanced case: time-sensitive tickets

Not everything fits neatly into "page now" or "ticket eventually". Some issues are urgent only
if nobody notices them soon, and what counts as *soon* depends on whether people are at their
desks.

Add a fourth state, `target: p0-ticket`. The flow is:

1. Alertmanager routes `p0-ticket` alerts to the ticketing system, unconditionally, exactly like
   `ticket` but to a different receiver.
2. Automation on the ticketing side (a trigger or webhook) flags the ticket and assigns it to a
   dedicated **p0 on-call queue**.
3. That queue has its own **escalation policy**: if nobody acknowledges within N minutes, the
   ticket is redirected to the real on-call queue.

```yaml
    - matchers: [target="p0-ticket"]
      receiver: p0-ticket
      group_wait: 1m
      repeat_interval: 1d
```

The key design decision is that **Alertmanager has no notion of time here**. It's tempting to
express "business hours" in Alertmanager, with `time_intervals` that send the alert to the p0
queue during the day and to the pager at night. That has a flaw: the routing decision is made
once, at the moment the alert fires. A ticket filed at 16:55 goes to the p0 queue, nobody is
looking at it by 17:30, and Alertmanager never revisits the decision, so it languishes until
someone happens to see it.

An escalation policy is a timer on the *ticket*, not a window on the clock. The ticket escalates
N minutes after it was created without an acknowledgement, whether that's 10:00 on a Tuesday or
16:55 on a Friday. During working hours, the people watching the p0 queue will usually catch it
first and nobody is paged. Otherwise the escalation fires and it reaches the real on-call queue
anyway, with no human having to decide that. It also keeps "who gets interrupted when" in one
place, the rota and escalation policy, which is where those changes already happen.

The point is that `p0-ticket` is *just another state*. It slots into the same promote/demote
ladder (`testing` to `ticket` to `p0-ticket` to `page`) with no new concepts, and no new
Alertmanager logic beyond one more `target` route.

## Things to watch out for

* **Keep the state space small.** Every state needs a distinct destination and a distinct
  expectation. If two states route to the same place, merge them.
* **Keep `uncaught` quiet but visible.** If it fires on every deploy, people will filter it,
  and you'll have rebuilt the problem it exists to catch. Keep its volume near zero.
* **Never route on `alertname`.** Per-alert routes put you back to editing Alertmanager config
  every time an alert changes. Keep routing keyed on `target` (and, for ownership, `team`), and
  keep the per-alert decisions in the rules.
* **One label, one meaning.** Don't overload `target` with team, environment, or severity. Route
  ownership with a separate label (`team`, say) using a nested route, so the two dimensions
  stay orthogonal.
* **Use `continue` deliberately.** If you also want everything mirrored into a firehose channel
  or a long-term archive, put that route first with `continue: true`.
* **Think about inhibition.** A firing `page` for a service can inhibit the `ticket` and `testing`
  versions of related alerts, so one incident doesn't create five different notifications.
* **Record transitions.** Because state is a label in a version-controlled rule file, `git log`
  gives you a free audit trail of when an alert was promoted or demoted, by whom, and (if you
  insist on good commit messages) why.

## Why this works

The underlying idea is the same one that makes feature flags and canary rollouts useful: separate
*deploying* a change from *exposing* it to the people it affects. An alert rule that is merged and
firing into `testing` is deployed. It only becomes exposed when someone makes the deliberate,
reviewable choice to promote it.

Once alerts have a lifecycle, you can build tooling around it: a policy that nothing stays in `testing` for more than 30
days, or automatic demotion proposals for pages with a low actionable ratio. None of that is possible when an alert is just
"on" or "off".
