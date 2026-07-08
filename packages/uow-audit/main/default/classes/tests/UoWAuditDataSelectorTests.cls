//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Test class for UoWAuditDataSelector.
 * Tests the data access layer singleton pattern and query methods.
 *
 * Testing strategy:
 * - Uses real DML for custom audit objects (UoWAuditTransaction__c, UoWAuditWorkItem__c)
 * - Tests null/empty input handling
 * - Tests actual query execution with real data
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Audit Test Utilities
 */
@isTest
@SuppressWarnings('PMD.MethodNamingConventions')
private class UoWAuditDataSelectorTests {

    // ============================================================================
    // TEST SETUP
    // ============================================================================

    @TestSetup
    static void setupTestData() {
        // Load test configurations from static resource
        UoWTestHelpers.loadTestConfigurations();

        // Create test user with UoWAuditAdmin permission set for USER_MODE queries
        // This is setup object DML (User, PermissionSetAssignment)
        User testUser = UoWAuditTestDataFactory.createAuditAdminUser();

        // Use System.runAs to create a new transaction context for non-setup objects
        // This avoids MIXED_DML_OPERATION error between setup and non-setup objects
        System.runAs(testUser) {
            // Create test transactions with various configurations
            UoWAuditTransaction__c txn = new UoWAuditTransaction__c(
                TransactionId__c = 'TXN-SELECTOR-001',
                CorrelationId__c = 'CORR-SELECTOR-001',
                TransactionStatus__c = 'SUCCESS',
                StartTime__c = DateTime.now().addMinutes(-5),
                EndTime__c = DateTime.now(),
                ExecutionTimeMs__c = 150,
                Timeline__c = UoWAuditTestDataFactory.getCompactTimelineJson(),
                Messages__c = UoWAuditTestDataFactory.getMessagesJson(),
                ConfigurationSnapshot__c = '{"enableAudit":true}',
                ConfigurationName__c = 'TestConfig',
                ErrorDetails__c = UoWAuditTestDataFactory.getErrorDetailsJson(),
                HasErrors__c = true,
                ErrorCount__c = 1
            );
            insert txn;

            // Create work item
            UoWAuditWorkItem__c workItem = new UoWAuditWorkItem__c(
                AuditTransaction__c = txn.Id,
                Name = 'WORK-SELECTOR-001',
                WorkType__c = 'DML',
                WorkItemStatus__c = 'SUCCESS',
                SObjectType__c = 'Account',
                DmlOperation__c = 'INSERT_OP',
                ErrorDetails__c = UoWAuditTestDataFactory.getWorkItemErrorDetailsJson(),
                HasErrors__c = true,
                ErrorCount__c = 1
            );
            insert workItem;

            // Create child transaction for hierarchy tests
            UoWAuditTransaction__c childTxn = new UoWAuditTransaction__c(
                TransactionId__c = 'TXN-SELECTOR-002',
                CorrelationId__c = 'CORR-SELECTOR-001', // Same correlation ID as parent
                TransactionStatus__c = 'SUCCESS',
                ParentTransaction__c = txn.Id,
                ParentTransactionId__c = 'TXN-SELECTOR-001'
            );
            insert childTxn;
        }
    }

    /**
     * Helper method to retrieve the test user with UoWAuditAdmin permission set.
     */
    private static User getAuditAdminUser() {
        return [SELECT Id FROM User WHERE Alias =: UoWAuditTestDataFactory.ADMIN_USER_ALIAS LIMIT 1];
    }

    // ============================================================================
    // SINGLETON PATTERN TESTS
    // ============================================================================

    @isTest
    static void test_getInstance_returnsSameInstance() {
        // Act
        UoWAuditDataSelector instance1 = UoWAuditDataSelector.getInstance();
        UoWAuditDataSelector instance2 = UoWAuditDataSelector.getInstance();

        // Assert
        Assert.isNotNull(instance1, 'First instance should not be null');
        Assert.isNotNull(instance2, 'Second instance should not be null');
        Assert.areEqual(instance1, instance2, 'Both calls should return the same instance');
    }

