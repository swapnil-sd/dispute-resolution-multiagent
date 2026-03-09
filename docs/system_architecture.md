# Transaction Dispute Resolution — Full System Architecture

## End-to-End Flow: Member Files Dispute → Decision

```
┌─────────────────────────────────────────────────────────────────────┐
│                        MEMBER INTERACTION                           │
│                                                                     │
│  Mobile App → Taps transaction → "Dispute this charge"               │
│  Fills form: reason, description, card in possession?               │
│                                                                     │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     STEP 1: API GATEWAY                             │
│                                                                     │
│  Creates raw dispute record:                                        │
│  ┌────────────────────────────────────────────┐                     │
│  │ dispute_id:       DSP-2026-XXXXX (generated)│                    │
│  │ member_id:        from auth session         │                    │
│  │ transaction_id:   from tapped transaction   │                    │
│  │ reason_code:      unauthorized / fraud / etc │                   │
│  │ member_statement: free-text from form        │                   │
│  │ filed_date:       timestamp                  │                   │
│  └────────────────────────────────────────────┘                     │
│                                                                     │
│  This is ONLY the member's input. No enrichment yet.                │
│                                                                     │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│              STEP 2: DISPUTE ORCHESTRATION SERVICE                   │
│                                                                     │
│  The "conductor" — calls 5 internal services in parallel:           │
│                                                                     │
│  ┌───────────────────────┐  ┌───────────────────────────────────┐   │
│  │  MEMBER SERVICE       │  │  TRANSACTION SERVICE (Galileo)    │   │
│  │                       │  │                                   │   │
│  │  GET /members/{id}    │  │  GET /transactions/{txn_id}       │   │
│  │                       │  │  GET /members/{id}/transactions   │   │
│  │  Returns:             │  │      ?days=30                     │   │
│  │  - account_age        │  │                                   │   │
│  │  - tier               │  │  Returns:                         │   │
│  │  - overdraft_limit       │  │  - amount, merchant, MCC          │   │
│  │  - direct_deposit     │  │  - card_present flag              │   │
│  │  - account_standing   │  │  - billing_descriptor             │   │
│  │                       │  │  - 30-day transaction history     │   │
│  └───────────────────────┘  └───────────────────────────────────┘   │
│                                                                     │
│  ┌───────────────────────┐  ┌───────────────────────────────────┐   │
│  │  RISK DATA WAREHOUSE  │  │  DISPUTE HISTORY SERVICE          │   │
│  │                       │  │                                   │   │
│  │  GET /merchants/{id}/ │  │  GET /members/{id}/disputes       │   │
│  │      risk-profile     │  │                                   │   │
│  │                       │  │  Returns:                         │   │
│  │  Returns:             │  │  - prior dispute count            │   │
│  │  - dispute_rate       │  │  - outcomes                       │   │
│  │  - chargeback_win_rate│  │  - frequency                      │   │
│  │  - common reasons     │  │                                   │   │
│  │  - risk_flag          │  │                                   │   │
│  │                       │  │                                   │   │
│  │  (pre-computed,       │  │                                   │   │
│  │   updated hourly)     │  │                                   │   │
│  └───────────────────────┘  └───────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────┐        │
│  │  COMPLIANCE RULES ENGINE                                 │       │
│  │                                                          │       │
│  │  POST /reg-e/calculate                                   │       │
│  │  Input: filed_date, txn_date, account_age, account_type  │       │
│  │                                                          │       │
│  │  Returns:                                                │       │
│  │  - liability_cap ($50 / $500 / unlimited)                │       │
│  │  - provisional_credit_deadline                           │       │
│  │  - investigation_deadline (45 or 90 days)                │       │
│  │  - timeliness status                                     │       │
│  │                                                          │       │
│  │  (CALCULATED, not stored — based on Reg E rules)         │       │
│  └─────────────────────────────────────────────────────────┘        │
│                                                                     │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    STEP 3: DATA PREPARATION                         │
│                                                                     │
│  Raw responses from 5 systems → Cleaned, normalized JSON            │
│                                                                     │
│  What happens here:                                                 │
│                                                                     │
│  1. SCHEMA NORMALIZATION                                            │
│     - Each service returns different formats (camelCase, snake_case,│
│       nested vs flat) → normalize to consistent schema              │
│                                                                     │
│  2. FIELD SELECTION                                                 │
│     - Transaction service returns 50+ fields per transaction        │
│     - Agents only need ~10 → select relevant fields only            │
│     - Reduces token usage and noise                                 │
│                                                                     │
│  3. DERIVED CALCULATIONS                                            │
│     - avg_transaction_amount (computed from history)                │
│     - max_transaction_last_90d                                      │
│     - transactions_above_200_last_12m (count)                       │
│     - account_age_months (from account_opened date)                 │
│     - electronics_purchases_last_12m (filtered subset)              │
│                                                                     │
│  4. PII HANDLING (critical for LLM safety)                          │
│     - MASK: SSN, full card number, date of birth                    │
│     - REDACT: address, phone, email                                 │
│     - KEEP: member name (needed for communication draft),           │
│       member_id, last 4 of card                                     │
│     - LLMs should NEVER see raw PII                                 │
│                                                                     │
│  5. VALIDATION                                                      │
│     - Reject if missing: transaction_id, member_id, amount          │
│     - Reject if amount <= 0 or filed_date is future                 │
│     - Flag if merchant_id not found (new merchant)                  │
│     - Don't send garbage to agents                                  │
│                                                                     │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   STEP 4: ASSEMBLED JSON                            │
│                                                                     │
│  The "enriched dispute payload" — complete, clean, safe for LLM     │
│  This is exactly what dispute_case.txt looks like.                  │
│                                                                     │
│  Sections:                                                          │
│  ├── dispute_id, filed_date                                         │
│  ├── member (profile + standing + deposit info)                     │
│  ├── disputed_transaction (amount, merchant, MCC, card_present)     │
│  ├── dispute_details (reason, statement, card status)               │
│  ├── merchant_data (risk profile + industry benchmarks)             │
│  ├── member_transaction_history (30-day + category-specific)        │
│  └── regulatory_context (Reg E timelines + liability)               │
│                                                                     │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│             STEP 5: MULTI-AGENT REASONING LAYER (Langflow)          │
│                                                                     │
│  POST → Langflow Webhook / API Endpoint                             │
│                                                                     │
│  ┌─────────────┐                                                    │
│  │ Chat Input  │ (receives assembled JSON)                          │
│  └──────┬──────┘                                                    │
│         │                                                           │
│         ├──────────────────┬──────────────────┐                     │
│         ▼                  ▼                  ▼                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │  Merchant    │  │  Member      │  │  Regulation  │              │
│  │  Pattern     │  │  History     │  │  Agent       │              │
│  │  Agent       │  │  Agent       │  │              │              │
│  │  (gpt-4o)    │  │  (gpt-4o-   │  │  (gpt-4o-   │              │
│  │              │  │   mini)      │  │   mini)      │              │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘              │
│         │                  │                  │                     │
│         └──────────────────┴──────────────────┘                     │
│                            │                                        │
│                            ▼                                        │
│                   ┌─────────────────┐                               │
│                   │  Synthesizer    │                               │
│                   │  Prompt Template│                               │
│                   └────────┬────────┘                               │
│                            │                                        │
│                            ▼                                        │
│                   ┌─────────────────┐                               │
│                   │  Decision Agent │                               │
│                   │  (gpt-4o)       │                               │
│                   └────────┬────────┘                               │
│                            │                                        │
│                            ▼                                        │
│                   ┌─────────────────┐                               │
│                   │  Chat Output    │                               │
│                   └─────────────────┘                               │
│                                                                     │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                  STEP 6: RESPONSE HANDLING                           │
│                                                                     │
│  Langflow returns Decision Agent output → Orchestration service     │
│  parses the decision and routes:                                    │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  IF decision == APPROVE_FULL_CREDIT:                         │   │
│  │    → Galileo API: issue provisional credit                   │   │
│  │    → Notification service: send member push/email            │   │
│  │    → Audit DB: log decision + rationale + agent outputs      │   │
│  │    → Dispute DB: update status to "provisional_credit_issued"│   │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  IF decision == ESCALATE_TO_HUMAN:                           │   │
│  │    → Ops queue: create case with pre-analyzed package        │   │
│  │    → Slack: post to #disputes-review with summary            │   │
│  │    → Notification service: send member "under review" msg    │   │
│  │    → Audit DB: log escalation reason                         │   │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  IF decision == DENY:                                        │   │
│  │    → Notification service: send denial with explanation      │   │
│  │    → Audit DB: log decision + rationale                      │   │
│  │    → Flag for QA sampling (denied cases get audited)         │   │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  ALL CASES:                                                         │
│  → Reg E compliance tracker: log all deadlines                      │
│  → Analytics pipeline: feed into dispute trend dashboards           │
│  → Feedback loop: outcome data used for future calibration          │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## System Dependency Map

```
                    ┌─────────────────┐
                    │   Mobile App    │
                    │   (Mobile/Web)  │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │   API Gateway   │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  Orchestration  │◄──── The brain that assembles
                    │  Service        │      the JSON payload
                    └──┬──┬──┬──┬──┬─┘
                       │  │  │  │  │
          ┌────────────┘  │  │  │  └────────────┐
          ▼               ▼  │  ▼               ▼
   ┌────────────┐  ┌──────┐  │  ┌──────────┐  ┌───────────┐
   │  Member    │  │Galileo│  │  │  Risk    │  │Compliance │
   │  Service   │  │(Txns) │  │  │  DW      │  │Rules Eng. │
   │            │  │       │  │  │          │  │           │
   │- profile   │  │- txn  │  │  │- merchant│  │- Reg E    │
   │- account   │  │  data │  │  │  risk    │  │  calc     │
   │- settings  │  │- hist │  │  │- fraud   │  │- deadlines│
   └────────────┘  └──────┘  │  └──────────┘  └───────────┘
                             │
                    ┌────────▼────────┐
                    │ Dispute History │
                    │ Service         │
                    │                 │
                    │- prior disputes │
                    │- outcomes       │
                    └─────────────────┘
