//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Test class for UoW Audit storage writer classes.
 * Covers: UoWAuditCustomObjectWriter, UoWAuditBigObjectWriter
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Audit Test Utilities
 */
@isTest
private class UoWAuditStorageWriterTests {

    // ============================================================================
    // CUSTOM OBJECT WRITER TESTS - NULL/EMPTY HANDLING
    // ============================================================================

    @isTest
    static void test_customObjectWriter_writeAuditData_nullTransactionEvents_handlesGracefully() {
        // Arrange
        List<UoWAuditEvent__e> workItemEvents = new List<UoWAuditEvent__e>();

        // Act
        Test.startTest();
        UoWAuditCustomObjectWriter.writeAuditData(null, workItemEvents);
        Test.stopTest();

        // Assert - No exception thrown
        Assert.isTrue(true, 'Should handle null transaction events gracefully');
    }

    @isTest
    static void test_customObjectWriter_writeAuditData_nullWorkItemEvents_handlesGracefully() {
        // Arrange
        List<UoWAuditEvent__e> transactionEvents = new List<UoWAuditEvent__e>();

        // Act
        Test.startTest();
        UoWAuditCustomObjectWriter.writeAuditData(transactionEvents, null);
        Test.stopTest();

        // Assert - No exception thrown
        Assert.isTrue(true, 'Should handle null work item events gracefully');
    }

    @isTest
    static void test_customObjectWriter_writeAuditData_emptyLists_handlesGracefully() {
        // Arrange
        List<UoWAuditEvent__e> transactionEvents = new List<UoWAuditEvent__e>();
        List<UoWAuditEvent__e> workItemEvents = new List<UoWAuditEvent__e>();

        // Act
        Test.startTest();
        UoWAuditCustomObjectWriter.writeAuditData(transactionEvents, workItemEvents);
        Test.stopTest();

        // Assert - No exception thrown
        Assert.isTrue(true, 'Should handle empty event lists gracefully');
    }

    @isTest
    static void test_customObjectWriter_writeAuditData_bothNull_handlesGracefully() {
        // Act
        Test.startTest();
        UoWAuditCustomObjectWriter.writeAuditData(null, null);
        Test.stopTest();

        // Assert - No exception thrown
        Assert.isTrue(true, 'Should handle both null parameters gracefully');
    }

    // ============================================================================
    // CUSTOM OBJECT WRITER TESTS - TRANSACTION CREATION
    // ============================================================================

    @isTest
    static void test_customObjectWriter_writeAuditData_createsTransactionRecord() {
        // Arrange
        String transactionId = 'TXN-' + System.now().getTime();
        UoWAuditEvent__e txnEvent = UoWAuditTestDataFactory.createTransactionEvent(
            transactionId, 'CUSTOM_OBJECT'
        );
        txnEvent.TransactionStatus__c = 'SUCCESS';
        txnEvent.ConfigurationName__c = 'TestConfig';

        List<UoWAuditEvent__e> transactionEvents = new List<UoWAuditEvent__e>{ txnEvent };

        // Act
        Test.startTest();
        UoWAuditCustomObjectWriter.writeAuditData(transactionEvents, null);
        Test.stopTest();

        // Assert
        List<UoWAuditTransaction__c> inserted = [
            SELECT Id, TransactionId__c, TransactionStatus__c, ConfigurationName__c
            FROM UoWAuditTransaction__c
            WHERE TransactionId__c = :transactionId
        ];
        Assert.areEqual(1, inserted.size(), 'Should create 1 transaction record');
        Assert.areEqual('SUCCESS', inserted[0].TransactionStatus__c, 'Status should be SUCCESS');
        Assert.areEqual('TestConfig', inserted[0].ConfigurationName__c, 'Config name should match');
    }

