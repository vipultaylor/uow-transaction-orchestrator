//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Tests for Flow invocable actions in UoW framework.
 * Covers complete Flow integration pattern (Initialize → Register → Commit),
 * all DML operations, communication (email, notification, event),
 * integration (callout, flow), relationships, and error handling.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Tests
 * @see UoWFlowInitializeAction
 * @see UoWFlowCommitAction
 * @see UoWFlowTransactionRegistry
 */
@isTest
@SuppressWarnings('PMD.MethodNamingConventions')
private class UoWFlowActionsTests {
    // ============================================================================
    // TEST SETUP
    // ============================================================================

    @TestSetup
    static void setupTestData() {
        // Load test configurations
        UoWTestHelpers.loadTestConfigurations();
    }

    // ============================================================================
    // LIFECYCLE TESTS
    // ============================================================================

    @isTest
    static void test_initializeAndCommit_succeeds() {
        // Arrange - Initialize transaction with mocks
        UoWFlowInitializeAction.InitializeRequest initRequest = new UoWFlowInitializeAction.InitializeRequest();
        initRequest.configurationName = 'TestConfigAllMocks';
        initRequest.isDryRun = false;
        initRequest.scenarioName = 'InitializeAndCommitTest';
        initRequest.description = 'Test transaction for initialize and commit';

        // Act - Initialize
        Test.startTest();
        List<UoWFlowInitializeAction.InitializeResult> initResults =
            UoWFlowInitializeAction.initialize(new List<UoWFlowInitializeAction.InitializeRequest>{ initRequest });

        // Assert - Initialize succeeded
        Assert.areEqual(1, initResults.size(), 'Should return 1 result');
        UoWFlowInitializeAction.InitializeResult initResult = initResults[0];
        Assert.isTrue(initResult.success, 'Initialize should succeed');
        Assert.isNotNull(initResult.transactionId, 'Should return transaction ID');

        // Configure mock DML strategy for org-independent testing
        UnitOfWork uow = UoWFlowTransactionRegistry.get(initResult.transactionId);
        UoWTestMocks.MockDmlStrategy mockStrategy = new UoWTestMocks.MockDmlStrategy();
        uow.withDmlStrategy(Account.SObjectType, mockStrategy);

        // Register a simple insert to avoid empty transaction issues
        Account acc = UoWCoreTestDataFactory.createAccount('Test Account');
        UoWFlowRegisterInsertAction.RegistrationRequest insertRequest =
            new UoWFlowRegisterInsertAction.RegistrationRequest();
        insertRequest.transactionId = initResult.transactionId;
        insertRequest.records = new List<SObject>{ acc };

        List<UoWFlowRegisterInsertAction.RegistrationResult> insertResults =
            UoWFlowRegisterInsertAction.registerInsert(
                new List<UoWFlowRegisterInsertAction.RegistrationRequest>{ insertRequest }
            );

        Assert.isTrue(insertResults[0].success, 'Insert registration should succeed');

        // Act - Commit transaction
        UoWFlowCommitAction.CommitResult commitResult = UoWFlowTestHelpers.commitTransaction(initResult.transactionId);
        Test.stopTest();

        // Assert - Commit succeeded
        Assert.isTrue(commitResult.success, 'Commit should succeed. Error: ' + commitResult.errorSummary);
        Assert.isNotNull(commitResult.correlationId, 'Should have correlation ID');
        Assert.areEqual(UoWEnums.TransactionStatus.SUCCESS.name(), commitResult.transactionStatus, 'Status should be SUCCESS');
        Assert.areEqual(1, commitResult.dmlInserts, 'Should have 1 insert');
        UoWTestHelpers.assertHasId(acc);  // Mock assigns fake IDs
    }

    @isTest
    static void test_initialize_withAllParameters_succeeds() {
        // Arrange
        UoWFlowInitializeAction.InitializeRequest request = new UoWFlowInitializeAction.InitializeRequest();
        request.configurationName = 'TestConfigAllMocks';
        request.isDryRun = true;
        request.agentId = 'test-agent';
        request.agentName = 'Test Agent';
        request.modelId = 'gpt-4';
        request.confidenceScore = 0.95;
        request.intent = 'Test Intent';

        // Act
        Test.startTest();
        List<UoWFlowInitializeAction.InitializeResult> results =
            UoWFlowInitializeAction.initialize(new List<UoWFlowInitializeAction.InitializeRequest>{ request });
        Test.stopTest();

        // Assert
        Assert.isTrue(results[0].success, 'Initialize with all parameters should succeed');
        Assert.isNotNull(results[0].transactionId, 'Should return transaction ID');
    }

    @isTest
    static void test_initialize_withInvalidConfig_failsFast() {
        // Arrange
        UoWFlowInitializeAction.InitializeRequest request = new UoWFlowInitializeAction.InitializeRequest();
        request.configurationName = 'NonExistentConfig';

        // Act
        Test.startTest();
        List<UoWFlowInitializeAction.InitializeResult> results =
            UoWFlowInitializeAction.initialize(new List<UoWFlowInitializeAction.InitializeRequest>{ request });
        Test.stopTest();

        // Assert - Should fail fast with clear error message (fail-fast principle)
        Assert.areEqual(1, results.size(), 'Should have a single result instance');
        Assert.isFalse(results[0].success, 'Should fail for invalid config (fail-fast)');
        Assert.isNull(results[0].transactionId, 'Should not return transaction ID on failure');
        Assert.isTrue(results[0].message.containsIgnoreCase('NonExistentConfig'), 'Error message should mention invalid config name');
    }

    // ============================================================================
    // DML TESTS - INSERT
    // ============================================================================

    @isTest
    static void test_registerInsert_singleRecord_succeeds() {
        // Arrange - Initialize transaction with mocks
        String transactionId = UoWFlowTestHelpers.initializeTransaction();

        // Create test account
        Account acc = UoWCoreTestDataFactory.createAccount('Test Account');

        // Register insert
        UoWFlowRegisterInsertAction.RegistrationRequest insertRequest =
            UoWFlowTestHelpers.buildRegisterInsertRequest(transactionId, new List<SObject>{ acc });

        // Act
        Test.startTest();
        List<UoWFlowRegisterInsertAction.RegistrationResult> insertResults =
            UoWFlowRegisterInsertAction.registerInsert(
                new List<UoWFlowRegisterInsertAction.RegistrationRequest>{ insertRequest }
            );

        // Commit
        UoWFlowCommitAction.CommitResult commitResult = UoWFlowTestHelpers.commitTransaction(transactionId);
        Test.stopTest();

        // Assert - Registration succeeded
        Assert.areEqual(1, insertResults.size(), 'Should return 1 result');
        Assert.isTrue(insertResults[0].success, 'Insert registration should succeed');
        Assert.isNotNull(insertResults[0].workItemId, 'Should return work item ID');

        // Assert - Commit succeeded with statistics
        Assert.isTrue(commitResult.success, 'Commit should succeed. Error: ' + commitResult.errorSummary);
        Assert.areEqual(1, commitResult.dmlInserts, 'Should have 1 insert');
        Assert.areEqual(1, commitResult.totalRecordsProcessed, 'Should process 1 record');

        // Verify record has ID (mock assigns fake IDs)
        UoWTestHelpers.assertHasId(acc);
    }