```

## Data Preparation — What Gets Filtered

| Raw Field (from source systems) | Action | Reason |
|---|---|---|
| SSN | REDACT | PII — never send to LLM |
| Full card number | MASK (last 4 only) | PCI compliance |
| Date of birth | REDACT | PII |
| Home address | REDACT | PII |
| Phone number | REDACT | PII |
| Email | REDACT | PII |
| Member name | KEEP | Needed for communication draft |
| Internal fraud score (raw) | TRANSFORM | Convert to risk_flag enum |
| Transaction auth codes | DROP | Not useful for agent reasoning |
| Galileo internal IDs | DROP | Internal reference only |
| IP address of transaction | KEEP | Useful for fraud geo-analysis |
| Device fingerprint | TRANSFORM | Convert to device_match boolean |
| 12-month transaction history | AGGREGATE | Too many tokens — compute summaries |

## Latency Budget

| Step | Expected Latency | Notes |
|---|---|---|
| API Gateway → Orchestration | ~50ms | Internal service call |
| 5 parallel data enrichment calls | ~200-400ms | Galileo is the slowest |
| Data preparation | ~50ms | Compute + validation |
| JSON assembly | ~10ms | Template rendering |
| POST to Langflow | ~50ms | Network |
| 3 parallel agents | ~3-5s | LLM inference (bottleneck) |
| Synthesizer + Decision Agent | ~3-5s | LLM inference |
| Response handling | ~100-200ms | API calls for credit/notification |
| **Total end-to-end** | **~7-11 seconds** | Member sees "analyzing your dispute..." |

## Cost Estimates (per dispute)

| Component | Model | Est. Tokens | Est. Cost |
|---|---|---|---|
| Merchant Pattern Agent | gpt-4o | ~2,000 in + ~500 out | ~$0.02 |
| Member History Agent | gpt-4o-mini | ~2,000 in + ~500 out | ~$0.001 |
| Regulation Agent | gpt-4o-mini | ~2,000 in + ~500 out | ~$0.001 |
| Decision Agent | gpt-4o | ~3,000 in + ~800 out | ~$0.04 |
| **Total per dispute** | | | **~$0.06** |

vs. human analyst cost: ~$15-25 per dispute (15-30 min at $50-60/hr loaded)

At 40% auto-resolution rate with 10,000 disputes/month:
- 4,000 auto-resolved × $0.06 = **$240/month AI cost**
- 4,000 × $20 avg analyst cost saved = **$80,000/month savings**

## Observability & Agent Tracking

### Agent Run Audit Trail

Every agent execution is logged to the `dispute_agent_runs` table. One dispute = 5-6 rows (one per agent including guard rail).

```
┌─────────────────────────────────────────────────────────────────────┐
│                    dispute_agent_runs                                │
│                                                                     │
│  run_id          │ uuid       │ run-a3f8-4b21                       │
│  dispute_id      │ string     │ DSP-2026-03847                      │
│  agent_name      │ enum       │ merchant_pattern / member_history /  │
│                  │            │ regulation / decision / guard_rail   │
│  model_used      │ string     │ gpt-4o / gpt-4o-mini               │
│  input_tokens    │ int        │ 2,140                               │
│  output_tokens   │ int        │ 487                                 │
│  latency_ms      │ int        │ 3,200                               │
│  input_payload   │ JSON       │ (data sent to this agent)           │
│  output_payload  │ JSON       │ (agent's full response)             │
│  key_findings    │ JSON       │ {"risk_score": "HIGH", ...}         │
│  timestamp       │ datetime   │ 2026-03-09T14:23:07Z                │
│  status          │ enum       │ success / error / timeout           │
│  error_message   │ string     │ null or error detail                │
└─────────────────────────────────────────────────────────────────────┘
```

**What this gives you:**
- **Traceability**: regulators ask "why was this approved?" → pull the 5 agent records, show the reasoning chain
- **Debugging**: agent gave wrong answer → inspect its exact input, see what it missed
- **Performance**: which agent is the bottleneck? which one errors most?

### Dispute Outcomes Table (Feedback Loop)

Populated weeks later when disputes are fully resolved. This is what powers quality metrics and closes the feedback loop.

```
┌─────────────────────────────────────────────────────────────────────┐
│                    dispute_outcomes                                  │
│                                                                     │
│  dispute_id              │ string   │ DSP-2026-03847                │
│  final_outcome           │ enum     │ approved_permanent /           │
│                          │          │ credit_reversed /              │
│                          │          │ denied_upheld /                │
│                          │          │ denied_overturned              │
│  resolution_date         │ datetime │ 2026-04-15                    │
│  resolved_by             │ enum     │ auto / human                  │
│  member_satisfaction     │ int      │ (if surveyed, 1-5)            │
│  merchant_responded      │ boolean  │ yes / no                      │
│  merchant_provided_proof │ boolean  │ yes / no                      │
│  regulatory_deadlines_met│ boolean  │ yes / no                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Monitoring Dashboard

Three tiers — operational, quality, and compliance.

### Tier 1: Operational Metrics (real-time — Datadog/Grafana)

| Metric | How to Calculate | Alert Threshold |
|---|---|---|
| **Auto-resolution rate** | `(APPROVE + DENY) / total disputes` | Drop below 30% → agents may be over-escalating |
| **Decision distribution** | % APPROVE vs ESCALATE vs DENY | DENY >15% → investigate, may be too aggressive |
| **Avg end-to-end latency** | `timestamp(output) - timestamp(input)` | >15 seconds → model degradation or API issue |
| **Per-agent latency** | from `dispute_agent_runs` | Any agent >8s → bottleneck |
| **Error rate** | `status=error / total runs` per agent | >2% → alert on-call |
| **Cost per dispute** | sum of `(input_tokens * rate + output_tokens * rate)` per dispute | Track daily avg, alert on spikes |
| **Throughput** | disputes processed / hour | Monitor for capacity planning |

### Tier 2: Quality Metrics (daily/weekly batch — Looker/Tableau)

| Metric | How to Calculate | What It Tells You |
|---|---|---|
| **Reversal rate** | `provisional credits reversed / total approved` | Are auto-approvals accurate? Target: <5% |
| **Escalation conversion** | `human approved / total escalated` | If >90%, agents are too cautious — loosen thresholds |
| **Denial appeal rate** | `appeals filed / total denied` | High appeal rate → denial criteria too strict |
| **Appeal overturn rate** | `appeal successful / appeals filed` | If >30%, Decision Agent is making bad deny calls |
| **Agent agreement rate** | How often all 3 specialist agents point the same direction | Low agreement = ambiguous cases trending up |
| **Guard Rail block rate** | `blocked / total decisions` | >10% → Decision Agent prompt needs tuning |
| **Guard Rail block reasons** | Distribution of which check fails most | Tells you what to fix (math errors? tone? compliance?) |

### Tier 3: Compliance Metrics (real-time, zero tolerance)

| Metric | How to Calculate | Requirement |
|---|---|---|
| **Provisional credit on-time rate** | `credits issued before deadline / total approved` | **Must be 100%.** Any miss = Reg E violation |
| **Investigation deadline compliance** | `investigations completed before 45/90-day deadline / total` | **Must be 100%** |
| **Written acknowledgment sent** | `ack sent within 10 business days / total disputes` | **Must be 100%** |
| **Member notification on resolution** | `notified within 3 business days of completion / total` | **Must be 100%** |
| **Avg time to provisional credit** | `credit_issued_timestamp - filed_timestamp` | Track trend; faster = better member experience |

### Dashboard Data Flow

```
dispute_agent_runs (per-agent logs)
        │
        ├──► Tier 1: Operational Dashboard (real-time, Datadog/Grafana)
        │    - latency, error rate, throughput, cost
        │    - source: dispute_agent_runs only
        │
        ├──► Tier 2: Quality Dashboard (daily batch, Looker/Tableau)
        │    - reversal rate, appeal rate, agent agreement
        │    - source: dispute_agent_runs JOIN dispute_outcomes
        │    (outcomes populated weeks later when disputes resolve)
        │
        └──► Tier 3: Compliance Dashboard (real-time, separate view)
             - deadline tracking with auto-alerts to compliance team
             - any miss → PagerDuty alert immediately
             - source: dispute_agent_runs + regulatory_context
```

## Production Enhancements (Future State)

### Guard Rail Agent

```
┌──────────────────────────────────────────────────────────────┐
│                    GUARD RAIL AGENT                           │
│                                                              │
│  Sits between Decision Agent and Response Handling.          │
│  Checks:                                                     │
│  - Decision doesn't violate Reg E                            │
│  - Provisional credit amount is calculated correctly         │
│  - Member communication tone is appropriate                  │
│  - No hallucinated deadlines or amounts                      │
│  - Deny decisions have sufficient justification              │
│                                                              │
│  If check fails → force ESCALATE_TO_HUMAN                    │
└──────────────────────────────────────────────────────────────┘
```

### Feedback Loop

```
┌──────────────────────────────────────────────────────────────┐
│                    FEEDBACK LOOP                              │
│                                                              │
│  After dispute is resolved (weeks later):                    │
│  - Was provisional credit reversed or made permanent?        │
│  - Did member appeal a denial?                               │
│  - Did merchant respond to chargeback?                       │
│  - Was the auto-resolution correct?                          │
│                                                              │
│  This data feeds back to calibrate confidence thresholds:    │
│  - If auto-approvals are reversed too often → tighten        │
│  - If escalations are always approved by humans → loosen     │
└──────────────────────────────────────────────────────────────┘
```

### Calibration Cycle

```
Week 1-4:   Conservative — escalate anything below HIGH confidence
            Expected auto-resolution: ~25-30%

Month 2-3:  Analyze dispute_outcomes — tune thresholds
            If reversal rate <3%, loosen APPROVE threshold
            If escalation conversion >85%, loosen ESCALATE threshold
            Expected auto-resolution: ~40-50%

Month 4+:   Steady state — continuous monitoring
            Retune quarterly or after any model/prompt changes
            Target auto-resolution: 50-60%
            Target reversal rate: <5%
```
