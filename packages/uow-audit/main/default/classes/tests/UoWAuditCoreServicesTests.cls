//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Test class for UoW Audit Core Services.
 * Covers: UoWAuditPlugin, UoWAuditEventPublisher, UoWAuditEventHandler
 *
 * Testing strategy:
 * - UoWAuditPlugin: Tests initialization from JSON settings, plugin configuration, and onFinally hook
 * - UoWAuditEventPublisher: Tests event building for CUSTOM_OBJECT and BIG_OBJECT modes
 * - UoWAuditEventHandler: Tests invocable method routing and storage mode parsing
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Audit Tests
 * @see UoWAuditPlugin
 * @see UoWAuditEventPublisher
 * @see UoWAuditEventHandler
 */
@isTest
@SuppressWarnings('PMD.MethodNamingConventions')
private class UoWAuditCoreServicesTests {

    // ============================================================================
    // TEST SETUP
    // ============================================================================

    @TestSetup
    static void setupTestData() {
        // Load test configurations from static resource
        UoWTestHelpers.loadTestConfigurations();

        // Create test user with UoWAuditAdmin permission set for USER_MODE queries
        UoWAuditTestDataFactory.createAuditAdminUser();
    }

    // ============================================================================
    // UOWAUDITPLUGIN TESTS - INITIALIZATION
    // ============================================================================

    @isTest
    static void test_plugin_initialize_parsesSettings_fromJson() {
        // Arrange
        UoWAuditPlugin plugin = new UoWAuditPlugin();
        UoWPluginSetting__mdt setting = new UoWPluginSetting__mdt(
            Settings__c = '{"storageMode":"BIG_OBJECT","archivalMode":"ARCHIVE","retentionDays":60}'
        );

        // Act
        Test.startTest();
        plugin.initialize(setting);
        Test.stopTest();

        // Assert
        Assert.areEqual(UoWAuditEnums.AuditStorageMode.BIG_OBJECT, plugin.getStorageMode(), 'Should parse storage mode');
        Assert.areEqual(UoWAuditEnums.AuditArchivalMode.ARCHIVE, plugin.getArchivalMode(), 'Should parse archival mode');
        Assert.areEqual(60, plugin.getRetentionDays(), 'Should parse retention days');
        Assert.isFalse(plugin.isCritical(), 'Audit plugin should be non-critical');
    }

    @isTest
    static void test_plugin_initialize_withPartialSettings_usesDefaultsForMissing() {
        // Arrange
        UoWAuditPlugin plugin = new UoWAuditPlugin();
        UoWPluginSetting__mdt setting = new UoWPluginSetting__mdt(
            Settings__c = '{"storageMode":"NONE"}'
        );

        // Act
        Test.startTest();
        plugin.initialize(setting);
        Test.stopTest();

        // Assert
        Assert.areEqual(UoWAuditEnums.AuditStorageMode.NONE, plugin.getStorageMode(), 'Should parse provided storage mode');
        Assert.isFalse(plugin.isAuditingEnabled(), 'Audit plugin should be disabled when Audit Storage is NONE');
        Assert.areEqual(UoWAuditEnums.AuditArchivalMode.PURGE, plugin.getArchivalMode(), 'Should use default archival mode when not provided');
        Assert.areEqual(30, plugin.getRetentionDays(), 'Should use default retention when not provided');
    }

    @isTest
    static void test_plugin_initialize_withNullSetting_usesDefaults() {
        // Arrange
        UoWAuditPlugin plugin = new UoWAuditPlugin();

        // Act
        Test.startTest();
        plugin.initialize(null);
        Test.stopTest();

        // Assert - verify defaults are maintained
        Assert.areEqual(UoWAuditEnums.AuditStorageMode.CUSTOM_OBJECT, plugin.getStorageMode(), 'Should use default CUSTOM_OBJECT storage mode');
        Assert.areEqual(UoWAuditEnums.AuditArchivalMode.PURGE, plugin.getArchivalMode(), 'Should use default PURGE archival mode');
        Assert.areEqual(30, plugin.getRetentionDays(), 'Should use default 30 day retention');
    }