    @isTest
    static void test_customObjectWriter_writeAuditData_createsMultipleTransactions() {
        // Arrange
        String txnId1 = 'TXN-MULTI-1-' + System.now().getTime();
        String txnId2 = 'TXN-MULTI-2-' + System.now().getTime();

        List<UoWAuditEvent__e> transactionEvents = new List<UoWAuditEvent__e>{
            UoWAuditTestDataFactory.createTransactionEvent(txnId1, 'CUSTOM_OBJECT'),
            UoWAuditTestDataFactory.createTransactionEvent(txnId2, 'CUSTOM_OBJECT')
        };

        // Act
        Test.startTest();
        UoWAuditCustomObjectWriter.writeAuditData(transactionEvents, null);
        Test.stopTest();

        // Assert
        List<UoWAuditTransaction__c> inserted = [
            SELECT Id, TransactionId__c
            FROM UoWAuditTransaction__c
            WHERE TransactionId__c IN (:txnId1, :txnId2)
        ];
        Assert.areEqual(2, inserted.size(), 'Should create 2 transaction records');
    }

    // ============================================================================
    // CUSTOM OBJECT WRITER TESTS - WORK ITEM CREATION
    // ============================================================================

    @isTest
    static void test_customObjectWriter_writeAuditData_createsWorkItemRecord() {
        // Arrange - First create parent transaction
        String transactionId = 'TXN-WI-' + System.now().getTime();
        UoWAuditEvent__e txnEvent = UoWAuditTestDataFactory.createTransactionEvent(
            transactionId, 'CUSTOM_OBJECT'
        );

        String workItemId = 'WORK-WI-' + System.now().getTime();
        UoWAuditEvent__e wiEvent = UoWAuditTestDataFactory.createWorkItemEvent(
            transactionId, workItemId, 'CUSTOM_OBJECT'
        );
        wiEvent.WorkType__c = 'DML';
        wiEvent.DmlOperation__c = 'INSERT_OP';
        wiEvent.SObjectType__c = 'Account';

        List<UoWAuditEvent__e> transactionEvents = new List<UoWAuditEvent__e>{ txnEvent };
        List<UoWAuditEvent__e> workItemEvents = new List<UoWAuditEvent__e>{ wiEvent };

        // Act
        Test.startTest();
        UoWAuditCustomObjectWriter.writeAuditData(transactionEvents, workItemEvents);
        Test.stopTest();

        // Assert
        List<UoWAuditWorkItem__c> insertedWorkItems = [
            SELECT Id, WorkType__c, DmlOperation__c, SObjectType__c, AuditTransaction__c
            FROM UoWAuditWorkItem__c
            WHERE AuditTransaction__r.TransactionId__c = :transactionId
        ];
        Assert.areEqual(1, insertedWorkItems.size(), 'Should create 1 work item record');
        Assert.areEqual('DML', insertedWorkItems[0].WorkType__c, 'Work type should be DML');
        Assert.areEqual('INSERT_OP', insertedWorkItems[0].DmlOperation__c, 'DML operation should be INSERT_OP');
        Assert.areEqual('Account', insertedWorkItems[0].SObjectType__c, 'SObject type should be Account');
    }

    @isTest
    static void test_customObjectWriter_writeAuditData_linksWorkItemToTransaction() {
        // Arrange
        String transactionId = 'TXN-LINK-' + System.now().getTime();
        UoWAuditEvent__e txnEvent = UoWAuditTestDataFactory.createTransactionEvent(
            transactionId, 'CUSTOM_OBJECT'
        );

        UoWAuditEvent__e wiEvent = UoWAuditTestDataFactory.createWorkItemEvent(
            transactionId, 'WORK-LINK-001', 'CUSTOM_OBJECT'
        );

        // Act
        Test.startTest();
        UoWAuditCustomObjectWriter.writeAuditData(
            new List<UoWAuditEvent__e>{ txnEvent },
            new List<UoWAuditEvent__e>{ wiEvent }
        );
        Test.stopTest();

        // Assert - Work item should be linked to transaction
        List<UoWAuditTransaction__c> transactions = [
            SELECT Id, (SELECT Id FROM WorkItems__r)
            FROM UoWAuditTransaction__c
            WHERE TransactionId__c = :transactionId
        ];
        Assert.areEqual(1, transactions.size(), 'Should have 1 transaction');
        Assert.areEqual(1, transactions[0].WorkItems__r.size(), 'Transaction should have 1 work item');
    }

    // ============================================================================
    // CUSTOM OBJECT WRITER TESTS - PARENT RELATIONSHIP
    // ============================================================================

