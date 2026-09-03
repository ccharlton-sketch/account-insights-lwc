# AI Knowledge & Insights (Ferguson)

A Salesforce Account-page panel that gives reps three things in one click:

1. **Performance Highlights** — Open Opportunity Amount, Closed This Year, and Customer Total Spend, computed live from Opportunity data. These three metrics are hardcoded but fully customizable to your own — see [Customizing Performance Highlights](ARCHITECTURE.md#customizing-performance-highlights).
2. **Needs Attention** — an AI-generated narrative summary of the account, rendered from markdown.
3. **Recommended Actions** — up to 3 "next best action" cards, chosen per-account by an Einstein Prompt Template from a growable catalog of candidate actions. Each card launches a Screen Flow in place, with a back button to return to the card list.

This repo contains the full source: Apex controller + tests, three Lightning Web Components, a Custom Metadata Type that acts as the action catalog, a Platform Cache partition so repeat views of the same account within 20 minutes skip re-running the AI generations, and the Prompt Template metadata for action selection.

- **Installing this?** Start with [INSTALL.md](INSTALL.md).
- **Want to understand how it fits together, add a new recommended action, or swap in your own Performance Highlights metrics?** See [ARCHITECTURE.md](ARCHITECTURE.md).

## Prerequisites

- Salesforce org with Einstein Generative AI / Prompt Builder enabled, and access to a GPT-class model (the shipped template defaults to `sfdc_ai__DefaultGPT5Mini` — see [INSTALL.md](INSTALL.md) if that's not available in your org).
- An existing Einstein Prompt Template that generates an account narrative (referred to below as `Account_Insights`) — **not included in this repo**, since it's org-specific. See the configuration section in [INSTALL.md](INSTALL.md).
- One or more Screen Flows to launch from the Recommended Actions cards, each accepting an `account` (Account record) input variable.

## What's NOT included

- The `Account_Insights` prompt template itself (customer-owned, org-specific — you point this repo's Apex at your own).
- Any Screen Flows — you bring your own, and register them in the `Recommended_Action__mdt` catalog.
- A ready-made FlexiPage — the button component is provided, but placement on your Account page is a manual Lightning App Builder step (see INSTALL.md).