    @isTest
    static void test_plugin_initialize_withEmptySettings_usesDefaults() {
        // Arrange
        UoWAuditPlugin plugin = new UoWAuditPlugin();
        UoWPluginSetting__mdt setting = new UoWPluginSetting__mdt(
            Settings__c = ''
        );

        // Act
        Test.startTest();
        plugin.initialize(setting);
        Test.stopTest();

        // Assert - verify defaults are maintained
        Assert.areEqual(UoWAuditEnums.AuditStorageMode.CUSTOM_OBJECT, plugin.getStorageMode(), 'Should use default CUSTOM_OBJECT storage mode');
        Assert.areEqual(UoWAuditEnums.AuditArchivalMode.PURGE, plugin.getArchivalMode(), 'Should use default PURGE archival mode');
        Assert.areEqual(30, plugin.getRetentionDays(), 'Should use default 30 day retention');
    }

    @isTest
    static void test_plugin_initialize_malformedJson_throwsException() {
        // Arrange
        UoWAuditPlugin plugin = new UoWAuditPlugin();
        UoWPluginSetting__mdt setting = new UoWPluginSetting__mdt(
            Settings__c = '{"storageMode":"BIG_OBJECT}'
        );

        // Act
        Test.startTest();
        try{
            plugin.initialize(setting);
            Assert.fail('Should throw an exception');
        } catch (System.JSONException ex){
            Assert.isTrue(ex.getMessage().containsIgnoreCase('was expecting closing quote for a string value'), 'JsonException - unexpected end of input error should have been thrown');
        }
        Test.stopTest();
    }

    @isTest
    static void test_plugin_initialize_invalidEnumValues_throwsException() {
        // Arrange
        UoWAuditPlugin plugin = new UoWAuditPlugin();
        UoWPluginSetting__mdt setting = new UoWPluginSetting__mdt(
            Settings__c = '{"storageMode":"INVALID"}'
        );

        // Act
        Test.startTest();
        try{
            plugin.initialize(setting);
            Assert.fail('Should throw an exception');
        } catch (System.NoSuchElementException ex){
            Assert.isTrue(ex.getMessage().containsIgnoreCase('No enum value found called INVALID'), 'NoSuchElementException - invalid enum value should throw an exception');
        }
        Test.stopTest();
    }

    // ============================================================================
    // UOWAUDITPLUGIN TESTS - ONFINALLY HOOK
    // ============================================================================

    @isTest
    static void test_plugin_onFinally_returnsSkipped_whenAuditingDisabled() {
        // Arrange
        UoWAuditPlugin plugin = new UoWAuditPlugin();
        UoWPluginSetting__mdt setting = new UoWPluginSetting__mdt(
            Settings__c = '{"storageMode":"NONE"}'
        );
        plugin.initialize(setting);

        // Create minimal mock context and result
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks');
        UoWContext ctx = uow.getContext();
        UoWResult result = new UoWResult(ctx);

        // Act
        Test.startTest();
        UoWPluginExecutor.PhaseResult phaseResult = plugin.onFinally(ctx, result);
        Test.stopTest();

        // Assert
        Assert.areEqual(UoWPluginExecutor.PhaseResult.SKIPPED, phaseResult, 'Should return SKIPPED when auditing is disabled');
    }

    @isTest
    static void test_plugin_onFinally_returnsExecuted_whenAuditingEnabled() {
        // Arrange
        UoWAuditPlugin plugin = new UoWAuditPlugin();
        // Default storage mode is CUSTOM_OBJECT (enabled)

        // Create minimal mock context and result
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks');
        UoWContext ctx = uow.getContext();
        UoWResult result = uow.commitWork();

        // Act
        Test.startTest();
        UoWPluginExecutor.PhaseResult phaseResult = plugin.onFinally(ctx, result);
        Test.stopTest();

        // Assert
        Assert.areEqual(UoWPluginExecutor.PhaseResult.EXECUTED, phaseResult, 'Should return EXECUTED when auditing is enabled');
    }

    // ============================================================================
    // UOWAUDITEVENTPUBLISHER TESTS - PUBLISH RESULT STRUCTURE
    // ============================================================================

