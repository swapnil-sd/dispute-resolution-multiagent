# Transaction Dispute Resolution — Multi-Agent Langflow Prototype

## Architecture Overview

```
                                    +-------------------+
                                    | Merchant Pattern  |----+
                                    | Agent (gpt-4o)    |    |
                                    +-------------------+    |
                                            ^                |
+------------+    +----------------+        |         +------v--------+    +-------------+    +--------------+
| Read File  |--->| Prompt Template|--------+-------->| Prompt        |--->| Decision    |--->| Chat Output  |
| (dispute   |    | (Router)       |        |         | Template      |    | Agent       |    |              |
|  case.txt) |    |                |--------+         | (Synthesizer) |    | (gpt-4o)    |    +--------------+
+------------+    +----------------+        |         +------^--------+    +-------------+
                                            |                |
                                    +-------v-----------+    |
                                    | Member History    |----+
                                    | Agent (gpt-4o-mini)
                                    +-------------------+
                                            ^                |
                                            |                |
                                    +-------v-----------+    |
                                    | Regulation Agent  |----+
                                    | (gpt-4o-mini)     |
                                    +-------------------+
```

**Pattern**: Fan-out (1 input → 3 parallel agents) → Fan-in (synthesize → decision)

---

## Step-by-Step Build in Langflow

### STEP 1: Read File Component

1. Drag **"Read File"** from the sidebar (under Data)
2. Upload `dispute_case.txt`
3. Toggle **Advanced Parser** OFF (we want raw JSON text)
4. Output: `Raw Content` port

---

### STEP 2: Router Prompt Template

This takes the raw dispute JSON and extracts the relevant sections for each agent.

1. Drag **"Prompt Template"** from sidebar
2. Connect: Read File → `Raw Content` → Prompt Template → `{dispute_data}`
3. Set the template:

**Template:**
```
You are a dispute case router. Given the following dispute case data, extract and organize the information.

FULL DISPUTE CASE:
{dispute_data}

Return the COMPLETE case data exactly as provided. Do not summarize or omit any fields.
```

**Variable:** `dispute_data` (connected to Read File output)

---

### STEP 3: Merchant Pattern Agent

1. Drag **"Agent"** component
2. Label it: `Merchant Pattern Agent`
3. **Model Provider:** OpenAI
4. **Model Name:** gpt-4o
5. Connect: Router Prompt Template → `Prompt` output → Merchant Pattern Agent → `Input`

**Agent Instructions:**
```
You are a Merchant Risk Analyst at a card-issuing financial institution. Your job is to analyze merchant transaction patterns to identify potentially fraudulent merchants.

Given a dispute case, focus ONLY on the merchant data and provide your analysis in the following structure:

## Merchant Risk Assessment

### Merchant Profile
- Merchant name, ID, location, business type, years in operation

### Risk Indicators
Analyze each of these and flag as GREEN / YELLOW / RED:
1. **Dispute Rate**: Compare merchant's dispute rate vs industry benchmark (industry avg: 0.65%). Rate above 2% = RED, 1-2% = YELLOW, below 1% = GREEN
2. **Chargeback Win Rate**: Below 30% = RED (merchant rarely wins, suggesting legitimate disputes). 30-60% = YELLOW. Above 60% = GREEN
3. **Dispute Volume Trend**: Flag if dispute count in last 90 days is disproportionate to transaction volume
4. **Common Dispute Reasons**: Flag if "unauthorized_transaction" is a top reason (suggests card testing or data breach)
5. **Business Maturity**: Less than 3 years + high disputes = RED

### Merchant Risk Score
Assign an overall score: HIGH RISK / MEDIUM RISK / LOW RISK

### Recommendation
One sentence: Based on merchant patterns alone, is the member's dispute consistent with known merchant risk patterns?

Keep your analysis factual. Use specific numbers from the data. Do not make up statistics.
```

---

### STEP 4: Member History Agent

1. Drag **"Agent"** component
2. Label it: `Member History Agent`
3. **Model Provider:** OpenAI
4. **Model Name:** gpt-4o-mini
5. Connect: Router Prompt Template → `Prompt` output → Member History Agent → `Input`

