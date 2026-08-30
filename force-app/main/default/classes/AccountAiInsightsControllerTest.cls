@isTest
private class AccountAiInsightsControllerTest {

    @TestSetup
    static void makeData() {
        Account acct = new Account(Name = 'Test Insights Account');
        insert acct;

        Integer currentYear = Date.today().year();

        List<Opportunity> opps = new List<Opportunity>{
            new Opportunity(
                Name = 'Open Deal',
                AccountId = acct.Id,
                StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(1),
                Amount = 5000
            ),
            new Opportunity(
                Name = 'Closed Won This Year',
                AccountId = acct.Id,
                StageName = 'Closed Won',
                CloseDate = Date.newInstance(currentYear, 1, 15),
                Amount = 10000
            ),
            new Opportunity(
                Name = 'Closed Won Prior Year',
                AccountId = acct.Id,
                StageName = 'Closed Won',
                CloseDate = Date.newInstance(currentYear - 1, 1, 15),
                Amount = 20000
            ),
            new Opportunity(
                Name = 'Closed Won Null Amount',
                AccountId = acct.Id,
                StageName = 'Closed Won',
                CloseDate = Date.newInstance(currentYear, 3, 1),
                Amount = null
            )
        };
        insert opps;
    }

    @isTest
    static void testGetPerformanceHighlightsAggregatesCorrectly() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Insights Account' LIMIT 1];

        Test.startTest();
        AccountAiInsightsController.PerformanceHighlights highlights =
            AccountAiInsightsController.getPerformanceHighlights(acct.Id);
        Test.stopTest();

        System.assertEquals(5000, highlights.openOpportunityAmount, 'Open opportunity amount should sum only open opps');
        System.assertEquals(10000, highlights.closedThisYearAmount, 'Closed this year should only include current-year closed won');
        System.assertEquals(30000, highlights.customerTotalSpend, 'Total spend should sum all closed won amounts across years, null-safe');
    }

    @isTest
    static void testGetPerformanceHighlightsNullAccountIdReturnsZeros() {
        Test.startTest();
        AccountAiInsightsController.PerformanceHighlights highlights =
            AccountAiInsightsController.getPerformanceHighlights(null);
        Test.stopTest();

        System.assertEquals(0, highlights.openOpportunityAmount);
        System.assertEquals(0, highlights.closedThisYearAmount);
        System.assertEquals(0, highlights.customerTotalSpend);
    }

    @isTest
    static void testGetAccountInsightsNarrativeNullAccountIdThrows() {
        Boolean threw = false;
        try {
            AccountAiInsightsController.getAccountInsightsNarrative(null);
        } catch (AuraHandledException ahe) {
            threw = true;
        }
        System.assert(threw, 'Expected an AuraHandledException for a null account Id');
    }

    @isTest
    static void testGetRecommendedActionsNullAccountIdThrows() {
        Boolean threw = false;
        try {
            AccountAiInsightsController.getRecommendedActions(null);
        } catch (AuraHandledException ahe) {
            threw = true;
        }
        System.assert(threw, 'Expected an AuraHandledException for a null account Id');
    }

    @isTest
    static void testParseActionKeysWrappedObjectAllKnownKeys() {
        String response = '{"title":"Next Best Action","Actions":["Escalate_Account","Create_Close_Plan","Engage_Specialist"]}';

        List<String> keys = AccountAiInsightsController.parseActionKeys(response);

        System.assertEquals(3, keys.size());
        System.assertEquals('Escalate_Account', keys[0]);
        System.assertEquals('Create_Close_Plan', keys[1]);
        System.assertEquals('Engage_Specialist', keys[2]);
    }

    @isTest
    static void testParseActionKeysBareArray() {
        String response = '["Escalate_Account","Engage_Specialist"]';

        List<String> keys = AccountAiInsightsController.parseActionKeys(response);

        System.assertEquals(2, keys.size());
        System.assertEquals('Escalate_Account', keys[0]);
        System.assertEquals('Engage_Specialist', keys[1]);
    }

    @isTest
    static void testParseActionKeysStripsCodeFence() {
        String response = '```json\n{"title":"Next Best Action","Actions":["Escalate_Account"]}\n```';

        List<String> keys = AccountAiInsightsController.parseActionKeys(response);

        System.assertEquals(1, keys.size());
        System.assertEquals('Escalate_Account', keys[0]);
    }

    @isTest
    static void testParseActionKeysUnparseableTextReturnsEmpty() {
        List<String> keys = AccountAiInsightsController.parseActionKeys('not json at all');

        System.assertEquals(0, keys.size());
    }

    @isTest
    static void testParseActionKeysBlankReturnsEmpty() {
        List<String> keys = AccountAiInsightsController.parseActionKeys('');

        System.assertEquals(0, keys.size());
    }

    @isTest
    static void testParseActionKeysMissingActionsKeyReturnsEmpty() {
        List<String> keys = AccountAiInsightsController.parseActionKeys('{"title":"Next Best Action"}');

        System.assertEquals(0, keys.size());
    }

    @isTest
    static void testResolveRecommendedActionsFiltersUnknownKeys() {
        Map<String, Recommended_Action__mdt> catalogByKey = new Map<String, Recommended_Action__mdt>();
        for (Recommended_Action__mdt action : Recommended_Action__mdt.getAll().values()) {
            catalogByKey.put(action.DeveloperName, action);
        }

        List<String> keys = new List<String>{ 'Escalate_Account', 'Totally_Made_Up_Key', 'Engage_Specialist' };

        List<AccountAiInsightsController.RecommendedAction> resolved =
            AccountAiInsightsController.resolveRecommendedActions(keys, catalogByKey);

        System.assertEquals(2, resolved.size(), 'Unknown key should be silently skipped, not error');
        System.assertEquals('Escalate_Account', resolved[0].actionKey);
        System.assertEquals('Engage_Specialist', resolved[1].actionKey);
    }

    @isTest
    static void testResolveRecommendedActionsCapsAtThree() {
        Map<String, Recommended_Action__mdt> catalogByKey = new Map<String, Recommended_Action__mdt>();
        for (Recommended_Action__mdt action : Recommended_Action__mdt.getAll().values()) {
            catalogByKey.put(action.DeveloperName, action);
        }

        List<String> keys = new List<String>{
            'Escalate_Account', 'Create_Close_Plan', 'Engage_Specialist', 'Escalate_Account'
        };

        List<AccountAiInsightsController.RecommendedAction> resolved =
            AccountAiInsightsController.resolveRecommendedActions(keys, catalogByKey);

        System.assertEquals(3, resolved.size(), 'Should cap resolved actions at 3');
    }

    @isTest
    static void testResolveRecommendedActionsAllUnknownReturnsEmpty() {
        Map<String, Recommended_Action__mdt> catalogByKey = new Map<String, Recommended_Action__mdt>();
        for (Recommended_Action__mdt action : Recommended_Action__mdt.getAll().values()) {
            catalogByKey.put(action.DeveloperName, action);
        }

        List<String> keys = new List<String>{ 'Nope', 'Also_Not_Real' };

        List<AccountAiInsightsController.RecommendedAction> resolved =
            AccountAiInsightsController.resolveRecommendedActions(keys, catalogByKey);

        System.assertEquals(0, resolved.size());
    }
}
