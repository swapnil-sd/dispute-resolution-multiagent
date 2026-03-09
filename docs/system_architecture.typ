#set page(margin: 0.5in, paper: "us-letter")
#set text(font: "New Computer Modern", size: 8pt)
#set par(leading: 0.5em)

#align(center)[
  #text(size: 18pt, weight: "bold")[Transaction Dispute Resolution]
  #v(-4pt)
  #text(size: 12pt, fill: rgb("555"))[Full System Architecture]
  #v(-4pt)
  #line(length: 100%, stroke: 0.5pt + rgb("ccc"))
]

#v(4pt)

#let section-header(title) = {
  v(6pt)
  block(
    width: 100%,
    fill: rgb("1a1a2e"),
    inset: (x: 10pt, y: 6pt),
    radius: 4pt,
    text(fill: white, weight: "bold", size: 10pt)[#title]
  )
  v(4pt)
}

#let card(title, color, body) = {
  block(
    width: 100%,
    stroke: (left: 3pt + color, rest: 0.5pt + rgb("ddd")),
    inset: 8pt,
    radius: (right: 4pt),
    fill: rgb("fafafa"),
    [
      #text(weight: "bold", fill: color, size: 9pt)[#title]
      #v(2pt)
      #body
    ]
  )
  v(4pt)
}

#let step-box(number, title, body) = {
  block(
    width: 100%,
    stroke: 0.5pt + rgb("ddd"),
    inset: 8pt,
    radius: 4pt,
    fill: white,
    [
      #box(
        fill: rgb("1a1a2e"),
        inset: (x: 6pt, y: 3pt),
        radius: 3pt,
        text(fill: white, weight: "bold", size: 8pt)[Step #number]
      )
      #h(6pt)
      #text(weight: "bold", size: 9pt)[#title]
      #v(4pt)
      #body
    ]
  )
  v(4pt)
}

// ─── STEP 1-2: INPUT & ORCHESTRATION ───

#section-header[End-to-End Flow: Member Files Dispute to Decision]

#step-box("1", "Member Interaction + API Gateway")[
  Member opens mobile app #sym.arrow.r taps transaction #sym.arrow.r "Dispute this charge" #sym.arrow.r fills form (reason, description, card status).

  API Gateway creates raw dispute record: `dispute_id` (generated), `member_id` (from auth), `transaction_id` (from tapped txn), `reason_code`, `member_statement`, `filed_date`. This is *only* the member's input -- no enrichment yet.
]

#step-box("2", "Dispute Orchestration Service")[
  The "conductor" calls 5 internal services in parallel:

  #grid(
    columns: (1fr, 1fr),
    gutter: 6pt,
    card("Member Service", rgb("2563eb"))[
      `GET /members/{id}` #sym.arrow.r account\_age, tier, overdraft\_limit, direct\_deposit, account\_standing
    ],
    card("Transaction Service (Galileo)", rgb("059669"))[
      `GET /transactions/{txn_id}` + `GET /members/{id}/transactions?days=30` #sym.arrow.r amount, merchant, MCC, card\_present, billing\_descriptor, 30-day history
    ],
    card("Risk Data Warehouse", rgb("dc2626"))[
      `GET /merchants/{id}/risk-profile` #sym.arrow.r dispute\_rate, chargeback\_win\_rate, common reasons, risk\_flag _(pre-computed, updated hourly)_
    ],
    card("Dispute History Service", rgb("7c3aed"))[
      `GET /members/{id}/disputes` #sym.arrow.r prior dispute count, outcomes, frequency
    ],
  )
  #card("Compliance Rules Engine", rgb("ea580c"))[
    `POST /reg-e/calculate` -- Input: filed\_date, txn\_date, account\_age, account\_type #sym.arrow.r liability\_cap (\$50/\$500/unlimited), provisional\_credit\_deadline, investigation\_deadline (45 or 90 days), timeliness status. _(Calculated, not stored -- based on Reg E rules)_
  ]
]