    @isTest
    static void test_customObjectWriter_writeAuditData_resolvesParentRelationship() {
        // Arrange - Parent and child in same batch
        String parentTxnId = 'TXN-PARENT-' + System.now().getTime();
        String childTxnId = 'TXN-CHILD-' + System.now().getTime();

        UoWAuditEvent__e parentEvent = UoWAuditTestDataFactory.createTransactionEvent(
            parentTxnId, 'CUSTOM_OBJECT'
        );

        UoWAuditEvent__e childEvent = UoWAuditTestDataFactory.createTransactionEvent(
            childTxnId, 'CUSTOM_OBJECT'
        );
        childEvent.ParentTransactionId__c = parentTxnId;
        childEvent.CorrelationId__c = parentEvent.CorrelationId__c; // Same correlation

        List<UoWAuditEvent__e> transactionEvents = new List<UoWAuditEvent__e>{
            parentEvent, childEvent
        };

        // Act
        Test.startTest();
        UoWAuditCustomObjectWriter.writeAuditData(transactionEvents, null);
        Test.stopTest();

        // Assert
        List<UoWAuditTransaction__c> transactions = [
            SELECT Id, TransactionId__c, ParentTransaction__c, HasChildTransactions__c
            FROM UoWAuditTransaction__c
            WHERE TransactionId__c IN (:parentTxnId, :childTxnId)
            ORDER BY TransactionId__c
        ];

        Assert.areEqual(2, transactions.size(), 'Should create 2 transactions');

        // Find parent and child
        UoWAuditTransaction__c parent = null;
        UoWAuditTransaction__c child = null;
        for (UoWAuditTransaction__c txn : transactions) {
            if (txn.TransactionId__c == parentTxnId) {
                parent = txn;
            } else {
                child = txn;
            }
        }

        Assert.isNotNull(parent, 'Should find parent');
        Assert.isNotNull(child, 'Should find child');

        // ParentTransaction__c lookup is resolved by scheduled flow (not at write time)
        // Verify ParentTransactionId__c text field is stored for deferred resolution
        List<UoWAuditTransaction__c> childWithParentId = [
            SELECT ParentTransactionId__c FROM UoWAuditTransaction__c WHERE Id = :child.Id
        ];
        Assert.areEqual(parentTxnId, childWithParentId[0].ParentTransactionId__c,
            'Child should store ParentTransactionId for deferred resolution');
    }

    // ============================================================================
    // BIG OBJECT WRITER TESTS - NULL/EMPTY HANDLING
    // ============================================================================

    @isTest
    static void test_bigObjectWriter_writeAuditData_nullWorkItemEvents_handlesGracefully() {
        // Act
        Test.startTest();
        UoWAuditBigObjectWriter.writeAuditData(null, null);
        Test.stopTest();

        // Assert - No exception thrown
        Assert.isTrue(true, 'Should handle null work item events gracefully');
    }

    @isTest
    static void test_bigObjectWriter_writeAuditData_emptyWorkItemEvents_handlesGracefully() {
        // Act
        Test.startTest();
        UoWAuditBigObjectWriter.writeAuditData(
            new List<UoWAuditEvent__e>(),
            new List<UoWAuditEvent__e>()
        );
        Test.stopTest();

        // Assert - No exception thrown
        Assert.isTrue(true, 'Should handle empty work item events gracefully');
    }

    @isTest
    static void test_bigObjectWriter_writeAuditData_ignoresTransactionEvents() {
        // Arrange - Big object writer ignores transaction events
        UoWAuditEvent__e txnEvent = UoWAuditTestDataFactory.createTransactionEvent(
            'TXN-IGNORED-' + System.now().getTime(), 'BIG_OBJECT'
        );

        List<UoWAuditEvent__e> transactionEvents = new List<UoWAuditEvent__e>{ txnEvent };

        // Act
        Test.startTest();
        UoWAuditBigObjectWriter.writeAuditData(transactionEvents, null);
        Test.stopTest();

        // Assert - No exception thrown, transaction events are ignored
        Assert.isTrue(true, 'Should ignore transaction events');
    }

    @isTest
    static void test_bigObjectWriter_writeSingleWorkItem_nullEvent_handlesGracefully() {
        // Act
        Test.startTest();
        UoWAuditBigObjectWriter.writeSingleWorkItem(null);
        Test.stopTest();

        // Assert - No exception thrown
        Assert.isTrue(true, 'Should handle null single work item gracefully');
    }