    @isTest
    static void test_setInstance_allowsCustomImplementation() {
        // Arrange - Get original instance
        UoWAuditDataSelector original = UoWAuditDataSelector.getInstance();

        // Act - Set same instance (just verifying the method exists and works)
        UoWAuditDataSelector.setInstance(original);
        UoWAuditDataSelector retrievedInstance = UoWAuditDataSelector.getInstance();

        // Assert
        Assert.areEqual(original, retrievedInstance, 'setInstance should allow setting custom implementation');
    }

    // ============================================================================
    // TRANSACTION QUERIES - SINGLE RECORD - NULL HANDLING
    // ============================================================================

    @isTest
    static void test_getTransactionById_nullId_returnsNull() {
        // Arrange
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        // Act
        UoWAuditTransaction__c result = selector.getTransactionById(null);

        // Assert
        Assert.isNull(result, 'Should return null for null ID');
    }

    @isTest
    static void test_getTransactionForTimeline_nullId_returnsNull() {
        // Arrange
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        // Act
        UoWAuditTransaction__c result = selector.getTransactionForTimeline(null);

        // Assert
        Assert.isNull(result, 'Should return null for null ID');
    }

    @isTest
    static void test_getTransactionForMessages_nullId_returnsNull() {
        // Arrange
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        // Act
        UoWAuditTransaction__c result = selector.getTransactionForMessages(null);

        // Assert
        Assert.isNull(result, 'Should return null for null ID');
    }

    @isTest
    static void test_getTransactionForConfiguration_nullId_returnsNull() {
        // Arrange
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        // Act
        UoWAuditTransaction__c result = selector.getTransactionForConfiguration(null);

        // Assert
        Assert.isNull(result, 'Should return null for null ID');
    }

    @isTest
    static void test_getTransactionForErrors_nullId_returnsNull() {
        // Arrange
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        // Act
        UoWAuditTransaction__c result = selector.getTransactionForErrors(null);

        // Assert
        Assert.isNull(result, 'Should return null for null ID');
    }

    // ============================================================================
    // TRANSACTION QUERIES - MULTIPLE RECORDS - NULL/EMPTY HANDLING
    // ============================================================================

    @isTest
    static void test_getTransactionIdToRecordIdMap_nullInput_returnsEmptyMap() {
        // Arrange
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        // Act
        Map<String, Id> result = selector.getTransactionIdToRecordIdMap(null);

        // Assert
        Assert.isNotNull(result, 'Should return empty map, not null');
        Assert.isTrue(result.isEmpty(), 'Map should be empty');
    }

    @isTest
    static void test_getTransactionIdToRecordIdMap_emptySet_returnsEmptyMap() {
        // Arrange
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        // Act
        Map<String, Id> result = selector.getTransactionIdToRecordIdMap(new Set<String>());

        // Assert
        Assert.isNotNull(result, 'Should return empty map, not null');
        Assert.isTrue(result.isEmpty(), 'Map should be empty');
    }

    @isTest
    static void test_getTransactionIdToRecordMap_nullInput_returnsEmptyMap() {
        // Arrange
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        // Act
        Map<String, UoWAuditTransaction__c> result = selector.getTransactionIdToRecordMap(null);

        // Assert
        Assert.isNotNull(result, 'Should return empty map, not null');
        Assert.isTrue(result.isEmpty(), 'Map should be empty');
    }

    @isTest
    static void test_getTransactionsWithWorkItems_nullInput_returnsEmptyList() {
        // Arrange
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        // Act
        List<UoWAuditTransaction__c> result = selector.getTransactionsWithWorkItems(null);

        // Assert
        Assert.isNotNull(result, 'Should return empty list, not null');
        Assert.isTrue(result.isEmpty(), 'List should be empty');
    }

    @isTest
    static void test_getTransactionsWithWorkItems_emptySet_returnsEmptyList() {
        // Arrange
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        // Act
        List<UoWAuditTransaction__c> result = selector.getTransactionsWithWorkItems(new Set<Id>());

        // Assert
        Assert.isNotNull(result, 'Should return empty list, not null');
        Assert.isTrue(result.isEmpty(), 'List should be empty');
    }

    // ============================================================================
    // WORK ITEM QUERIES - NULL HANDLING
    // ============================================================================