    @isTest
    static void test_registerInsert_withoutTransactionId_fails() {
        // Arrange
        UoWFlowRegisterInsertAction.RegistrationRequest request =
            UoWFlowTestHelpers.buildRegisterInsertRequest(null, new List<SObject>{ UoWCoreTestDataFactory.createAccount('Test') });

        // Act
        Test.startTest();
        List<UoWFlowRegisterInsertAction.RegistrationResult> results =
            UoWFlowRegisterInsertAction.registerInsert(
                new List<UoWFlowRegisterInsertAction.RegistrationRequest>{ request }
            );
        Test.stopTest();

        // Assert
        Assert.isFalse(results[0].success, 'Should fail without transaction ID');
        Assert.isNotNull(results[0].message, 'Should have error message');
    }

    @isTest
    static void test_registerInsert_withEmptyRecords_fails() {
        // Arrange
        String transactionId = UoWFlowTestHelpers.initializeTransaction();

        UoWFlowRegisterInsertAction.RegistrationRequest request =
            UoWFlowTestHelpers.buildRegisterInsertRequest(transactionId, new List<SObject>()); // Empty list

        // Act
        Test.startTest();
        List<UoWFlowRegisterInsertAction.RegistrationResult> results =
            UoWFlowRegisterInsertAction.registerInsert(
                new List<UoWFlowRegisterInsertAction.RegistrationRequest>{ request }
            );
        Test.stopTest();

        // Assert
        Assert.isFalse(results[0].success, 'Should fail with empty records');
    }

    @isTest
    static void test_registerInsert_withInvalidRelationshipField_fails() {
        // Arrange
        String transactionId = UoWFlowTestHelpers.initializeTransaction();

        // Register parent
        Account acc = UoWCoreTestDataFactory.createAccount('Parent');
        UoWFlowRegisterInsertAction.RegistrationRequest parentRequest =
            UoWFlowTestHelpers.buildRegisterInsertRequest(transactionId, new List<SObject>{ acc });

        List<UoWFlowRegisterInsertAction.RegistrationResult> parentResults =
            UoWFlowRegisterInsertAction.registerInsert(
                new List<UoWFlowRegisterInsertAction.RegistrationRequest>{ parentRequest }
            );

        // Register child with invalid relationship field
        Contact con = UoWCoreTestDataFactory.createContact('Child', null);
        UoWFlowRegisterInsertAction.RegistrationRequest childRequest =
            UoWFlowTestHelpers.buildRegisterInsertRequest(transactionId, new List<SObject>{ con });
        childRequest.parentWorkItemId = parentResults[0].workItemId;
        childRequest.relationshipField = 'InvalidField__c'; // Invalid field

        // Act
        Test.startTest();
        List<UoWFlowRegisterInsertAction.RegistrationResult> childResults =
            UoWFlowRegisterInsertAction.registerInsert(
                new List<UoWFlowRegisterInsertAction.RegistrationRequest>{ childRequest }
            );
        Test.stopTest();

        // Assert - Registration should fail with invalid field (fail-fast validation)
        Assert.isFalse(childResults[0].success, 'Registration should fail with invalid field');
        Assert.isNotNull(childResults[0].message, 'Should have error message');
        Assert.isTrue(childResults[0].message.containsIgnoreCase('InvalidField__c'), 'Error should mention the invalid field');
    }

    @isTest
    static void test_registerInsert_withInvalidParentWorkItemId_fails() {
        // Arrange
        String transactionId = UoWFlowTestHelpers.initializeTransaction();

        Contact con = UoWCoreTestDataFactory.createContact('Child', null);
        UoWFlowRegisterInsertAction.RegistrationRequest request =
            UoWFlowTestHelpers.buildRegisterInsertRequest(transactionId, new List<SObject>{ con });
        request.parentWorkItemId = 'INVALID-WORK-ID';
        request.relationshipField = 'AccountId';

        // Act
        Test.startTest();
        List<UoWFlowRegisterInsertAction.RegistrationResult> results =
            UoWFlowRegisterInsertAction.registerInsert(
                new List<UoWFlowRegisterInsertAction.RegistrationRequest>{ request }
            );
        Test.stopTest();

        // Assert
        Assert.isFalse(results[0].success, 'Should fail with invalid parent work item ID');
        Assert.isNotNull(results[0].message, 'Should have error message');
    }

    // ============================================================================
    // DML TESTS - UPSERT
    // ============================================================================

    @isTest
    static void test_registerUpsert_insertsNewRecord() {
        // Arrange - Use mocks for org-independent testing
        String transactionId = UoWFlowTestHelpers.initializeTransaction();

        Account acc = UoWCoreTestDataFactory.createAccount('New Account');
        // No ID = insert

        UoWFlowRegisterUpsertAction.RegistrationRequest upsertRequest =
            UoWFlowTestHelpers.buildRegisterUpsertRequest(transactionId, new List<SObject>{ acc });

        // Act
        Test.startTest();
        List<UoWFlowRegisterUpsertAction.RegistrationResult> upsertResults =
            UoWFlowRegisterUpsertAction.registerUpsert(
                new List<UoWFlowRegisterUpsertAction.RegistrationRequest>{ upsertRequest }
            );

        UoWFlowCommitAction.CommitResult commitResult = UoWFlowTestHelpers.commitTransaction(transactionId);
        Test.stopTest();

        // Assert
        Assert.isTrue(upsertResults[0].success, 'Upsert registration should succeed');
        Assert.isTrue(commitResult.success, 'Commit should succeed. Error: ' + commitResult.errorSummary);
        Assert.areEqual(1, commitResult.totalRecordsProcessed, 'Should process 1 record');
        UoWTestHelpers.assertHasId(acc);  // Mock assigns fake IDs
    }

    @isTest
    static void test_registerUpsert_withParentRelationship_succeeds() {
        // Arrange - Use mocks for org-independent testing
        String transactionId = UoWFlowTestHelpers.initializeTransaction();

        Account parentAcc = UoWCoreTestDataFactory.createAccount('Parent Account');
        Opportunity opp = UoWCoreTestDataFactory.createOpportunity('Test Opportunity', null);

        // Register parent insert
        UoWFlowRegisterInsertAction.RegistrationRequest parentRequest =
            UoWFlowTestHelpers.buildRegisterInsertRequest(transactionId, new List<SObject>{ parentAcc });

        List<UoWFlowRegisterInsertAction.RegistrationResult> parentResults =
            UoWFlowRegisterInsertAction.registerInsert(
                new List<UoWFlowRegisterInsertAction.RegistrationRequest>{ parentRequest }
            );

        String parentWorkItemId = parentResults[0].workItemId;

        // Register child upsert with relationship
        UoWFlowRegisterUpsertAction.RegistrationRequest childRequest =
            UoWFlowTestHelpers.buildRegisterUpsertRequest(transactionId, new List<SObject>{ opp });
        childRequest.parentWorkItemId = parentWorkItemId;
        childRequest.relationshipField = 'AccountId';

        // Act
        Test.startTest();
        List<UoWFlowRegisterUpsertAction.RegistrationResult> childResults =
            UoWFlowRegisterUpsertAction.registerUpsert(
                new List<UoWFlowRegisterUpsertAction.RegistrationRequest>{ childRequest }
            );

        UoWFlowCommitAction.CommitResult commitResult = UoWFlowTestHelpers.commitTransaction(transactionId);
        Test.stopTest();

        // Assert
        Assert.isTrue(childResults[0].success, 'Upsert registration should succeed');
        Assert.isTrue(commitResult.success, 'Commit should succeed. Error: ' + commitResult.errorSummary);
        Assert.areEqual(1, commitResult.dmlInserts, 'Should have 1 insert (parent)');
        Assert.areEqual(2, commitResult.totalRecordsProcessed, 'Should process 2 records total');

        // Verify relationship - mocks assign fake IDs and resolve relationships
        UoWTestHelpers.assertHasId(parentAcc);
        UoWTestHelpers.assertHasId(opp);
        Assert.areEqual(parentAcc.Id, opp.AccountId, 'Opportunity should be linked to Account');
    }