    // ============================================================================
    // BIG OBJECT WRITER TESTS - RECORD CREATION
    // Note: Big Object inserts are async (Database.insertAsync), making verification complex.
    // These tests verify the method executes without error.
    // ============================================================================

    @isTest
    static void test_bigObjectWriter_writeAuditData_processesWorkItemEvents() {
        // Arrange
        UoWAuditMocks.BigObjectDmlMockProvider mockProvider = UoWAuditMocks.installBigObjectMock();

        String transactionId = 'TXN-BO-' + System.now().getTime();
        String correlationId = 'CORR-BO-' + System.now().getTime();

        UoWAuditEvent__e wiEvent = UoWAuditTestDataFactory.createWorkItemEvent(
            transactionId, correlationId, 'WORK-BO-001', 'BIG_OBJECT', 'DML'
        );
        // Add required fields for Big Object
        wiEvent.Sequence__c = 1;

        List<UoWAuditEvent__e> workItemEvents = new List<UoWAuditEvent__e>{ wiEvent };

        // Act
        Test.startTest();
        UoWAuditBigObjectWriter.writeAuditData(null, workItemEvents);
        Test.stopTest();

        // Assert - Verify mock captured the Big Object record
        Assert.areEqual(1, mockProvider.capturedRecords.size(), 'Should create 1 Big Object record');
        Assert.areEqual(transactionId, mockProvider.capturedRecords[0].TransactionId__c, 'Should preserve TransactionId');
    }

    @isTest
    static void test_bigObjectWriter_writeSingleWorkItem_processesEvent() {
        // Arrange
        UoWAuditMocks.BigObjectDmlMockProvider mockProvider = UoWAuditMocks.installBigObjectMock();

        UoWAuditEvent__e wiEvent = UoWAuditTestDataFactory.createWorkItemEvent(
            'TXN-SINGLE-' + System.now().getTime(),
            'WORK-SINGLE-001',
            'BIG_OBJECT'
        );
        wiEvent.Sequence__c = 1;
        wiEvent.CorrelationId__c = 'CORR-SINGLE-' + System.now().getTime();

        // Act
        Test.startTest();
        UoWAuditBigObjectWriter.writeSingleWorkItem(wiEvent);
        Test.stopTest();

        // Assert - Verify mock captured the Big Object record
        Assert.areEqual(1, mockProvider.capturedRecords.size(), 'Should create 1 Big Object record');
    }

    // ============================================================================
    // CUSTOM OBJECT WRITER TESTS - SCENARIO RECORDS
    // ============================================================================

    @isTest
    static void test_customObjectWriter_writeAuditData_upsertsScenarioRecord() {
        // Arrange
        String transactionId = 'TXN-SCENARIO-' + System.now().getTime();
        String scenarioName = 'TestScenario-' + System.now().getTime();

        UoWAuditEvent__e txnEvent = UoWAuditTestDataFactory.createTransactionEvent(
            transactionId, 'CUSTOM_OBJECT'
        );
        txnEvent.EnableScenarioRecordTracking__c = true;
        txnEvent.TransactionScenarioName__c = scenarioName;

        List<UoWAuditEvent__e> transactionEvents = new List<UoWAuditEvent__e>{ txnEvent };

        // Act
        Test.startTest();
        UoWAuditCustomObjectWriter.writeAuditData(transactionEvents, null);
        Test.stopTest();

        // Assert - Scenario record should be created
        List<UoWScenario__c> scenarios = [
            SELECT Id, Name, UniqueId__c
            FROM UoWScenario__c
            WHERE UniqueId__c = :scenarioName
        ];
        Assert.areEqual(1, scenarios.size(), 'Should create scenario record');
        Assert.areEqual(scenarioName, scenarios[0].Name, 'Scenario name should match');
    }