    @isTest
    static void test_getWorkItemById_nullId_throwsException() {
        // Arrange
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        // Act
        Test.startTest();
        try {
            selector.getWorkItemById(null);
            Assert.fail('Should have thrown UoWException');
        } catch (UoWExceptionService.UoWException ex){
            Assert.areEqual('Work Item Record Id cannot be blank', ex.getMessage(),
                'Exception message should throw non blank error for null work item record id');
        }
        Test.stopTest();
    }

    @isTest
    static void test_getWorkItemForErrors_nullId_returnsNull() {
        // Arrange
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        // Act
        Test.startTest();
        try {
            selector.getWorkItemForErrors(null);
            Assert.fail('Should have thrown UoWException');
        } catch (UoWExceptionService.UoWException ex){
            Assert.areEqual('Work Item Record Id cannot be blank', ex.getMessage(),
                'Exception message should throw non blank error for null work item record id');
        }
        Test.stopTest();
    }

    @isTest
    static void test_getWorkItemNameToRecordIdMap_nullInput_returnsEmptyMap() {
        // Arrange
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        // Act
        Map<String, Id> result = selector.getWorkItemNameToRecordIdMap(null);

        // Assert
        Assert.isNotNull(result, 'Should return empty map, not null');
        Assert.isTrue(result.isEmpty(), 'Map should be empty');
    }

    @isTest
    static void test_getWorkItemNameToRecordIdMap_emptySet_returnsEmptyMap() {
        // Arrange
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        // Act
        Map<String, Id> result = selector.getWorkItemNameToRecordIdMap(new Set<String>());

        // Assert
        Assert.isNotNull(result, 'Should return empty map, not null');
        Assert.isTrue(result.isEmpty(), 'Map should be empty');
    }

    // ============================================================================
    // HIERARCHY QUERIES - NULL/BLANK HANDLING
    // ============================================================================

    @isTest
    static void test_getTransactionsByCorrelationId_blankId_returnsEmptyList() {
        // Arrange
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        // Act
        List<UoWAuditTransaction__c> result = selector.getTransactionsByCorrelationId('');

        // Assert
        Assert.isNotNull(result, 'Should return empty list, not null');
        Assert.isTrue(result.isEmpty(), 'List should be empty');
    }

    @isTest
    static void test_getTransactionsByCorrelationId_nullId_returnsEmptyList() {
        // Arrange
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        // Act
        List<UoWAuditTransaction__c> result = selector.getTransactionsByCorrelationId(null);

        // Assert
        Assert.isNotNull(result, 'Should return empty list, not null');
        Assert.isTrue(result.isEmpty(), 'List should be empty');
    }

    @isTest
    static void test_getCorrelationIdByTransactionId_nullId_returnsNull() {
        // Arrange
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        // Act
        String result = selector.getCorrelationIdByTransactionId(null);

        // Assert
        Assert.isNull(result, 'Should return null for null ID');
    }

    @isTest
    static void test_getRecentRootTransactions_nullLimit_usesDefault() {
        // Arrange
        User testUser = getAuditAdminUser();

        // Act - Must use System.runAs for USER_MODE FLS enforcement
        System.runAs(testUser) {
            UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

            List<UoWAuditTransaction__c> result = selector.getRecentRootTransactions(null);

            // Assert
            Assert.isNotNull(result, 'Should return list (possibly empty)');
        }
    }

    @isTest
    static void test_getRecentRootTransactions_zeroLimit_usesDefault() {
        // Arrange
        User testUser = getAuditAdminUser();

        // Act - Must use System.runAs for USER_MODE FLS enforcement
        System.runAs(testUser) {
            UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

            List<UoWAuditTransaction__c> result = selector.getRecentRootTransactions(0);

            // Assert
            Assert.isNotNull(result, 'Should return list (possibly empty)');
        }
    }

    @isTest
    static void test_getRecentRootTransactions_negativeLimit_usesDefault() {
        // Arrange
        User testUser = getAuditAdminUser();

        // Act - Must use System.runAs for USER_MODE FLS enforcement
        System.runAs(testUser) {
            UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

            List<UoWAuditTransaction__c> result = selector.getRecentRootTransactions(-5);

            // Assert
            Assert.isNotNull(result, 'Should return list (possibly empty)');
        }
    }

    // ============================================================================
    // ASYNC JOB QUERIES - NULL HANDLING
    // ============================================================================