#step-box("3", "Data Preparation")[
  Raw responses from 5 systems #sym.arrow.r cleaned, normalized JSON:

  #grid(
    columns: (1fr, 1fr),
    gutter: 6pt,
    card("Schema Normalization", rgb("2563eb"))[
      Each service returns different formats (camelCase, snake\_case, nested vs flat) #sym.arrow.r normalize to consistent schema
    ],
    card("Field Selection", rgb("059669"))[
      Transaction service returns 50+ fields per txn; agents only need ~10 #sym.arrow.r select relevant fields only, reduces token usage
    ],
    card("Derived Calculations", rgb("7c3aed"))[
      avg\_transaction\_amount, max\_transaction\_last\_90d, transactions\_above\_200, account\_age\_months, category-specific purchase history
    ],
    card("Validation", rgb("ea580c"))[
      Reject if missing: transaction\_id, member\_id, amount. Reject if amount ≤ 0 or filed\_date is future. Flag if merchant\_id not found.
    ],
  )
  #card("PII Handling (Critical)", rgb("dc2626"))[
    *MASK:* SSN, full card number, DOB #h(8pt) *REDACT:* address, phone, email #h(8pt) *KEEP:* member name (for comms), member\_id, last 4 of card #h(8pt) *LLMs should NEVER see raw PII*
  ]
]

#step-box("4", "Assembled JSON")[
  The "enriched dispute payload" -- complete, clean, safe for LLM. Sections: dispute\_id/filed\_date, member profile, disputed\_transaction, dispute\_details, merchant\_data (risk profile + benchmarks), member\_transaction\_history (30-day + category-specific), regulatory\_context (Reg E timelines + liability).
]

// ─── STEP 5: MULTI-AGENT LAYER ───

#step-box("5", "Multi-Agent Reasoning Layer (Langflow)")[
  POST #sym.arrow.r Langflow Webhook / API Endpoint

  #align(center)[
    #block(
      width: 90%,
      stroke: 0.5pt + rgb("ddd"),
      inset: 10pt,
      radius: 4pt,
      fill: rgb("f0f4ff"),
      [
        #text(size: 8pt)[
          *Chat Input* (receives assembled JSON) \
          #h(20pt) #sym.arrow.b \
          #grid(
            columns: (1fr, 1fr, 1fr),
            gutter: 4pt,
            align(center)[#box(fill: rgb("dbeafe"), inset: 5pt, radius: 3pt)[*Merchant Pattern*\ Agent (gpt-4o)]],
            align(center)[#box(fill: rgb("d1fae5"), inset: 5pt, radius: 3pt)[*Member History*\ Agent (gpt-4o-mini)]],
            align(center)[#box(fill: rgb("fde68a"), inset: 5pt, radius: 3pt)[*Regulation*\ Agent (gpt-4o-mini)]],
          )
          #align(center)[#sym.arrow.b]
          #align(center)[#box(fill: rgb("e0e7ff"), inset: 5pt, radius: 3pt)[*Synthesizer* Prompt Template]]
          #align(center)[#sym.arrow.b]
          #align(center)[#box(fill: rgb("c7d2fe"), inset: 5pt, radius: 3pt)[*Decision Agent* (gpt-4o)]]
          #align(center)[#sym.arrow.b]
          #align(center)[#box(fill: rgb("fecaca"), inset: 5pt, radius: 3pt)[*Guard Rail Agent* (gpt-4o)]]
          #align(center)[#sym.arrow.b]
          #align(center)[#box(fill: rgb("e5e7eb"), inset: 5pt, radius: 3pt)[*Chat Output* + *Airtable Audit Log*]]
        ]
      ]
    )
  ]
]

#step-box("6", "Response Handling")[
  Langflow returns decision #sym.arrow.r Orchestration service parses and routes:

  #grid(
    columns: (1fr, 1fr, 1fr),
    gutter: 4pt,
    card("APPROVE", rgb("059669"))[
      Galileo API: issue provisional credit #sym.arrow.r Notification: send member push/email #sym.arrow.r Audit DB: log decision + rationale #sym.arrow.r Dispute DB: update status
    ],
    card("ESCALATE", rgb("ea580c"))[
      Ops queue: create case with pre-analyzed package #sym.arrow.r Slack: post to \#disputes-review #sym.arrow.r Notification: send "under review" msg #sym.arrow.r Audit DB: log reason
    ],
    card("DENY", rgb("dc2626"))[
      Notification: send denial with explanation #sym.arrow.r Audit DB: log decision + rationale #sym.arrow.r Flag for QA sampling (denied cases get audited)
    ],
  )
  *All cases:* Reg E compliance tracker (log deadlines) #sym.arrow.r Analytics pipeline (trend dashboards) #sym.arrow.r Feedback loop (outcome data for calibration)
]

// ─── DATA PREPARATION TABLE ───

#section-header[Data Preparation -- What Gets Filtered]