    @isTest
    static void test_publisher_customObjectMode_buildsBothEventTypes() {
        // Arrange - Create a real UoW execution to get valid context and result
        UnitOfWork uow = UoWTestHelpers.generateUoW_AllWorkItems('TestConfigAllMocks');
        UoWContext ctx = uow.getContext();
        UoWResult result = uow.commitWork();

        // Default is CUSTOM_OBJECT mode
        UoWAuditPlugin plugin = new UoWAuditPlugin();

        // Act
        Test.startTest();
        UoWAuditEventPublisher.PublishResult publishResult = UoWAuditEventPublisher.publishAuditEvents(ctx, result, plugin);
        Test.stopTest();

        // Assert
        Integer workItemCount = result.getAllWorkItems().size();
        Assert.isTrue(publishResult.transactionEventBuilt, 'Should build transaction event for CUSTOM_OBJECT mode');
        Assert.areEqual(workItemCount, publishResult.workItemEventsBuilt, 'Should track count of work item events built');
        Assert.areEqual(1 + workItemCount, publishResult.getTotalEventsAttempted(), 'Should calculate total as 1 transaction + ' + workItemCount + ' work items');

        //Check database
        List<UoWAuditTransaction__c> auditTransactions = [SELECT Id FROM UoWAuditTransaction__c WHERE CorrelationId__c = :result.correlationId];
        System.Assert.areEqual(1, auditTransactions.size(), 'Should have inserted 1 Audit transaction record');
        List<UoWAuditWorkItem__c> auditWorkItems = [SELECT Id FROM UoWAuditWorkItem__c WHERE AuditTransaction__c =: auditTransactions[0].Id];
        System.Assert.areEqual(workItemCount, auditWorkItems.size(), 'Should have inserted ' + workItemCount + ' audit work item records');
    }

    @isTest
    static void test_publisher_customObjectMode_withErrors_buildsBothEventTypes() {
        // Arrange - Inject failure
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.alwaysFail(
            UoWChaosEngine.Point.DML_INSERT,
            UoWChaosEngine.sampleInsertDmlException()
        );

        // Arrange - Create a real UoW execution to get valid context and result
        UnitOfWork uow = UoWTestHelpers.generateUoW_AllWorkItems('TestConfigAllMocks');
        UoWContext ctx = uow.getContext();
        UoWResult result = uow.commitWork();

        // Default is CUSTOM_OBJECT mode
        UoWAuditPlugin plugin = new UoWAuditPlugin();

        // Act
        Test.startTest();
        UoWAuditEventPublisher.PublishResult publishResult = UoWAuditEventPublisher.publishAuditEvents(ctx, result, plugin);
        Test.stopTest();

        // Assert
        Integer workItemCount = result.getAllWorkItems().size(); // Even in complete failure - all work items should still publish
        Assert.isTrue(publishResult.isSuccess, 'Publsihing should have succeeded');
        Assert.isTrue(publishResult.transactionEventBuilt, 'Should build transaction event for CUSTOM_OBJECT mode');
        Assert.areEqual(workItemCount, publishResult.workItemEventsBuilt, 'Should track count of work item events built');
        Assert.areEqual(1 + workItemCount, publishResult.getTotalEventsAttempted(), 'Should calculate total as 1 transaction + ' + workItemCount + ' work items');
    }

    @isTest
    static void test_publisher_customObjectMode_buildsRecordIndexFromSnapshots() {
        // Arrange - DML inserts only, so work items carry snapshots with real (mock) record Ids
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks');
        UoWContext ctx = uow.getContext();
        UoWResult result = uow.commitWork();

        UoWAuditPlugin plugin = new UoWAuditPlugin(); // default CUSTOM_OBJECT mode

        // Act - publish + deliver platform events (subscriber flow persists records + index rows)
        Test.startTest();
        UoWAuditEventPublisher.publishAuditEvents(ctx, result, plugin);
        Test.stopTest();

        // Assert - reverse-lookup index rows were created for the sampled DML records
        List<UoWAuditRecordIndex__c> indexRows = [
            SELECT RecordId__c, SObjectType__c, Operation__c FROM UoWAuditRecordIndex__c
        ];
        Assert.isFalse(indexRows.isEmpty(), 'DML work items should produce reverse-lookup index rows');
        for (UoWAuditRecordIndex__c row : indexRows) {
            Assert.isNotNull(row.RecordId__c, 'Each index row should carry a record Id');
            Assert.isNotNull(row.SObjectType__c, 'Each index row should carry the SObject type');
        }
    }

