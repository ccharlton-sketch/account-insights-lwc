# Install Guide

## 0. Prerequisites

- Salesforce CLI (`sf`) installed, authenticated to your target org.
- Einstein Generative AI / Prompt Builder enabled in your org, with access to a supported model.
- At least one Screen Flow you want surfaced as a "Recommended Action" (you can start with just one — the catalog is empty-safe).

## 1. Deploy the metadata

From the repo root:

```bash
sf project deploy start -d force-app --target-org <your-target-org>
```

This deploys, in one shot:

- `AccountAiInsightsController` + its test class (Apex)
- The `Recommended_Action__mdt` Custom Metadata Type (empty — no seed records ship in this repo, see step 3)
- The `Next_Steps_AI_Recommendation` Prompt Template
- Three LWCs: `aiKnowledgeInsightsButton`, `aiKnowledgeInsightsModal`, `markdownUtils`

If your org enforces the standard 75% Apex code-coverage gate on deploy, run with `--test-level RunSpecifiedTests --tests AccountAiInsightsControllerTest` instead so only the new class needs coverage (it's written to hit ~85%+ on its own; the uncovered lines are the live AI callout body, which can't be exercised without a real callout — this is expected and fine).

## 2. Configure the "Needs Attention" prompt template

`AccountAiInsightsController.getAccountInsightsNarrative()` calls a prompt template by developer name **`Account_Insights`**. This template is **not part of this repo** — it's expected to already exist in your org, or you build your own equivalent (one input, `Input:account`, an Account SObject reference, instructed to produce a markdown account summary).

If you name your template anything other than `Account_Insights`, update the string literal in `AccountAiInsightsController.cls`:

```apex
// force-app/main/default/classes/AccountAiInsightsController.cls
ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate('Account_Insights', promptGenerationsInput);
```

## 3. Configure the model used by "Next Best Action" selection

The shipped `Next_Steps_AI_Recommendation` template is set to `sfdc_ai__DefaultGPT5Mini`. If that model isn't enabled in your org, open the template in Prompt Builder after deploying and change the model, then re-save/re-activate that version.

**Important:** Prompt Builder's own "Generated Response" preview panel is more forgiving of vague instructions than the actual runtime API path this Apex code calls. If you edit the instructions, keep them literal and directive (return exactly this JSON shape, no hedging language like "probably") — we hit this exact issue during development: the preview returned correct JSON while the live API call returned an empty `{}` until the instructions were made unambiguous. Always re-test with a live Apex call (see step 6) after editing the template, not just the Prompt Builder preview.

## 4. Populate the Recommended Action catalog

No seed records ship in this repo (your Screen Flow API names won't match ours). In Setup → Custom Metadata Types → Recommended Action → Manage Records, create one record per action you want available. Each record needs:

| Field | Purpose |
|---|---|
| `Title__c` | Card title shown to the rep |
| `Description__c` | Card description text |
| `FlowApiName__c` | API name of the Screen Flow to launch — **must accept an input variable named `account`, type Record (Account)** |
| `IconName__c` | SLDS icon, e.g. `utility:warning` |
| `IconVariant__c` | Icon color variant, e.g. `warning`, `success`, `brand` (optional) |
| `SelectionCriteria__c` | Plain-English guidance for *when* the AI should pick this action — this isn't fed to the AI automatically today (see [ARCHITECTURE.md](ARCHITECTURE.md#growing-the-catalog-past-a-few-actions) for what's needed to wire that up as the catalog grows past a handful of actions) |

The **DeveloperName** you give each record (e.g. `Escalate_Account`) is the exact key the AI must return to select that card — see ARCHITECTURE.md for how selection works.

## 5. Add the button to the Account page

The button component (`aiKnowledgeInsightsButton`) is exposed for `lightning__RecordPage` on `Account`. Add it via Lightning App Builder (Setup → Object Manager → Account → Lightning Record Pages → your Account page → Edit):

1. Drag the **AI Knowledge & Insights** component onto the page (sidebar or wherever fits your layout).
2. Save and Activate.

A working example placement is in `reference/example-flexipage-sidebar-snippet.xml` — this is the actual FlexiPage XML from the org this was built in, included **for reference only**. Don't deploy it directly; it's tied to that org's specific FlexiPage name and would overwrite whatever Account page exists at that name in your org.

## 6. Verify

Run a quick Apex sanity check against a real Account before opening the UI:

```bash
sf apex run --target-org <your-target-org>
```
```apex
System.debug(AccountAiInsightsController.getPerformanceHighlights('<some Account Id>'));
System.debug(AccountAiInsightsController.getRecommendedActions('<some Account Id>'));
```

- `getPerformanceHighlights` should return non-zero amounts for an account with Opportunities.
- `getRecommendedActions` should return a list (up to 3) of action wrappers with real `title`/`flowApiName` values pulled from your catalog — not an empty list. If it's empty, check (in order): the Prompt Template is Active/Published with the version you expect, the model configured is enabled for your org, and your catalog has at least one record whose `DeveloperName` matches something the AI could plausibly return.

Then open an Account record in the browser, click **AI Knowledge & Insights**, and confirm all three sections load, a Recommended Action card launches its Flow in place, and the back button returns to the card list.
