# Architecture

## Request flow

```
Account record page
  └─ aiKnowledgeInsightsButton (LWC, on the page)
       └─ opens aiKnowledgeInsightsModal.open({ recordId }) via lightning/modal
            ├─ getPerformanceHighlights(accountId)         → Apex → SOQL aggregate on Opportunity
            ├─ getAccountInsightsNarrative(accountId)      → Apex → ConnectApi → "Account_Insights" prompt template → markdown
            │       └─ markdownUtils.convertMarkdownToHtml() → lightning-formatted-rich-text
            └─ getRecommendedActions(accountId)            → Apex → ConnectApi → "Next_Steps_AI_Recommendation" prompt template
                    └─ Apex parses the AI's JSON, resolves keys against Recommended_Action__mdt
                    └─ up to 3 RecommendedAction cards rendered
                            └─ click a card → lightning-flow launches that card's flowApiName in place
                            └─ "Back" button → returns to the card grid (no navigation away from the modal)
```

All three loads (Performance Highlights, Needs Attention, Recommended Actions) kick off in parallel from `connectedCallback()` and resolve independently — each has its own loading spinner, error state, and (for Recommended Actions) empty state, so a failure in one section never blocks the others.

## What each piece does

### `AccountAiInsightsController.cls` (Apex, `public with sharing`)

The only controller in this feature. Three `@AuraEnabled` methods, one per modal section:

- **`getPerformanceHighlights(Id accountId)`** — `@AuraEnabled(cacheable=true)`. One grouped SOQL query (`GROUP BY IsWon, IsClosed, CALENDAR_YEAR(CloseDate)`) aggregated in Apex into a `PerformanceHighlights` wrapper: `openOpportunityAmount`, `closedThisYearAmount`, `customerTotalSpend`. Null-Amount-safe (defaults to 0), and returns zeros rather than throwing for a null/missing account.

- **`getAccountInsightsNarrative(Id accountId)`** — calls `ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate('Account_Insights', ...)` with the Account as the `Input:account` SObject-reference input, and returns the raw markdown text of the first generation. Not cacheable — triggers a real generation every call. Throws `AuraHandledException` on a null Id, a missing/erroring template, or an empty generations list.