    @isTest
    static void test_publisher_bigObjectMode_skipsTransactionEvent() {
        // Arrange
        UnitOfWork uow = UoWTestHelpers.generateUoW_AllWorkItems('TestConfigAllMocks');
        UoWContext ctx = uow.getContext();
        UoWResult result = uow.commitWork();

        UoWAuditPlugin plugin = new UoWAuditPlugin();
        UoWPluginSetting__mdt setting = new UoWPluginSetting__mdt(
            Settings__c = '{"storageMode":"BIG_OBJECT"}'
        );
        plugin.initialize(setting);

        // Act
        Test.startTest();
        UoWAuditEventPublisher.PublishResult publishResult = UoWAuditEventPublisher.publishAuditEvents(ctx, result, plugin);
        Test.stopTest();

        // Assert
        Integer workItemCount = result.getAllWorkItems().size();
        Assert.isTrue(publishResult.isSuccess, 'Publsihing should have succeeded');
        Assert.isFalse(publishResult.transactionEventBuilt, 'Should NOT build transaction event for BIG_OBJECT mode');
        Assert.areEqual(workItemCount, publishResult.workItemEventsBuilt, 'Should still build ' + workItemCount + ' work item events for BIG_OBJECT mode');
        Assert.areEqual(workItemCount, publishResult.getTotalEventsAttempted(), 'Should calculate total as 1 transaction + ' + workItemCount + ' work items');
    }

    @isTest
    static void test_publisher_processResults_allFailures_setsErrorDetails() {
        // Arrange - Create mock failed SaveResults to simulate synchronous publish failures
        // Scenario: CUSTOM_OBJECT mode (1 TRANSACTION + 2 WORK_ITEM events), all fail
        List<Database.SaveResult> failedResults = UoWMockResultBuilder.createFailedSaveResults(
            3, 'REQUIRED_FIELD_MISSING: CorrelationId__c', 'REQUIRED_FIELD_MISSING'
        );

        // Act
        Test.startTest();
        UoWAuditEventPublisher.PublishResult publishResult =
            UoWAuditEventPublisher.processPublishResults(failedResults, 2, true);
        Test.stopTest();

        // Assert - PublishResult fully populated
        Assert.isFalse(publishResult.isSuccess, 'Should mark as failed when all SaveResults fail');
        Assert.isTrue(publishResult.transactionEventBuilt, 'Should reflect CUSTOM_OBJECT mode (has transaction event)');
        Assert.areEqual(2, publishResult.workItemEventsBuilt, 'Should track work item count');
        Assert.areEqual(0, publishResult.successCount, 'No events should succeed');
        Assert.areEqual(3, publishResult.failureCount, 'All 3 events should fail');
        Assert.areEqual(3, publishResult.errors.size(), 'Should capture 3 error entries');

        // Assert - Event identification (first = TRANSACTION, rest = WORK_ITEM_N)
        Assert.areEqual('TRANSACTION', publishResult.errors[0].eventIdentifier, 'First failure should be TRANSACTION event');
        Assert.areEqual('WORK_ITEM_1', publishResult.errors[1].eventIdentifier, 'Second failure should be WORK_ITEM_1');
        Assert.areEqual('WORK_ITEM_2', publishResult.errors[2].eventIdentifier, 'Third failure should be WORK_ITEM_2');

        // Assert - Error details
        Assert.areEqual('REQUIRED_FIELD_MISSING', publishResult.errors[0].errorCode, 'Should capture error status code');
        Assert.isTrue(publishResult.errors[0].errorMessage.contains('CorrelationId__c'), 'Should capture error message');
    }

    @isTest
    static void test_publisher_processResults_partialFailure_capturesMixedResults() {
        // Arrange - BIG_OBJECT mode (no transaction event): 3 work item events, middle one fails
        // Use Account SObjects for mock result generation (processPublishResults only consumes
        // SaveResults, not the original events; platform events don't support Id assignment)
        List<SObject> mockRecords = new List<SObject>{
            new Account(Name = 'Mock Event 1'),
            new Account(Name = 'Mock Event 2'),
            new Account(Name = 'Mock Event 3')
        };
        List<Database.SaveResult> partialResults = UoWMockResultBuilder.createPartialPublishResults(
            mockRecords,
            new List<Integer>{ 1 },
            'Event bus capacity exceeded',
            System.StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION
        );

        // Act
        Test.startTest();
        UoWAuditEventPublisher.PublishResult publishResult =
            UoWAuditEventPublisher.processPublishResults(partialResults, 3, false);
        Test.stopTest();

        // Assert - Mixed results
        Assert.isFalse(publishResult.isSuccess, 'Should mark as failed when any SaveResult fails');
        Assert.isFalse(publishResult.transactionEventBuilt, 'Should reflect BIG_OBJECT mode (no transaction event)');
        Assert.areEqual(3, publishResult.workItemEventsBuilt, 'Should track work item count');
        Assert.areEqual(2, publishResult.successCount, 'Two events should succeed');
        Assert.areEqual(1, publishResult.failureCount, 'One event should fail');
        Assert.areEqual(1, publishResult.errors.size(), 'Should capture 1 error entry');

        // Assert - BIG_OBJECT mode: no TRANSACTION event, so all are WORK_ITEM_N (1-indexed)
        Assert.areEqual('WORK_ITEM_2', publishResult.errors[0].eventIdentifier, 'Failed event should be WORK_ITEM_2 (index 1, 1-indexed)');
    }

