# Transaction Dispute Resolution — Multi-Agent System

A multi-agent orchestration system built with Langflow that automates transaction dispute resolution for card-issuing financial institutions. The system uses specialized AI agents analyzing disputes in parallel, then synthesizing findings into a single resolution decision.

## Architecture

```
Chat Input (dispute JSON)
  ├── Merchant Pattern Agent (gpt-4o)     → analyzes merchant risk profile
  ├── Member History Agent (gpt-4o-mini)  → analyzes member behavior patterns
  └── Regulation Agent (gpt-4o-mini)      → checks Reg E compliance & deadlines
                    │
                    ▼
              Synthesizer (combines 3 analyses)
                    │
                    ▼
              Decision Agent (gpt-4o) → APPROVE / ESCALATE / DENY
                    │
                    ▼
              Chat Output + Airtable Audit Log
```

### Key Design Patterns
- **Fan-out / Fan-in**: 3 specialist agents run in parallel, outputs converge into a single decision
- **Mixed model strategy**: gpt-4o for reasoning-heavy agents, gpt-4o-mini for rule-based analysis (~60% cost reduction)
- **Separation of concerns**: Each agent is independently updatable and auditable

### Prompting Techniques
- **Role Prompting**: Each agent is a domain specialist
- **Scope Constraint**: Agents only analyze their domain, preventing cross-contamination
- **Structured Output**: Every agent returns a specific format with scores and tables
- **Chain-of-Thought**: Agents analyze individual factors before arriving at a score

## Repo Structure

```
├── README.md
├── flow/
│   └── dispute_resolution_flow.json    ← Import this into Langflow
├── test-cases/
│   ├── dispute_case.txt                ← APPROVE scenario (clear-cut fraud)
│   └── dispute_case_escalate.txt       ← ESCALATE scenario (ambiguous signals)
└── docs/
    ├── system_architecture.md          ← Full system architecture
    ├── system_architecture.pdf         ← PDF version
    ├── system_architecture.typ         ← Typst source
    └── langflow_build_guide.md         ← Step-by-step build guide with all prompts
```

## Quick Start

1. Install [Langflow](https://langflow.org/) (desktop app or `pip install langflow`)
2. Import `flow/dispute_resolution_flow.json`
3. Add your OpenAI API key to each agent component
4. Open the chat panel and paste the contents of either test case
5. Watch the multi-agent flow process the dispute

## Test Cases

### Case 1: Jordan Rivera — APPROVE_FULL_CREDIT (high confidence)
- 33-month account, good standing, $4,200/mo direct deposit
- $284.99 charge from TechGear Pro Online (HIGH RISK merchant: 4.91% dispute rate, 99th percentile)
- Transaction is 5.4x member's average, unusual category
- Reported within 1 day (Reg E timely, $50 liability cap)

### Case 2: Casey Whitmore — ESCALATE_TO_HUMAN (conflicting signals)
- 4-month account, no direct deposit, 3 prior disputes in 4 months
- $199.99 at EliteWear Fashion (LOW RISK merchant: 0.70% dispute rate)
- Clothing is member's #1 spend category — transaction fits their pattern
- Device fingerprint matches member's own device
- Prior dispute was denied (merchant proved delivery)

## Production Architecture

The full system architecture (see `docs/system_architecture.md`) covers:
- **Data pipeline**: 5 backend services assemble the enriched dispute JSON
- **PII handling**: SSN, card numbers, DOB redacted before LLM exposure
- **Observability**: Per-agent audit trail logged to Airtable/database
- **3-tier monitoring**: Operational (real-time), Quality (weekly batch), Compliance (zero tolerance)
- **Cost**: ~$0.09/dispute vs $15-25/dispute human analyst
- **Latency**: ~9-14 seconds end-to-end

## Built With
- [Langflow](https://langflow.org/) — visual multi-agent orchestration
- OpenAI GPT-4o / GPT-4o-mini — LLM inference
- Airtable — audit trail logging