#table(
  columns: (2fr, 1fr, 2fr),
  fill: (_, y) => if y == 0 { rgb("1a1a2e") } else if calc.odd(y) { rgb("f5f5f5") } else { white },
  stroke: 0.5pt + rgb("ddd"),
  inset: 6pt,
  text(fill: white, weight: "bold")[Raw Field], text(fill: white, weight: "bold")[Action], text(fill: white, weight: "bold")[Reason],
  [SSN], [REDACT], [PII -- never send to LLM],
  [Full card number], [MASK (last 4)], [PCI compliance],
  [Date of birth], [REDACT], [PII],
  [Home address / Phone / Email], [REDACT], [PII],
  [Member name], [KEEP], [Needed for communication draft],
  [Internal fraud score], [TRANSFORM], [Convert to risk\_flag enum],
  [Transaction auth codes], [DROP], [Not useful for agent reasoning],
  [Galileo internal IDs], [DROP], [Internal reference only],
  [IP address], [KEEP], [Useful for fraud geo-analysis],
  [Device fingerprint], [TRANSFORM], [Convert to device\_match boolean],
  [12-month txn history], [AGGREGATE], [Too many tokens -- compute summaries],
)

// ─── LATENCY & COST ───

#section-header[Latency Budget & Cost Estimates]

#grid(
  columns: (1fr, 1fr),
  gutter: 8pt,
  [
    #card("Latency Budget", rgb("2563eb"))[
      #table(
        columns: (2fr, 1fr, 2fr),
        fill: (_, y) => if y == 0 { rgb("2563eb") } else if calc.odd(y) { rgb("f0f4ff") } else { white },
        stroke: 0.5pt + rgb("ddd"),
        inset: 5pt,
        text(fill: white, weight: "bold", size: 7pt)[Step], text(fill: white, weight: "bold", size: 7pt)[Latency], text(fill: white, weight: "bold", size: 7pt)[Notes],
        [API Gateway], [~50ms], [Internal call],
        [5 enrichment calls], [~200-400ms], [Galileo slowest],
        [Data prep], [~50ms], [Compute + validation],
        [JSON assembly], [~10ms], [Template rendering],
        [POST to Langflow], [~50ms], [Network],
        [3 parallel agents], [~3-5s], [LLM inference],
        [Synth + Decision + Guard Rail], [~5-8s], [LLM inference],
        [Response handling], [~100-200ms], [API calls],
        text(weight: "bold")[*Total*], text(weight: "bold")[*~9-14s*], [Member sees "analyzing..."],
      )
    ]
  ],
  [
    #card("Cost per Dispute", rgb("059669"))[
      #table(
        columns: (2fr, 1fr, 1fr),
        fill: (_, y) => if y == 0 { rgb("059669") } else if calc.odd(y) { rgb("d1fae5") } else { white },
        stroke: 0.5pt + rgb("ddd"),
        inset: 5pt,
        text(fill: white, weight: "bold", size: 7pt)[Agent], text(fill: white, weight: "bold", size: 7pt)[Model], text(fill: white, weight: "bold", size: 7pt)[Cost],
        [Merchant Pattern], [gpt-4o], [~\$0.02],
        [Member History], [gpt-4o-mini], [~\$0.001],
        [Regulation], [gpt-4o-mini], [~\$0.001],
        [Decision], [gpt-4o], [~\$0.04],
        [Guard Rail], [gpt-4o], [~\$0.03],
        text(weight: "bold")[*Total*], [], text(weight: "bold")[*~\$0.09*],
      )

      #v(6pt)
      vs. human analyst: *\$15-25/dispute*

      At 40% auto-resolution, 10K disputes/mo: \
      *\$360/mo AI* vs *\$80,000/mo analyst savings*
    ]
  ],
)

// ─── OBSERVABILITY ───

#section-header[Observability & Agent Tracking]

#grid(
  columns: (1fr, 1fr),
  gutter: 8pt,
  card("Agent Run Audit Trail", rgb("7c3aed"))[
    Every agent execution logged to `dispute_agent_runs`. One dispute = 6 rows.

    *Fields:* run\_id (uuid), dispute\_id, agent\_name (enum), model\_used, input\_tokens, output\_tokens, latency\_ms, input\_payload (JSON), output\_payload (JSON), key\_findings (JSON), timestamp, status (success/error/timeout), error\_message

    *Value:* Traceability (regulators), debugging (inspect inputs), performance (find bottlenecks)
  ],
  card("Dispute Outcomes Table", rgb("ea580c"))[
    Populated weeks later when disputes resolve. Powers the feedback loop.

    *Fields:* dispute\_id, final\_outcome (approved\_permanent / credit\_reversed / denied\_upheld / denied\_overturned), resolution\_date, resolved\_by (auto/human), member\_satisfaction, merchant\_responded, merchant\_provided\_proof, regulatory\_deadlines\_met
  ],
)