    // ============================================================================
    // UOWAUDITEVENTPUBLISHER TESTS - ASYNC FAILURE CALLBACK
    // ============================================================================

    @isTest
    static void test_publisher_injectFailure_auditRecordsNotCreated() {
        // Arrange - Create a real UoW execution to get valid context and result
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');
        UoWContext ctx = uow.getContext();
        UoWResult result = uow.commitWork();

        // Default is CUSTOM_OBJECT mode
        UoWAuditPlugin plugin = new UoWAuditPlugin();

        // Act
        Test.startTest();
        // Publish the events
        UoWAuditEventPublisher.PublishResult publishResult = UoWAuditEventPublisher.publishAuditEvents(ctx, result, plugin);
        // Instruct the test event bus to fail all publishes
        Test.getEventBus().fail();
        Test.stopTest();

        // Assert - Synchronous publish always succeeds; Test.getEventBus().fail() only affects async delivery
        Integer workItemCount = result.getAllWorkItems().size();
        Assert.isTrue(publishResult.isSuccess, 'Synchronous publish should succeed even with async failure injection');
        Assert.isTrue(publishResult.transactionEventBuilt, 'Should build transaction event for CUSTOM_OBJECT mode');
        Assert.areEqual(workItemCount, publishResult.workItemEventsBuilt, 'Should track count of work item events built');
        Assert.areEqual(1 + workItemCount, publishResult.getTotalEventsAttempted(), 'Should calculate total as 1 transaction + ' + workItemCount + ' work items');

        // Check database - no NORMAL audit transactions (events failed to deliver to handler)
        List<UoWAuditTransaction__c> normalTransactions = [
            SELECT Id FROM UoWAuditTransaction__c
            WHERE CorrelationId__c = :result.correlationId
            AND TransactionType__c != 'TOMBSTONE'
        ];
        Assert.areEqual(0, normalTransactions.size(), 'Should have no normal audit transaction records (events did not deliver)');

        // Check for tombstone transaction created by AuditPublishFailureCallback
        List<UoWAuditTransaction__c> tombstones = [
            SELECT Id, TransactionType__c, TransactionStatus__c, HasErrors__c
            FROM UoWAuditTransaction__c
            WHERE CorrelationId__c = :result.correlationId
            AND TransactionType__c = 'TOMBSTONE'
        ];
        Assert.areEqual(1, tombstones.size(), 'Should have 1 tombstone audit transaction');
        Assert.areEqual('TOMBSTONE', tombstones[0].TransactionType__c, 'Tombstone should have TOMBSTONE type');
        Assert.areEqual('FAILED', tombstones[0].TransactionStatus__c, 'Tombstone should have FAILED status');

        // Check for failure tracking record
        List<UoWEventPublishFailure__c> failures = [
            SELECT Id, FailureSource__c, AuditTransaction__c, HasRelatedTransaction__c
            FROM UoWEventPublishFailure__c
            WHERE CorrelationId__c = :result.correlationId
        ];
        Assert.areEqual(1, failures.size(), 'Should have 1 event publish failure record');
        Assert.areEqual('AUDIT_EVENT', failures[0].FailureSource__c, 'Failure source should be AUDIT_EVENT');
        Assert.isTrue(failures[0].HasRelatedTransaction__c, 'Failure should be linked to tombstone');
        Assert.areEqual(tombstones[0].Id, failures[0].AuditTransaction__c, 'Failure should reference the tombstone transaction');
    }

