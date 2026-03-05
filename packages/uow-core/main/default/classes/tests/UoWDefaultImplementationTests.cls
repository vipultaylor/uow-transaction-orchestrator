//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Tests for default framework implementations.
 * Covers base DML strategy operations, default channels (email, event, notification, flow),
 * default risk assessor, and channel/strategy resolvers.
 * Uses org-independent failure patterns (invalid data) to ensure consistent behavior.
 *
 * Testing Philosophy:
 * - Assume failure, test recovery: Create invalid data that will always fail
 * - Test error handling: Verify strategies/channels properly capture and report errors
 * - No assumptions: Don't assume any field is/isn't required
 * - Org-independent: Tests pass in ANY org (scratch, sandbox, production)
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Tests
 * @see UoWBaseDmlStrategy
 */
@isTest
@SuppressWarnings('PMD.MethodNamingConventions')
private class UoWDefaultImplementationTests {
    // ============================================================================
    // TEST SETUP
    // ============================================================================

    @TestSetup
    static void setupTestData() {
        // Load test configurations
        UoWTestHelpers.loadTestConfigurations();

        //Create Test Users
        UoWCoreTestDataFactory.createTestUser(UoWCoreTestDataFactory.TestUserType.ADMIN, true);
        UoWCoreTestDataFactory.createTestUser(UoWCoreTestDataFactory.TestUserType.MIN_ACCESS, true);
        UoWCoreTestDataFactory.createPartialAccessUser();
    }

    // ============================================================================
    // DML STRATEGY TESTS - INSERT
    // ============================================================================

    @isTest
    static void test_baseDmlStrategy_insert_invalidData_capturesErrors() {
        UoWBaseDmlStrategy strategy = new UoWBaseDmlStrategy('TestStrategy');
        UoWContext ctx = new UoWContext('TestConfigMinimal');

        //Create invalid accounts for org independent testing
        List<Account> accounts = UoWCoreTestDataFactory.createAccountsWithBlankName(5);

        UoWDmlWorkItem workItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.INSERT_OP,
            Account.SObjectType,
            accounts
        );
        workItem.continueOnError = true;  // Enable partial success (allOrNone=false)

        // Act - Strategy should handle errors gracefully with continueOnError=true
        Test.startTest();
        try {
            strategy.executeInsert(workItem, ctx);
        } catch (Exception ex) {
            // Strategy should NOT throw for partial failures with continueOnError=true
            Assert.fail('Strategy should not throw exception for DML errors: ' + ex.getMessage());
        }
        Test.stopTest();

        // Assert - Verify errors were captured in saveResults
        Assert.areEqual(5, workItem.saveResults.size(), 'Should have 5 save results');

        for (Database.SaveResult sr : workItem.saveResults) {
            Assert.isFalse(sr.isSuccess(), 'Invalid account should fail');
            Assert.isTrue(sr.getErrors().size() > 0, 'Should have error details');
        }