    @isTest
    static void test_getAsyncJobStatus_nullJobId_returnsNull() {
        // Arrange
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        // Act
        AsyncApexJob result = selector.getAsyncJobStatus(null);

        // Assert
        Assert.isNull(result, 'Should return null for null job ID');
    }

    // ============================================================================
    // TRANSACTION QUERIES - REAL DATA TESTS
    // ============================================================================

    @isTest
    static void test_getTransactionById_returnsRecord() {
        // Arrange
        UoWAuditTransaction__c txn = [SELECT Id FROM UoWAuditTransaction__c WHERE TransactionId__c = 'TXN-SELECTOR-001' LIMIT 1];
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

            Test.startTest();
            UoWAuditTransaction__c result = selector.getTransactionById(txn.Id);
            Test.stopTest();

            // Assert
            Assert.isNotNull(result, 'Should return transaction');
            Assert.areEqual('TXN-SELECTOR-001', result.TransactionId__c, 'Should return correct transaction');
        }
    }

    @isTest
    static void test_getTransactionForTimeline_returnsRecordWithTimelineField() {
        // Arrange
        UoWAuditTransaction__c txn = [SELECT Id FROM UoWAuditTransaction__c WHERE TransactionId__c = 'TXN-SELECTOR-001' LIMIT 1];
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

            Test.startTest();
            UoWAuditTransaction__c result = selector.getTransactionForTimeline(txn.Id);
            Test.stopTest();

            // Assert
            Assert.isNotNull(result, 'Should return transaction');
            Assert.isNotNull(result.Timeline__c, 'Should include Timeline__c field');
        }
    }

    @isTest
    static void test_getTransactionForMessages_returnsRecordWithMessagesField() {
        // Arrange
        UoWAuditTransaction__c txn = [SELECT Id FROM UoWAuditTransaction__c WHERE TransactionId__c = 'TXN-SELECTOR-001' LIMIT 1];
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

            Test.startTest();
            UoWAuditTransaction__c result = selector.getTransactionForMessages(txn.Id);
            Test.stopTest();

            // Assert
            Assert.isNotNull(result, 'Should return transaction');
            Assert.isNotNull(result.Messages__c, 'Should include Messages__c field');
        }
    }

    @isTest
    static void test_getTransactionForConfiguration_returnsRecordWithConfigField() {
        // Arrange
        UoWAuditTransaction__c txn = [SELECT Id FROM UoWAuditTransaction__c WHERE TransactionId__c = 'TXN-SELECTOR-001' LIMIT 1];
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

            Test.startTest();
            UoWAuditTransaction__c result = selector.getTransactionForConfiguration(txn.Id);
            Test.stopTest();

            // Assert
            Assert.isNotNull(result, 'Should return transaction');
            Assert.isNotNull(result.ConfigurationSnapshot__c, 'Should include ConfigurationSnapshot__c field');
        }
    }

    @isTest
    static void test_getTransactionForErrors_returnsRecordWithErrorsField() {
        // Arrange
        UoWAuditTransaction__c txn = [SELECT Id FROM UoWAuditTransaction__c WHERE TransactionId__c = 'TXN-SELECTOR-001' LIMIT 1];
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

            Test.startTest();
            UoWAuditTransaction__c result = selector.getTransactionForErrors(txn.Id);
            Test.stopTest();

            // Assert
            Assert.isNotNull(result, 'Should return transaction');
            Assert.isNotNull(result.ErrorDetails__c, 'Should include ErrorDetails__c field');
        }
    }

    @isTest
    static void test_getTransactionIdToRecordIdMap_returnsValidMap() {
        // Arrange
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

            Test.startTest();
            Map<String, Id> result = selector.getTransactionIdToRecordIdMap(
                new Set<String>{ 'TXN-SELECTOR-001', 'TXN-SELECTOR-002' }
            );
            Test.stopTest();

            // Assert
            Assert.isNotNull(result, 'Should return map');
            Assert.areEqual(2, result.size(), 'Should find both transactions');
            Assert.isTrue(result.containsKey('TXN-SELECTOR-001'), 'Should contain first transaction');
            Assert.isTrue(result.containsKey('TXN-SELECTOR-002'), 'Should contain second transaction');
        }
    }

    @isTest
    static void test_getTransactionIdToRecordMap_returnsValidMap() {
        // Arrange
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

            Test.startTest();
            Map<String, UoWAuditTransaction__c> result = selector.getTransactionIdToRecordMap(
                new Set<String>{ 'TXN-SELECTOR-001' }
            );
            Test.stopTest();

            // Assert
            Assert.isNotNull(result, 'Should return map');
            Assert.areEqual(1, result.size(), 'Should find transaction');
            Assert.isTrue(result.containsKey('TXN-SELECTOR-001'), 'Should contain transaction');
            Assert.areEqual('CORR-SELECTOR-001', result.get('TXN-SELECTOR-001').CorrelationId__c, 'Should have correct data');
        }
    }

    @isTest
    static void test_getTransactionsWithWorkItems_returnsWithChildren() {
        // Arrange
        UoWAuditTransaction__c txn = [SELECT Id FROM UoWAuditTransaction__c WHERE TransactionId__c = 'TXN-SELECTOR-001' LIMIT 1];
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

            Test.startTest();
            List<UoWAuditTransaction__c> result = selector.getTransactionsWithWorkItems(new Set<Id>{ txn.Id });
            Test.stopTest();

            // Assert
            Assert.isNotNull(result, 'Should return list');
            Assert.areEqual(1, result.size(), 'Should find one transaction');
            Assert.isFalse(result[0].WorkItems__r.isEmpty(), 'Should include work items');
        }
    }

    // ============================================================================
    // WORK ITEM QUERIES - REAL DATA TESTS
    // ============================================================================

    @isTest
    static void test_getWorkItemById_returnsRecord() {
        // Arrange
        UoWAuditWorkItem__c workItem = [SELECT Id FROM UoWAuditWorkItem__c WHERE Name = 'WORK-SELECTOR-001' LIMIT 1];
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

            Test.startTest();
            UoWAuditWorkItem__c result = selector.getWorkItemById(workItem.Id);
            Test.stopTest();

            // Assert
            Assert.isNotNull(result, 'Should return work item');
            Assert.areEqual('DML', result.WorkType__c, 'Should return correct work item');
        }
    }

    @isTest
    static void test_getWorkItemForErrors_returnsRecordWithErrorsField() {
        // Arrange
        UoWAuditWorkItem__c workItem = [SELECT Id FROM UoWAuditWorkItem__c WHERE Name = 'WORK-SELECTOR-001' LIMIT 1];
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

            Test.startTest();
            UoWAuditWorkItem__c result = selector.getWorkItemForErrors(workItem.Id);
            Test.stopTest();

            // Assert
            Assert.isNotNull(result, 'Should return work item');
            Assert.isNotNull(result.ErrorDetails__c, 'Should include ErrorDetails__c field');
        }
    }

    @isTest
    static void test_getWorkItemNameToRecordIdMap_returnsValidMap() {
        // Arrange
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

            Test.startTest();
            Map<String, Id> result = selector.getWorkItemNameToRecordIdMap(
                new Set<String>{ 'WORK-SELECTOR-001' }
            );
            Test.stopTest();

            // Assert
            Assert.isNotNull(result, 'Should return map');
            Assert.areEqual(1, result.size(), 'Should find work item');
            Assert.isTrue(result.containsKey('WORK-SELECTOR-001'), 'Should contain work item');
        }
    }

    // ============================================================================
    // HIERARCHY QUERIES - REAL DATA TESTS
    // ============================================================================

    @isTest
    static void test_getTransactionsByCorrelationId_returnsMultipleRecords() {
        // Arrange
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

            Test.startTest();
            List<UoWAuditTransaction__c> result = selector.getTransactionsByCorrelationId('CORR-SELECTOR-001');
            Test.stopTest();

            // Assert
            Assert.isNotNull(result, 'Should return list');
            Assert.areEqual(2, result.size(), 'Should find both transactions with same correlation ID');
        }
    }

    @isTest
    static void test_getCorrelationIdByTransactionId_returnsCorrelationId() {
        // Arrange
        UoWAuditTransaction__c txn = [SELECT Id FROM UoWAuditTransaction__c WHERE TransactionId__c = 'TXN-SELECTOR-001' LIMIT 1];
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

            Test.startTest();
            String result = selector.getCorrelationIdByTransactionId(txn.Id);
            Test.stopTest();

            // Assert
            Assert.areEqual('CORR-SELECTOR-001', result, 'Should return correct correlation ID');
        }
    }

    @isTest
    static void test_getRecentRootTransactions_returnsRootTransactions() {
        // Arrange
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

            Test.startTest();
            List<UoWAuditTransaction__c> result = selector.getRecentRootTransactions(10);
            Test.stopTest();

            // Assert
            Assert.isNotNull(result, 'Should return list');
            // Only root transactions (no parent) should be returned
            for (UoWAuditTransaction__c txn : result) {
                Assert.isNull(txn.ParentTransaction__c, 'Should only return root transactions');
            }
        }
    }

    // ============================================================================
    // ARCHIVAL QUERY LOCATOR TEST
    // ============================================================================

    @isTest
    static void test_getArchivableTransactionsLocator_returnsQueryLocator() {
        // Arrange
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();
        Date archivalDate = Date.today();

        // Act
        Test.startTest();
        Database.QueryLocator locator = selector.getArchivableTransactionsLocator(archivalDate);
        Test.stopTest();

        // Assert
        Assert.isNotNull(locator, 'Should return a QueryLocator');
    }

    // ============================================================================
    // ARCHIVE QUERIES - BIG OBJECT - NULL HANDLING
    // ============================================================================

    @isTest
    static void test_getArchiveByKey_blankCorrelationId_returnsNull() {
        // Arrange
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        // Act
        UoWAuditHistory__b result = selector.getArchiveByKey('', 1, DateTime.now());

        // Assert
        Assert.isNull(result, 'Should return null for blank correlation ID');
    }

    @isTest
    static void test_getArchiveByKey_nullTimestamp_returnsNull() {
        // Arrange
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        // Act
        UoWAuditHistory__b result = selector.getArchiveByKey('CORR-001', 1, null);

        // Assert
        Assert.isNull(result, 'Should return null for null timestamp');
    }

    // ============================================================================
    // ARCHIVE QUERIES - BIG OBJECT - QUERY EXECUTION
    // ============================================================================

    @isTest
    static void test_getArchiveByKey_executesQueryWithValidParams() {
        // Arrange
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        // Act - Exercise the full SOQL path with valid parameters
        Test.startTest();
        try {
            UoWAuditHistory__b result = selector.getArchiveByKey(
                'CORR-NONEXISTENT', 1, DateTime.newInstance(2024, 6, 15, 12, 0, 0)
            );
            // No data exists, but query executed without error
            Assert.isNull(result, 'Should return null when no matching record exists');
        } catch (Exception e) {
            // Big Object queries may fail in test context
            Assert.isFalse(e.getMessage().contains('null'), 'Should not be a null pointer error');
        }
        Test.stopTest();
    }

    @isTest
    static void test_queryArchiveRecords_executesWithAllFilters() {
        // Arrange
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        // Act - Exercise the dynamic query builder with all filter paths
        Test.startTest();
        try {
            List<UoWAuditHistory__b> results = selector.queryArchiveRecords(
                'CORR-NONEXISTENT',
                Date.today().addDays(-30),
                Date.today(),
                DateTime.now().addDays(-1),
                10
            );
            Assert.isNotNull(results, 'Should return empty list');
            Assert.isTrue(results.isEmpty(), 'Should have no records');
        } catch (Exception e) {
            // Big Object queries may fail in test context
            Assert.isFalse(e.getMessage().contains('null'), 'Should not be a null pointer error');
        }
        Test.stopTest();
    }

    @isTest
    static void test_queryArchiveRecords_executesWithMinimalFilters() {
        // Arrange - Only date range, no correlationId or cursor
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        // Act
        Test.startTest();
        try {
            List<UoWAuditHistory__b> results = selector.queryArchiveRecords(
                null, Date.today().addDays(-7), Date.today(), null, 50
            );
            Assert.isNotNull(results, 'Should return list');
        } catch (Exception e) {
            // Big Object queries may fail in test context
            Assert.isFalse(e.getMessage().contains('null'), 'Should not be a null pointer error');
        }
        Test.stopTest();
    }

    // ============================================================================
    // RECORD INDEX QUERIES (REVERSE LOOKUP)
    // ============================================================================

    @isTest
    static void test_getAuditActivityByRecordId_nullId_returnsEmpty() {
        Test.startTest();
        List<UoWAuditRecordIndex__c> result =
            UoWAuditDataSelector.getInstance().getAuditActivityByRecordId(null, 50);
        Test.stopTest();
        Assert.areEqual(0, result.size(), 'Null record Id should return empty list');
    }

    @isTest
    static void test_getAuditActivityByRecordId_returnsRowsMostRecentFirst() {
        // Arrange - two work items touching the same record at different times
        String recId = '001000000000777AAA';
        UoWAuditTransaction__c txn = new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-IDX-SEL-1',
            CorrelationId__c = 'CORR-IDX-SEL-1',
            TransactionStatus__c = 'SUCCESS',
            StartTime__c = DateTime.now().addMinutes(-2),
            EndTime__c = DateTime.now()
        );
        insert txn;

        UoWAuditWorkItem__c wi = new UoWAuditWorkItem__c(
            AuditTransaction__c = txn.Id, Name = 'WI-IDX-1',
            WorkType__c = 'DML', WorkItemStatus__c = 'SUCCESS',
            SObjectType__c = 'Account', DmlOperation__c = 'INSERT_OP'
        );
        insert wi;

        insert new List<UoWAuditRecordIndex__c>{
            new UoWAuditRecordIndex__c(
                AuditWorkItem__c = wi.Id, RecordId__c = recId,
                SObjectType__c = 'Account', Operation__c = 'INSERT',
                Timestamp__c = DateTime.now().addMinutes(-10)
            ),
            new UoWAuditRecordIndex__c(
                AuditWorkItem__c = wi.Id, RecordId__c = recId,
                SObjectType__c = 'Account', Operation__c = 'UPDATE',
                Timestamp__c = DateTime.now()
            ),
            // A different record - should be excluded
            new UoWAuditRecordIndex__c(
                AuditWorkItem__c = wi.Id, RecordId__c = '001000000000888AAA',
                SObjectType__c = 'Account', Operation__c = 'INSERT',
                Timestamp__c = DateTime.now()
            )
        };

        // Act
        User testUser = getAuditAdminUser();
        List<UoWAuditRecordIndex__c> result;
        System.runAs(testUser) {
            Test.startTest();
            result = UoWAuditDataSelector.getInstance().getAuditActivityByRecordId(recId, 50);
            Test.stopTest();
        }

        // Assert
        Assert.areEqual(2, result.size(), 'Should return only rows for the requested record');
        Assert.areEqual('UPDATE', result[0].Operation__c, 'Most recent row should be first');
        Assert.areEqual('INSERT', result[1].Operation__c, 'Older row should be second');
        Assert.areEqual('WI-IDX-1', result[0].AuditWorkItem__r.Name, 'Parent work item should be traversed');
    }

    @isTest
    static void test_getAuditActivityByRecordId_respectsLimit() {
        // Arrange - three rows for one record
        String recId = '001000000000999AAA';
        UoWAuditTransaction__c txn = new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-IDX-SEL-2', CorrelationId__c = 'CORR-IDX-SEL-2',
            TransactionStatus__c = 'SUCCESS', StartTime__c = DateTime.now(), EndTime__c = DateTime.now()
        );
        insert txn;
        UoWAuditWorkItem__c wi = new UoWAuditWorkItem__c(
            AuditTransaction__c = txn.Id, Name = 'WI-IDX-2',
            WorkType__c = 'DML', WorkItemStatus__c = 'SUCCESS', SObjectType__c = 'Account'
        );
        insert wi;
        List<UoWAuditRecordIndex__c> rows = new List<UoWAuditRecordIndex__c>();
        for (Integer i = 0; i < 3; i++) {
            rows.add(new UoWAuditRecordIndex__c(
                AuditWorkItem__c = wi.Id, RecordId__c = recId,
                SObjectType__c = 'Account', Operation__c = 'INSERT',
                Timestamp__c = DateTime.now().addSeconds(-i)
            ));
        }
        insert rows;

        // Act
        User testUser = getAuditAdminUser();
        List<UoWAuditRecordIndex__c> result;
        System.runAs(testUser) {
            result = UoWAuditDataSelector.getInstance().getAuditActivityByRecordId(recId, 2);
        }

        // Assert
        Assert.areEqual(2, result.size(), 'Should respect the query limit');
    }
}
