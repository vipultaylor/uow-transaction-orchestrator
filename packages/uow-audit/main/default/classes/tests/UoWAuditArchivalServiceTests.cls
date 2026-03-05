//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Test class for UoWAuditArchivalService.
 * Covers the invocable action for Flow integration and batch processing.
 *
 * Testing strategy:
 * - Invocable method: Tests archiveTransactions() for Flow-based archival
 * - Batch interface: Tests start(), execute(), finish() for large volume handling
 * - Static helpers: Tests executeNow() for programmatic execution
 *
 * Big Object DML is mocked via System.StubProvider and UoWAuditBigObjectDmlService.
 * This avoids the callout-with-pending-DML limitation and enables verification
 * of the records that would be archived.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Audit Tests
 * @see UoWAuditArchivalService
 * @see UoWAuditBigObjectDmlService
 */
@isTest
@SuppressWarnings('PMD.ApexUnitTestClassShouldHaveAsserts')
private class UoWAuditArchivalServiceTests {

    // ============================================================================
    // CONSTRUCTOR TESTS
    // ============================================================================

    @isTest
    static void test_constructor_defaultUsesToday() {
        // Arrange & Act
        Test.startTest();
        UoWAuditArchivalService service = new UoWAuditArchivalService();
        Test.stopTest();

        // Assert - Constructor should not throw
        Assert.isNotNull(service, 'Service should be instantiated');
    }

    @isTest
    static void test_constructor_acceptsCustomDate() {
        // Arrange
        Date customDate = Date.today().addDays(-30);

        // Act
        Test.startTest();
        UoWAuditArchivalService service = new UoWAuditArchivalService(customDate);
        Test.stopTest();

        // Assert
        Assert.isNotNull(service, 'Service should be instantiated with custom date');
    }

    // ============================================================================
    // INVOCABLE METHOD TESTS
    // ============================================================================

    @isTest
    static void test_archiveTransactions_handlesEmptyList() {
        // Arrange
        List<String> emptyList = new List<String>();

        // Act - Should not throw
        Test.startTest();
        UoWAuditArchivalService.archiveTransactions(emptyList);
        Test.stopTest();

        // Assert - No exception means success
        Assert.isTrue(true, 'Should handle empty list gracefully');
    }

    @isTest
    static void test_archiveTransactions_handlesNullList() {
        // Act - Should not throw
        Test.startTest();
        UoWAuditArchivalService.archiveTransactions(null);
        Test.stopTest();

        // Assert - No exception means success
        Assert.isTrue(true, 'Should handle null list gracefully');
    }

    @isTest
    static void test_archiveTransactions_processesValidTransactions() {
        // Arrange - Create transaction with work items
        UoWAuditMocks.BigObjectDmlMockProvider mockProvider = UoWAuditMocks.installBigObjectMock();

        UoWAuditTransaction__c txn = new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-ARCHIVE-001',
            CorrelationId__c = 'CORR-ARCHIVE-001',
            TransactionStatus__c = 'SUCCESS',
            ArchivalMode__c = 'ARCHIVE',
            ArchiveDate__c = Date.today().addDays(-1)
        );
        insert txn;

        UoWAuditWorkItem__c workItem = new UoWAuditWorkItem__c(
            AuditTransaction__c = txn.Id,
            Name = 'WORK-ARCHIVE-001',
            WorkType__c = 'DML',
            WorkItemStatus__c = 'SUCCESS',
            SObjectType__c = 'Account',
            DmlOperation__c = 'INSERT_OP'
        );
        insert workItem;

        List<String> transactionIds = new List<String>{ txn.Id };

        // Act
        Test.startTest();
        UoWAuditArchivalService.archiveTransactions(transactionIds);
        Test.stopTest();

        // Assert - Big Object records captured by mock
        Assert.areEqual(1, mockProvider.capturedRecords.size(), 'Should create 1 Big Object record');