    @isTest
    static void test_registerUpsert_withParentButNoRelationshipField_fails() {
        // Arrange
        String transactionId = UoWFlowTestHelpers.initializeTransaction();

        // Register parent
        Account parentAcc = UoWCoreTestDataFactory.createAccount('Parent');
        UoWFlowRegisterInsertAction.RegistrationRequest parentRequest =
            UoWFlowTestHelpers.buildRegisterInsertRequest(transactionId, new List<SObject>{ parentAcc });

        List<UoWFlowRegisterInsertAction.RegistrationResult> parentResults =
            UoWFlowRegisterInsertAction.registerInsert(
                new List<UoWFlowRegisterInsertAction.RegistrationRequest>{ parentRequest }
            );

        // Register upsert with parentWorkItemId but NO relationshipField
        Opportunity opp = UoWCoreTestDataFactory.createOpportunity('Test Opportunity', null);
        UoWFlowRegisterUpsertAction.RegistrationRequest childRequest =
            UoWFlowTestHelpers.buildRegisterUpsertRequest(transactionId, new List<SObject>{ opp });
        childRequest.parentWorkItemId = parentResults[0].workItemId;
        // Missing: childRequest.relationshipField = 'AccountId';

        // Act
        Test.startTest();
        List<UoWFlowRegisterUpsertAction.RegistrationResult> childResults =
            UoWFlowRegisterUpsertAction.registerUpsert(
                new List<UoWFlowRegisterUpsertAction.RegistrationRequest>{ childRequest }
            );
        Test.stopTest();

        // Assert
        Assert.isFalse(childResults[0].success, 'Should fail without relationship field');
        Assert.isNotNull(childResults[0].message, 'Should have error message');
        Assert.isTrue(childResults[0].message.containsIgnoreCase('Relationship Field'),
                      'Error should mention Relationship Field is required');
    }

    @isTest
    static void test_registerUpsert_withoutExternalIdField_fails() {
        // Arrange
        String transactionId = UoWFlowTestHelpers.initializeTransaction();

        UoWFlowRegisterUpsertAction.RegistrationRequest request =
            UoWFlowTestHelpers.buildRegisterUpsertRequest(transactionId, new List<SObject>{ UoWCoreTestDataFactory.createAccount('Test') });
        request.externalIdField = null; // Missing required field

        Test.startTest();
        List<UoWFlowRegisterUpsertAction.RegistrationResult> results =
            UoWFlowRegisterUpsertAction.registerUpsert(
                new List<UoWFlowRegisterUpsertAction.RegistrationRequest>{ request }
            );
        Test.stopTest();

        // Assert
        Assert.isFalse(results[0].success, 'Should fail without external ID field');
        Assert.isNotNull(results[0].message, 'Should have error message');
    }

    // ============================================================================
    // DML TESTS - UPDATE
    // ============================================================================

    @isTest
    static void test_registerUpdate_succeeds() {
        // Arrange - Create record with fake ID (no real DML)
        Account acc = UoWCoreTestDataFactory.createExistingAccount('Original Name');

        // Initialize transaction with mocks
        String transactionId = UoWFlowTestHelpers.initializeTransaction();

        // Modify record
        acc.Name = 'Updated Name';

        // Register update
        UoWFlowRegisterUpdateAction.RegistrationRequest updateRequest = 
            UoWFlowTestHelpers.buildRegisterUpdateRequest(transactionId, new List<SObject>{ acc });

        // Act
        Test.startTest();
        List<UoWFlowRegisterUpdateAction.RegistrationResult> updateResults =
            UoWFlowRegisterUpdateAction.registerUpdate(
                new List<UoWFlowRegisterUpdateAction.RegistrationRequest>{ updateRequest }
            );

        UoWFlowCommitAction.CommitResult commitResult = UoWFlowTestHelpers.commitTransaction(transactionId);
        Test.stopTest();

        // Assert
        Assert.isTrue(updateResults[0].success, 'Update registration should succeed');
        Assert.isTrue(commitResult.success, 'Commit should succeed. Error: ' + commitResult.errorSummary);
        Assert.areEqual(1, commitResult.dmlUpdates, 'Should have 1 update');

        // Verify mock processed update (no real SOQL query)
        Assert.isNotNull(acc.Id, 'Account should still have ID after update');
    }

    @isTest
    static void test_registerUpdate_withoutTransactionId_fails() {
        // Arrange
        UoWFlowRegisterUpdateAction.RegistrationRequest request =
            UoWFlowTestHelpers.buildRegisterUpdateRequest(null, new List<SObject>{ UoWCoreTestDataFactory.createAccount('Test') });

        // Act
        Test.startTest();
        List<UoWFlowRegisterUpdateAction.RegistrationResult> results =
            UoWFlowRegisterUpdateAction.registerUpdate(
                new List<UoWFlowRegisterUpdateAction.RegistrationRequest>{ request }
            );
        Test.stopTest();

        // Assert
        Assert.isFalse(results[0].success, 'Should fail without transaction ID');
        Assert.isNotNull(results[0].message, 'Should have error message');
    }

    @isTest
    static void test_registerUpdate_withoutRecordId_fails() {
        // Arrange - Create record with fake ID (no real DML)
        Account acc = UoWCoreTestDataFactory.createAccount('Original Name');

        // Initialize transaction with mocks
        String transactionId = UoWFlowTestHelpers.initializeTransaction();

        // Modify record
        acc.Name = 'Updated Name';

        // Register update
        UoWFlowRegisterUpdateAction.RegistrationRequest updateRequest =
            UoWFlowTestHelpers.buildRegisterUpdateRequest(transactionId, new List<SObject>{ acc });

        // Act
        Test.startTest();
        List<UoWFlowRegisterUpdateAction.RegistrationResult> updateResults =
            UoWFlowRegisterUpdateAction.registerUpdate(
                new List<UoWFlowRegisterUpdateAction.RegistrationRequest>{ updateRequest }
            );
        Test.stopTest();

        // Assert
        Assert.areEqual(1, updateResults.size(), 'Update registration should return 1 result');
        UoWFlowRegisterUpdateAction.RegistrationResult updateResult = updateResults[0];
        Assert.isFalse(updateResult.success, 'Update registration should fail');
        Assert.isTrue(updateResult.message.containsIgnoreCase('Cannot update records without Id field'), 'Should have returned a no id error on update registration');
    }

    // ============================================================================
    // DML TESTS - DELETE
    // ============================================================================