    @isTest
    static void test_customObjectWriter_writeAuditData_skipsScenarioWhenNotEnabled() {
        // Arrange
        String transactionId = 'TXN-NO-SCENARIO-' + System.now().getTime();
        String scenarioName = 'TestScenario-NoTrack-' + System.now().getTime();

        UoWAuditEvent__e txnEvent = UoWAuditTestDataFactory.createTransactionEvent(
            transactionId, 'CUSTOM_OBJECT'
        );
        txnEvent.EnableScenarioRecordTracking__c = false;
        txnEvent.TransactionScenarioName__c = scenarioName;

        List<UoWAuditEvent__e> transactionEvents = new List<UoWAuditEvent__e>{ txnEvent };

        // Act
        Test.startTest();
        UoWAuditCustomObjectWriter.writeAuditData(transactionEvents, null);
        Test.stopTest();

        // Assert - Scenario record should NOT be created
        List<UoWScenario__c> scenarios = [
            SELECT Id
            FROM UoWScenario__c
            WHERE UniqueId__c = :scenarioName
        ];
        Assert.areEqual(0, scenarios.size(), 'Should not create scenario record when not enabled');
    }

    // ============================================================================
    // CUSTOM OBJECT WRITER TESTS - FIELD MAPPING
    // ============================================================================

    @isTest
    static void test_customObjectWriter_writeAuditData_mapsAllTransactionFields() {
        // Arrange
        String transactionId = 'TXN-FIELDS-' + System.now().getTime();
        String correlationId = 'CORR-FIELDS-' + System.now().getTime();

        UoWAuditEvent__e txnEvent = new UoWAuditEvent__e(
            EventType__c = UoWAuditParameter.EVENT_TYPE_TRANSACTION,
            TransactionId__c = transactionId,
            CorrelationId__c = correlationId,
            StorageMode__c = 'CUSTOM_OBJECT',
            TransactionStatus__c = 'SUCCESS',
            ConfigurationName__c = 'TestConfig',
            ExecutionTimeMs__c = 250,
            ErrorCount__c = 0,
            WorkItemCount__c = 3,
            Description__c = 'Test transaction description',
            IsDryRun__c = false,
            RiskLevel__c = 'LOW',
            RiskScore__c = 10,
            Timestamp__c = DateTime.now()
        );

        // Act
        Test.startTest();
        UoWAuditCustomObjectWriter.writeAuditData(
            new List<UoWAuditEvent__e>{ txnEvent },
            null
        );
        Test.stopTest();

        // Assert
        List<UoWAuditTransaction__c> inserted = [
            SELECT Id, TransactionId__c, CorrelationId__c, TransactionStatus__c,
                   ConfigurationName__c, ExecutionTimeMs__c, ErrorCount__c,
                   TotalWorkItems__c, Description__c, IsDryRun__c, RiskLevel__c, RiskScore__c
            FROM UoWAuditTransaction__c
            WHERE TransactionId__c = :transactionId
        ];

        Assert.areEqual(1, inserted.size(), 'Should create 1 transaction');
        UoWAuditTransaction__c txn = inserted[0];

        Assert.areEqual(correlationId, txn.CorrelationId__c, 'CorrelationId should be mapped');
        Assert.areEqual('SUCCESS', txn.TransactionStatus__c, 'Status should be mapped');
        Assert.areEqual('TestConfig', txn.ConfigurationName__c, 'Config name should be mapped');
        Assert.areEqual(250, txn.ExecutionTimeMs__c, 'ExecutionTimeMs should be mapped');
        Assert.areEqual('Test transaction description', txn.Description__c, 'Description should be mapped');
    }