    @isTest
    static void test_publisher_asyncFailure_bigObjectMode_createsTombstone() {
        // Arrange - BIG_OBJECT mode only produces denormalized WORK_ITEM events (no TRANSACTION event),
        // so we need at least 1 work item for events to be published and the failure callback to fire
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks');
        UoWContext ctx = uow.getContext();
        UoWResult result = uow.commitWork();

        UoWAuditPlugin plugin = new UoWAuditPlugin();
        UoWPluginSetting__mdt setting = new UoWPluginSetting__mdt(
            Settings__c = '{"storageMode":"BIG_OBJECT"}'
        );
        plugin.initialize(setting);

        // Act
        Test.startTest();
        UoWAuditEventPublisher.PublishResult publishResult = UoWAuditEventPublisher.publishAuditEvents(ctx, result, plugin);
        Test.getEventBus().fail();
        Test.stopTest();

        // Assert - Synchronous publish succeeds
        Assert.isTrue(publishResult.isSuccess, 'Synchronous publish should succeed');
        Assert.isFalse(publishResult.transactionEventBuilt, 'BIG_OBJECT mode should NOT build separate transaction event');

        // BIG_OBJECT mode writes tombstones to UoWAuditHistory__b only (not custom objects)
        List<UoWAuditTransaction__c> tombstones = [
            SELECT Id FROM UoWAuditTransaction__c
            WHERE CorrelationId__c = :result.correlationId
            AND TransactionType__c = 'TOMBSTONE'
        ];
        Assert.areEqual(0, tombstones.size(), 'BIG_OBJECT mode should NOT create custom object tombstones');

        // Verify captured context (confirms callback was invoked)
        List<UoWEventPublishFailureContext> captured =
            UoWAuditPublishFailureCallback.capturedAuditFailures;
        Assert.areEqual(1, captured.size(), 'Should capture 1 audit failure context');
        Assert.areEqual(result.correlationId, captured[0].correlationId, 'Captured context should have correct correlationId');
        Assert.areEqual('BIG_OBJECT', captured[0].metadata.get('storageMode'), 'Captured context should have correct storage mode');
    }

    @isTest
    static void test_publisher_successfulPublish_noFailureRecords() {
        // Arrange - Successful publish (no Test.getEventBus().fail())
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');
        UoWContext ctx = uow.getContext();
        UoWResult result = uow.commitWork();

        UoWAuditPlugin plugin = new UoWAuditPlugin();

        // Act
        Test.startTest();
        UoWAuditEventPublisher.PublishResult publishResult = UoWAuditEventPublisher.publishAuditEvents(ctx, result, plugin);
        Test.stopTest();

        // Assert
        Assert.isTrue(publishResult.isSuccess, 'Publishing should succeed');

        // No tombstone transactions should exist
        List<UoWAuditTransaction__c> tombstones = [
            SELECT Id FROM UoWAuditTransaction__c
            WHERE CorrelationId__c = :result.correlationId
            AND TransactionType__c = 'TOMBSTONE'
        ];
        Assert.areEqual(0, tombstones.size(), 'Should have no tombstone transactions on successful publish');

        // No failure records should exist
        List<UoWEventPublishFailure__c> failures = [
            SELECT Id FROM UoWEventPublishFailure__c
            WHERE CorrelationId__c = :result.correlationId
        ];
        Assert.areEqual(0, failures.size(), 'Should have no failure records on successful publish');

        // No captured audit failures
        List<UoWEventPublishFailureContext> captured =
            UoWAuditPublishFailureCallback.capturedAuditFailures;
        Assert.areEqual(0, captured.size(), 'Should capture no audit failure contexts on success');
    }

    // ============================================================================
    // UOWAUDITEVENTPUBLISHFAILUREHANDLER TESTS - BUSINESS EVENT FAILURES
    // ============================================================================