// ─── MONITORING DASHBOARD ───

#section-header[Monitoring Dashboard -- Three Tiers]

#card("Tier 1: Operational Metrics (real-time -- Datadog/Grafana)", rgb("2563eb"))[
  #table(
    columns: (2fr, 3fr, 2fr),
    fill: (_, y) => if y == 0 { rgb("2563eb") } else if calc.odd(y) { rgb("f0f4ff") } else { white },
    stroke: 0.5pt + rgb("ddd"),
    inset: 5pt,
    text(fill: white, weight: "bold", size: 7pt)[Metric], text(fill: white, weight: "bold", size: 7pt)[Calculation], text(fill: white, weight: "bold", size: 7pt)[Alert Threshold],
    [Auto-resolution rate], [(APPROVE + DENY) / total], [< 30% #sym.arrow.r over-escalating],
    [Decision distribution], [% APPROVE vs ESCALATE vs DENY], [DENY > 15% #sym.arrow.r too aggressive],
    [Avg E2E latency], [timestamp(out) - timestamp(in)], [> 15s #sym.arrow.r model issue],
    [Per-agent latency], [from agent\_runs], [Any agent > 8s #sym.arrow.r bottleneck],
    [Error rate], [errors / total per agent], [> 2% #sym.arrow.r alert on-call],
    [Cost per dispute], [sum(tokens \* rate)], [Track daily, alert on spikes],
  )
]

#card("Tier 2: Quality Metrics (daily/weekly -- Looker/Tableau)", rgb("7c3aed"))[
  #table(
    columns: (2fr, 3fr, 2fr),
    fill: (_, y) => if y == 0 { rgb("7c3aed") } else if calc.odd(y) { rgb("f3f0ff") } else { white },
    stroke: 0.5pt + rgb("ddd"),
    inset: 5pt,
    text(fill: white, weight: "bold", size: 7pt)[Metric], text(fill: white, weight: "bold", size: 7pt)[Calculation], text(fill: white, weight: "bold", size: 7pt)[Insight],
    [Reversal rate], [credits reversed / total approved], [Target: < 5%],
    [Escalation conversion], [human approved / total escalated], [> 90% #sym.arrow.r loosen thresholds],
    [Appeal overturn rate], [successful appeals / appeals filed], [> 30% #sym.arrow.r bad deny calls],
    [Guard Rail block rate], [blocked / total decisions], [> 10% #sym.arrow.r tune Decision prompt],
  )
]

#card("Tier 3: Compliance Metrics (real-time, zero tolerance)", rgb("dc2626"))[
  #table(
    columns: (2fr, 3fr, 1fr),
    fill: (_, y) => if y == 0 { rgb("dc2626") } else if calc.odd(y) { rgb("fef2f2") } else { white },
    stroke: 0.5pt + rgb("ddd"),
    inset: 5pt,
    text(fill: white, weight: "bold", size: 7pt)[Metric], text(fill: white, weight: "bold", size: 7pt)[Calculation], text(fill: white, weight: "bold", size: 7pt)[Req],
    [Provisional credit on-time], [credits before deadline / total approved], [*100%*],
    [Investigation deadline], [completed before 45/90d / total], [*100%*],
    [Written acknowledgment], [ack within 10 biz days / total], [*100%*],
    [Member notification], [notified within 3 biz days / total], [*100%*],
  )
]

// ─── PRODUCTION ENHANCEMENTS ───

#section-header[Production Enhancements & Calibration]

#grid(
  columns: (1fr, 1fr, 1fr),
  gutter: 6pt,
  card("Guard Rail Agent", rgb("dc2626"))[
    Sits between Decision Agent and Response Handling. Checks: Reg E compliance, provisional credit math, member communication tone, no hallucinated deadlines, deny justification.

    *If check fails #sym.arrow.r force ESCALATE\_TO\_HUMAN*
  ],
  card("Feedback Loop", rgb("059669"))[
    After resolution (weeks later): Was credit reversed or permanent? Did member appeal? Did merchant respond? Was auto-resolution correct?

    Feeds back to calibrate confidence thresholds.
  ],
  card("Calibration Cycle", rgb("2563eb"))[
    *Week 1-4:* Conservative, ~25-30% auto-resolution \
    *Month 2-3:* Tune thresholds, ~40-50% \
    *Month 4+:* Steady state, target 50-60% auto-resolution, < 5% reversal rate
  ],
)

#v(8pt)
#align(center)[
  #text(size: 7pt, fill: rgb("999"))[Transaction Dispute Resolution System Architecture | Multi-Agent Orchestration with Langflow | March 2026]
]
