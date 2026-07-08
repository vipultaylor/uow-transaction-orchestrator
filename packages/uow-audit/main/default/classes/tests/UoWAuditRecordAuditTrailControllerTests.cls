//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Test class for UoWAuditRecordAuditTrailController.
 * Uses real DML for package-owned audit objects (per the audit testing strategy) and a mock
 * selector for the error path.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Audit Test Utilities
 */
@isTest
@SuppressWarnings('PMD.MethodNamingConventions')
private class UoWAuditRecordAuditTrailControllerTests {

    private static final String RECORD_ID = '001000000000ABCAAA';

    @isTest
    static void test_getAuditActivityForRecord_groupsByTransactionMostRecentFirst() {
        User testUser = UoWAuditTestDataFactory.createAuditAdminUser();

        System.runAs(testUser) {
            // Older transaction: two work items touched the record
            UoWAuditTransaction__c older = insertTransaction('TXN-CTRL-OLD', DateTime.now().addMinutes(-30));
            UoWAuditWorkItem__c olderWi1 = insertWorkItem(older.Id, 'WI-OLD-1', 'INSERT_OP');
            UoWAuditWorkItem__c olderWi2 = insertWorkItem(older.Id, 'WI-OLD-2', 'UPDATE_OP');
            insertIndex(olderWi1.Id, RECORD_ID, 'INSERT', DateTime.now().addMinutes(-30));
            insertIndex(olderWi2.Id, RECORD_ID, 'UPDATE', DateTime.now().addMinutes(-29));

            // Newer transaction: one work item touched the record
            UoWAuditTransaction__c newer = insertTransaction('TXN-CTRL-NEW', DateTime.now());
            UoWAuditWorkItem__c newerWi = insertWorkItem(newer.Id, 'WI-NEW-1', 'DELETE_OP');
            insertIndex(newerWi.Id, RECORD_ID, 'DELETE', DateTime.now());

            Test.startTest();
            List<UoWAuditRecordAuditTrailController.TransactionActivity> result =
                UoWAuditRecordAuditTrailController.getAuditActivityForRecord(RECORD_ID);
            Test.stopTest();

            // Name is an autonumber on UoWAuditTransaction__c, so assert ordering via the
            // work-item operations we control instead. Rows order most-recent-first:
            // DELETE (now) -> UPDATE (-29m) -> INSERT (-30m); grouping keeps first-seen order.
            Assert.areEqual(2, result.size(), 'Should group into two transactions');
            Assert.areEqual(1, result[0].workItems.size(), 'Newer transaction has one work item');
            Assert.areEqual('DELETE', result[0].workItems[0].operation, 'Newer transaction should be first');
            Assert.areEqual(2, result[1].workItems.size(), 'Older transaction has two work items');
            Assert.areEqual('UPDATE', result[1].workItems[0].operation, 'Older transaction most-recent work item first');
            Assert.areEqual('INSERT', result[1].workItems[1].operation, 'Older transaction older work item second');
        }
    }

    @isTest
    static void test_getAuditActivityForRecord_noActivity_returnsEmpty() {
        User testUser = UoWAuditTestDataFactory.createAuditAdminUser();
        System.runAs(testUser) {
            Test.startTest();
            List<UoWAuditRecordAuditTrailController.TransactionActivity> result =
                UoWAuditRecordAuditTrailController.getAuditActivityForRecord('001000000000ZZZAAA');
            Test.stopTest();
            Assert.areEqual(0, result.size(), 'No indexed activity should return an empty list');
        }
    }

    @isTest
    static void test_getAuditActivityForRecord_wrapsErrorsAsAuraException() {
        UoWAuditDataSelector.setInstance(new ThrowingSelector());

        Boolean threw = false;
        Test.startTest();
        try {
            UoWAuditRecordAuditTrailController.getAuditActivityForRecord(RECORD_ID);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Selector failures should surface as an AuraHandledException');
    }

    // ============================================================================
    // FIXTURE HELPERS
    // ============================================================================

    private static UoWAuditTransaction__c insertTransaction(String txnId, DateTime startTime) {
        UoWAuditTransaction__c txn = new UoWAuditTransaction__c(
            TransactionId__c = txnId,
            CorrelationId__c = 'CORR-' + txnId,
            TransactionStatus__c = 'SUCCESS',
            CommitMode__c = 'SYNC',
            StartTime__c = startTime,
            EndTime__c = startTime.addSeconds(1),
            ExecutionTimeMs__c = 120
        );
        insert txn;
        return txn;
    }

    private static UoWAuditWorkItem__c insertWorkItem(Id txnId, String name, String operation) {
        UoWAuditWorkItem__c wi = new UoWAuditWorkItem__c(
            AuditTransaction__c = txnId,
            Name = name,
            WorkType__c = 'DML',
            WorkItemStatus__c = 'SUCCESS',
            SObjectType__c = 'Account',
            DmlOperation__c = operation,
            ProcessedCount__c = 1
        );
        insert wi;
        return wi;
    }

    private static void insertIndex(Id workItemId, String recordId, String operation, DateTime ts) {
        insert new UoWAuditRecordIndex__c(
            AuditWorkItem__c = workItemId,
            RecordId__c = recordId,
            SObjectType__c = 'Account',
            Operation__c = operation,
            Timestamp__c = ts
        );
    }

    /**
     * Selector stub that throws, to exercise the controller's error handling.
     */
    private class ThrowingSelector extends UoWAuditDataSelector {
        public override List<UoWAuditRecordIndex__c> getAuditActivityByRecordId(Id recordId, Integer queryLimit) {
            throw new QueryException('Simulated selector failure');
        }
    }
}