    @isTest
    static void test_auditFailureHandler_businessEvent_createsFailureRecord() {
        // Arrange - First create an audit transaction that the handler can link to
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');
        UoWContext ctx = uow.getContext();
        UoWResult result = uow.commitWork();

        // Publish audit events so we have a real audit transaction record
        UoWAuditPlugin plugin = new UoWAuditPlugin();

        Test.startTest();
        UoWAuditEventPublisher.publishAuditEvents(ctx, result, plugin);
        Test.stopTest();

        // Verify audit transaction exists
        List<UoWAuditTransaction__c> auditTxns = [
            SELECT Id FROM UoWAuditTransaction__c
            WHERE TransactionId__c = :result.transactionId
        ];
        Assert.areEqual(1, auditTxns.size(), 'Should have audit transaction record to link to');

        // Act - Invoke the business event failure handler directly
        UoWEventPublishFailureHandler handler = new UoWEventPublishFailureHandler();
        Assert.areEqual('Event Publish Failure Handler', handler.getName(), 'Handler name should match');

        UoWEventPublishFailureContext failureCtx = new UoWEventPublishFailureContext();
        failureCtx.correlationId = result.correlationId;
        failureCtx.transactionId = result.transactionId;
        failureCtx.workId = 'test-work-id-001';
        failureCtx.failedEventCount = 3;
        failureCtx.publishedEventCount = 5;
        failureCtx.failedAt = DateTime.now();

        handler.handleFailure(failureCtx);

        // Assert - Failure record should be created with BUSINESS_EVENT source
        List<UoWEventPublishFailure__c> failures = [
            SELECT Id, FailureSource__c, WorkId__c, FailedEventCount__c,
                   PublishedEventCount__c, AuditTransaction__c, HasRelatedTransaction__c
            FROM UoWEventPublishFailure__c
            WHERE CorrelationId__c = :result.correlationId
        ];
        Assert.areEqual(1, failures.size(), 'Should have 1 failure record from handler');
        Assert.areEqual('BUSINESS_EVENT', failures[0].FailureSource__c, 'Failure source should be BUSINESS_EVENT');
        Assert.areEqual('test-work-id-001', failures[0].WorkId__c, 'WorkId should match');
        Assert.areEqual(3, failures[0].FailedEventCount__c, 'Failed event count should match');
        Assert.areEqual(5, failures[0].PublishedEventCount__c, 'Published event count should match');
        Assert.isTrue(failures[0].HasRelatedTransaction__c, 'Should be linked to audit transaction');
        Assert.areEqual(auditTxns[0].Id, failures[0].AuditTransaction__c, 'Should reference the correct audit transaction');
    }

    @isTest
    static void test_auditFailureHandler_noAuditTransaction_createsOrphan() {
        // Arrange - Do NOT create an audit transaction beforehand.
        // This simulates a timing issue where the failure callback fires
        // before audit events have been processed into UoWAuditTransaction__c.
        UoWEventPublishFailureHandler handler = new UoWEventPublishFailureHandler();

        // Use raw UUIDs - CorrelationId__c and TransactionId__c have max length 36
        String orphanTransactionId = UoWUtils.generateUUID();
        String orphanCorrelationId = UoWUtils.generateUUID();

        UoWEventPublishFailureContext failureCtx = new UoWEventPublishFailureContext();
        failureCtx.correlationId = orphanCorrelationId;
        failureCtx.transactionId = orphanTransactionId;
        failureCtx.workId = 'test-work-id-orphan';
        failureCtx.failedEventCount = 2;
        failureCtx.publishedEventCount = 2;
        failureCtx.failedAt = DateTime.now();

        // Act
        Test.startTest();
        handler.handleFailure(failureCtx);
        Test.stopTest();

        // Assert - Orphan transaction should be created with ORPHAN type
        List<UoWAuditTransaction__c> orphanTxns = [
            SELECT Id, TransactionType__c, TransactionStatus__c, HasErrors__c
            FROM UoWAuditTransaction__c
            WHERE TransactionId__c = :orphanTransactionId
        ];
        Assert.areEqual(1, orphanTxns.size(), 'Should create orphan audit transaction');
        Assert.areEqual('TOMBSTONE', orphanTxns[0].TransactionType__c, 'Transaction type should be TOMBSTONE');
        Assert.areEqual('FAILED', orphanTxns[0].TransactionStatus__c, 'Transaction status should be FAILED');

        // Assert - Failure record should be linked to the orphan transaction
        List<UoWEventPublishFailure__c> failures = [
            SELECT Id, AuditTransaction__c, HasRelatedTransaction__c, FailureSource__c
            FROM UoWEventPublishFailure__c
            WHERE CorrelationId__c = :orphanCorrelationId
        ];
        Assert.areEqual(1, failures.size(), 'Should have 1 failure record');
        Assert.areEqual(orphanTxns[0].Id, failures[0].AuditTransaction__c, 'Failure should reference orphan transaction');
        Assert.isTrue(failures[0].HasRelatedTransaction__c, 'Should be linked to orphan transaction');
        Assert.areEqual('BUSINESS_EVENT', failures[0].FailureSource__c, 'Failure source should be BUSINESS_EVENT');
    }

}