    @isTest
    static void test_registerDelete_succeeds() {
        // Arrange - Create record with fake ID (no real DML)
        Account acc = UoWCoreTestDataFactory.createExistingAccount('To Delete');

        String transactionId = UoWFlowTestHelpers.initializeTransaction();

        // Register delete
        UoWFlowRegisterDeleteAction.RegistrationRequest deleteRequest =
            UoWFlowTestHelpers.buildRegisterDeleteRequest(transactionId, new List<SObject>{ acc });

        // Act
        Test.startTest();
        List<UoWFlowRegisterDeleteAction.RegistrationResult> deleteResults =
            UoWFlowRegisterDeleteAction.registerDelete(
                new List<UoWFlowRegisterDeleteAction.RegistrationRequest>{ deleteRequest }
            );

        UoWFlowCommitAction.CommitResult commitResult = UoWFlowTestHelpers.commitTransaction(transactionId);
        Test.stopTest();

        // Assert
        Assert.isTrue(deleteResults[0].success, 'Delete registration should succeed');
        Assert.isTrue(commitResult.success, 'Commit should succeed. Error: ' + commitResult.errorSummary);
        Assert.areEqual(1, commitResult.dmlDeletes, 'Should have 1 delete');

        // Verify mock processed delete (no real SOQL query)
        Assert.isNotNull(acc.Id, 'Account should have ID (mocks don\'t modify records)');
    }

    @isTest
    static void test_registerDelete_withoutTransactionId_fails() {
        // Arrange
        UoWFlowRegisterDeleteAction.RegistrationRequest request =
            UoWFlowTestHelpers.buildRegisterDeleteRequest(null, new List<SObject>{ UoWCoreTestDataFactory.createAccount('Test') });

        // Act
        Test.startTest();
        List<UoWFlowRegisterDeleteAction.RegistrationResult> results =
            UoWFlowRegisterDeleteAction.registerDelete(
                new List<UoWFlowRegisterDeleteAction.RegistrationRequest>{ request }
            );
        Test.stopTest();

        // Assert
        Assert.isFalse(results[0].success, 'Should fail without transaction ID');
        Assert.isNotNull(results[0].message, 'Should have error message');
    }

    @isTest
    static void test_registerDelete_withoutRecordId_fails() {
        // Arrange - Create record with fake ID (no real DML)
        Account acc = UoWCoreTestDataFactory.createAccount('To Delete');

        String transactionId = UoWFlowTestHelpers.initializeTransaction();

        // Register delete
        UoWFlowRegisterDeleteAction.RegistrationRequest deleteRequest =
            UoWFlowTestHelpers.buildRegisterDeleteRequest(transactionId, new List<SObject>{ acc });

        // Act
        Test.startTest();
        List<UoWFlowRegisterDeleteAction.RegistrationResult> deleteResults =
            UoWFlowRegisterDeleteAction.registerDelete(
                new List<UoWFlowRegisterDeleteAction.RegistrationRequest>{ deleteRequest }
            );
        Test.stopTest();

        // Assert
        Assert.areEqual(1, deleteResults.size(), 'Delete registration should return 1 result');
        UoWFlowRegisterDeleteAction.RegistrationResult deleteResult = deleteResults[0];
        Assert.isFalse(deleteResult.success, 'Delete registration should fail');
        Assert.isTrue(deleteResult.message.containsIgnoreCase('Cannot delete records without Id field'), 'Should have returned a no id error on delete registration');
    }

    // ============================================================================
    // DML TESTS - UNDELETE
    // ============================================================================

    @isTest
    static void test_registerUndelete_succeeds() {
        // Arrange - Mock deleted record (no real DML)
        Account acc = UoWCoreTestDataFactory.createAccount('To Undelete');
        acc.Id = UoWTestHelpers.generateFakeId(Account.SObjectType, 1);  // Mock existing deleted record

        String transactionId = UoWFlowTestHelpers.initializeTransaction();

        // Build request
        UoWFlowRegisterUndeleteAction.RegistrationRequest undeleteRequest =
            UoWFlowTestHelpers.buildRegisterUndeleteRequest(transactionId, new List<SObject>{ acc });

        // Act
        Test.startTest();
        List<UoWFlowRegisterUndeleteAction.RegistrationResult> undeleteResults =
            UoWFlowRegisterUndeleteAction.registerUndelete(
                new List<UoWFlowRegisterUndeleteAction.RegistrationRequest>{ undeleteRequest }
            );

        UoWFlowCommitAction.CommitResult commitResult = UoWFlowTestHelpers.commitTransaction(transactionId);
        Test.stopTest();

        // Assert
        Assert.isTrue(undeleteResults[0].success, 'Undelete registration should succeed');
        Assert.isTrue(commitResult.success, 'Commit should succeed. Error: ' + commitResult.errorSummary);
        Assert.areEqual(1, commitResult.totalRecordsProcessed, 'Should process 1 undelete');
        Assert.isNotNull(acc.Id, 'Account should still have ID after undelete');
    }

    @isTest
    static void test_registerUndelete_withoutTransactionId_fails() {
        // Arrange
        UoWFlowRegisterUndeleteAction.RegistrationRequest request =
            UoWFlowTestHelpers.buildRegisterUndeleteRequest(null, new List<SObject>{ UoWCoreTestDataFactory.createAccount('Test') });

        // Act
        Test.startTest();
        List<UoWFlowRegisterUndeleteAction.RegistrationResult> results =
            UoWFlowRegisterUndeleteAction.registerUndelete(
                new List<UoWFlowRegisterUndeleteAction.RegistrationRequest>{ request }
            );
        Test.stopTest();

        // Assert
        Assert.isFalse(results[0].success, 'Should fail without transaction ID');
        Assert.isNotNull(results[0].message, 'Should have error message');
    }

    @isTest
    static void test_registerUndelete_withoutRecordId_fails() {
        // Arrange - Mock deleted record (no real DML)
        Account acc = UoWCoreTestDataFactory.createAccount('To Undelete');

        String transactionId = UoWFlowTestHelpers.initializeTransaction();

        UoWFlowRegisterUndeleteAction.RegistrationRequest undeleteRequest =
            UoWFlowTestHelpers.buildRegisterUndeleteRequest(transactionId, new List<SObject>{ acc });

        // Act
        Test.startTest();
        List<UoWFlowRegisterUndeleteAction.RegistrationResult> undeleteResults =
            UoWFlowRegisterUndeleteAction.registerUndelete(
                new List<UoWFlowRegisterUndeleteAction.RegistrationRequest>{ undeleteRequest }
            );
        Test.stopTest();

        // Assert
        Assert.areEqual(1, undeleteResults.size(), 'Undelete registration should return 1 result');
        UoWFlowRegisterUndeleteAction.RegistrationResult undeleteResult = undeleteResults[0];
        Assert.isFalse(undeleteResult.success, 'Undelete registration should fail');
        Assert.isTrue(undeleteResult.message.containsIgnoreCase('Cannot undelete records without Id field'), 'Should have returned a no id error on undelete registration');
    }

    // ============================================================================
    // RELATIONSHIP TESTS
    // ============================================================================

