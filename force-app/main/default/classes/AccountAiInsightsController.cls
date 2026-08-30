/**
 * AccountAiInsightsController
 *
 * Apex controller for the aiKnowledgeInsightsModal LWC.
 * Provides Performance Highlights (Opportunity aggregates) and a generated
 * account insights narrative sourced from the "Account_Insights" prompt template.
 */
public with sharing class AccountAiInsightsController {

    /**
     * Wrapper for the Performance Highlights metric cards
     */
    public class PerformanceHighlights {
        @AuraEnabled public Decimal openOpportunityAmount { get; set; }
        @AuraEnabled public Decimal closedThisYearAmount { get; set; }
        @AuraEnabled public Decimal customerTotalSpend { get; set; }

        public PerformanceHighlights() {
            this.openOpportunityAmount = 0;
            this.closedThisYearAmount = 0;
            this.customerTotalSpend = 0;
        }
    }

    /**
     * Get Performance Highlights (Open Opportunity Amount, Closed This Year, Customer Total Spend)
     * @param accountId The Account record ID
     * @return PerformanceHighlights wrapper
     */
    @AuraEnabled(cacheable=true)
    public static PerformanceHighlights getPerformanceHighlights(Id accountId) {
        PerformanceHighlights result = new PerformanceHighlights();

        if (accountId == null) {
            return result;
        }

        Integer currentYear = Date.today().year();

        try {
            for (AggregateResult ar : [
                SELECT IsWon, IsClosed, CALENDAR_YEAR(CloseDate) yr, SUM(Amount) amt
                FROM Opportunity
                WHERE AccountId = :accountId
                WITH USER_MODE
                GROUP BY IsWon, IsClosed, CALENDAR_YEAR(CloseDate)
            ]) {
                Boolean isWon = (Boolean) ar.get('IsWon');
                Boolean isClosed = (Boolean) ar.get('IsClosed');
                Integer yr = (Integer) ar.get('yr');
                Decimal amt = (Decimal) ar.get('amt');
                if (amt == null) {
                    amt = 0;
                }

                if (!isClosed) {
                    result.openOpportunityAmount += amt;
                }
                if (isWon) {
                    result.customerTotalSpend += amt;
                    if (yr == currentYear) {
                        result.closedThisYearAmount += amt;
                    }
                }
            }
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException('Error retrieving performance highlights: ' + e.getMessage());
            ahe.setMessage('Error retrieving performance highlights: ' + e.getMessage());
            throw ahe;
        }

        return result;
    }

    /**
     * Generate an account insights narrative by invoking the "Account_Insights" prompt template.
     * @param accountId The Account record ID
     * @return Markdown-formatted narrative text from the generation
     */
    @AuraEnabled
    public static String getAccountInsightsNarrative(Id accountId) {
        if (accountId == null) {
            AuraHandledException ahe = new AuraHandledException('Account Id is required.');
            ahe.setMessage('Account Id is required.');
            throw ahe;
        }

        try {
            ConnectApi.EinsteinPromptTemplateGenerationsInput promptGenerationsInput =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            promptGenerationsInput.isPreview = false;

            Map<String, ConnectApi.WrappedValue> valueMap = new Map<String, ConnectApi.WrappedValue>();
            Map<String, String> accountRecordIdMap = new Map<String, String>();
            accountRecordIdMap.put('id', accountId);

            ConnectApi.WrappedValue accountWrappedValue = new ConnectApi.WrappedValue();
            accountWrappedValue.value = accountRecordIdMap;
            valueMap.put('Input:account', accountWrappedValue);
            promptGenerationsInput.inputParams = valueMap;

            promptGenerationsInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            promptGenerationsInput.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generationsOutput =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate('Account_Insights', promptGenerationsInput);

            if (generationsOutput == null
                    || generationsOutput.generations == null
                    || generationsOutput.generations.isEmpty()) {
                AuraHandledException ahe = new AuraHandledException('No insights were generated for this account.');
                ahe.setMessage('No insights were generated for this account.');
                throw ahe;
            }

            return generationsOutput.generations[0].text;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException('Error generating account insights: ' + e.getMessage());
            ahe.setMessage('Error generating account insights: ' + e.getMessage());
            throw ahe;
        }
    }

    /**
     * Wrapper for a single Recommended Actions card, resolved from Recommended_Action__mdt
     */
    public class RecommendedAction {
        @AuraEnabled public String actionKey { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String flowApiName { get; set; }
        @AuraEnabled public String iconName { get; set; }
        @AuraEnabled public String iconVariant { get; set; }
    }

    /**
     * Get up to 3 Recommended Action cards by invoking the "Next_Steps_AI_Recommendation" prompt
     * template and resolving its selected action keys against the Recommended_Action__mdt catalog.
     * @param accountId The Account record ID
     * @return List<RecommendedAction>, empty if nothing in the AI's response matched the catalog
     */
    @AuraEnabled
    public static List<RecommendedAction> getRecommendedActions(Id accountId) {
        if (accountId == null) {
            AuraHandledException ahe = new AuraHandledException('Account Id is required.');
            ahe.setMessage('Account Id is required.');
            throw ahe;
        }

        Map<String, Recommended_Action__mdt> catalogByKey = new Map<String, Recommended_Action__mdt>();
        for (Recommended_Action__mdt action : Recommended_Action__mdt.getAll().values()) {
            catalogByKey.put(action.DeveloperName, action);
        }

        String responseText;
        try {
            ConnectApi.EinsteinPromptTemplateGenerationsInput promptGenerationsInput =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            promptGenerationsInput.isPreview = false;

            Map<String, ConnectApi.WrappedValue> valueMap = new Map<String, ConnectApi.WrappedValue>();
            Map<String, String> accountRecordIdMap = new Map<String, String>();
            accountRecordIdMap.put('id', accountId);

            ConnectApi.WrappedValue accountWrappedValue = new ConnectApi.WrappedValue();
            accountWrappedValue.value = accountRecordIdMap;
            valueMap.put('Input:account', accountWrappedValue);
            promptGenerationsInput.inputParams = valueMap;

            promptGenerationsInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            promptGenerationsInput.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generationsOutput =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate('Next_Steps_AI_Recommendation', promptGenerationsInput);

            if (generationsOutput == null
                    || generationsOutput.generations == null
                    || generationsOutput.generations.isEmpty()) {
                return new List<RecommendedAction>();
            }

            responseText = generationsOutput.generations[0].text;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException('Error generating recommended actions: ' + e.getMessage());
            ahe.setMessage('Error generating recommended actions: ' + e.getMessage());
            throw ahe;
        }

        return resolveRecommendedActions(parseActionKeys(responseText), catalogByKey);
    }

    /**
     * Resolves candidate action keys against the catalog, in order, capped at 3.
     * Unrecognized keys (hallucinated or stale) are silently skipped.
     */
    @TestVisible
    private static List<RecommendedAction> resolveRecommendedActions(List<String> keys, Map<String, Recommended_Action__mdt> catalogByKey) {
        List<RecommendedAction> results = new List<RecommendedAction>();
        for (String key : keys) {
            Recommended_Action__mdt record = catalogByKey.get(key);
            if (record == null) {
                continue;
            }
            RecommendedAction action = new RecommendedAction();
            action.actionKey = record.DeveloperName;
            action.title = record.Title__c;
            action.description = record.Description__c;
            action.flowApiName = record.FlowApiName__c;
            action.iconName = record.IconName__c;
            action.iconVariant = record.IconVariant__c;
            results.add(action);
            if (results.size() == 3) {
                break;
            }
        }
        return results;
    }

    /**
     * Parses the prompt response into a list of candidate action keys. Accepts either
     * {"title": ..., "Actions": [...]}  or a bare JSON array, and tolerates code-fence wrapping.
     * Returns an empty list (never throws) if the response can't be parsed.
     */
    @TestVisible
    private static List<String> parseActionKeys(String responseText) {
        if (String.isBlank(responseText)) {
            return new List<String>();
        }

        String cleaned = responseText.trim();
        if (cleaned.startsWith('```')) {
            Integer firstNewline = cleaned.indexOf('\n');
            cleaned = firstNewline >= 0 ? cleaned.substring(firstNewline + 1) : cleaned;
            if (cleaned.endsWith('```')) {
                cleaned = cleaned.substring(0, cleaned.length() - 3);
            }
            cleaned = cleaned.trim();
        }

        List<Object> rawKeys;
        try {
            Object parsed = JSON.deserializeUntyped(cleaned);
            if (parsed instanceof Map<String, Object>) {
                Object actionsValue = ((Map<String, Object>) parsed).get('Actions');
                if (!(actionsValue instanceof List<Object>)) {
                    return new List<String>();
                }
                rawKeys = (List<Object>) actionsValue;
            } else if (parsed instanceof List<Object>) {
                rawKeys = (List<Object>) parsed;
            } else {
                return new List<String>();
            }
        } catch (Exception e) {
            return new List<String>();
        }

        List<String> keys = new List<String>();
        for (Object rawKey : rawKeys) {
            if (rawKey instanceof String) {
                keys.add((String) rawKey);
            }
        }
        return keys;
    }
}