- **`getRecommendedActions(Id accountId)`** — the "next best action" pipeline:
  1. Loads the full `Recommended_Action__mdt` catalog into a `Map<DeveloperName, record>`.
  2. Calls `ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate('Next_Steps_AI_Recommendation', ...)`, same `Input:account` shape as above.
  3. Hands the raw response text to `parseActionKeys()` (`@TestVisible`, private) — tolerant JSON parsing that accepts either `{"title": ..., "Actions": [...]}` or a bare `["key1", "key2"]` array, strips ` ``` ` code-fence wrapping if the model adds it, and returns an empty list (never throws) on anything unparseable.
  4. Hands the resulting keys plus the catalog map to `resolveRecommendedActions()` (`@TestVisible`, private) — looks each key up in the catalog, silently skips anything not found (a hallucinated or stale key), and caps the result at 3.
  5. Returns `List<RecommendedAction>` — a plain wrapper (`actionKey`, `title`, `description`, `flowApiName`, `iconName`, `iconVariant`) built from the matched `Recommended_Action__mdt` record, not from anything the AI wrote. **The AI only ever selects which keys to show — it never generates the card text, icon, or flow that actually gets executed.** This is deliberate: it makes hallucination harmless (an unrecognized key is just dropped) and means the flow that ultimately launches is always one you configured in the catalog, never something free-text from a model response.

  Real failures (callout error, missing template) throw `AuraHandledException`, same pattern as `getAccountInsightsNarrative`. An empty catalog match (parsed fine, but nothing resolved) returns an empty list — the LWC shows an empty-state message, not an error.

### `Recommended_Action__mdt` (Custom Metadata Type)

The action catalog. One record per candidate action, editable in Setup with no code change or deploy required. Fields: `Title__c`, `Description__c`, `FlowApiName__c`, `IconName__c`, `IconVariant__c`, `SelectionCriteria__c` (see "Growing the catalog" below for the current limitation on this last field).

### `Next_Steps_AI_Recommendation` (Einstein Prompt Template)

One required input, `Input:account` (Account SObject reference). `responseFormat` is set to `JSON`. As shipped, the instructions hardcode the 3 example action keys directly in the template body — this was intentionally built as a proof-of-concept ("does the AI-selection pipeline work at all") before scaling the catalog. See "Growing the catalog" below for what changes when you add a 4th+ action.

### LWCs

- **`aiKnowledgeInsightsButton`** — the only component exposed to App Builder (`lightning__RecordPage` / `Account`). Opens the modal via `LightningModal.open()`, passing `recordId`.
- **`aiKnowledgeInsightsModal`** — not exposed; only ever opened programmatically by the button. Owns all state and both Apex/ConnectApi calls. Contains the click-to-launch-flow-in-place logic: clicking a Recommended Action card sets `activeFlow` to that card's data (matched by `actionKey`), which swaps the card grid for a `lightning-flow` bound to `activeFlow.flowApiName`, passing the account record as a flow input variable named `account`. A "Back" button (or the flow finishing) clears `activeFlow` and returns to the grid — the modal itself never closes during this, so the rep never loses their place.
- **`markdownUtils`** — no UI, just an exported `convertMarkdownToHtml()` function. A small hand-rolled regex converter (headers, bold, ordered/unordered lists, tables, horizontal rules) — no external markdown library. Output is fed into `lightning-formatted-rich-text`, which sanitizes to a safe tag allowlist, so this is safe by construction even though the source text comes from a model.

## How action selection actually works (today)

The prompt template returns a JSON object naming which catalog keys to show. Apex resolves those keys against real `Recommended_Action__mdt` records and discards anything it doesn't recognize. This means:

- The DeveloperName you give a catalog record **is** the key the AI must return — e.g. a record with DeveloperName `Escalate_Account` is selected by the AI returning the literal string `"Escalate_Account"`.
- Nothing about a card's visible content (title, icon, description) is AI-generated. Only the *choice of which 3 cards to show* is.

## Growing the catalog past a few actions

The current shipped template hardcodes its 3 example keys directly in the prompt instructions text, and doesn't reference the account's actual data when choosing. That was a deliberate simplification to prove the selection pipeline end-to-end before investing in the full design. **Before adding a meaningful number of actions (more than you'd want listed by hand in the prompt body), do this:**

1. **Add a second input to the template**, `Input:actionCatalog` (plain Text), and rewrite the instructions to reference it (e.g. `{!Input:actionCatalog}`) instead of the hardcoded key list.
2. **In `getRecommendedActions`**, build that catalog text from the `Recommended_Action__mdt.getAll()` map you already have in memory — one line per action, including its `DeveloperName` (the key), `Title__c`, and its `SelectionCriteria__c` (this field exists in the schema today specifically for this — it's just not being sent to the AI yet). Pass it as a second `ConnectApi.WrappedValue` in the same `valueMap`, alongside `Input:account`. For a plain-Text input, the `WrappedValue.value` is the raw string directly — not wrapped in a map (that map-wrapping is only for SObject-reference inputs like `Input:account`).
3. **Rewrite the instructions** to tell the model to actually reason over the account's data and the catalog's `SelectionCriteria__c` guidance when choosing 3 keys, rather than always returning the same fixed set.
4. **Keep instructions literal and directive**, not descriptive — see the note in [INSTALL.md](INSTALL.md#3-configure-the-model-used-by-next-best-action-selection) about why vague/hedged instructions can pass in the Prompt Builder preview but fail against the real API path this Apex code uses.

Nothing in `parseActionKeys`/`resolveRecommendedActions` needs to change for this — they already treat the response as an arbitrary set of candidate keys resolved against whatever's currently in the catalog, so the catalog can grow to any size without an Apex change.

## Adding a single new action (no catalog redesign needed)

If you just want to add one more action today, without doing the "growing the catalog" work above:

1. Build (or point at) the Screen Flow, with an input variable named `account` (Record, Account).
2. Create a new `Recommended_Action__mdt` record in Setup with a unique `DeveloperName`, and fill in `Title__c`, `Description__c`, `FlowApiName__c`, `IconName__c`.
3. Add that `DeveloperName` to the hardcoded key list in the `Next_Steps_AI_Recommendation` template's instructions text, and re-activate.

This works fine for a handful of actions; it doesn't scale past that because every action has to be manually listed in the prompt text and the AI has no actual account-specific reasoning to go on — see the previous section once you outgrow this.