    @isTest
    static void test_parentChildRelationship_viaWorkItemIds_succeeds() {
        // Arrange - Use mocks for org-independent testing
        String transactionId = UoWFlowTestHelpers.initializeTransaction();

        Account acc = UoWCoreTestDataFactory.createAccount('Parent Account');
        Contact con = UoWCoreTestDataFactory.createContact('Child Contact', null);

        // Register parent insert
        UoWFlowRegisterInsertAction.RegistrationRequest parentRequest =
            UoWFlowTestHelpers.buildRegisterInsertRequest(transactionId, new List<SObject>{ acc });

        List<UoWFlowRegisterInsertAction.RegistrationResult> parentResults =
            UoWFlowRegisterInsertAction.registerInsert(
                new List<UoWFlowRegisterInsertAction.RegistrationRequest>{ parentRequest }
            );

        String parentWorkItemId = parentResults[0].workItemId;

        // Register child insert with relationship
        UoWFlowRegisterInsertAction.RegistrationRequest childRequest =
            UoWFlowTestHelpers.buildRegisterInsertRequest(transactionId, new List<SObject>{ con });
        childRequest.parentWorkItemId = parentWorkItemId;
        childRequest.relationshipField = 'AccountId';

        // Act
        Test.startTest();
        List<UoWFlowRegisterInsertAction.RegistrationResult> childResults =
            UoWFlowRegisterInsertAction.registerInsert(
                new List<UoWFlowRegisterInsertAction.RegistrationRequest>{ childRequest }
            );

        UoWFlowCommitAction.CommitResult commitResult = UoWFlowTestHelpers.commitTransaction(transactionId);
        Test.stopTest();

        // Assert
        Assert.isTrue(childResults[0].success, 'Child registration should succeed');
        Assert.isTrue(commitResult.success, 'Commit should succeed. Error: ' + commitResult.errorSummary);
        Assert.areEqual(2, commitResult.dmlInserts, 'Should have 2 inserts');

        // Verify relationship - mocks assign fake IDs and resolve relationships
        UoWTestHelpers.assertHasId(acc);
        UoWTestHelpers.assertHasId(con);
        Assert.areEqual(acc.Id, con.AccountId, 'Contact should be linked to Account');
    }

    // ============================================================================
    // PLATFORM EVENT TESTS
    // ============================================================================

    @isTest
    static void test_registerPlatformEvent_succeeds() {
        // Arrange - Use mocks for org-independent testing
        String transactionId = UoWFlowTestHelpers.initializeTransaction();

        // Configure mock event channel
        UnitOfWork uow = UoWFlowTransactionRegistry.get(transactionId);
        UoWTestMocks.MockEventChannel mockEventChannel = new UoWTestMocks.MockEventChannel();
        uow.withEventChannel(mockEventChannel);

        // Use Account as mock platform event (SObject type)
        SObject mockEvent = new Account(Name = 'Test Event');

        UoWFlowRegisterPlatformEventAction.RegistrationRequest request =
            UoWFlowTestHelpers.buildRegisterPlatformEventRequest(transactionId, new List<SObject>{ mockEvent });

        // Act
        Test.startTest();
        List<UoWFlowRegisterPlatformEventAction.RegistrationResult> results =
            UoWFlowRegisterPlatformEventAction.registerPlatformEvent(
                new List<UoWFlowRegisterPlatformEventAction.RegistrationRequest>{ request }
            );

        UoWFlowCommitAction.CommitResult commitResult = UoWFlowTestHelpers.commitTransaction(transactionId);
        Test.stopTest();

        // Assert - Registration
        Assert.isTrue(results[0].success, 'Platform event registration should succeed');

        // Assert - Commit and execution
        Assert.isTrue(commitResult.success, 'Commit should succeed. Error: ' + commitResult.errorSummary);
        Assert.areEqual(1, commitResult.eventsPublished, 'Should publish 1 event');
    }

    @isTest
    static void test_registerPlatformEvent_withoutTransactionId_fails() {
        // Arrange
        SObject mockEvent = new Account(Name = 'Test Event');

        UoWFlowRegisterPlatformEventAction.RegistrationRequest request =
            UoWFlowTestHelpers.buildRegisterPlatformEventRequest(null, new List<SObject>{ mockEvent });

        // Act
        Test.startTest();
        List<UoWFlowRegisterPlatformEventAction.RegistrationResult> results =
            UoWFlowRegisterPlatformEventAction.registerPlatformEvent(
                new List<UoWFlowRegisterPlatformEventAction.RegistrationRequest>{ request }
            );
        Test.stopTest();

        // Assert
        Assert.isFalse(results[0].success, 'Should fail without transaction ID');
        Assert.isNotNull(results[0].message, 'Should have error message');
    }

    @isTest
    static void test_registerPlatformEvent_withInvalidPhase_fails() {
        // Arrange
        String transactionId = UoWFlowTestHelpers.initializeTransaction();
        SObject mockEvent = new Account(Name = 'Test Event');

        UoWFlowRegisterPlatformEventAction.RegistrationRequest request =
            UoWFlowTestHelpers.buildRegisterPlatformEventRequest(transactionId, new List<SObject>{ mockEvent });
        request.executionPhase = 'INVALID-PHASE';

        // Act
        Test.startTest();
        List<UoWFlowRegisterPlatformEventAction.RegistrationResult> results =
            UoWFlowRegisterPlatformEventAction.registerPlatformEvent(
                new List<UoWFlowRegisterPlatformEventAction.RegistrationRequest>{ request }
            );
        Test.stopTest();

        // Assert
        Assert.isFalse(results[0].success, 'Should fail without transaction ID');
        Assert.isNotNull(results[0].message, 'Should have error message');
        Assert.isTrue(results[0].message.containsIgnoreCase('Invalid work phase'), 'Should contain invalid work phase error message');
    }

    // ============================================================================
    // EMAIL TESTS
    // ============================================================================

    @isTest
    static void test_registerEmail_succeeds() {
        // Arrange
        String transactionId = UoWFlowTestHelpers.initializeTransaction();
        UnitOfWork uow = UoWFlowTransactionRegistry.get(transactionId);

        UoWFlowRegisterEmailAction.RegistrationRequest request =
            UoWFlowTestHelpers.buildRegisterEmailRequest(transactionId, 'test@example.com');

        // Act
        Test.startTest();
        List<UoWFlowRegisterEmailAction.RegistrationResult> emailResults =
            UoWFlowRegisterEmailAction.registerEmail(
                new List<UoWFlowRegisterEmailAction.RegistrationRequest>{ request }
            );

        UoWFlowCommitAction.CommitResult commitResult = UoWFlowTestHelpers.commitTransaction(transactionId);
        Test.stopTest();

        // Assert
        Assert.isTrue(emailResults[0].success, 'Email registration should succeed');
        Assert.isTrue(commitResult.success, 'Commit should succeed');
        Assert.areEqual(1, commitResult.emailsSent, 'Should have 1 email sent');
    }

    // NOTE: Template-based emails cannot be tested with registration or commit in org-independent tests
    // because Salesforce validates template IDs during Messaging.SingleEmailMessage construction.
    // TODO: Test it IF the framework adds an email template