        // Verify NO records were inserted
        List<Account> inserted = [SELECT Id FROM Account];
        Assert.areEqual(0, inserted.size(), 'No accounts should be inserted');
    }

    @isTest
    static void test_baseDmlStrategy_insert_emptyRecords_succeeds() {
        // Arrange - Create empty accounts list
        UoWBaseDmlStrategy strategy = new UoWBaseDmlStrategy('TestStrategy');
        UoWContext ctx = new UoWContext('TestConfigMinimal');

        List<Account> accounts = new List<Account>();

        UoWDmlWorkItem workItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.INSERT_OP,
            Account.SObjectType,
            accounts
        );

        // Act - Strategy should return with no records
        Test.startTest();
        strategy.executeInsert(workItem, ctx);
        Test.stopTest();

        // Verify NO records were inserted
        Assert.isNull(workItem.saveResults, 'No saveresults should be updated for empty records');
    }

    // ============================================================================
    // DML STRATEGY TESTS - UPSERT
    // ============================================================================

    @isTest
    static void test_baseDmlStrategy_upsert_invalidData_capturesErrors() {
        // Arrange - Upsert without external ID field will fail
        UoWBaseDmlStrategy strategy = new UoWBaseDmlStrategy('TestStrategy');
        UoWContext ctx = new UoWContext('TestConfigMinimal');

        List<Account> accounts = UoWCoreTestDataFactory.createAccountsWithBlankName(5);

        UoWDmlWorkItem workItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.UPSERT_OP,
            Account.SObjectType,
            accounts
        );
        workItem.externalIdField = Account.Id;
        workItem.continueOnError = true;  // Enable partial success (allOrNone=false)

        // Act
        Test.startTest();
        try {
            strategy.executeUpsert(workItem, ctx);
        } catch (Exception ex) {
            Assert.fail('Strategy should not throw: ' + ex.getMessage());
        }
        Test.stopTest();

        // Assert - Should have results with errors
        Assert.areEqual(5, workItem.upsertResults.size(), 'Should have 5 upsert results');
        for (Database.UpsertResult ur : workItem.upsertResults) {
            Assert.isFalse(ur.isSuccess(), 'Invalid account should fail');
            Assert.isTrue(ur.getErrors().size() > 0, 'Should have error details');
        }
    }

    @isTest
    static void test_baseDmlStrategy_upsert_invalidData_withoutExternalId_capturesErrors() {
        // Arrange - Upsert without external ID field will fail
        UoWBaseDmlStrategy strategy = new UoWBaseDmlStrategy('TestStrategy');
        UoWContext ctx = new UoWContext('TestConfigMinimal');

        List<Account> accounts = UoWCoreTestDataFactory.createAccountsWithBlankName(5);

        UoWDmlWorkItem workItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.UPSERT_OP,
            Account.SObjectType,
            accounts
        );
        workItem.continueOnError = true;  // Enable partial success (allOrNone=false)

        // Act
        Test.startTest();
        try {
            strategy.executeUpsert(workItem, ctx);
        } catch (Exception ex) {
            Assert.fail('Strategy should not throw: ' + ex.getMessage());
        }
        Test.stopTest();

        // Assert - Should have results with errors
        Assert.areEqual(5, workItem.upsertResults.size(), 'Should have 5 upsert results');
        for (Database.UpsertResult ur : workItem.upsertResults) {
            Assert.isFalse(ur.isSuccess(), 'Invalid upsert should fail');
        }
    }

    @isTest
    static void test_baseDmlStrategy_upsert_emptyRecords_succeeds() {
        // Arrange - Create empty accounts list
        UoWBaseDmlStrategy strategy = new UoWBaseDmlStrategy('TestStrategy');
        UoWContext ctx = new UoWContext('TestConfigMinimal');

        List<Account> accounts = new List<Account>();

        UoWDmlWorkItem workItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.UPSERT_OP,
            Account.SObjectType,
            accounts
        );

        // Act - Strategy should return with no records
        Test.startTest();
        strategy.executeUpsert(workItem, ctx);
        Test.stopTest();

        // Verify NO records were upserted
        Assert.isNull(workItem.upsertResults, 'No accounts should be upserted');
    }

    // ============================================================================
    // DML STRATEGY TESTS - UPDATE
    // ============================================================================

    @isTest
    static void test_baseDmlStrategy_update_missingId_capturesErrors() {
        // Arrange - Create accounts WITHOUT IDs (update will fail)
        UoWBaseDmlStrategy strategy = new UoWBaseDmlStrategy('TestStrategy');
        UoWContext ctx = new UoWContext('TestConfigMinimal');

        //Create accounts with no id
        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5);

        UoWDmlWorkItem workItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.UPDATE_OP,
            Account.SObjectType,
            accounts
        );
        workItem.continueOnError = true;  // Enable partial success (allOrNone=false)

        // Act
        Test.startTest();
        try {
            strategy.executeUpdate(workItem, ctx);
        } catch (Exception ex) {
            Assert.fail('Strategy should not throw an exception (because of continueOnError): ' + ex.getMessage());
        }
        Test.stopTest();

        // Assert - All should fail with "missing ID" error
        Assert.areEqual(5, workItem.saveResults.size(), 'Should have 5 save results');
        for (Database.SaveResult sr : workItem.saveResults) {
            Assert.isFalse(sr.isSuccess(), 'Update without ID should fail');
            Assert.isTrue(sr.getErrors().size() > 0, 'Should have error details');
        }
    }

    @isTest
    static void test_baseDmlStrategy_update_emptyRecords_succeeds() {
        // Arrange - Create empty accounts list
        UoWBaseDmlStrategy strategy = new UoWBaseDmlStrategy('TestStrategy');
        UoWContext ctx = new UoWContext('TestConfigMinimal');

        List<Account> accounts = new List<Account>();

        UoWDmlWorkItem workItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.UPDATE_OP,
            Account.SObjectType,
            accounts
        );

        // Act - Strategy should return with no records
        Test.startTest();
        strategy.executeUpdate(workItem, ctx);
        Test.stopTest();

        // Verify NO records were updated
        Assert.isNull(workItem.saveResults, 'No accounts should be updated');
    }

    // ============================================================================
    // DML STRATEGY TESTS - DELETE
    // ============================================================================

    @isTest
    static void test_baseDmlStrategy_delete_nonexistentId_capturesErrors() {
        // Arrange - Create fake IDs that don't exist
        UoWBaseDmlStrategy strategy = new UoWBaseDmlStrategy('TestStrategy');
        UoWContext ctx = new UoWContext('TestConfigMinimal');

        // Generate accounts with fake IDs (won't exist in database)
        List<Account> accounts = UoWCoreTestDataFactory.createExistingAccounts(5);

        UoWDmlWorkItem workItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.DELETE_OP,
            Account.SObjectType,
            accounts
        );
        workItem.continueOnError = true;  // Enable partial success (allOrNone=false)

        // Act
        Test.startTest();
        try {
            strategy.executeDelete(workItem, ctx);
        } catch (Exception ex) {
            Assert.fail('Strategy should not throw: ' + ex.getMessage());
        }
        Test.stopTest();

        // Assert - All should fail (records don't exist)
        Assert.areEqual(5, workItem.deleteResults.size(), 'Should have 5 delete results');
        for (Database.DeleteResult dr : workItem.deleteResults) {
            Assert.isFalse(dr.isSuccess(), 'Delete of nonexistent record should fail');
            Assert.isTrue(dr.getErrors().size() > 0, 'Should have error details');
        }
    }

    @isTest
    static void test_baseDmlStrategy_delete_emptyRecords_succeeds() {
        // Arrange - Create empty accounts list
        UoWBaseDmlStrategy strategy = new UoWBaseDmlStrategy('TestStrategy');
        UoWContext ctx = new UoWContext('TestConfigMinimal');

        List<Account> accounts = new List<Account>();

        UoWDmlWorkItem workItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.DELETE_OP,
            Account.SObjectType,
            accounts
        );

        // Act - Strategy should return with no records
        Test.startTest();
        strategy.executeDelete(workItem, ctx);
        Test.stopTest();

        // Verify NO records were deleted
        Assert.isNull(workItem.deleteResults, 'No accounts should be deleted');
    }

    // ============================================================================
    // DML STRATEGY TESTS - UNDELETE
    // ============================================================================

    @isTest
    static void test_baseDmlStrategy_undelete_nonexistentId_capturesErrors() {
        // Arrange - Try to undelete nonexistent records
        UoWBaseDmlStrategy strategy = new UoWBaseDmlStrategy('TestStrategy');
        UoWContext ctx = new UoWContext('TestConfigMinimal');

        // Generate accounts with fake IDs (won't exist in database)
        List<Account> accounts = UoWCoreTestDataFactory.createExistingAccounts(5);

        UoWDmlWorkItem workItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.UNDELETE_OP,
            Account.SObjectType,
            accounts
        );
        workItem.continueOnError = true;  // Enable partial success (allOrNone=false)

        // Act
        Test.startTest();
        try {
            strategy.executeUndelete(workItem, ctx);
        } catch (Exception ex) {
            Assert.fail('Strategy should not throw: ' + ex.getMessage());
        }
        Test.stopTest();

        // Assert - Should fail (record doesn't exist)
        Assert.areEqual(5, workItem.undeleteResults.size(), 'Should have 5 undelete results');
        for (Database.UndeleteResult ur : workItem.undeleteResults) {
            Assert.isFalse(ur.isSuccess(), 'Undelete should fail');
            Assert.isTrue(ur.getErrors().size() > 0, 'Should have error details');
        }
    }

    @isTest
    static void test_baseDmlStrategy_undelete_emptyRecords_succeeds() {
        // Arrange - Create empty accounts list
        UoWBaseDmlStrategy strategy = new UoWBaseDmlStrategy('TestStrategy');
        UoWContext ctx = new UoWContext('TestConfigMinimal');

        List<Account> accounts = new List<Account>();

        UoWDmlWorkItem workItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.UNDELETE_OP,
            Account.SObjectType,
            accounts
        );

        // Act - Strategy should return with no records
        Test.startTest();
        strategy.executeUndelete(workItem, ctx);
        Test.stopTest();

        // Verify NO records were undeleted
        Assert.isNull(workItem.undeleteResults, 'No accounts should be undeleted');
    }

    // ============================================================================
    // ENFORCED MODE SECURITY ENFORCEMENT TESTS
    // ============================================================================

    @isTest
    // Scenario: Admin has full access, stripInaccessible is called but strips nothing
    static void test_baseDmlStrategy_enforced_fullAccess_noFieldsStripped() {
        User adminUser = UoWCoreTestDataFactory.getTestUser(UoWCoreTestDataFactory.TestUserType.ADMIN);

        // Arrange - ENFORCED mode, blank Name (guaranteed to fail validation)
        UoWBaseDmlStrategy strategy = new UoWBaseDmlStrategy();
        UoWContext ctx = new UoWContext('TestConfigEnforced');

        Assert.areEqual('Default DML Strategy', strategy.getName(), 'Strategy name should be default');

        List<Account> accounts = UoWCoreTestDataFactory.createAccountsWithBlankName(5);

        // Act - Test security enforcement directly
        List<SObject> securedRecords;
        Test.startTest();
        System.runAs(adminUser) {
            securedRecords = strategy.enforceSecurityIfNeeded(accounts, AccessType.CREATABLE, ctx);
        }
        Test.stopTest();

        // Assert - Records returned (admin has full access)
        Assert.isNotNull(securedRecords, 'Should return records after security check');
        Assert.areEqual(5, securedRecords.size(), 'Should have 5 records');

        // Verify Industry field is still present (admin has FLS access)
        for(SObject acc : securedRecords) {
            Account securedAcc = (Account) acc;
            Assert.areEqual('Technology', securedAcc.Industry, 'Industry field should NOT be stripped for admin');
        }

        // Verify no stripped field warnings
        Assert.isFalse(contextHasStrippedFieldWarning(ctx, 'Industry'), 'Should NOT have stripped field warning for admin user');
    }

    @isTest
    // Scenario: User has no access to Account object, NoAccessException thrown
    static void test_baseDmlStrategy_enforced_noEntityAccess_throwsNoAccessException() {
        User minAccessUser = UoWCoreTestDataFactory.getTestUser(UoWCoreTestDataFactory.TestUserType.MIN_ACCESS);

        // Arrange - ENFORCED mode, blank Name (guaranteed to fail validation)
        UoWBaseDmlStrategy strategy = new UoWBaseDmlStrategy();
        UoWContext ctx = new UoWContext('TestConfigEnforced');

        Assert.areEqual('Default DML Strategy', strategy.getName(), 'Strategy name should be default');

        List<Account> accounts = UoWCoreTestDataFactory.createAccountsWithBlankName(5);

        // Act & Assert - Should throw NoAccessException
        Boolean exceptionThrown = false;

        Test.startTest();
        System.runAs(minAccessUser) {
            try {
                strategy.enforceSecurityIfNeeded(accounts, AccessType.CREATABLE, ctx);
                Assert.fail('Exception should have been thrown');
            } catch (System.NoAccessException ex) {
                exceptionThrown = true;
            }
        }
        Test.stopTest();

        Assert.isTrue(exceptionThrown, 'Should throw NoAccessException for user without entity access');

        // Verify error was logged to context
        Assert.isTrue(contextHasSecurityErrorMessage(ctx), 'Should log security error message to context');
    }

    @isTest
    // Scenario: User has object access but only Name field access, Industry stripped
    static void test_baseDmlStrategy_enforced_partialAccess_stripsInaccessibleField() {
        User partialAccessUser = UoWCoreTestDataFactory.getTestUser(UoWCoreTestDataFactory.TestUserType.PARTIAL_FIELD_ACCESS);

        // Arrange - ENFORCED mode, oversized Name + inaccessible Industry field
        UoWBaseDmlStrategy strategy = new UoWBaseDmlStrategy();
        UoWContext ctx = new UoWContext('TestConfigEnforced');

        Assert.areEqual('Default DML Strategy', strategy.getName(), 'Strategy name should be default');

        List<Account> accounts = UoWCoreTestDataFactory.createAccountWithOversizedName(5, true); // includes Industry

        // Verify Industry is set before security enforcement
        Assert.areEqual('Technology', accounts[0].Industry, 'Industry should be set before security check');

        // Act - Test security enforcement directly
        List<SObject> securedRecords;
        Test.startTest();
        System.runAs(partialAccessUser) {
            securedRecords = strategy.enforceSecurityIfNeeded(accounts, AccessType.CREATABLE, ctx);
        }
        Test.stopTest();

        // Assert - Records returned with Industry stripped
        Assert.isNotNull(securedRecords, 'Should return records after security check');
        Assert.areEqual(5, securedRecords.size(), 'Should have 5 records');

        // Verify Industry field was stripped (user has no FLS access via Standard User profile)
        for(SObject acc : securedRecords) {
            Account securedAcc = (Account) acc;
            Assert.isNull(securedAcc.Industry, 'Industry field should be stripped due to lack of FLS access');
            // Verify Name is still present (user has FLS access via UoWCoreSecurityTest PS)
            Assert.areEqual(256, securedAcc.Name.length(), 'Name field should be preserved');
        }


        // Verify warning was logged about stripped field
        Assert.isTrue(contextHasStrippedFieldWarning(ctx, 'Industry'), 'Should have warning about stripped Industry field');
    }

    // ============================================================================
    // PERMISSIVE MODE - Security Bypass
    // ============================================================================

    @isTest
    static void test_baseDmlStrategy_permissive_bypassesSecurity_noStripping() {
        User partialAccessUser = UoWCoreTestDataFactory.getTestUser(UoWCoreTestDataFactory.TestUserType.PARTIAL_FIELD_ACCESS);

        // Arrange - ENFORCED mode, blank Name (guaranteed to fail validation)
        UoWBaseDmlStrategy strategy = new UoWBaseDmlStrategy();
        Assert.areEqual('Default DML Strategy', strategy.getName(), 'Strategy name should be default');

        UoWContext ctx = new UoWContext('TestConfigEnforced');
        Assert.areEqual(UoWEnums.SecurityMode.ENFORCED, ctx.getFeatureSettings().getDmlSecurityMode(), 'Security mode should be ENFORCED because of the config');

        //Override Security Mode to PERMISSIVE
        ctx.getFeatureSettings().setSecurityMode(UoWEnums.SecurityMode.PERMISSIVE);
        Assert.areEqual(UoWEnums.SecurityMode.PERMISSIVE, ctx.getFeatureSettings().getDmlSecurityMode(), 'Security mode should be overridden to PERMISSIVE');

        List<Account> accounts = UoWCoreTestDataFactory.createAccountsWithBlankName(5);

        // Act - Test security enforcement directly
        List<SObject> securedRecords;
        Test.startTest();
        System.runAs(partialAccessUser) {
            securedRecords = strategy.enforceSecurityIfNeeded(accounts, AccessType.CREATABLE, ctx);
        }
        Test.stopTest();

        // Assert - Records returned (admin has full access)
        Assert.isNotNull(securedRecords, 'Should return records after security check');
        Assert.areEqual(5, securedRecords.size(), 'Should have 5 records');
        Assert.areEqual(accounts, securedRecords, 'PERMISSIVE mode should return original records unchanged');

        // Verify no stripped field warnings (PERMISSIVE mode bypasses security)
        Assert.isFalse(contextHasStrippedFieldWarning(ctx, 'Industry'), 'PERMISSIVE mode should not generate stripped field warnings');

    }

    // ============================================================================
    // EVENT CHANNEL TESTS
    // ============================================================================

    @isTest
    static void test_defaultEventChannel_emptyEventsList_succeeds() {
        // Arrange
        UoWDefaultPlatformEventChannel channel = new UoWDefaultPlatformEventChannel();
        UoWContext ctx = new UoWContext('TestConfigMinimal');

        // Create a generic SObject list (platform events inherit from SObject)
        // Note: Can't create actual platform event in test without custom event type
        //Can't even create a dummy list as publishing a non platform event list throws UnxpectedException
        // and we cant catch it using the standard try catch block
        List<SObject> events = new List<SObject>();

        // Using Account.SObjectType as a placeholder since we can't access platform event types in test
        // without creating some platform events as part of this framework
        UoWEventWorkItem workItem = new UoWEventWorkItem(
            UoWEnums.WorkPhase.POST_DML,
            Account.SObjectType,
            events
        );

        // Act
        Test.startTest();
        channel.publishEvents(workItem, ctx);
        Test.stopTest();

        // Results depend on whether events list is empty or not
        Assert.areEqual('Default Platform Event Bus', channel.getName(), 'Default event channel name should match');
        Assert.isNotNull(workItem.publishResults, 'Publish Results should be initialized for the work item');
        Assert.areEqual(0, workItem.publishResults.size(), 'Publish Results should be empty for the work item');
    }

    // ============================================================================
    // DEFAULT PUBLISH FAILURE CALLBACK TESTS
    // ============================================================================

    @isTest
    static void test_defaultPublishFailureCallback_onFailure_populatesContextAndDelegates() {
        // Arrange
        UoWTestMocks.resetEventFailureHandlerTracking();
        UoWDefaultPublishFailureCallback.capturedFailures.clear();

        UoWContext uowCtx = new UoWContext('TestConfigMinimal');
        List<SObject> events = new List<SObject>{
            new Account(Name = 'Event 1'), new Account(Name = 'Event 2'),
            new Account(Name = 'Event 3'), new Account(Name = 'Event 4'),
            new Account(Name = 'Event 5')
        };
        UoWEventWorkItem workItem = new UoWEventWorkItem(
            UoWEnums.WorkPhase.POST_DML, Account.SObjectType, events
        );

        // Tests call handleFailure() directly instead of onFailure() because the platform's
        // EventPublishFailureCallback.onFailure() can only be invoked through the EventBus
        // framework with real platform events (via Test.getEventBus().fail()).
        // handleFailure() contains all the business logic and is @TestVisible.
        UoWDefaultPublishFailureCallback callback = new UoWDefaultPublishFailureCallback(
            uowCtx, workItem, 'UoWTestMocks.MockEventPublishFailureHandler'
        );

        // Act
        Test.startTest();
        callback.handleFailure();
        Test.stopTest();

        // Assert - Context fields populated correctly from UoWContext and UoWEventWorkItem
        List<UoWEventPublishFailureContext> captured = UoWDefaultPublishFailureCallback.capturedFailures;
        Assert.areEqual(1, captured.size(), 'Should capture exactly 1 failure context');

        UoWEventPublishFailureContext failureCtx = captured[0];
        Assert.areEqual(uowCtx.correlationId, failureCtx.correlationId, 'correlationId should be derived from UoWContext');
        Assert.areEqual(uowCtx.transactionId, failureCtx.transactionId, 'transactionId should be derived from UoWContext');
        Assert.areEqual(workItem.workId, failureCtx.workId, 'workId should be derived from UoWEventWorkItem');
        Assert.areEqual(5, failureCtx.publishedEventCount, 'publishedEventCount should be derived from event list size');
        Assert.areEqual(5, failureCtx.failedEventCount, 'failedEventCount should equal total (entire batch fails)');
        Assert.isNotNull(failureCtx.failedAt, 'failedAt timestamp should be set');

        // Assert - Handler was invoked via dynamic instantiation
        Assert.areEqual(1, UoWTestMocks.eventFailureHandlerCallCount, 'Handler should be called exactly once');
        UoWEventPublishFailureContext handlerCtx = UoWTestMocks.eventFailureCapturedContext;
        Assert.isNotNull(handlerCtx, 'Handler should receive failure context');
        Assert.areEqual(uowCtx.correlationId, handlerCtx.correlationId, 'Handler should receive correct correlationId');
    }

    @isTest
    static void test_defaultPublishFailureCallback_onFailure_noHandler_capturesOnly() {
        // Arrange
        UoWDefaultPublishFailureCallback.capturedFailures.clear();

        UoWContext uowCtx = new UoWContext('TestConfigMinimal');
        List<SObject> events = new List<SObject>{
            new Account(Name = 'Event 1'), new Account(Name = 'Event 2')
        };
        UoWEventWorkItem workItem = new UoWEventWorkItem(
            UoWEnums.WorkPhase.POST_DML, Account.SObjectType, events
        );

        // null handler - should skip handler delegation entirely
        UoWDefaultPublishFailureCallback callback = new UoWDefaultPublishFailureCallback(
            uowCtx, workItem, null
        );

        // Act
        Test.startTest();
        callback.handleFailure();
        Test.stopTest();

        // Assert - Context still captured even without handler
        List<UoWEventPublishFailureContext> captured = UoWDefaultPublishFailureCallback.capturedFailures;
        Assert.areEqual(1, captured.size(), 'Should capture failure context even without handler');
        Assert.areEqual(uowCtx.correlationId, captured[0].correlationId, 'Should have correct correlationId');
        Assert.areEqual(2, captured[0].failedEventCount, 'Should have correct failedEventCount');
    }

    @isTest
    static void test_defaultPublishFailureCallback_onFailure_handlerErrors_handlesGracefully() {
        // Arrange - Test both invalid handler class AND handler that throws
        UoWDefaultPublishFailureCallback.capturedFailures.clear();
        UoWTestMocks.resetEventFailureHandlerTracking();

        UoWContext uowCtx = new UoWContext('TestConfigMinimal');
        List<SObject> events = new List<SObject>{
            new Account(Name = 'Event 1'), new Account(Name = 'Event 2'),
            new Account(Name = 'Event 3')
        };
        UoWEventWorkItem workItem = new UoWEventWorkItem(
            UoWEnums.WorkPhase.POST_DML, Account.SObjectType, events
        );

        // Scenario 1: Non-existent handler class - should not throw
        UoWDefaultPublishFailureCallback invalidCallback = new UoWDefaultPublishFailureCallback(
            uowCtx, workItem, 'NonExistentHandlerClass'
        );

        // Scenario 2: Handler that throws an exception - should not throw
        UoWTestMocks.eventFailureHandlerShouldThrow = true;
        UoWDefaultPublishFailureCallback throwingCallback = new UoWDefaultPublishFailureCallback(
            uowCtx, workItem, 'UoWTestMocks.MockEventPublishFailureHandler'
        );

        // Act - Neither should throw
        Test.startTest();
        invalidCallback.handleFailure();
        throwingCallback.handleFailure();
        Test.stopTest();

        // Assert - Both failures captured despite handler errors
        List<UoWEventPublishFailureContext> captured = UoWDefaultPublishFailureCallback.capturedFailures;
        Assert.areEqual(2, captured.size(), 'Should capture both failure contexts despite handler errors');

        // Throwing handler was still invoked before failing
        Assert.areEqual(1, UoWTestMocks.eventFailureHandlerCallCount,
            'Throwing handler should have been called before throwing');
    }

    // ============================================================================
    // EMAIL CHANNEL TESTS
    // ============================================================================

    @isTest
    static void test_defaultEmailChannel_noRecipients_fails() {
        // Arrange
        UoWDefaultEmailChannel channel = new UoWDefaultEmailChannel();
        UoWContext ctx = new UoWContext('TestConfigMinimal');

        List<Messaging.SingleEmailMessage> emails = UoWCoreTestDataFactory.createEmailsWithNoRecipients(5);

        UoWEmailWorkItem workItem = new UoWEmailWorkItem(UoWEnums.WorkPhase.POST_DML, emails);

        // Act
        Test.startTest();
        channel.sendEmails(workItem, ctx);
        Test.stopTest();

        // Assert
        Assert.areEqual('Default Salesforce Email Service', channel.getName(), 'Default email channel name should match');
        Assert.areEqual(5, workItem.sendResults.size(), 'Should have 5 results');
        for (Messaging.SendEmailResult result : workItem.sendResults) {
            Assert.isFalse(result.isSuccess(), 'Email send should fail due to no recipients');
        }
    }

    // ============================================================================
    // NOTIFICATION CHANNEL TESTS
    // ============================================================================

    @isTest
    static void test_defaultNotificationChannel_invalidNotificationType_succeeds() {
        // Arrange
        UoWDefaultNotificationChannel channel = new UoWDefaultNotificationChannel();
        UoWContext ctx = new UoWContext('TestConfigMinimal');

        // Create work item directly (not using registration for isolated channel testing)
        UoWNotificationWorkItem workItem = new UoWNotificationWorkItem(UoWEnums.WorkPhase.ON_SUCCESS)
            .withNotificationType(UoWTestHelpers.generateFakeId(CustomNotificationType.SObjectType, 1), 'TestNotification')
            .withRecipients(new Set<String> { UserInfo.getUserId() })
            .withTitle('Test')
            .withBody('Body')
            .withTargetId(UoWTestHelpers.generateFakeId(User.SObjectType, 1));

        // Act
        Test.startTest();
        channel.sendNotification(workItem, ctx);
        Test.stopTest();

        // Assert - Dry run should complete without error
        Assert.isNotNull(workItem, 'Work item should be processed');
        Assert.areEqual('Default Custom Notifications', channel.getName(), 'Default notification channel name should match');
    }

    // ============================================================================
    // FLOW CHANNEL TESTS
    // ============================================================================

    @isTest
    static void test_defaultFlowChannel_invalidFlowName_throwsException() {
        // Arrange
        UoWDefaultFlowChannel channel = new UoWDefaultFlowChannel();
        UoWContext ctx = new UoWContext('TestConfigMinimal');

        // Create work item directly (not using registration for isolated channel testing)
        UoWFlowWorkItem workItem = new UoWFlowWorkItem('UoWNonExistentFlow', UoWEnums.WorkPhase.POST_DML);
        workItem.flowInputs.put('testParam', 'testValue');

        // Act
        Test.startTest();
        Boolean exceptionThrown = false;
        try{
            channel.executeFlow(workItem, ctx);
            Assert.fail('Exception should have been thrown');
        } catch (Exception ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        // Assert - Exception should be thrown
        Assert.isTrue(exceptionThrown, 'NonExistentFLow should throw exception on error');
        Assert.areEqual('Default Salesforce Flow Engine', channel.getName(), 'Default flow channel name should match');
    }

    // ============================================================================
    // BASE CALLOUT STRATEGY TESTS
    // ============================================================================

    @isTest
    static void test_baseCalloutStrategy_executesHttpCallout_success() {
        // Set Mock
        UoWTestMocks.MockHttpCallout mockCallout = new UoWTestMocks.MockHttpCallout();
        mockCallout.statusCode = 200;
        mockCallout.responseBody = '{"status": "success", "data": "test"}';
        Test.setMock(HttpCalloutMock.class, mockCallout);

        // Arrange
        UoWBaseCalloutStrategy strategy = new UoWBaseCalloutStrategy();
        UoWContext ctx = new UoWContext('TestConfigMinimal');

        // Create work item directly (not using registration for isolated channel testing)
        UoWCalloutWorkItem workItem = new UoWCalloutWorkItem('https://api.example.com/data', 'POST')
            .withHeader('Content-Type', 'application/json')
            .withQueryParam('key', 'value')
            .withBody('{"name": "Test"}')
            .withTimeout(3000)
            .withRetryConfig(UoWRetryConfig.builder().withMaxRetries(2).withBackoffMultiplier(2).build());

        // Act
        Test.startTest();
        strategy.executeCallout(workItem, ctx);
        Test.stopTest();

        // Assert
        Assert.isNotNull(workItem.response, 'The Callout should have returned a valid response');
        Assert.areEqual(200, workItem.response.getStatusCode(), 'The Callout should have returned a 200 response status code');
        Assert.areEqual('Default Callout Strategy', strategy.getName(), 'Default callout strategy name should match');
    }

    @isTest
    static void test_baseCalloutStrategy_executesHttpCallout_returnsError() {
        // Set Mock
        UoWTestMocks.MockHttpCallout mockCallout = new UoWTestMocks.MockHttpCallout();
        mockCallout.statusCode = 400;
        mockCallout.responseBody = '{"status": "error", "data": "test"}';
        Test.setMock(HttpCalloutMock.class, mockCallout);

        // Arrange
        UoWBaseCalloutStrategy strategy = new UoWBaseCalloutStrategy();
        UoWContext ctx = new UoWContext('TestConfigMinimal');

        // Create work item directly (not using registration for isolated channel testing)
        UoWCalloutWorkItem workItem = new UoWCalloutWorkItem('https://api.example.com/data', 'POST')
            .withMethod('GET');

        // Act
        Test.startTest();
        try{
            strategy.executeCallout(workItem, ctx);
        } catch (UoWExceptionService.UoWException ex) {
            // Expected exception due to error response
            Assert.isTrue(ex.getMessage().contains('HTTP callout failed'), 'Exception message should contain HTTP callout failed');
        }
        Test.stopTest();

        // Assert
        Assert.isNotNull(workItem.response, 'The Callout should have returned a valid response');
        Assert.areEqual(400, workItem.response.getStatusCode(), 'The Callout should have returned a 400 response status code');
    }

    // ============================================================================
    // BASE PLUGIN TESTS
    // ============================================================================

    @isTest
    static void test_basePlugin_defaultCategory_isStandard() {
        // Arrange
        UoWBasePlugin plugin = new UoWBasePlugin('TestPlugin');

        // Act
        UoWEnums.PluginCategory category = plugin.getCategory();

        // Assert
        Assert.areEqual(UoWEnums.PluginCategory.STANDARD, category, 'Default plugin category should be STANDARD');
    }

    @isTest
    static void test_basePlugin_defaultCritical_isFalse() {
        // Arrange
        UoWBasePlugin plugin = new UoWBasePlugin('TestPlugin');

        // Act
        Boolean isCritical = plugin.isCritical();

        // Assert
        Assert.isFalse(isCritical, 'Default plugin should not be critical');
    }

    @isTest
    static void test_basePlugin_auditCategory_canBeSet() {
        // Arrange
        UoWBasePlugin plugin = new UoWBasePlugin('AuditPlugin', UoWEnums.PluginCategory.AUDIT);

        // Act
        UoWEnums.PluginCategory category = plugin.getCategory();

        // Assert
        Assert.areEqual(UoWEnums.PluginCategory.AUDIT, category, 'Plugin category should be AUDIT');
    }

    @isTest
    static void test_basePlugin_getName_returnsName() {
        // Arrange
        UoWBasePlugin plugin = new UoWBasePlugin('MyCustomPlugin');

        // Act
        String name = plugin.getName();

        // Assert
        Assert.areEqual('MyCustomPlugin', name, 'Plugin name should match constructor argument');
    }

    @isTest
    static void test_basePlugin_lifecycleMethods_haveDefaultImplementations() {
        // Arrange
        UoWBasePlugin plugin = new UoWBasePlugin('TestPlugin');
        UoWContext ctx = new UoWContext('TestConfigMinimal');
        UoWPlan plan = new UoWPlan();
        UoWResult result = new UoWResult(ctx);
        Exception testEx = new UoWExceptionService.UoWException('Test error');

        // Act - all lifecycle methods should execute without error
        Test.startTest();
        UoWPluginExecutor.PhaseResult onBeforeCommitResult = plugin.onBeforeCommit(ctx, plan, result);
        UoWPluginExecutor.PhaseResult onAfterCommitResult = plugin.onAfterCommit(ctx, result);
        UoWPluginExecutor.PhaseResult onErrorResult = plugin.onError(ctx, testEx, result);
        UoWPluginExecutor.PhaseResult onFinallyResult = plugin.onFinally(ctx, result);
        Test.stopTest();

        // Assert - no exceptions thrown means default implementations work
        Assert.areEqual(UoWPluginExecutor.PhaseResult.NOT_IMPLEMENTED, onBeforeCommitResult, 'onBeforeComit should return NOT_IMPLEMENTED by default');
        Assert.areEqual(UoWPluginExecutor.PhaseResult.NOT_IMPLEMENTED, onAfterCommitResult, 'onAfterCommit should return NOT_IMPLEMENTED by default');
        Assert.areEqual(UoWPluginExecutor.PhaseResult.NOT_IMPLEMENTED, onErrorResult, 'onError should return NOT_IMPLEMENTED by default');
        Assert.areEqual(UoWPluginExecutor.PhaseResult.NOT_IMPLEMENTED, onFinallyResult, 'onFinally should return NOT_IMPLEMENTED by default');
    }

    // ============================================================================
    // BASE POLICY TESTS
    // ============================================================================

    @isTest
    static void test_basePolicy_defaultCategory_isBusinessRules() {
        // Arrange
        UoWBasePolicy policy = new UoWBasePolicy('TestPolicy');

        // Act
        UoWEnums.PolicyCategory category = policy.getCategory();

        // Assert
        Assert.areEqual(UoWEnums.PolicyCategory.BUSINESS_RULES, category, 'Default policy category should be BUSINESS_RULES');
    }

    @isTest
    static void test_basePolicy_defaultCritical_isTrue() {
        // Arrange
        UoWBasePolicy policy = new UoWBasePolicy('TestPolicy');

        // Act
        Boolean isCritical = policy.isCritical();

        // Assert
        Assert.isTrue(isCritical, 'Default policy should be critical');
    }

    @isTest
    static void test_basePolicy_auditCategory_canBeSet() {
        // Arrange
        UoWBasePolicy policy = new UoWBasePolicy('AuditPolicy', UoWEnums.PolicyCategory.SECURITY);

        // Act
        UoWEnums.PolicyCategory category = policy.getCategory();

        // Assert
        Assert.areEqual(UoWEnums.PolicyCategory.SECURITY, category, 'Policy category should be SECURITY');
    }

    @isTest
    static void test_basePolicy_getName_returnsName() {
        // Arrange
        UoWBasePolicy policy = new UoWBasePolicy('MyCustomPolicy');

        // Act
        String name = policy.getName();

        // Assert
        Assert.areEqual('MyCustomPolicy', name, 'Policy name should match constructor argument');
    }

    @isTest
    static void test_basePolicy_defaultWorkItemEvaluation_returnsAllow() {
        // Arrange
        UoWBasePolicy policy = new UoWBasePolicy('MyCustomPolicy');
        UoWContext ctx = new UoWContext('TestConfigMinimal');
        UoWDmlWorkItem workItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.INSERT_OP,
            Account.SObjectType,
            UoWCoreTestDataFactory.createAccounts(1)
        );

        // Act
        UoWPolicyEvaluation.Evaluation evaluation = policy.evaluate(ctx, workItem);

        // Assert
        Assert.areEqual(UoWEnums.PolicyAction.ALLOW, evaluation.action, 'Default policy evaluation should return ALLOW');
        Assert.isNull(evaluation.reason, 'Default policy evaluation should return no reason message');
        Assert.isTrue(evaluation.evidence.keySet().isEmpty(), 'Default policy evaluation should return no evidence');
    }

    // ============================================================================
    // RISK ASSESSOR TESTS
    // ============================================================================

    @isTest
    static void test_standardRiskAssessor_emptyPlan_lowRisk() {
        // Arrange
        UoWStandardRiskAssessor assessor = new UoWStandardRiskAssessor();
        UoWContext ctx = new UoWContext('TestConfigMinimal');
        UoWPlan plan = new UoWPlan();  // Empty plan

        // Act
        Test.startTest();
        UoWRiskTypes.RiskAssessment assessment = assessor.assessRisk(ctx, plan);
        Test.stopTest();

        // Assert
        Assert.isNotNull(assessment, 'Should return assessment');
        Assert.isTrue(assessment.riskScore >= 0, 'Risk score should be non-negative');
        Assert.isNotNull(assessment.riskLevel, 'Should have risk level');
    }

    @isTest
    static void test_standardRiskAssessor_lowVolume_increasesRisk() {
        // Arrange
        UoWStandardRiskAssessor assessor = new UoWStandardRiskAssessor();
        UoWContext ctx = new UoWContext('TestConfigMinimal');
        UoWPlan plan = new UoWPlan();

        // Add large volume of records (triggers volume risk factor)
        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(150);
        UoWDmlWorkItem workItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.INSERT_OP,
            Account.SObjectType,
            accounts
        );
        plan.registerDmlWork(workItem);

        // Act
        Test.startTest();
        UoWRiskTypes.RiskAssessment assessment = assessor.assessRisk(ctx, plan);
        Test.stopTest();

        // Assert - Volume should increase risk score
        Assert.isTrue(assessment.riskScore >= 5, 'Record volume should increase risk score');
        Assert.isTrue(assessment.riskFactors.size() > 0, 'Should have volume risk factor');
        List<UoWRiskTypes.RiskFactor> volumeRiskFactors = assessment.getFactorsByCategory(UoWRiskTypes.RiskFactorCategory.VOLUME);
        Assert.areEqual(1, volumeRiskFactors.size(), 'Should have 1 volume risk factor');
        Assert.isFalse(volumeRiskFactors[0].metadata.isEmpty(), 'Risk factor should have metadata');
        Assert.areEqual('Low', volumeRiskFactors[0].metadata.get('volumeLevel'), 'Risk factor should have low volumeLevel');
    }

    @isTest
    static void test_standardRiskAssessor_moderateVolume_increasesRisk() {
        // Arrange
        UoWStandardRiskAssessor assessor = new UoWStandardRiskAssessor();
        UoWContext ctx = new UoWContext('TestConfigMinimal');
        UoWPlan plan = new UoWPlan();

        // Add large volume of records (triggers volume risk factor)
        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(600);
        UoWDmlWorkItem workItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.INSERT_OP,
            Account.SObjectType,
            accounts
        );
        plan.registerDmlWork(workItem);

        // Act
        Test.startTest();
        UoWRiskTypes.RiskAssessment assessment = assessor.assessRisk(ctx, plan);
        Test.stopTest();

        // Assert - Volume should increase risk score
        Assert.isTrue(assessment.riskScore >= 10, 'Record volume should increase risk score');
        Assert.isTrue(assessment.riskFactors.size() > 0, 'Should have volume risk factor');
        List<UoWRiskTypes.RiskFactor> volumeRiskFactors = assessment.getFactorsByCategory(UoWRiskTypes.RiskFactorCategory.VOLUME);
        Assert.areEqual(1, volumeRiskFactors.size(), 'Should have 1 volume risk factor');
        Assert.isFalse(volumeRiskFactors[0].metadata.isEmpty(), 'Risk factor should have metadata');
        Assert.areEqual('Moderate', volumeRiskFactors[0].metadata.get('volumeLevel'), 'Risk factor should have Moderate volumeLevel');
    }

    @isTest
    static void test_standardRiskAssessor_largeVolume_increasesRisk() {
        // Arrange
        UoWStandardRiskAssessor assessor = new UoWStandardRiskAssessor();
        UoWContext ctx = new UoWContext('TestConfigMinimal');
        UoWPlan plan = new UoWPlan();

        // Add large volume of records (triggers volume risk factor)
        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(1100);
        UoWDmlWorkItem workItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.INSERT_OP,
            Account.SObjectType,
            accounts
        );
        plan.registerDmlWork(workItem);

        // Act
        Test.startTest();
        UoWRiskTypes.RiskAssessment assessment = assessor.assessRisk(ctx, plan);
        Test.stopTest();

        // Assert - Volume should increase risk score
        Assert.isTrue(assessment.riskScore >= 12, 'High volume should increase risk score');
        Assert.isTrue(assessment.riskFactors.size() > 0, 'Should have volume risk factor');
        List<UoWRiskTypes.RiskFactor> volumeRiskFactors = assessment.getFactorsByCategory(UoWRiskTypes.RiskFactorCategory.VOLUME);
        Assert.areEqual(1, volumeRiskFactors.size(), 'Should have 1 volume risk factor');
        Assert.isFalse(volumeRiskFactors[0].metadata.isEmpty(), 'Risk factor should have metadata');
        Assert.areEqual('High', volumeRiskFactors[0].metadata.get('volumeLevel'), 'Risk factor should have High volumeLevel');
    }

    @isTest
    static void test_standardRiskAssessor_veryLargeVolume_increasesRisk() {
        // Arrange
        UoWStandardRiskAssessor assessor = new UoWStandardRiskAssessor();
        UoWContext ctx = new UoWContext('TestConfigMinimal');
        UoWPlan plan = new UoWPlan();

        // Add large volume of records (triggers volume risk factor)
        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5100);// > 5000 triggers Large volume risk
        UoWDmlWorkItem workItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.INSERT_OP,
            Account.SObjectType,
            accounts
        );
        plan.registerDmlWork(workItem);

        // Act
        Test.startTest();
        UoWRiskTypes.RiskAssessment assessment = assessor.assessRisk(ctx, plan);
        Test.stopTest();

        // Assert - Volume should increase risk score
        Assert.isTrue(assessment.riskScore >= UoWRiskTypes.MAX_RISK_FACTOR_SCORE, 'High volume should increase risk score');
        Assert.isTrue(assessment.riskFactors.size() > 0, 'Should have volume risk factor');
        List<UoWRiskTypes.RiskFactor> volumeRiskFactors = assessment.getFactorsByCategory(UoWRiskTypes.RiskFactorCategory.VOLUME);
        Assert.areEqual(1, volumeRiskFactors.size(), 'Should have 1 volume risk factor');
        Assert.isFalse(volumeRiskFactors[0].metadata.isEmpty(), 'Risk factor should have metadata');
        Assert.areEqual('Very High', volumeRiskFactors[0].metadata.get('volumeLevel'), 'Risk factor should have Very High volumeLevel');
    }

    @isTest
    static void test_standardRiskAssessor_deleteOperation_addsRiskFactor() {
        // Arrange
        UoWStandardRiskAssessor assessor = new UoWStandardRiskAssessor();
        UoWContext ctx = new UoWContext('TestConfigMinimal');
        UoWPlan plan = new UoWPlan();

        // Add delete operation (destructive)
        List<Account> accounts = UoWCoreTestDataFactory.createExistingAccounts(10);
        UoWDmlWorkItem workItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.DELETE_OP,
            Account.SObjectType,
            accounts
        );
        plan.registerDmlWork(workItem);

        // Act
        Test.startTest();
        UoWRiskTypes.RiskAssessment assessment = assessor.assessRisk(ctx, plan);
        Test.stopTest();

        // Assert - Delete operation should add risk factor
        Assert.isTrue(assessment.riskScore > 0, 'Delete operation should increase risk score');
        Assert.isTrue(assessment.riskFactors.size() > 0, 'Should have delete operation risk factor');
    }

    @isTest
    static void test_standardRiskAssessor_getName_returnsDefaultName() {
        // Arrange
        UoWStandardRiskAssessor assessor = new UoWStandardRiskAssessor();

        // Act
        Test.startTest();
        String name = assessor.getName();
        Test.stopTest();

        // Assert
        Assert.areEqual('StandardRiskAssessor', name, 'Should return default risk assessor name');
    }

    @isTest
    static void test_standardRiskAssessor_riskLevel_lowThreshold() {
        // Arrange - Test LOW risk level threshold
        UoWStandardRiskAssessor assessor = new UoWStandardRiskAssessor();
        UoWContext ctx = new UoWContext('TestConfigMinimal');
        UoWPlan plan = new UoWPlan();

        // Add low-volume records for minimal risk
        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(50);
        UoWDmlWorkItem workItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.INSERT_OP,
            Account.SObjectType,
            accounts
        );
        plan.registerDmlWork(workItem);

        // Act
        Test.startTest();
        UoWRiskTypes.RiskAssessment assessment = assessor.assessRisk(ctx, plan);
        Test.stopTest();

        // Assert - Should have NONE or LOW risk level
        Assert.isNotNull(assessment.riskLevel, 'Should have risk level');
        Assert.isTrue(
            assessment.riskLevel == UoWRiskTypes.RiskLevel.NONE ||
            assessment.riskLevel == UoWRiskTypes.RiskLevel.LOW,
            'Low-volume insert should result in NONE or LOW risk level'
        );
    }

    @isTest
    static void test_standardRiskAssessor_riskLevel_mediumThreshold() {
        // Arrange - Test LOW risk level threshold
        UoWStandardRiskAssessor assessor = new UoWStandardRiskAssessor();
        UoWContext ctx = new UoWContext('TestConfigAllMocks');
        UoWPlan plan = new UoWPlan();

        // Add low-volume records for minimal risk
        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(500);
        List<Contact> contacts = UoWCoreTestDataFactory.createContacts(500, null);

        UoWDmlWorkItem accountWorkItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.INSERT_OP,
            Account.SObjectType,
            accounts
        );
        plan.registerDmlWork(accountWorkItem);

       UoWDmlWorkItem contactWorkItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.UPDATE_OP,
            Contact.SObjectType,
            contacts
        );
        plan.registerDmlWork(contactWorkItem);

        // Act
        Test.startTest();
        UoWRiskTypes.RiskAssessment assessment = assessor.assessRisk(ctx, plan);
        Test.stopTest();

        // Assert
        Assert.areEqual(UoWRiskTypes.RiskLevel.MEDIUM, assessment.riskLevel, 'Multiple medium-volume insert should result in MEDIUM risk level');
    }

    @isTest
    static void test_standardRiskAssessor_riskLevel_highThreshold() {
        // Arrange - Test HIGH risk level threshold
        UoWStandardRiskAssessor assessor = new UoWStandardRiskAssessor();
        UoWContext ctx = new UoWContext('TestConfigAllMocks');
        UoWPlan plan = new UoWPlan();

        // Add low-volume records for minimal risk
        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(6000);
        List<Contact> contacts = UoWCoreTestDataFactory.createContacts(6000, null);
        List<Opportunity> opportunities = UoWCoreTestDataFactory.createOpportunities(6000, null);
        List<Case> cases = UoWCoreTestDataFactory.createCases(6000, null);

        UoWDmlWorkItem accountWorkItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.INSERT_OP,
            Account.SObjectType,
            accounts
        );
        plan.registerDmlWork(accountWorkItem);

       UoWDmlWorkItem contactWorkItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.UPDATE_OP,
            Contact.SObjectType,
            contacts
        );
        plan.registerDmlWork(contactWorkItem);

        UoWDmlWorkItem opportunityWorkItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.UPSERT_OP,
            Opportunity.SObjectType,
            opportunities
        );
        plan.registerDmlWork(opportunityWorkItem);

        UoWDmlWorkItem caseWorkItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.UNDELETE_OP,
            Case.SObjectType,
            cases
        );
        plan.registerDmlWork(caseWorkItem);

        // Act
        Test.startTest();
        UoWRiskTypes.RiskAssessment assessment = assessor.assessRisk(ctx, plan);
        Test.stopTest();

        // Assert
        Assert.areEqual(UoWRiskTypes.RiskLevel.HIGH, assessment.riskLevel, 'Multiple operations and large volumes should result in HIGH risk level');
    }

    @isTest
    static void test_standardRiskAssessor_approvalThreshold_setsFlag() {
        // Arrange - Test approval threshold logic
        UoWStandardRiskAssessor assessor = new UoWStandardRiskAssessor();
        UoWContext ctx = new UoWContext('TestConfigAllMocks');

        // Note: Approval threshold comes from configuration metadata
        UoWPlan plan = new UoWPlan();

        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(6000);
        UoWDmlWorkItem accountWorkItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.INSERT_OP,
            Account.SObjectType,
            accounts
        );
        plan.registerDmlWork(accountWorkItem);

        List<Account> deleteAccounts = UoWCoreTestDataFactory.createExistingAccounts(6000);
        UoWDmlWorkItem deleteWorkItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.DELETE_OP,
            Account.SObjectType,
            deleteAccounts
        );
        plan.registerDmlWork(deleteWorkItem);

        List<Contact> contacts = UoWCoreTestDataFactory.createContacts(6000, null);
        UoWDmlWorkItem contactWorkItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.INSERT_OP,
            Contact.SObjectType,
            contacts
        );
        plan.registerDmlWork(contactWorkItem);

        // Act
        Test.startTest();
        UoWRiskTypes.RiskAssessment assessment = assessor.assessRisk(ctx, plan);
        Test.stopTest();

        // Assert - Should require approval when score exceeds threshold
        Assert.isTrue(assessment.requiresApproval, 'Should require approval when score exceeds threshold');
        Assert.isNotNull(assessment.approvalReason, 'Should have approval reason');
        Assert.isTrue(assessment.approvalReason.contains('threshold'), 'Approval reason should mention threshold');
    }

    @isTest
    static void test_standardRiskAssessor_assessedAt_setCorrectly() {
        // Arrange
        UoWStandardRiskAssessor assessor = new UoWStandardRiskAssessor();
        UoWContext ctx = new UoWContext('TestConfigMinimal');
        UoWPlan plan = new UoWPlan();

        DateTime beforeAssessment = DateTime.now();

        // Act
        Test.startTest();
        UoWRiskTypes.RiskAssessment assessment = assessor.assessRisk(ctx, plan);
        Test.stopTest();

        DateTime afterAssessment = DateTime.now();

        // Assert - assessedAt should be within the test execution time
        Assert.isNotNull(assessment.assessedAt, 'Should have assessedAt timestamp');
        Assert.isTrue(assessment.assessedAt >= beforeAssessment, 'assessedAt should be >= test start time');
        Assert.isTrue(assessment.assessedAt <= afterAssessment, 'assessedAt should be <= test end time');
    }

    @isTest
    static void test_standardRiskAssessor_riskScoreCapped_at100() {
        // Arrange - Test that risk score is capped at 100
        UoWStandardRiskAssessor assessor = new UoWStandardRiskAssessor();
        UoWContext ctx = new UoWContext('TestConfigMinimal');
        UoWPlan plan = new UoWPlan();

        // Create extreme scenario: large volume delete
        List<Account> accounts = UoWCoreTestDataFactory.createExistingAccounts(6000);
        UoWDmlWorkItem workItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.DELETE_OP,
            Account.SObjectType,
            accounts
        );
        plan.registerDmlWork(workItem);

        // Act
        Test.startTest();
        UoWRiskTypes.RiskAssessment assessment = assessor.assessRisk(ctx, plan);
        Test.stopTest();

        // Assert - Score should be capped at 100
        Assert.isTrue(assessment.riskScore <= 100, 'Risk score should be capped at 100');
    }

    @isTest
    static void test_standardRiskAssessor_operationMultipliers_applied() {
        // Arrange - Test that different operations have different risk weights
        UoWStandardRiskAssessor assessor = new UoWStandardRiskAssessor();
        UoWContext ctx = new UoWContext('TestConfigMinimal');

        // Test INSERT vs DELETE risk (DELETE should be higher)
        UoWPlan insertPlan = new UoWPlan();
        List<Account> insertAccounts = UoWCoreTestDataFactory.createAccounts(100);
        UoWDmlWorkItem insertWorkItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.INSERT_OP,
            Account.SObjectType,
            insertAccounts
        );
        insertPlan.registerDmlWork(insertWorkItem);

        UoWPlan deletePlan = new UoWPlan();
        List<Account> deleteAccounts = UoWCoreTestDataFactory.createExistingAccounts(100);
        UoWDmlWorkItem deleteWorkItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.DELETE_OP,
            Account.SObjectType,
            deleteAccounts
        );
        deletePlan.registerDmlWork(deleteWorkItem);

        // Act
        Test.startTest();
        UoWRiskTypes.RiskAssessment insertAssessment = assessor.assessRisk(ctx, insertPlan);
        UoWRiskTypes.RiskAssessment deleteAssessment = assessor.assessRisk(ctx, deletePlan);
        Test.stopTest();

        // Assert - DELETE should have higher risk than INSERT (delete has operation risk factor)
        Assert.isTrue(deleteAssessment.riskScore >= insertAssessment.riskScore, 'DELETE operation should have higher or equal risk than INSERT');
    }

    // ============================================================================
    // Private Helpers
    // ============================================================================

    private static Boolean contextHasStrippedFieldWarning(UoWContext ctx, String fieldName) {
        for (UoWMessage msg : ctx.getMessages()) {
            if (msg.loggingLevel == System.LoggingLevel.WARN &&
                msg.message != null &&
                msg.message.contains('inaccessible fields') &&
                msg.message.containsIgnoreCase(fieldName)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean contextHasSecurityErrorMessage(UoWContext ctx) {
        for (UoWMessage msg : ctx.getMessages()) {
            if (msg.loggingLevel == System.LoggingLevel.ERROR &&
                msg.message != null &&
                msg.message.contains('Security enforcement failed')) {
                return true;
            }
        }
        return false;
    }

}