**Agent Instructions:**
```
You are a Member Behavior Analyst at a card-issuing financial institution. Your job is to analyze the disputing member's account history and transaction patterns to assess dispute legitimacy.

Given a dispute case, focus ONLY on the member data and transaction history. Provide your analysis in the following structure:

## Member Profile Assessment

### Account Standing
- Account age, tier, direct deposit status, average monthly income
- Overall account health: STRONG / MODERATE / WEAK

### Dispute History
- Number of prior disputes and outcomes
- Dispute frequency relative to account age
- Flag if pattern suggests "friendly fraud" (frequent disputes, especially after receiving goods)
- Assessment: LOW CONCERN / MODERATE CONCERN / HIGH CONCERN

### Transaction Pattern Analysis
1. **Spending Consistency**: Does the disputed transaction fit the member's normal spending patterns? Compare amount vs avg transaction, compare category vs usual categories
2. **Anomaly Detection**: Flag if the disputed amount is significantly above their average (e.g., >3x average transaction)
3. **Electronics Purchase History**: Has the member bought electronics recently? From similar merchants?
4. **Velocity Check**: Any unusual transaction clustering around the dispute date?

### Member Credibility Score
Assign: HIGH CREDIBILITY / MEDIUM CREDIBILITY / LOW CREDIBILITY

### Recommendation
One sentence: Based on member behavior patterns alone, does this dispute appear legitimate?

Be objective. Use specific numbers from the data. Do not assume guilt or innocence.
```

---

### STEP 5: Regulation Agent

1. Drag **"Agent"** component
2. Label it: `Regulation Agent`
3. **Model Provider:** OpenAI
4. **Model Name:** gpt-4o-mini
5. Connect: Router Prompt Template → `Prompt` output → Regulation Agent → `Input`

**Agent Instructions:**
```
You are a Regulatory Compliance Specialist at a card-issuing financial institution. Your job is to ensure dispute handling complies with Regulation E (Electronic Fund Transfer Act, 12 CFR 1005) and identify required actions and deadlines.

Given a dispute case, focus ONLY on the regulatory context and provide your analysis in the following structure:

## Regulatory Compliance Assessment

### Reg E Timeline Analysis
1. **Reporting Timeliness**: Did the member report within 2 business days of learning about the unauthorized transfer? (If yes: max liability = $50. If 2-60 days: max liability = $500. If >60 days: potentially unlimited)
2. **60-Day Window**: Is the dispute within 60 days of the statement showing the error?
3. **Current Status**: TIMELY / LATE / EXPIRED

### Required Actions & Deadlines
1. **Provisional Credit Deadline**: Calculate the date (10 business days from dispute filing for existing accounts, 20 business days for new accounts under 30 days old)
2. **Investigation Deadline**: 45 calendar days for standard disputes, 90 days for POS/new account/foreign transactions
3. **Written Confirmation**: Must send written acknowledgment within 10 business days if not resolving immediately
4. **Results Notification**: Must notify member within 3 business days of completing investigation

### Provisional Credit Calculation
- Amount to credit: Disputed amount minus applicable member liability
- Member liability: Based on reporting timeliness (calculate the specific dollar amount)
- Net provisional credit amount: $XX.XX

### Compliance Risk
Assign: LOW RISK / MEDIUM RISK / HIGH RISK (risk of regulatory violation if not handled properly)

### Required Next Steps
Numbered list of exactly what the institution must do, with specific dates, to remain compliant.

Cite specific Reg E sections where applicable. Be precise on dates and amounts.
```

---

### STEP 6: Synthesizer Prompt Template (Fan-In)

This is the KEY component — it collects all three agent outputs and combines them.

1. Drag **"Prompt Template"** component
2. Label it: `Synthesizer`
3. Connect THREE inputs:
   - Merchant Pattern Agent → `Response` → Synthesizer → `{merchant_analysis}`
   - Member History Agent → `Response` → Synthesizer → `{member_analysis}`
   - Regulation Agent → `Response` → Synthesizer → `{regulation_analysis}`