    @isTest
    static void test_registerEmail_withoutTransactionId_fails() {
        // Arrange
        UoWFlowRegisterEmailAction.RegistrationRequest request =
            UoWFlowTestHelpers.buildRegisterEmailRequest(null, 'test@example.com');

        // Act
        Test.startTest();
        List<UoWFlowRegisterEmailAction.RegistrationResult> results =
            UoWFlowRegisterEmailAction.registerEmail(
                new List<UoWFlowRegisterEmailAction.RegistrationRequest>{ request }
            );
        Test.stopTest();

        // Assert
        Assert.isFalse(results[0].success, 'Should fail without transaction ID');
        Assert.isNotNull(results[0].message, 'Should have error message');
    }

    @isTest
    static void test_registerEmail_withoutRecipients_fails() {
        // Arrange
        String transactionId = UoWFlowTestHelpers.initializeTransaction();

        UoWFlowRegisterEmailAction.RegistrationRequest request =
            UoWFlowTestHelpers.buildRegisterEmailRequest(transactionId, null);

        // Act
        Test.startTest();
        List<UoWFlowRegisterEmailAction.RegistrationResult> results =
            UoWFlowRegisterEmailAction.registerEmail(
                new List<UoWFlowRegisterEmailAction.RegistrationRequest>{ request }
            );
        Test.stopTest();

        // Assert
        Assert.isFalse(results[0].success, 'Should fail without any recipients');
        Assert.isNotNull(results[0].message, 'Should have error message');
        Assert.isTrue(results[0].message.containsIgnoreCase('Either To Addresses or Email Template ID is required'), 'Should have missing recipients error message');
    }

    // ============================================================================
    // NOTIFICATION TESTS
    // ============================================================================

    @isTest
    static void test_registerNotification_succeeds() {
        // Arrange
        String transactionId = UoWFlowTestHelpers.initializeTransaction();
        UnitOfWork uow = UoWFlowTransactionRegistry.get(transactionId);

        UoWFlowRegisterNotificationAction.RegistrationRequest request =
            UoWFlowTestHelpers.buildRegisterNotificationRequest(transactionId);

        // Act
        Test.startTest();
        List<UoWFlowRegisterNotificationAction.RegistrationResult> notifResults =
            UoWFlowRegisterNotificationAction.registerNotification(
                new List<UoWFlowRegisterNotificationAction.RegistrationRequest>{ request }
            );

        UoWFlowCommitAction.CommitResult commitResult = UoWFlowTestHelpers.commitTransaction(transactionId);
        Test.stopTest();

        // Assert
        Assert.isTrue(notifResults[0].success, 'Notification registration should succeed');
        Assert.isTrue(commitResult.success, 'Commit should succeed');
        Assert.areEqual(1, commitResult.notificationsSent, 'Should have 1 notification sent');
    }

    @isTest
    static void test_registerNotification_withoutTransactionId_fails() {
        // Arrange
        UoWFlowRegisterNotificationAction.RegistrationRequest request =
            UoWFlowTestHelpers.buildRegisterNotificationRequest(null);

        // Act
        Test.startTest();
        List<UoWFlowRegisterNotificationAction.RegistrationResult> results =
            UoWFlowRegisterNotificationAction.registerNotification(
                new List<UoWFlowRegisterNotificationAction.RegistrationRequest>{ request }
            );
        Test.stopTest();

        // Assert
        Assert.isFalse(results[0].success, 'Should fail without transaction ID');
        Assert.isNotNull(results[0].message, 'Should have error message');
    }

    // ============================================================================
    // FLOW EXECUTION TESTS
    // ============================================================================

    @isTest
    static void test_registerFlowExecution_succeeds() {
        // Arrange - Use mocks for org-independent testing
        String transactionId = UoWFlowTestHelpers.initializeTransaction();

        // Configure mock flow channel
        UnitOfWork uow = UoWFlowTransactionRegistry.get(transactionId);
        UoWTestMocks.MockFlowChannel mockFlowChannel = new UoWTestMocks.MockFlowChannel();
        uow.withFlowChannel(mockFlowChannel);

        UoWFlowRegisterFlowExecutionAction.RegistrationRequest request =
            UoWFlowTestHelpers.buildRegisterFlowExecutionRequest(transactionId,'MyAutolauchedFlow');

        // Act
        Test.startTest();
        List<UoWFlowRegisterFlowExecutionAction.RegistrationResult> results =
            UoWFlowRegisterFlowExecutionAction.registerFlowExecution(
                new List<UoWFlowRegisterFlowExecutionAction.RegistrationRequest>{ request }
            );

        UoWFlowCommitAction.CommitResult commitResult = UoWFlowTestHelpers.commitTransaction(transactionId);
        Test.stopTest();

        // Assert - Registration
        Assert.isTrue(results[0].success, 'Flow execution registration should succeed');

        // Assert - Commit and execution
        Assert.isTrue(commitResult.success, 'Commit should succeed. Error: ' + commitResult.errorSummary);
        Assert.areEqual(1, commitResult.flowsExecuted, 'Should execute 1 flow');
    }

    @isTest
    static void test_registerFlowExecution_withoutTransactionId_fails() {
        // Arrange
        UoWFlowRegisterFlowExecutionAction.RegistrationRequest request =
            UoWFlowTestHelpers.buildRegisterFlowExecutionRequest(null,'MyAutolauchedFlow');

        // Act
        Test.startTest();
        List<UoWFlowRegisterFlowExecutionAction.RegistrationResult> results =
            UoWFlowRegisterFlowExecutionAction.registerFlowExecution(
                new List<UoWFlowRegisterFlowExecutionAction.RegistrationRequest>{ request }
            );
        Test.stopTest();

        // Assert
        Assert.isFalse(results[0].success, 'Should fail without transaction ID');
        Assert.isNotNull(results[0].message, 'Should have error message');
    }

    @isTest
    static void test_registerFlowExecution_withoutFlowApiName_fails() {
        // Arrange
        String transactionId = UoWFlowTestHelpers.initializeTransaction();

        UoWFlowRegisterFlowExecutionAction.RegistrationRequest request =
            UoWFlowTestHelpers.buildRegisterFlowExecutionRequest(transactionId, null); // Missing flow API name

        // Act
        Test.startTest();
        List<UoWFlowRegisterFlowExecutionAction.RegistrationResult> results =
            UoWFlowRegisterFlowExecutionAction.registerFlowExecution(
                new List<UoWFlowRegisterFlowExecutionAction.RegistrationRequest>{ request }
            );
        Test.stopTest();

        // Assert
        Assert.isFalse(results[0].success, 'Should fail without flow API name');
        Assert.isNotNull(results[0].message, 'Should have error message');
    }

    // ============================================================================
    // CALLOUT TESTS
    // ============================================================================

    @isTest
    static void test_registerCallout_succeeds() {
        // Arrange - Use mocks for org-independent testing
        String transactionId = UoWFlowTestHelpers.initializeTransaction();

        // Configure mock HTTP callout
        UnitOfWork uow = UoWFlowTransactionRegistry.get(transactionId);

        UoWFlowRegisterCalloutAction.RegistrationRequest request =
            UoWFlowTestHelpers.buildRegisterCalloutRequest(transactionId,'callout:MyAPI/endpoint');

        // Act
        Test.startTest();
        List<UoWFlowRegisterCalloutAction.RegistrationResult> results =
            UoWFlowRegisterCalloutAction.registerCallout(
                new List<UoWFlowRegisterCalloutAction.RegistrationRequest>{ request }
            );

        UoWFlowCommitAction.CommitResult commitResult = UoWFlowTestHelpers.commitTransaction(transactionId);
        Test.stopTest();

        // Assert - Registration
        Assert.isTrue(results[0].success, 'Callout registration should succeed');

        // Assert - Commit and execution
        Assert.isTrue(commitResult.success, 'Commit should succeed. Error: ' + commitResult.errorSummary);
        Assert.areEqual(1, commitResult.calloutsMade, 'Should make 1 callout');
    }

