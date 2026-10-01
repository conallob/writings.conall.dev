---
title: "Alerts as a State Machine: Promote, Demote, Repeat"
date: 2026-10-01T09:00:00+01:00
draft: true
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
| *(no match)* | The backstop. Anything that matches none of the above. | An email address or a ticket queue | Someone eventually notices and fixes the label. |

That last row isn't a value you set; it's the state an alert lands in when it matches nothing else.
Every state machine needs a defined behaviour for input it doesn't recognise, and this one is
no exception.

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

And Alertmanager routes purely on that label:

```yaml
route:
  receiver: backstop         # default: anything matching no route below
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
  - name: backstop
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

Two details are doing real work here:

* **The root route is a backstop, and it is not `page`.** An alert with a missing or misspelled
  `target` matches none of the child routes and falls through to the root receiver. That receiver
  should be cheap and low-urgency, so failing means failing quiet, but it should also be
  *distinct* from `testing`. `testing` is a deliberate state that people choose and expect to be
  noisy; the backstop means "this alert is misrouted", and it needs an owner. An email address
  or a ticket destination both work: use email if you have a small routing team who'll see it,
  and a ticket if you want someone to be accountable for clearing it.
* **Treat anything in the backstop as a bug.** The fix is almost always to set a valid `target`
  on the rule, which moves the alert into the state machine proper. Pair the backstop with a
  lint check in CI that rejects rules whose `target` isn't one of the known values. That's the
  kind of thing a static analysis pass over rule files is very good at, and it stops the
  backstop from becoming a permanent home.
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

If you want to demote without touching the rule file (for example, a rule owned by another team),
you can also override at the Alertmanager layer by matching on `alertname` ahead of the
`target`-based routes:

```yaml
    - matchers: [alertname="FrontendHighErrorRatio"]
      receiver: testing   # temporary demotion, link the bug here
```

That's an escape hatch, not the default. State in the rule is easier to review and audit than
state hidden in routing.

## The advanced case: time-sensitive tickets

Not everything fits neatly into "page now" or "ticket eventually". Some issues are urgent only
if nobody notices them soon, and what counts as *soon* depends on whether people are at their
desks.

Add a fourth state, `target: p0-ticket`. The flow is:

1. Alertmanager routes `p0-ticket` alerts to the ticketing system, creating a ticket as usual.
2. Automation on the ticketing side (a trigger or webhook) flags the ticket and assigns it to a
   dedicated **p0 on-call queue**.
3. That queue has its own **escalation policy**: if nobody acknowledges within N minutes, the
   ticket is redirected to the real on-call queue, which pages.

The result is a grace period. During business hours, the people watching the p0 queue will usually
catch it first, without anyone being paged. Out of hours, or when nobody's looking, the
escalation fires and it becomes a page anyway, with no human having to decide that.

Alertmanager can express the business-hours side of this directly with
[time intervals](https://prometheus.io/docs/alerting/latest/configuration/#time_interval):

```yaml
time_intervals:
  - name: business-hours
    time_intervals:
      - weekdays: ['monday:friday']
        times:
          - start_time: '09:00'
            end_time: '17:00'
        location: 'Europe/Dublin'

route:
  routes:
    - matchers: [target="p0-ticket"]
      receiver: p0-ticket
      active_time_intervals: [business-hours]
    - matchers: [target="p0-ticket"]
      receiver: pager         # out of hours: skip the grace period
      mute_time_intervals: [business-hours]
```

Whether you encode the business-hours split in Alertmanager or leave it to the escalation policy
in the ticketing system is a judgement call. I prefer keeping Alertmanager dumb and the
escalation policy as the single source of truth for "who gets interrupted when", since that's
where rota changes already happen.

The point is that `p0-ticket` is *just another state*. It slots into the same promote/demote
ladder (`testing` to `ticket` to `p0-ticket` to `page`) with no new concepts.

## Things to watch out for

* **Keep the state space small.** Every state needs a distinct destination and a distinct
  expectation. If two states route to the same place, merge them.
* **Keep the backstop quiet but visible.** If it fires on every deploy, people will filter it,
  and you'll have rebuilt the problem it exists to catch. Keep its volume near zero.
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

Once alerts have a lifecycle, you can build tooling around it: dashboards counting alerts per
state, a policy that nothing stays in `testing` for more than 30 days, or automatic demotion
proposals for pages with a low actionable ratio. None of that is possible when an alert is just
"on" or "off".