    @isTest
    static void test_customObjectWriter_writeAuditData_mapsAllWorkItemFields() {
        // Arrange
        String transactionId = 'TXN-WI-FIELDS-' + System.now().getTime();

        UoWAuditEvent__e txnEvent = UoWAuditTestDataFactory.createTransactionEvent(
            transactionId, 'CUSTOM_OBJECT'
        );

        UoWAuditEvent__e wiEvent = new UoWAuditEvent__e(
            EventType__c = UoWAuditParameter.EVENT_TYPE_WORK_ITEM,
            TransactionId__c = transactionId,
            CorrelationId__c = 'CORR-' + transactionId,
            WorkId__c = 'WORK-FIELDS-001',
            StorageMode__c = 'CUSTOM_OBJECT',
            WorkType__c = 'DML',
            DmlOperation__c = 'INSERT_OP',
            SObjectType__c = 'Contact',
            PlannedCount__c = 10,
            ProcessedCount__c = 10,
            SuccessCount__c = 8,
            FailureCount__c = 2,
            ExecutionTimeMs__c = 75,
            Timestamp__c = DateTime.now()
        );

        // Act
        Test.startTest();
        UoWAuditCustomObjectWriter.writeAuditData(
            new List<UoWAuditEvent__e>{ txnEvent },
            new List<UoWAuditEvent__e>{ wiEvent }
        );
        Test.stopTest();

        // Assert
        List<UoWAuditWorkItem__c> inserted = [
            SELECT Id, WorkType__c, DmlOperation__c, SObjectType__c,
                   PlannedCount__c, ProcessedCount__c, SuccessCount__c, FailureCount__c,
                   ExecutionTimeMs__c
            FROM UoWAuditWorkItem__c
            WHERE AuditTransaction__r.TransactionId__c = :transactionId
        ];

        Assert.areEqual(1, inserted.size(), 'Should create 1 work item');
        UoWAuditWorkItem__c wi = inserted[0];

        Assert.areEqual('DML', wi.WorkType__c, 'WorkType should be mapped');
        Assert.areEqual('INSERT_OP', wi.DmlOperation__c, 'DmlOperation should be mapped');
        Assert.areEqual('Contact', wi.SObjectType__c, 'SObjectType should be mapped');
        Assert.areEqual(10, wi.PlannedCount__c, 'PlannedCount should be mapped');
        Assert.areEqual(10, wi.ProcessedCount__c, 'ProcessedCount should be mapped');
        Assert.areEqual(8, wi.SuccessCount__c, 'SuccessCount should be mapped');
        Assert.areEqual(2, wi.FailureCount__c, 'FailureCount should be mapped');
        Assert.areEqual(75, wi.ExecutionTimeMs__c, 'ExecutionTimeMs should be mapped');
    }

    // ============================================================================
    // CUSTOM OBJECT WRITER TESTS - RECORD INDEX (REVERSE LOOKUP)
    // ============================================================================

    @isTest
    static void test_customObjectWriter_createsRecordIndexRows() {
        // Arrange - one work item that touched two records
        String txnId = 'TXN-IDX-' + System.now().getTime();
        String recA = '001000000000001AAA';
        String recB = '001000000000002AAA';

        UoWAuditEvent__e txnEvent = UoWAuditTestDataFactory.createTransactionEvent(txnId, 'CUSTOM_OBJECT');
        UoWAuditEvent__e wiEvent = UoWAuditTestDataFactory.createWorkItemEvent(txnId, 'WI-1', 'CUSTOM_OBJECT');
        wiEvent.SObjectType__c = 'Account';
        wiEvent.DmlOperation__c = 'INSERT_OP';
        wiEvent.EndTime__c = System.now();
        wiEvent.RecordIds__c = recA + ',' + recB;

        // Act
        Test.startTest();
        UoWAuditCustomObjectWriter.writeAuditData(
            new List<UoWAuditEvent__e>{ txnEvent },
            new List<UoWAuditEvent__e>{ wiEvent }
        );
        Test.stopTest();

        // Assert
        List<UoWAuditRecordIndex__c> rows = [
            SELECT RecordId__c, SObjectType__c, Operation__c, Timestamp__c, AuditWorkItem__c
            FROM UoWAuditRecordIndex__c
            ORDER BY RecordId__c ASC
        ];
        Assert.areEqual(2, rows.size(), 'Should create one index row per record Id');
        Assert.areEqual(recA, rows[0].RecordId__c, 'First index row Id should match');
        Assert.areEqual('Account', rows[0].SObjectType__c, 'SObjectType should be denormalized');
        Assert.areEqual('INSERT', rows[0].Operation__c, 'Operation should have _OP suffix stripped');
        Assert.areNotEqual(null, rows[0].AuditWorkItem__c, 'Index row should link to its work item');
        Assert.areNotEqual(null, rows[0].Timestamp__c, 'Timestamp should be denormalized from EndTime');
    }