    @isTest
    static void test_registerCallout_withoutTransactionId_fails() {
        // Arrange
        UoWFlowRegisterCalloutAction.RegistrationRequest request =
            UoWFlowTestHelpers.buildRegisterCalloutRequest(null, 'callout:MyAPI/endpoint');

        // Act
        Test.startTest();
        List<UoWFlowRegisterCalloutAction.RegistrationResult> results =
            UoWFlowRegisterCalloutAction.registerCallout(
                new List<UoWFlowRegisterCalloutAction.RegistrationRequest>{ request }
            );
        Test.stopTest();

        // Assert
        Assert.isFalse(results[0].success, 'Should fail without transaction ID');
        Assert.isNotNull(results[0].message, 'Should have error message');
    }

    @isTest
    static void test_registerCallout_withoutEndpoint_fails() {
        // Arrange
        String transactionId = UoWFlowTestHelpers.initializeTransaction();

        UoWFlowRegisterCalloutAction.RegistrationRequest request =
            UoWFlowTestHelpers.buildRegisterCalloutRequest(transactionId, null); // Missing endpoint

        // Act
        Test.startTest();
        List<UoWFlowRegisterCalloutAction.RegistrationResult> results =
            UoWFlowRegisterCalloutAction.registerCallout(
                new List<UoWFlowRegisterCalloutAction.RegistrationRequest>{ request }
            );
        Test.stopTest();

        // Assert
        Assert.isFalse(results[0].success, 'Should fail without endpoint');
        Assert.isNotNull(results[0].message, 'Should have error message');
    }

    // ============================================================================
    // COMMIT TESTS
    // ============================================================================

    @isTest
    static void test_commit_withSyncMode_succeeds() {
        // Arrange - Test that commit mode parameter is correctly parsed (use SYNC for testability)
        String transactionId = UoWFlowTestHelpers.initializeTransaction();

        // Get UnitOfWork and configure with mock strategy
        UnitOfWork uow = UoWFlowTransactionRegistry.get(transactionId);

        Account acc = UoWCoreTestDataFactory.createAccount('Sync Test');

        UoWFlowRegisterInsertAction.RegistrationRequest insertRequest =
            UoWFlowTestHelpers.buildRegisterInsertRequest(transactionId, new List<SObject>{ acc });

        UoWFlowRegisterInsertAction.registerInsert(
            new List<UoWFlowRegisterInsertAction.RegistrationRequest>{ insertRequest }
        );

        // Act - Test with explicit SYNC mode
        Test.startTest();
        UoWFlowCommitAction.CommitRequest commitRequest = new UoWFlowCommitAction.CommitRequest();
        commitRequest.transactionId = transactionId;
        commitRequest.commitMode = UoWEnums.CommitMode.SYNC.name();

        List<UoWFlowCommitAction.CommitResult> results =
            UoWFlowCommitAction.commitTransaction(new List<UoWFlowCommitAction.CommitRequest>{ commitRequest });
        Test.stopTest();

        // Assert - Framework processed SYNC commit
        Assert.isTrue(results[0].success, 'SYNC commit should succeed. Error: ' + results[0].errorSummary);
        Assert.areEqual(1, results[0].dmlInserts, 'Should report 1 insert');
        UoWTestHelpers.assertHasId(acc); // Mock assigns IDs
    }

    @isTest
    static void test_commit_withInvalidTransactionId_fails() {
        // Arrange
        UoWFlowCommitAction.CommitRequest request = new UoWFlowCommitAction.CommitRequest();
        request.transactionId = 'INVALID-ID';

        // Act
        Test.startTest();
        List<UoWFlowCommitAction.CommitResult> results =
            UoWFlowCommitAction.commitTransaction(new List<UoWFlowCommitAction.CommitRequest>{ request });
        Test.stopTest();

        // Assert
        Assert.areEqual(1, results.size(), 'Should return 1 result');
        Assert.isFalse(results[0].success, 'Should fail with invalid transaction ID');
        Assert.isNotNull(results[0].errorSummary, 'Should have error message');
    }

    @isTest
    static void test_commit_withInvalidCommitMode_fails() {
        // Arrange - Initialize transaction
        String transactionId = UoWFlowTestHelpers.initializeTransaction();
        UoWFlowCommitAction.CommitRequest request = new UoWFlowCommitAction.CommitRequest();
        request.transactionId = transactionId;
        request.commitMode = 'INVALID-MODE';

        // Act
        Test.startTest();
        List<UoWFlowCommitAction.CommitResult> results =
            UoWFlowCommitAction.commitTransaction(new List<UoWFlowCommitAction.CommitRequest>{ request });
        Test.stopTest();

        // Assert
        Assert.areEqual(1, results.size(), 'Should return 1 result');
        Assert.isFalse(results[0].success, 'Should fail with invalid commit mode');
        Assert.isNotNull(results[0].errorSummary, 'Should have error message');
        Assert.isTrue(results[0].errorSummary.containsIgnoreCase('Invalid commit mode'), 'Should have invalid commit mode error message');
    }

    // ============================================================================
    // COMPREHENSIVE ERROR HANDLING TESTS
    // ============================================================================