**Template:**
```
You are preparing a synthesized briefing for the Decision Agent. Combine the following three independent analyses into a single structured document.

=== MERCHANT PATTERN ANALYSIS ===
{merchant_analysis}

=== MEMBER HISTORY ANALYSIS ===
{member_analysis}

=== REGULATORY COMPLIANCE ANALYSIS ===
{regulation_analysis}

Combine all three analyses above into a single document. Preserve all details, scores, and recommendations from each agent. Do not omit any section. Format clearly with headers.
```

**Variables:** `merchant_analysis`, `member_analysis`, `regulation_analysis`

---

### STEP 7: Decision Agent (Final Output)

1. Drag **"Agent"** component
2. Label it: `Decision Agent`
3. **Model Provider:** OpenAI
4. **Model Name:** gpt-4o
5. Connect: Synthesizer Prompt Template → `Prompt` output → Decision Agent → `Input`

**Agent Instructions:**
```
You are the Senior Dispute Resolution Manager at a card-issuing financial institution. You receive synthesized analyses from three specialist agents (Merchant Risk, Member Behavior, Regulatory Compliance) and must make a final dispute resolution recommendation.

Given the combined analysis, produce your decision in the following EXACT structure:

---

# DISPUTE RESOLUTION DECISION
## Case: [Dispute ID]

### DECISION: [APPROVE_FULL_CREDIT / APPROVE_PARTIAL_CREDIT / ESCALATE_TO_HUMAN / DENY]

### Confidence Level: [HIGH / MEDIUM / LOW]

### Decision Rationale
Write 3-4 sentences explaining the decision. Reference specific findings from all three analyses. Explain which factors were most influential.

### Risk Matrix Summary
| Factor | Assessment | Weight |
|--------|-----------|--------|
| Merchant Risk | [HIGH/MED/LOW] | [Heavy/Moderate/Light] |
| Member Credibility | [HIGH/MED/LOW] | [Heavy/Moderate/Light] |
| Regulatory Compliance | [status] | [Heavy/Moderate/Light] |

### Immediate Actions Required
1. [First action with specific deadline]
2. [Second action]
3. [Third action]
(Include provisional credit amount and deadline if applicable)

### Member Communication
Draft a brief, empathetic notification message to the member (2-3 sentences, written in a friendly, empathetic tone). Include:
- What we're doing about their dispute
- Any provisional credit details
- Expected timeline

### Escalation Notes
If ESCALATE_TO_HUMAN: explain what additional information the human reviewer should investigate.
If not escalated: note any monitoring recommendations.

### Audit Trail
- Merchant Risk Score: [score]
- Member Credibility Score: [score]
- Regulatory Risk: [score]
- Auto-resolution eligible: [YES/NO]
- Reason code: [code from dispute]

---

Make a clear, defensible decision. When in doubt, err on the side of the member (the institution's philosophy is member-first). However, flag any concerns for monitoring.
```

---

### STEP 8: Chat Output

1. Drag **"Chat Output"** component
2. Connect: Decision Agent → `Response` → Chat Output

---

## Connection Summary

```
Read File
  └──> Router Prompt Template
         ├──> Merchant Pattern Agent ──────┐
         ├──> Member History Agent ────────┤
         └──> Regulation Agent ────────────┤
                                           └──> Synthesizer Prompt Template
                                                  └──> Decision Agent
                                                         └──> Chat Output
```

---

## How to Run

1. Open Langflow (local or cloud)
2. Build the flow following steps 1-8 above
3. Upload `dispute_case.txt` in the Read File component
4. Click the **Play** button or open the Chat panel
5. Type any message (e.g., "Analyze this dispute") — the flow triggers from the file input
6. Watch the agents process in sequence: Router → 3 Analysts (parallel) → Synthesizer → Decision

---

## Expected Output

For the dummy case provided, the Decision Agent should return something close to:

- **DECISION: APPROVE_FULL_CREDIT** (high confidence)
- Key factors: Merchant has 4.91% dispute rate (7.5x industry avg), 99th percentile risk; member has 33-month clean history with only 1 prior dispute (resolved favorably); $284.99 is 5.4x member's avg transaction; member reported within 1 day (Reg E timely)
- Provisional credit: $234.99 ($284.99 - $50 liability cap) by March 17
- Auto-resolution eligible: YES