    @isTest
    static void test_customObjectWriter_singleRecord_populatesRecordIdSingle() {
        // Arrange - one work item, one record
        String txnId = 'TXN-SINGLE-' + System.now().getTime();
        String recId = '001000000000009AAA';

        UoWAuditEvent__e txnEvent = UoWAuditTestDataFactory.createTransactionEvent(txnId, 'CUSTOM_OBJECT');
        UoWAuditEvent__e wiEvent = UoWAuditTestDataFactory.createWorkItemEvent(txnId, 'WI-1', 'CUSTOM_OBJECT');
        wiEvent.SObjectType__c = 'Account';
        wiEvent.EndTime__c = System.now();
        wiEvent.RecordIds__c = recId;

        // Act
        Test.startTest();
        UoWAuditCustomObjectWriter.writeAuditData(
            new List<UoWAuditEvent__e>{ txnEvent },
            new List<UoWAuditEvent__e>{ wiEvent }
        );
        Test.stopTest();

        // Assert - single index row and the RecordIdSingle__c convenience field populated
        List<UoWAuditRecordIndex__c> rows = [SELECT RecordId__c FROM UoWAuditRecordIndex__c];
        Assert.areEqual(1, rows.size(), 'Single record should create one index row');

        UoWAuditWorkItem__c wi = [SELECT RecordIdSingle__c FROM UoWAuditWorkItem__c LIMIT 1];
        Assert.areEqual(recId, wi.RecordIdSingle__c, 'RecordIdSingle should be populated for single-record ops');
    }

    @isTest
    static void test_customObjectWriter_blankRecordIds_createsNoIndexRows() {
        // Arrange - work item with no record Ids (e.g. object sampling strategy = NONE)
        String txnId = 'TXN-NONE-' + System.now().getTime();

        UoWAuditEvent__e txnEvent = UoWAuditTestDataFactory.createTransactionEvent(txnId, 'CUSTOM_OBJECT');
        UoWAuditEvent__e wiEvent = UoWAuditTestDataFactory.createWorkItemEvent(txnId, 'WI-1', 'CUSTOM_OBJECT');
        wiEvent.SObjectType__c = 'Account';
        wiEvent.EndTime__c = System.now();
        // RecordIds__c intentionally left blank

        // Act
        Test.startTest();
        UoWAuditCustomObjectWriter.writeAuditData(
            new List<UoWAuditEvent__e>{ txnEvent },
            new List<UoWAuditEvent__e>{ wiEvent }
        );
        Test.stopTest();

        // Assert
        Assert.areEqual(0, [SELECT COUNT() FROM UoWAuditRecordIndex__c],
            'No index rows should be created when there are no record Ids');
        UoWAuditWorkItem__c wi = [SELECT RecordIdSingle__c FROM UoWAuditWorkItem__c LIMIT 1];
        Assert.areEqual(null, wi.RecordIdSingle__c, 'RecordIdSingle should be blank when no record Ids');
    }

    @isTest
    static void test_customObjectWriter_deleteTransaction_cascadesIndexRows() {
        // Arrange
        String txnId = 'TXN-CASCADE-' + System.now().getTime();
        UoWAuditEvent__e txnEvent = UoWAuditTestDataFactory.createTransactionEvent(txnId, 'CUSTOM_OBJECT');
        UoWAuditEvent__e wiEvent = UoWAuditTestDataFactory.createWorkItemEvent(txnId, 'WI-1', 'CUSTOM_OBJECT');
        wiEvent.SObjectType__c = 'Account';
        wiEvent.EndTime__c = System.now();
        wiEvent.RecordIds__c = '001000000000010AAA';

        UoWAuditCustomObjectWriter.writeAuditData(
            new List<UoWAuditEvent__e>{ txnEvent },
            new List<UoWAuditEvent__e>{ wiEvent }
        );
        Assert.areEqual(1, [SELECT COUNT() FROM UoWAuditRecordIndex__c], 'Index row should exist before delete');

        // Act - delete the parent transaction
        Test.startTest();
        delete [SELECT Id FROM UoWAuditTransaction__c WHERE TransactionId__c = :txnId];
        Test.stopTest();

        // Assert - master-detail cascade removes the index rows
        Assert.areEqual(0, [SELECT COUNT() FROM UoWAuditRecordIndex__c],
            'Deleting the transaction should cascade-delete index rows');
    }
}