    @isTest
    static void test_allWorkTypes_mixedResults_partialSuccess() {
        // Arrange - Setup mocks and ChaosEngine for targeted failures
        String transactionId = UoWFlowTestHelpers.initializeTransaction();
        UnitOfWork uow = UoWFlowTransactionRegistry.get(transactionId);

        // Configure ChaosEngine for ALL work types to fail (except 1 DML insert)
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();

        // DML Insert: Partial failure - only first account succeeds
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_INSERT,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{1}, // Second account fails
                'Required field missing',
                System.StatusCode.REQUIRED_FIELD_MISSING
            )
        );

        // DML Update - all records fail (continueOnError=true, so no exception)
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_UPDATE,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{0}, // All records fail
                'Update validation failed',
                System.StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION
            )
        );

        // DML Delete - all records fail (continueOnError=true, so no exception)
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_DELETE,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{0}, // All records fail
                'Delete not allowed',
                System.StatusCode.DELETE_FAILED
            )
        );

        // DML Upsert - all records fail (continueOnError=true, so no exception)
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_UPSERT,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{0}, // All records fail
                'Upsert failed',
                System.StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION
            )
        );

        // DML Undelete - all records fail (continueOnError=true, so no exception)
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_UNDELETE,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{0}, // All records fail
                'Undelete not allowed',
                System.StatusCode.UNDELETE_FAILED
            )
        );

        // Platform Event: Always fail
        UoWChaosEngine.alwaysFail(
            UoWChaosEngine.Point.PLATFORM_EVENT_PUBLISH,
            new UoWExceptionService.UoWException('Event publishing failed')
        );

        // Flow: Always fail
        UoWChaosEngine.alwaysFail(
            UoWChaosEngine.Point.FLOW_INVOKE,
            new UoWExceptionService.UoWException('Flow execution failed')
        );

        // Email: Always fail
        UoWChaosEngine.alwaysFail(
            UoWChaosEngine.Point.EMAIL_SEND,
            new UoWExceptionService.UoWException('Email send failed')
        );

        // Notification: Always fail
        UoWChaosEngine.alwaysFail(
            UoWChaosEngine.Point.CUSTOM_NOTIFICATION_SEND,
            new UoWExceptionService.UoWException('Notification send failed')
        );

        // Callout: Always fail
        UoWChaosEngine.alwaysFail(
            UoWChaosEngine.Point.CALLOUT,
            new UoWExceptionService.UoWException('Callout failed')
        );

        // Register ALL work types with continueOnError()

        // 1. DML - Insert 2 accounts (1 succeeds, 1 fails)
        List<SObject> accounts = UoWCoreTestDataFactory.createAccounts(2);
        Account existingAccount = UoWCoreTestDataFactory.createExistingAccount('Existing Account');

        UoWFlowRegisterInsertAction.RegistrationRequest insertRequest =
            UoWFlowTestHelpers.buildRegisterInsertRequest(transactionId, accounts );
        insertRequest.continueOnError = true;

        UoWFlowRegisterInsertAction.registerInsert(
            new List<UoWFlowRegisterInsertAction.RegistrationRequest>{ insertRequest }
        );

        // 2. DML - Upsert
        UoWFlowRegisterUpsertAction.RegistrationRequest upsertRequest =
            UoWFlowTestHelpers.buildRegisterUpsertRequest(transactionId, new List<SObject>{ existingAccount });
        upsertRequest.continueOnError = true;

        UoWFlowRegisterUpsertAction.registerUpsert(
            new List<UoWFlowRegisterUpsertAction.RegistrationRequest>{ upsertRequest }
        );

        // 3. DML - Update
        UoWFlowRegisterUpdateAction.RegistrationRequest updateRequest =
            UoWFlowTestHelpers.buildRegisterUpdateRequest(transactionId, new List<SObject>{ existingAccount });
        updateRequest.continueOnError = true;

        UoWFlowRegisterUpdateAction.registerUpdate(
            new List<UoWFlowRegisterUpdateAction.RegistrationRequest>{ updateRequest }
        );

        // 4. DML - Delete
        UoWFlowRegisterDeleteAction.RegistrationRequest deleteRequest =
            UoWFlowTestHelpers.buildRegisterDeleteRequest(transactionId, new List<SObject>{ existingAccount });
        deleteRequest.continueOnError = true;

        UoWFlowRegisterDeleteAction.registerDelete(
            new List<UoWFlowRegisterDeleteAction.RegistrationRequest>{ deleteRequest }
        );

        // 5. DML - Undelete
        UoWFlowRegisterUndeleteAction.RegistrationRequest undeleteRequest =
            UoWFlowTestHelpers.buildRegisterUndeleteRequest(transactionId, new List<SObject>{ existingAccount });
        undeleteRequest.continueOnError = true;

        UoWFlowRegisterUndeleteAction.registerUndelete(
            new List<UoWFlowRegisterUndeleteAction.RegistrationRequest>{ undeleteRequest }
        );

        // 6. Platform Event
        SObject mockEvent = new Account(Name = 'Test Event');
        UoWFlowRegisterPlatformEventAction.RegistrationRequest eventRequest =
            UoWFlowTestHelpers.buildRegisterPlatformEventRequest(transactionId, new List<SObject>{ mockEvent });
        eventRequest.continueOnError = true;
        eventRequest.executionPhase = null;

        UoWFlowRegisterPlatformEventAction.registerPlatformEvent(
            new List<UoWFlowRegisterPlatformEventAction.RegistrationRequest>{ eventRequest }
        );

        // 7. Email
        UoWFlowRegisterEmailAction.RegistrationRequest emailRequest =
            UoWFlowTestHelpers.buildRegisterEmailRequest(transactionId, 'test@example.com');
        emailRequest.continueOnError = true;
        emailRequest.executionPhase = null;

        UoWFlowRegisterEmailAction.registerEmail(
            new List<UoWFlowRegisterEmailAction.RegistrationRequest>{ emailRequest }
        );

        // 8. Notification
        UoWFlowRegisterNotificationAction.RegistrationRequest notificationRequest =
            UoWFlowTestHelpers.buildRegisterNotificationRequest(transactionId);
        notificationRequest.continueOnError = true;
        notificationRequest.executionPhase = null;

        UoWFlowRegisterNotificationAction.registerNotification(
            new List<UoWFlowRegisterNotificationAction.RegistrationRequest>{ notificationRequest }
        );

        // 9. Flow Execution
        UoWFlowRegisterFlowExecutionAction.RegistrationRequest flowRequest =
            UoWFlowTestHelpers.buildRegisterFlowExecutionRequest(transactionId,'TestFlow');
        flowRequest.continueOnError = true;
        flowRequest.executionPhase = null;

        UoWFlowRegisterFlowExecutionAction.registerFlowExecution(
            new List<UoWFlowRegisterFlowExecutionAction.RegistrationRequest>{ flowRequest }
        );

        // 10. Callout
        UoWFlowRegisterCalloutAction.RegistrationRequest calloutRequest =
            UoWFlowTestHelpers.buildRegisterCalloutRequest(transactionId,'callout:TestAPI');
        calloutRequest.continueOnError = true;
        calloutRequest.executionPhase = null;

        UoWFlowRegisterCalloutAction.registerCallout(
            new List<UoWFlowRegisterCalloutAction.RegistrationRequest>{ calloutRequest }
        );

        // Act
        Test.startTest();
        UoWFlowCommitAction.CommitResult commitResult = UoWFlowTestHelpers.commitTransaction(transactionId);
        Test.stopTest();

        // Assert - PARTIAL_SUCCESS (1 DML succeeded, all else failed)
        Assert.isFalse(commitResult.success, 'Should not be fully successful with failures');
        Assert.areEqual(UoWEnums.TransactionStatus.PARTIAL_SUCCESS.name(), commitResult.transactionStatus, 'Status should be PARTIAL_SUCCESS');

        // Verify statistics
        Assert.areEqual(1, commitResult.dmlInserts, 'Should have 1 successful insert');
        Assert.areEqual(5, commitResult.dmlErrors, 'Should have 5 DML error');
        Assert.areEqual(0, commitResult.eventsPublished, 'Should have 0 events published (failed)');
        Assert.areEqual(0, commitResult.flowsExecuted, 'Should have 0 flows executed (failed)');
        Assert.areEqual(0, commitResult.emailsSent, 'Should have 0 emails sent (failed)');
        Assert.areEqual(0, commitResult.notificationsSent, 'Should have 0 notifications sent (failed)');
        Assert.areEqual(0, commitResult.calloutsMade, 'Should have 0 callouts made (failed)');

        // Verify errors exist
        Assert.isTrue(commitResult.hasErrors, 'Should have errors');
        Assert.isNotNull(commitResult.errorSummary, 'Should have error summary');
        Assert.isNotNull(commitResult.errorDetailsJson, 'Should have error details JSON');

        // Verify error summary contains all work types
        Assert.isTrue(commitResult.errorSummary.contains('DML'), 'Error summary should mention DML errors');
    }
}