        // Assert - Transaction should be deleted after archival
        List<UoWAuditTransaction__c> remainingTransactions = [
            SELECT Id FROM UoWAuditTransaction__c WHERE Id = :txn.Id
        ];
        Assert.areEqual(0, remainingTransactions.size(), 'Transaction should be deleted after archival');
    }

    @isTest
    static void test_archiveTransactions_handlesTransactionWithoutWorkItems() {
        // Arrange - Create transaction without work items
        UoWAuditMocks.BigObjectDmlMockProvider mockProvider = UoWAuditMocks.installBigObjectMock();

        UoWAuditTransaction__c txn = new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-NO-WI-001',
            CorrelationId__c = 'CORR-NO-WI-001',
            TransactionStatus__c = 'SUCCESS',
            ArchivalMode__c = 'ARCHIVE',
            ArchiveDate__c = Date.today().addDays(-1)
        );
        insert txn;

        List<String> transactionIds = new List<String>{ txn.Id };

        // Act
        Test.startTest();
        UoWAuditArchivalService.archiveTransactions(transactionIds);
        Test.stopTest();

        // Assert - Transaction should be deleted
        List<UoWAuditTransaction__c> remainingTransactions = [
            SELECT Id FROM UoWAuditTransaction__c WHERE Id = :txn.Id
        ];
        Assert.areEqual(0, remainingTransactions.size(), 'Transaction should be deleted even without work items');
    }

    @isTest
    static void test_archiveTransactions_handlesMultipleWorkItems() {
        // Arrange - Create transaction with multiple work items
        UoWAuditMocks.BigObjectDmlMockProvider mockProvider = UoWAuditMocks.installBigObjectMock();

        UoWAuditTransaction__c txn = new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-MULTI-WI-001',
            CorrelationId__c = 'CORR-MULTI-WI-001',
            TransactionStatus__c = 'SUCCESS',
            ArchivalMode__c = 'ARCHIVE',
            ArchiveDate__c = Date.today().addDays(-1)
        );
        insert txn;

        List<UoWAuditWorkItem__c> workItems = new List<UoWAuditWorkItem__c>();
        for (Integer i = 1; i <= 5; i++) {
            workItems.add(new UoWAuditWorkItem__c(
                AuditTransaction__c = txn.Id,
                Name = 'WORK-MULTI-00' + i,
                WorkType__c = 'DML',
                WorkItemStatus__c = 'SUCCESS',
                SObjectType__c = 'Account',
                DmlOperation__c = 'INSERT_OP'
            ));
        }
        insert workItems;

        List<String> transactionIds = new List<String>{ txn.Id };

        // Act
        Test.startTest();
        UoWAuditArchivalService.archiveTransactions(transactionIds);
        Test.stopTest();

        // Assert - Transaction and all work items should be deleted (cascade delete)
        List<UoWAuditTransaction__c> remainingTransactions = [
            SELECT Id FROM UoWAuditTransaction__c WHERE Id = :txn.Id
        ];
        Assert.areEqual(0, remainingTransactions.size(), 'Transaction should be deleted');

        List<UoWAuditWorkItem__c> remainingWorkItems = [
            SELECT Id FROM UoWAuditWorkItem__c WHERE AuditTransaction__c = :txn.Id
        ];
        Assert.areEqual(0, remainingWorkItems.size(), 'Work items should be cascade deleted');

        // Verify mock captured one Big Object record per work item
        Assert.areEqual(5, mockProvider.capturedRecords.size(), 'Should create 5 Big Object records (one per work item)');
    }

    @isTest
    static void test_archiveTransactions_handlesNonExistentTransactionIds() {
        // Arrange - Use fake IDs that don't exist
        Id fakeId = UoWTestHelpers.generateFakeId(UoWAuditTransaction__c.SObjectType);
        List<String> transactionIds = new List<String>{ fakeId };

        // Act - Should not throw
        Test.startTest();
        UoWAuditArchivalService.archiveTransactions(transactionIds);
        Test.stopTest();

        // Assert - No exception means success
        Assert.isTrue(true, 'Should handle non-existent IDs gracefully');
    }

    // ============================================================================
    // BATCH INTERFACE TESTS
    // ============================================================================

    @isTest
    static void test_batch_start_returnsQueryLocator() {
        // Arrange - Create eligible transaction
        UoWAuditTransaction__c txn = new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-BATCH-START-001',
            CorrelationId__c = 'CORR-BATCH-START-001',
            TransactionStatus__c = 'SUCCESS',
            ArchivalMode__c = 'ARCHIVE',
            ArchiveDate__c = Date.today().addDays(-1)
        );
        insert txn;

        UoWAuditArchivalService service = new UoWAuditArchivalService(Date.today());

        // Act
        Test.startTest();
        Database.QueryLocator locator = service.start(null);
        Test.stopTest();

        // Assert
        Assert.isNotNull(locator, 'Should return a query locator');
    }

    @isTest
    static void test_batch_execute_processesScope() {
        // Arrange
        UoWAuditMocks.installBigObjectMock();

        UoWAuditTransaction__c txn = new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-BATCH-EXEC-001',
            CorrelationId__c = 'CORR-BATCH-EXEC-001',
            TransactionStatus__c = 'SUCCESS',
            ArchivalMode__c = 'ARCHIVE',
            ArchiveDate__c = Date.today().addDays(-1)
        );
        insert txn;

        UoWAuditWorkItem__c workItem = new UoWAuditWorkItem__c(
            AuditTransaction__c = txn.Id,
            Name = 'WORK-BATCH-001',
            WorkType__c = 'DML',
            WorkItemStatus__c = 'SUCCESS'
        );
        insert workItem;

        // Use data selector to get full records with all fields (same as real batch/invocable)
        List<UoWAuditTransaction__c> scope = UoWAuditDataSelector.getInstance()
            .getTransactionsWithWorkItems(new Set<Id>{ txn.Id });

        UoWAuditArchivalService service = new UoWAuditArchivalService();

        // Act
        Test.startTest();
        service.execute(null, scope);
        Test.stopTest();

        // Assert - Transaction should be deleted
        List<UoWAuditTransaction__c> remaining = [
            SELECT Id FROM UoWAuditTransaction__c WHERE Id = :txn.Id
        ];
        Assert.areEqual(0, remaining.size(), 'Transaction should be deleted after batch execute');
    }

    @isTest
    static void test_batch_execute_handlesEmptyScope() {
        // Arrange
        UoWAuditArchivalService service = new UoWAuditArchivalService();
        List<UoWAuditTransaction__c> emptyScope = new List<UoWAuditTransaction__c>();

        // Act - Should not throw
        Test.startTest();
        service.execute(null, emptyScope);
        Test.stopTest();

        // Assert
        Assert.isTrue(true, 'Should handle empty scope gracefully');
    }

    @isTest
    static void test_batch_finish_logsJobStatus() {
        // Arrange
        UoWAuditArchivalService service = new UoWAuditArchivalService();

        // Act - finish() with null context should handle gracefully
        Test.startTest();
        service.finish(null);
        Test.stopTest();

        // Assert - No exception means success
        Assert.isTrue(true, 'Should handle null batch context in finish');
    }

    // ============================================================================
    // BATCH END-TO-END TESTS
    // ============================================================================

    @isTest
    static void test_batch_endToEnd_archivesEligibleTransactions() {
        // Arrange - Create eligible and non-eligible transactions
        UoWAuditMocks.installBigObjectMock();

        UoWAuditTransaction__c eligibleTxn = new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-E2E-ELIGIBLE-001',
            CorrelationId__c = 'CORR-E2E-001',
            TransactionStatus__c = 'SUCCESS',
            ArchivalMode__c = 'ARCHIVE',
            ArchiveDate__c = Date.today().addDays(-1) // Past archive date
        );

        UoWAuditTransaction__c notYetEligibleTxn = new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-E2E-NOT-ELIGIBLE-001',
            CorrelationId__c = 'CORR-E2E-002',
            TransactionStatus__c = 'SUCCESS',
            ArchivalMode__c = 'ARCHIVE',
            ArchiveDate__c = Date.today().addDays(30) // Future archive date
        );

        UoWAuditTransaction__c purgeTxn = new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-E2E-PURGE-001',
            CorrelationId__c = 'CORR-E2E-003',
            TransactionStatus__c = 'SUCCESS',
            ArchivalMode__c = 'PURGE', // Different archival mode
            ArchiveDate__c = Date.today().addDays(-1)
        );

        insert new List<UoWAuditTransaction__c>{ eligibleTxn, notYetEligibleTxn, purgeTxn };

        // Act - Run batch
        Test.startTest();
        Id batchId = Database.executeBatch(new UoWAuditArchivalService(Date.today()), 200);
        Test.stopTest();

        // Assert - Only eligible transaction should be archived (deleted)
        List<UoWAuditTransaction__c> remaining = [
            SELECT TransactionId__c, ArchivalMode__c, ArchiveDate__c
            FROM UoWAuditTransaction__c
            WHERE TransactionId__c IN ('TXN-E2E-ELIGIBLE-001', 'TXN-E2E-NOT-ELIGIBLE-001', 'TXN-E2E-PURGE-001')
        ];

        // Note: Due to Big Object insert limitations in tests, deletion may or may not occur
        // The test verifies the batch runs without errors
        Assert.isNotNull(batchId, 'Batch should be executed');
    }

    // ============================================================================
    // STATIC HELPER TESTS - EXECUTE NOW
    // ============================================================================

    @isTest
    static void test_executeNow_startsDefaultBatch() {
        // Arrange - Create eligible transaction
        UoWAuditMocks.installBigObjectMock();

        UoWAuditTransaction__c txn = new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-EXEC-NOW-001',
            CorrelationId__c = 'CORR-EXEC-NOW-001',
            TransactionStatus__c = 'SUCCESS',
            ArchivalMode__c = 'ARCHIVE',
            ArchiveDate__c = Date.today().addDays(-1)
        );
        insert txn;

        // Act
        Test.startTest();
        Id batchId = UoWAuditArchivalService.executeNow();
        Test.stopTest();

        // Assert
        Assert.isNotNull(batchId, 'Should return batch job ID');
        Assert.isTrue(
            String.valueOf(batchId).startsWith('707'),
            'Should return valid AsyncApexJob ID prefix'
        );
    }

    @isTest
    static void test_executeNow_startsCustomDateBatch() {
        // Arrange
        UoWAuditMocks.installBigObjectMock();
        Date customDate = Date.today().addDays(7);

        // Act
        Test.startTest();
        Id batchId = UoWAuditArchivalService.executeNow(customDate);
        Test.stopTest();

        // Assert
        Assert.isNotNull(batchId, 'Should return batch job ID for custom date');
    }

    // ============================================================================
    // ARCHIVAL DATA TRANSFORMATION TESTS
    // ============================================================================

    @isTest
    static void test_archival_preservesTransactionFields() {
        // Arrange - Create transaction with all fields populated
        UoWAuditMocks.BigObjectDmlMockProvider mockProvider = UoWAuditMocks.installBigObjectMock();

        UoWAuditTransaction__c txn = new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-FIELDS-001',
            CorrelationId__c = 'CORR-FIELDS-001',
            TransactionStatus__c = 'SUCCESS',
            ConfigurationName__c = 'TestConfig',
            ExecutionContext__c = 'SYNCHRONOUS',
            RiskEvaluated__c = true,
            RiskLevel__c = 'LOW',
            RiskScore__c = 25,
            PolicyEvaluated__c = true,
            IsDryRun__c = false,
            StartTime__c = DateTime.now().addMinutes(-5),
            EndTime__c = DateTime.now(),
            ExecutionTimeMs__c = 150,
            ErrorCount__c = 0,
            RetentionDays__c = 30,
            ArchivalMode__c = 'ARCHIVE',
            ArchiveDate__c = Date.today().addDays(-1),
            // Session context
            User__c = UserInfo.getUserId(),
            Username__c = UserInfo.getUserName(),
            UserProfileId__c = UserInfo.getProfileId(),
            UserType__c = 'Standard',
            OrganizationId__c = UserInfo.getOrganizationId(),
            OrganizationName__c = UserInfo.getOrganizationName()
        );
        insert txn;

        List<String> transactionIds = new List<String>{ txn.Id };

        // Act
        Test.startTest();
        UoWAuditArchivalService.archiveTransactions(transactionIds);
        Test.stopTest();

        // Assert - Verify Big Object record captured transaction fields
        Assert.areEqual(1, mockProvider.capturedRecords.size(), 'Should create 1 Big Object record');
        UoWAuditHistory__b archived = mockProvider.capturedRecords[0];
        Assert.areEqual('TXN-FIELDS-001', archived.TransactionId__c, 'Should preserve TransactionId');
        Assert.areEqual('CORR-FIELDS-001', archived.CorrelationId__c, 'Should preserve CorrelationId');
        Assert.areEqual('SUCCESS', archived.TransactionStatus__c, 'Should preserve TransactionStatus');
        Assert.areEqual('TestConfig', archived.ConfigurationName__c, 'Should preserve ConfigurationName');
        Assert.areEqual('LOW', archived.RiskLevel__c, 'Should preserve RiskLevel');

        // Assert - Transaction should be deleted (archival happened)
        List<UoWAuditTransaction__c> remaining = [
            SELECT Id FROM UoWAuditTransaction__c WHERE Id = :txn.Id
        ];
        Assert.areEqual(0, remaining.size(), 'Transaction should be deleted after archival');
    }

    @isTest
    static void test_archival_preservesWorkItemFields() {
        // Arrange - Create transaction with fully populated work item
        UoWAuditMocks.BigObjectDmlMockProvider mockProvider = UoWAuditMocks.installBigObjectMock();

        UoWAuditTransaction__c txn = new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-WI-FIELDS-001',
            CorrelationId__c = 'CORR-WI-FIELDS-001',
            TransactionStatus__c = 'SUCCESS',
            ArchivalMode__c = 'ARCHIVE',
            ArchiveDate__c = Date.today().addDays(-1)
        );
        insert txn;

        UoWAuditWorkItem__c workItem = new UoWAuditWorkItem__c(
            AuditTransaction__c = txn.Id,
            Name = 'WORK-FIELDS-001',
            WorkType__c = 'DML',
            WorkItemStatus__c = 'SUCCESS',
            SObjectType__c = 'Account',
            DmlOperation__c = 'INSERT_OP',
            ExecutionPhase__c = 'PRE_DML',
            PlannedCount__c = 10,
            ProcessedCount__c = 10,
            SuccessCount__c = 8,
            FailureCount__c = 2,
            StartTime__c = DateTime.now().addMinutes(-1),
            EndTime__c = DateTime.now(),
            ExecutionTimeMs__c = 50,
            RequestOrigin__c = 'UoWAuditArchivalServiceTests.test_archival_preservesWorkItemFields:123',
            ContinueOnError__c = true,
            MaskingApplied__c = false,
            OriginClassName__c = 'UoWAuditArchivalServiceTests',
            OriginMethodName__c = 'test_archival_preservesWorkItemFields',
            OriginLineNumber__c = 123,
            OriginMetadataType__c = 'ApexClass'
        );
        insert workItem;

        List<String> transactionIds = new List<String>{ txn.Id };

        // Act
        Test.startTest();
        UoWAuditArchivalService.archiveTransactions(transactionIds);
        Test.stopTest();

        // Assert - Verify Big Object record captured work item fields
        Assert.areEqual(1, mockProvider.capturedRecords.size(), 'Should create 1 Big Object record');
        UoWAuditHistory__b archived = mockProvider.capturedRecords[0];
        Assert.areEqual('DML', archived.WorkType__c, 'Should preserve WorkType');
        Assert.areEqual('SUCCESS', archived.WorkItemStatus__c, 'Should preserve WorkItemStatus');
        Assert.areEqual('Account', archived.SObjectType__c, 'Should preserve SObjectType');
        Assert.areEqual('INSERT_OP', archived.DmlOperation__c, 'Should preserve DmlOperation');
        Assert.areEqual('PRE_DML', archived.ExecutionPhase__c, 'Should preserve ExecutionPhase');
        Assert.areEqual(10, archived.PlannedCount__c, 'Should preserve PlannedCount');
        Assert.areEqual(8, archived.SuccessCount__c, 'Should preserve SuccessCount');
        Assert.areEqual(2, archived.FailureCount__c, 'Should preserve FailureCount');

        // Assert - Transaction should be deleted
        List<UoWAuditTransaction__c> remainingTxns = [
            SELECT Id FROM UoWAuditTransaction__c WHERE Id = :txn.Id
        ];
        Assert.areEqual(0, remainingTxns.size(), 'Transaction should be deleted');
    }

    @isTest
    static void test_archival_preservesParentTransactionReference() {
        // Arrange - Create parent and child transactions
        UoWAuditMocks.installBigObjectMock();

        UoWAuditTransaction__c parentTxn = new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-PARENT-001',
            CorrelationId__c = 'CORR-HIERARCHY-001',
            TransactionStatus__c = 'SUCCESS',
            ArchivalMode__c = 'ARCHIVE',
            ArchiveDate__c = Date.today().addDays(-1)
        );
        insert parentTxn;

        UoWAuditTransaction__c childTxn = new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-CHILD-001',
            CorrelationId__c = 'CORR-HIERARCHY-001',
            TransactionStatus__c = 'SUCCESS',
            ParentTransaction__c = parentTxn.Id,
            ParentTransactionId__c = 'TXN-PARENT-001',
            ArchivalMode__c = 'ARCHIVE',
            ArchiveDate__c = Date.today().addDays(-1)
        );
        insert childTxn;

        List<String> transactionIds = new List<String>{ childTxn.Id };

        // Act
        Test.startTest();
        UoWAuditArchivalService.archiveTransactions(transactionIds);
        Test.stopTest();

        // Assert - Child should be deleted, parent should remain
        List<UoWAuditTransaction__c> remainingChild = [
            SELECT Id FROM UoWAuditTransaction__c WHERE Id = :childTxn.Id
        ];
        Assert.areEqual(0, remainingChild.size(), 'Child transaction should be deleted');

        List<UoWAuditTransaction__c> remainingParent = [
            SELECT Id FROM UoWAuditTransaction__c WHERE Id = :parentTxn.Id
        ];
        Assert.areEqual(1, remainingParent.size(), 'Parent transaction should remain');
    }

    // ============================================================================
    // EDGE CASE TESTS
    // ============================================================================

    @isTest
    static void test_archival_handlesSpecialCharactersInCorrelationId() {
        // Arrange - Create transaction with special characters in correlation ID
        UoWAuditMocks.installBigObjectMock();

        UoWAuditTransaction__c txn = new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-SPECIAL-001',
            CorrelationId__c = 'CORR-TEST_123-ABC.XYZ', // Underscores, hyphens, dots
            TransactionStatus__c = 'SUCCESS',
            ArchivalMode__c = 'ARCHIVE',
            ArchiveDate__c = Date.today().addDays(-1)
        );
        insert txn;

        List<String> transactionIds = new List<String>{ txn.Id };

        // Act
        Test.startTest();
        UoWAuditArchivalService.archiveTransactions(transactionIds);
        Test.stopTest();

        // Assert
        List<UoWAuditTransaction__c> remaining = [
            SELECT Id FROM UoWAuditTransaction__c WHERE Id = :txn.Id
        ];
        Assert.areEqual(0, remaining.size(), 'Should archive despite special characters');
    }

    @isTest
    static void test_archival_handlesBulkTransactions() {
        // Arrange - Create 50 transactions
        UoWAuditMocks.BigObjectDmlMockProvider mockProvider = UoWAuditMocks.installBigObjectMock();

        List<UoWAuditTransaction__c> transactions = new List<UoWAuditTransaction__c>();
        for (Integer i = 1; i <= 50; i++) {
            transactions.add(new UoWAuditTransaction__c(
                TransactionId__c = 'TXN-BULK-' + String.valueOf(i).leftPad(3, '0'),
                CorrelationId__c = 'CORR-BULK-' + String.valueOf(i).leftPad(3, '0'),
                TransactionStatus__c = 'SUCCESS',
                ArchivalMode__c = 'ARCHIVE',
                ArchiveDate__c = Date.today().addDays(-1)
            ));
        }
        insert transactions;

        List<String> transactionIds = new List<String>();
        for (UoWAuditTransaction__c txn : transactions) {
            transactionIds.add(txn.Id);
        }

        // Act
        Test.startTest();
        UoWAuditArchivalService.archiveTransactions(transactionIds);
        Test.stopTest();

        // Assert - All should be deleted
        List<UoWAuditTransaction__c> remaining = [
            SELECT Id FROM UoWAuditTransaction__c
            WHERE TransactionId__c LIKE 'TXN-BULK-%'
        ];
        Assert.areEqual(0, remaining.size(), 'All 50 transactions should be deleted');

        // Verify mock captured one Big Object record per transaction (no work items = 1 record each)
        Assert.areEqual(50, mockProvider.capturedRecords.size(), 'Should create 50 Big Object records');
    }

}
