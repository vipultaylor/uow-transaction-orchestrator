//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Tests for UoW serialization architecture.
 * Covers round-trip serialization for async execution (Queueable),
 * work item prepare/hydrate lifecycle, and UoWSerializationService methods.
 *
 * These tests validate that:
 * - Schema.SObjectType is properly restored from sobjectTypeName strings
 * - Schema.SObjectField is properly restored from field name strings
 * - Messaging.Email is properly captured/restored via EmailMetadata
 * - UoWRelationship childField is properly serialized/hydrated
 * - UoWFeatureSettings extensibility points are resolved after deserialization
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Tests
 * @see UoWSerializationService
 * @see UoWQueueable
 */
@isTest
@SuppressWarnings('PMD.MethodNamingConventions')
private class UoWCoreSerializationTests {

    // ============================================================================
    // TEST SETUP
    // ============================================================================

    @TestSetup
    static void setupTestData() {
        UoWTestHelpers.loadTestConfigurations();
    }

    // ============================================================================
    // COMPREHENSIVE ASYNC ROUND-TRIP TESTS (ALL WORK TYPES)
    // ============================================================================

    @isTest
    static void test_allWorkItems_asyncRoundTrip_preservesState() {
        // Arrange - Use helper to generate UoW with ALL work item types
        UnitOfWork uow = UoWTestHelpers.generateUoW_AllWorkItems('TestConfigAllMocks');
        UoWContext ctx = uow.getContext();
        UoWPlan plan = uow.getPlan();

        // Add errors with context to some work items to test error serialization
        UoWDmlWorkItem firstDmlItem = plan.getPlannedDmlWork()[0];
        UoWExceptionService.ErrorInfo testError = new UoWExceptionService.ErrorInfo('TEST_ERROR', 'Test validation error');
        testError.addContext('fieldName', 'Name');
        testError.addContext('recordIndex', 0);
        testError.addContext('severity', 'HIGH');
        firstDmlItem.addError(testError);

        // Capture counts before serialization
        Integer dmlWorkCount = plan.getPlannedDmlWork().size();
        Integer eventWorkCount = plan.getPlannedEventWork().size();
        Integer emailWorkCount = plan.getPlannedEmailWork().size();
        Integer flowWorkCount = plan.getPlannedFlowWork().size();
        Integer notificationWorkCount = plan.getPlannedNotificationWork().size();
        Integer calloutWorkCount = plan.getPlannedCalloutWork().size();
        Integer relationshipCount = plan.getRelationships().size();

        // Act - Prepare for async serialization
        UoWSerializationService.prepareForAsync(ctx, plan);

        // Simulate serialization - clear ALL transient fields
        for (UoWDmlWorkItem item : plan.getPlannedDmlWork()) {
            item.sobjectType = null;
            item.externalIdField = null;
            // Clear error context transient fields
            for (UoWExceptionService.ErrorInfo err : item.errors) {
                err.errorContext = null;
            }
        }
        for (UoWEventWorkItem item : plan.getPlannedEventWork()) {
            item.sobjectType = null;
        }
        for (UoWRelationship rel : plan.getRelationships()) {
            rel.childField = null;
        }

        // Hydrate from async
        UoWSerializationService.hydrateFromAsync(ctx, plan);

        // Assert - All work item counts preserved
        Assert.areEqual(dmlWorkCount, plan.getPlannedDmlWork().size(), 'DML work item count should be preserved');
        Assert.areEqual(eventWorkCount, plan.getPlannedEventWork().size(), 'Event work item count should be preserved');
        Assert.areEqual(emailWorkCount, plan.getPlannedEmailWork().size(), 'Email work item count should be preserved');
        Assert.areEqual(flowWorkCount, plan.getPlannedFlowWork().size(), 'Flow work item count should be preserved');
        Assert.areEqual(notificationWorkCount, plan.getPlannedNotificationWork().size(), 'Notification work item count should be preserved');
        Assert.areEqual(calloutWorkCount, plan.getPlannedCalloutWork().size(), 'Callout work item count should be preserved');
        Assert.areEqual(relationshipCount, plan.getRelationships().size(), 'Relationship count should be preserved');

        // Assert - Transient fields restored for DML work items
        for (UoWDmlWorkItem item : plan.getPlannedDmlWork()) {
            Assert.isNotNull(item.sobjectType, 'DML sobjectType should be restored');
            Assert.isNotNull(item.sobjectTypeName, 'DML sobjectTypeName should be preserved');
            Assert.isTrue(item.getOriginalRecords().size() > 0, 'DML records should be restored');
        }

        // Assert - Error context restored
        UoWDmlWorkItem restoredDmlItem = plan.getPlannedDmlWork()[0];
        Assert.areEqual(1, restoredDmlItem.errors.size(), 'Error count should be preserved');
        UoWExceptionService.ErrorInfo restoredError = restoredDmlItem.errors[0];
        Assert.isNotNull(restoredError.errorContext, 'Error context should be restored');
        Assert.areEqual('Name', restoredError.errorContext.get('fieldName'), 'Error context fieldName should be restored');
        Assert.areEqual(0, restoredError.errorContext.get('recordIndex'), 'Error context recordIndex should be restored');
        Assert.areEqual('HIGH', restoredError.errorContext.get('severity'), 'Error context severity should be restored');

        // Assert - Transient fields restored for Event work items
        for (UoWEventWorkItem item : plan.getPlannedEventWork()) {
            Assert.isNotNull(item.sobjectType, 'Event sobjectType should be restored');
        }

        // Assert - Emails restored from metadata
        for (UoWEmailWorkItem item : plan.getPlannedEmailWork()) {
            Assert.isTrue(item.getEmails().size() > 0, 'Emails should be restored');
        }

        // Assert - Relationships restored
        for (UoWRelationship rel : plan.getRelationships()) {
            Assert.isNotNull(rel.childField, 'Relationship childField should be restored');
        }

        // Assert - Flow work items preserved
        for (UoWFlowWorkItem item : plan.getPlannedFlowWork()) {
            Assert.isNotNull(item.flowApiName, 'Flow apiName should be preserved');
        }

        // Assert - Notification work items preserved
        for (UoWNotificationWorkItem item : plan.getPlannedNotificationWork()) {
            Assert.isNotNull(item.title, 'Notification title should be preserved');
        }

        // Assert - Callout work items preserved
        for (UoWCalloutWorkItem item : plan.getPlannedCalloutWork()) {
            Assert.isNotNull(item.endpoint, 'Callout endpoint should be preserved');
        }
    }

    @isTest
    static void test_allWorkItems_prepareForAudit_appliesSampling() {
        // Arrange - Use helper to generate UoW with ALL work item types
        UnitOfWork uow = UoWTestHelpers.generateUoW_AllWorkItems('TestConfigAllMocks');

        // Act - Execute the transaction first to populate results
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Transaction completed successfully
        UoWTestHelpers.assertSuccess(result);

        // Now prepare for audit AFTER commitWork - get work items FROM RESULT (not plan)
        UoWSerializationConfig config = UoWSerializationConfig.forAudit(
            UoWEnums.SamplingStrategy.FIRST_N, 2
        );

        // Prepare ALL executed work item types for audit with sampling
        for (UoWDmlWorkItem item : result.getAllDmlWork()) {
            item.prepareForSerialization(config);
        }
        for (UoWEventWorkItem item : result.getAllEventWork()) {
            item.prepareForSerialization(config);
        }
        for (UoWEmailWorkItem item : result.getAllEmailWork()) {
            item.prepareForSerialization(config);
        }
        for (UoWFlowWorkItem item : result.getAllFlowWork()) {
            item.prepareForSerialization(config);
        }
        for (UoWNotificationWorkItem item : result.getAllNotificationWork()) {
            item.prepareForSerialization(config);
        }
        for (UoWCalloutWorkItem item : result.getAllCalloutWork()) {
            item.prepareForSerialization(config);
        }

        // Assert - DML snapshots should be sampled (max 2 per work item)
        for (UoWDmlWorkItem item : result.getAllDmlWork()) {
            List<UoWDmlWorkItem.RecordSnapshot> snapshots = item.getSnapshots();
            Assert.isNotNull(snapshots, 'DML snapshots should not be null');
            Assert.isTrue(snapshots.size() <= 2, 'DML snapshots should be limited to sample size: ' + snapshots.size());
        }

        // Assert - Event snapshots should be sampled
        for (UoWEventWorkItem item : result.getAllEventWork()) {
            List<UoWEventWorkItem.EventSnapshot> snapshots = item.getSnapshots();
            Assert.isNotNull(snapshots, 'Event snapshots should not be null');
            Assert.isTrue(snapshots.size() <= 2, 'Event snapshots should be limited to sample size: ' + snapshots.size());
        }

        // Assert - Email work items were processed (prepareForSerialization captures metadata internally)
        Assert.isFalse(result.getAllEmailWork().isEmpty(), 'Should have email work items');
        for (UoWEmailWorkItem item : result.getAllEmailWork()) {
            if(item.executionPhase == UoWEnums.WorkPhase.ON_FAILURE){
                Assert.isFalse(item.isExecuted, 'Email work item ON_FILURE should NOT be marked as executed');
            } else {
                Assert.isTrue(item.isExecuted, 'Email work item should be marked as executed');
            }
        }
    }

    @isTest
    static void test_dmlWorkItems_prepareForAudit_withErrors_capturesErrorContext() {
        // Configure ChaosEngine to inject partial failures on DML INSERT
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_INSERT,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{ 0 },  // Fail first record
                'Validation failed for test',
                System.StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION
            )
        );

        // Arrange - Create UoW with DML work items only
        UnitOfWork uow = new UnitOfWork('TestConfigAllMocks');
        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(3);
        uow.registerInsert(accounts).continueOnError();

        // Act - Execute the transaction (will have partial failures)
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Transaction should be PARTIAL_SUCCESS
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.PARTIAL_SUCCESS);

        // Prepare DML work items for audit
        UoWSerializationConfig config = UoWSerializationConfig.forAudit(
            UoWEnums.SamplingStrategy.FIRST_N, 10
        );

        // Prepare for serialization
        UoWSerializationService.prepareWorkItemsForAuditSnapshot(result.getAllDmlWork(), config);

        // Assert - DML work items should have errors captured
        Boolean foundDmlErrors = false;
        for (UoWDmlWorkItem item : result.getAllDmlWork()) {
            if (item.operation == UoWEnums.DmlOperation.INSERT_OP && !item.errors.isEmpty()) {
                foundDmlErrors = true;

                // Verify error context was captured for serialization
                for (UoWExceptionService.ErrorInfo error : item.errors) {
                    Assert.isNotNull(error.errorType, 'Error should have errorType');
                    Assert.isNotNull(error.errorMessage, 'Error should have errorMessage');

                    // Verify context is captured to serialized string
                    if (error.errorContext != null && !error.errorContext.isEmpty()) {
                        Assert.isNotNull(error.errorContextSerialized, 'Error context should be serialized');
                    }
                }

                // Verify snapshots include the failed record
                List<UoWDmlWorkItem.RecordSnapshot> snapshots = item.getSnapshots();
                Assert.isNotNull(snapshots, 'Snapshots should be built');
                Assert.isFalse(snapshots.isEmpty(), 'Should have snapshots including failed records');
            }
        }
        Assert.isTrue(foundDmlErrors, 'Should have found DML work items with errors');
        Assert.isTrue(result.hasErrors(), 'Result should have errors tracked');

        // Cleanup chaos
        UoWChaosEngine.reset();
    }

    @isTest
    static void test_eventWorkItems_prepareForAudit_withErrors_capturesErrorContext() {
        // Configure ChaosEngine to inject complete failure on event publish
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.PLATFORM_EVENT_PUBLISH,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{0},
                'You must enter a value: RequiredField__c',
                System.StatusCode.REQUIRED_FIELD_MISSING
            )
        );

        // Arrange - Create UoW with event work items only
        UnitOfWork uow = new UnitOfWork('TestConfigAllMocks');
        UoWTestHelpers.TestUoWOptions options = new UoWTestHelpers.TestUoWOptions(false, true);
        UoWTestHelpers.registerEvents(uow, options, 3);

        // Act - Execute the transaction (events will fail)
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Transaction should have failures
        Assert.isTrue(result.hasErrors(), 'Result should have errors from event failure');

        // Prepare event work items for audit
        UoWSerializationConfig config = UoWSerializationConfig.forAudit(
            UoWEnums.SamplingStrategy.FIRST_N, 10
        );

        // Prepare for serialization
        UoWSerializationService.prepareWorkItemsForAuditSnapshot(result.getAllEventWork(), config);

        // Assert - Event work items should have errors captured
        Boolean foundEventErrors = false;
        for (UoWEventWorkItem item : result.getAllEventWork()) {
            if (!item.errors.isEmpty()) {
                foundEventErrors = true;

                // Verify error context was captured
                for (UoWExceptionService.ErrorInfo error : item.errors) {
                    Assert.isNotNull(error.errorType, 'Error should have errorType');
                    Assert.isNotNull(error.errorMessage, 'Error should have errorMessage');
                }

                // Verify snapshots are built
                List<UoWEventWorkItem.EventSnapshot> snapshots = item.getSnapshots();
                Assert.isNotNull(snapshots, 'Event snapshots should be built');
            }
        }
        Assert.isTrue(foundEventErrors, 'Should have found event work items with errors');

        // Cleanup chaos
        UoWChaosEngine.reset();
    }

    @isTest
    static void test_emailWorkItems_prepareForAudit_withErrors_capturesErrorContext() {
        // Configure ChaosEngine to inject failure on email send
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.EMAIL_SEND,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{0},
                'Invalid email address',
                System.StatusCode.INVALID_EMAIL_ADDRESS
            )
        );

        // Arrange - Create UoW with email work items only
        UnitOfWork uow = new UnitOfWork('TestConfigAllMocks');
        UoWTestHelpers.TestUoWOptions options = new UoWTestHelpers.TestUoWOptions(false, true);
        UoWTestHelpers.registerEmails(uow, options, 1);

        // Act - Execute the transaction (email will fail)
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Transaction should have failures
        Assert.isTrue(result.hasErrors(), 'Result should have errors from email failure');

        // Prepare email work items for audit
        UoWSerializationConfig config = UoWSerializationConfig.forAudit(
            UoWEnums.SamplingStrategy.FIRST_N, 10
        );

        // Prepare for serialization
        UoWSerializationService.prepareWorkItemsForAuditSnapshot(result.getAllEmailWork(), config);

        // Assert - Email work items should have errors captured
        Boolean foundEmailErrors = false;
        for (UoWEmailWorkItem item : result.getAllEmailWork()) {
            if (!item.errors.isEmpty()) {
                foundEmailErrors = true;

                // Verify error context was captured
                for (UoWExceptionService.ErrorInfo error : item.errors) {
                    Assert.isNotNull(error.errorType, 'Error should have errorType');
                    Assert.isNotNull(error.errorMessage, 'Error should have errorMessage');
                }
            }
        }
        Assert.isTrue(foundEmailErrors, 'Should have found email work items with errors');

        // Cleanup chaos
        UoWChaosEngine.reset();
    }

    // ============================================================================
    // UPSERT EXTERNAL ID FIELD SERIALIZATION (SPECIAL CASE)
    // ============================================================================

    @isTest
    static void test_upsertWorkItem_externalIdField_roundTrip() {
        // Arrange - UPSERT has special handling for externalIdField
        Account acc = UoWCoreTestDataFactory.createAccount('Upsert Test');
        UoWDmlWorkItem workItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.UPSERT_OP,
            Account.SObjectType,
            new List<SObject>{ acc }
        );
        workItem.externalIdField = Account.Id;
        workItem.externalIdFieldName = 'Id';

        // Act - Round-trip serialization
        workItem.prepareForSerialization();
        workItem.sobjectType = null;
        workItem.externalIdField = null;
        workItem.hydrate();

        // Assert
        Assert.areEqual(Account.SObjectType, workItem.sobjectType, 'sobjectType should be restored');
        Assert.isNotNull(workItem.externalIdField, 'externalIdField should be restored for UPSERT');
        Assert.areEqual('Id', workItem.externalIdFieldName, 'externalIdFieldName should be preserved');
    }

    // ============================================================================
    // RELATIONSHIP SERIALIZATION TESTS
    // ============================================================================

    @isTest
    static void test_relationship_captureFieldName_storesFieldApiName() {
        // Arrange
        Account parentAcc = UoWCoreTestDataFactory.createAccount('Parent');
        Contact childCon = UoWCoreTestDataFactory.createContact('Child', null);

        UoWRelationship rel = new UoWRelationship(childCon, Contact.AccountId, parentAcc);

        // Act
        rel.captureFieldName();

        // Assert
        Assert.areEqual('AccountId', rel.childFieldName, 'childFieldName should be AccountId');
        Assert.areEqual('Contact', rel.childSObjectTypeName, 'childSObjectTypeName should be Contact');
    }

    @isTest
    static void test_relationship_hydrateField_restoresSchemaField() {
        // Arrange
        Account parentAcc = UoWCoreTestDataFactory.createAccount('Parent');
        Contact childCon = UoWCoreTestDataFactory.createContact('Child', null);

        UoWRelationship rel = new UoWRelationship(childCon, Contact.AccountId, parentAcc);
        rel.captureFieldName();
        rel.childField = null; // Simulate serialization

        // Act
        rel.hydrateField();

        // Assert
        Assert.isNotNull(rel.childField, 'childField should be restored');
        Assert.areEqual(Contact.AccountId, rel.childField, 'childField should be Contact.AccountId');
    }

    // ============================================================================
    // UOWSERIALIZATIONCONFIG FACTORY METHOD TESTS
    // ============================================================================

    @isTest
    static void test_serializationConfig_forAsync_setsCorrectDefaults() {
        // Act
        UoWSerializationConfig config = UoWSerializationConfig.forAsync();

        // Assert
        Assert.areEqual(false, config.applyMasking, 'forAsync should not apply masking');
        Assert.areEqual(false, config.applySampling, 'forAsync should not apply sampling');
        Assert.areEqual(UoWEnums.SamplingStrategy.FIRST_N, config.samplingStrategy, 'Default strategy should be FIRST_N');
        Assert.areEqual(5, config.samplingCount, 'Default sample count should be 5');
    }

    @isTest
    static void test_serializationConfig_forAudit_noSampling_setsCorrectDefaults() {
        // Act
        UoWSerializationConfig config = UoWSerializationConfig.forAudit();

        // Assert
        Assert.areEqual(true, config.applyMasking, 'forAudit should apply masking');
        Assert.areEqual(false, config.applySampling, 'forAudit (no params) should not apply sampling');
    }

    @isTest
    static void test_serializationConfig_forAudit_withSampling_setsCorrectValues() {
        // Act
        UoWSerializationConfig config = UoWSerializationConfig.forAudit(
            UoWEnums.SamplingStrategy.LAST_N, 10
        );

        // Assert
        Assert.areEqual(true, config.applyMasking, 'forAudit should apply masking');
        Assert.areEqual(true, config.applySampling, 'forAudit with params should apply sampling');
        Assert.areEqual(UoWEnums.SamplingStrategy.LAST_N, config.samplingStrategy, 'Strategy should be LAST_N');
        Assert.areEqual(10, config.samplingCount, 'Sample count should be 10');
    }

    @isTest
    static void test_serializationConfig_forAudit_withNullParams_usesDefaults() {
        // Act
        UoWSerializationConfig config = UoWSerializationConfig.forAudit(null, null);

        // Assert
        Assert.areEqual(UoWEnums.SamplingStrategy.FIRST_N, config.samplingStrategy, 'Null strategy should default to FIRST_N');
        Assert.areEqual(5, config.samplingCount, 'Null count should default to 5');
    }

    @isTest
    static void test_serializationConfig_fromObjectSetting_withValidSettings() {
        // Arrange
        UoWFeatureSettings.ObjectSetting objSetting = new UoWFeatureSettings.ObjectSetting();
        objSetting.auditSampleStrategy = 'LAST_N';
        objSetting.auditSampleSize = 15;

        // Act
        UoWSerializationConfig config = UoWSerializationConfig.fromObjectSetting(objSetting);

        // Assert
        Assert.areEqual(true, config.applyMasking, 'fromObjectSetting should apply masking');
        Assert.areEqual(true, config.applySampling, 'Should apply sampling when size > 0');
        Assert.areEqual(UoWEnums.SamplingStrategy.LAST_N, config.samplingStrategy, 'Strategy should be LAST_N');
        Assert.areEqual(15, config.samplingCount, 'Sample count should be 15');
    }

    @isTest
    static void test_serializationConfig_fromObjectSetting_withNullOrInvalidSettings() {
        // Test null setting
        UoWSerializationConfig config1 = UoWSerializationConfig.fromObjectSetting(null);
        Assert.areEqual(false, config1.applySampling, 'Null setting should not apply sampling');

        // Test zero sample size
        UoWFeatureSettings.ObjectSetting objSetting = new UoWFeatureSettings.ObjectSetting();
        objSetting.auditSampleSize = 0;
        UoWSerializationConfig config2 = UoWSerializationConfig.fromObjectSetting(objSetting);
        Assert.areEqual(false, config2.applySampling, 'Zero sample size should not apply sampling');

        // Test invalid strategy
        objSetting.auditSampleStrategy = 'INVALID_STRATEGY';
        objSetting.auditSampleSize = 10;
        UoWSerializationConfig config3 = UoWSerializationConfig.fromObjectSetting(objSetting);
        Assert.areEqual(UoWEnums.SamplingStrategy.FIRST_N, config3.samplingStrategy, 'Invalid strategy should default to FIRST_N');
    }

    // ============================================================================
    // UOWSAMPLINGSERVICE TESTS
    // ============================================================================

    @isTest
    static void test_samplingService_allStrategies() {
        UoWSerializationConfig configFirstN = UoWSerializationConfig.forAudit(UoWEnums.SamplingStrategy.FIRST_N, 3);
        UoWSerializationConfig configLastN = UoWSerializationConfig.forAudit(UoWEnums.SamplingStrategy.LAST_N, 3);
        UoWSerializationConfig configRandom = UoWSerializationConfig.forAudit(UoWEnums.SamplingStrategy.RANDOM, 3);

        // Test FIRST_N
        List<Integer> firstN = UoWSamplingService.sampleIndices(10, null, configFirstN);
        Assert.areEqual(3, firstN.size(), 'FIRST_N should return 3 indices');
        Assert.areEqual(0, firstN[0], 'FIRST_N first index should be 0');
        Assert.areEqual(2, firstN[2], 'FIRST_N last index should be 2');

        // Test LAST_N
        List<Integer> lastN = UoWSamplingService.sampleIndices(10, null, configLastN);
        Assert.areEqual(3, lastN.size(), 'LAST_N should return 3 indices');
        Assert.areEqual(7, lastN[0], 'LAST_N first index should be 7');
        Assert.areEqual(9, lastN[2], 'LAST_N last index should be 9');

        // Test RANDOM
        List<Integer> random = UoWSamplingService.sampleIndices(10, null, configRandom);
        Assert.areEqual(3, random.size(), 'RANDOM should return 3 indices');
        Set<Integer> uniqueRandom = new Set<Integer>(random);
        Assert.areEqual(3, uniqueRandom.size(), 'RANDOM indices should be unique');
    }

    @isTest
    static void test_samplingService_disabledOrFitsWithinLimit() {
        // Sampling disabled
        UoWSerializationConfig configAsync = UoWSerializationConfig.forAsync();
        List<Integer> allIndices = UoWSamplingService.sampleIndices(10, null, configAsync);
        Assert.areEqual(10, allIndices.size(), 'Disabled sampling should return all indices');

        // Count fits within sample size
        UoWSerializationConfig configAudit = UoWSerializationConfig.forAudit(UoWEnums.SamplingStrategy.FIRST_N, 10);
        List<Integer> fitsInLimit = UoWSamplingService.sampleIndices(5, null, configAudit);
        Assert.areEqual(5, fitsInLimit.size(), 'Should return all when count <= sample size');

        // Null config
        List<Integer> nullConfig = UoWSamplingService.sampleIndices(10, null, null);
        Assert.areEqual(10, nullConfig.size(), 'Null config should return all indices');
    }

    @isTest
    static void test_samplingService_edgeCases() {
        UoWSerializationConfig config = UoWSerializationConfig.forAudit(UoWEnums.SamplingStrategy.FIRST_N, 5);

        // Null count
        List<Integer> nullCount = UoWSamplingService.sampleIndices(null, null, config);
        Assert.areEqual(0, nullCount.size(), 'Null count should return empty list');

        // Zero count
        List<Integer> zeroCount = UoWSamplingService.sampleIndices(0, null, config);
        Assert.areEqual(0, zeroCount.size(), 'Zero count should return empty list');
    }

    // ============================================================================
    // ERROR-PRIORITY SAMPLING TESTS
    // ============================================================================

    @isTest
    static void test_samplingService_errorPriority_includesAllFailedIndicesFirst() {
        // Arrange - 3 failures out of 10 records, sample size 5
        UoWSerializationConfig config = UoWSerializationConfig.forAudit(UoWEnums.SamplingStrategy.FIRST_N, 5);
        Set<Integer> failedIndices = new Set<Integer>{ 2, 5, 8 };

        // Act
        List<Integer> indices = UoWSamplingService.sampleIndices(10, failedIndices, config);

        // Assert
        Assert.areEqual(5, indices.size(), 'Should return 5 indices');
        Assert.isTrue(indices.contains(2), 'Should include failed index 2');
        Assert.isTrue(indices.contains(5), 'Should include failed index 5');
        Assert.isTrue(indices.contains(8), 'Should include failed index 8');
        // Remaining 2 should be first successful indices (0, 1)
        Assert.isTrue(indices.contains(0), 'Should include success index 0');
        Assert.isTrue(indices.contains(1), 'Should include success index 1');
    }

    @isTest
    static void test_samplingService_errorPriority_moreFailuresThanSampleSize() {
        // Arrange - 8 failures out of 10 records, sample size 5
        UoWSerializationConfig config = UoWSerializationConfig.forAudit(UoWEnums.SamplingStrategy.FIRST_N, 5);
        Set<Integer> failedIndices = new Set<Integer>{ 0, 1, 2, 3, 4, 5, 6, 7 };

        // Act
        List<Integer> indices = UoWSamplingService.sampleIndices(10, failedIndices, config);

        // Assert
        Assert.areEqual(5, indices.size(), 'Should return only 5 indices');
        for (Integer idx : indices) {
            Assert.isTrue(failedIndices.contains(idx), 'All returned indices should be from failures');
        }
    }

    @isTest
    static void test_samplingService_errorPriority_lastN_withMixedResults() {
        // Arrange - Failures at 1, 3, sample size 4, LAST_N strategy
        UoWSerializationConfig config = UoWSerializationConfig.forAudit(UoWEnums.SamplingStrategy.LAST_N, 4);
        Set<Integer> failedIndices = new Set<Integer>{ 1, 3 };

        // Act
        List<Integer> indices = UoWSamplingService.sampleIndices(10, failedIndices, config);

        // Assert
        Assert.areEqual(4, indices.size(), 'Should return 4 indices');
        Assert.isTrue(indices.contains(1), 'Should include failed index 1');
        Assert.isTrue(indices.contains(3), 'Should include failed index 3');
        // Remaining 2 should be last 2 successes (8, 9)
        Assert.isTrue(indices.contains(8), 'Should include last success index 8');
        Assert.isTrue(indices.contains(9), 'Should include last success index 9');
    }

    @isTest
    static void test_samplingService_errorPriority_resultsAreSorted() {
        // Arrange - Failures at various positions
        UoWSerializationConfig config = UoWSerializationConfig.forAudit(UoWEnums.SamplingStrategy.FIRST_N, 5);
        Set<Integer> failedIndices = new Set<Integer>{ 8, 2, 5 };

        // Act
        List<Integer> indices = UoWSamplingService.sampleIndices(10, failedIndices, config);

        // Assert - Verify sorted
        for (Integer i = 1; i < indices.size(); i++) {
            Assert.isTrue(indices[i] > indices[i-1], 'Indices should be sorted');
        }
    }

    // ============================================================================
    // MASKING BEHAVIOR TESTS
    // ============================================================================

    @isTest
    static void test_dmlWorkItem_maskingBehavior() {
        // Arrange - Create work item with both original and masked records
        List<SObject> originals = new List<SObject>();
        List<SObject> masked = new List<SObject>();
        for (Integer i = 0; i < 5; i++) {
            originals.add(new Account(Name = 'Original ' + i));
            masked.add(new Account(Name = 'Masked ' + i));
        }
        UoWDmlWorkItem workItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.INSERT_OP,
            Account.SObjectType,
            originals
        );
        workItem.setMaskedRecords(masked);

        // Test with masking ENABLED (forAudit)
        UoWSerializationConfig configMasked = UoWSerializationConfig.forAudit();
        workItem.prepareForSerialization(configMasked);
        List<UoWDmlWorkItem.RecordSnapshot> maskedSnapshots = workItem.getSnapshots();
        for (UoWDmlWorkItem.RecordSnapshot snap : maskedSnapshots) {
            Account acc = (Account) snap.rec;
            Assert.isTrue(acc.Name.startsWith('Masked'), 'Should use masked data when masking enabled');
        }

        // Reset and test with masking DISABLED (forAsync)
        UoWSerializationConfig configOriginal = UoWSerializationConfig.forAsync();
        workItem.prepareForSerialization(configOriginal);
        List<UoWDmlWorkItem.RecordSnapshot> originalSnapshots = workItem.getSnapshots();
        for (UoWDmlWorkItem.RecordSnapshot snap : originalSnapshots) {
            Account acc = (Account) snap.rec;
            Assert.isTrue(acc.Name.startsWith('Original'), 'Should use original data when masking disabled');
        }
    }

    @isTest
    static void test_eventWorkItem_maskingBehavior() {
        // Arrange
        List<SObject> originals = new List<SObject>();
        List<SObject> masked = new List<SObject>();
        for (Integer i = 0; i < 3; i++) {
            originals.add(new Account(Name = 'Original Event ' + i));
            masked.add(new Account(Name = 'Masked Event ' + i));
        }
        UoWEventWorkItem workItem = new UoWEventWorkItem(
            UoWEnums.WorkPhase.POST_DML,
            Account.SObjectType,
            originals
        );
        workItem.setMaskedEvents(masked);

        // Test with masking enabled
        UoWSerializationConfig config = UoWSerializationConfig.forAudit();
        workItem.prepareForSerialization(config);
        List<UoWEventWorkItem.EventSnapshot> snapshots = workItem.getSnapshots();
        for (UoWEventWorkItem.EventSnapshot snap : snapshots) {
            Account evt = (Account) snap.evt;
            Assert.isTrue(evt.Name.startsWith('Masked'), 'Should use masked events when masking enabled');
        }
    }

    // ============================================================================
    // SERIALIZATION SERVICE HIGH-LEVEL API TESTS
    // ============================================================================

    @isTest
    static void test_serializationService_handlesNullInputs() {
        // Act - Should not throw with null inputs
        UoWSerializationService.prepareForAsync(null, null);
        UoWSerializationService.hydrateFromAsync(null, null);

        // Assert - No exception means success
        Assert.isTrue(true, 'Should handle null inputs gracefully');
    }

    @isTest
    static void test_serializationService_prepareWorkItemsForAuditSnapshot() {
        // Arrange
        UnitOfWork uow = UoWTestHelpers.generateUoW_AllWorkItems('TestConfigAllMocks');
        List<UoWWorkItem> allItems = new List<UoWWorkItem>();
        allItems.addAll(uow.getPlan().getPlannedDmlWork());

        UoWSerializationConfig config = UoWSerializationConfig.forAudit(UoWEnums.SamplingStrategy.FIRST_N, 2);

        // Act
        UoWSerializationService.prepareWorkItemsForAuditSnapshot(allItems, config);

        // Assert - Items should have snapshots built
        for (UoWWorkItem item : allItems) {
            if (item instanceof UoWDmlWorkItem) {
                UoWDmlWorkItem dmlItem = (UoWDmlWorkItem) item;
                Assert.isNotNull(dmlItem.getSnapshots(), 'Snapshots should be built');
            }
        }
    }

    @isTest
    static void test_serializationService_serializeWorkItemForAudit() {
        // Arrange
        Account acc = UoWCoreTestDataFactory.createAccount('Audit Test');
        UoWDmlWorkItem item = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.INSERT_OP,
            Account.SObjectType,
            new List<SObject>{ acc }
        );
        UoWSerializationConfig config = UoWSerializationConfig.forAudit();

        // Act
        String json = UoWSerializationService.serializeWorkItemForAudit(item, config);

        // Assert
        Assert.isNotNull(json, 'JSON should not be null');
        Assert.isTrue(json.contains('Account'), 'JSON should contain Account type name');
        Assert.isTrue(json.contains('INSERT_OP'), 'JSON should contain operation type');

        // Test null handling
        String nullJson = UoWSerializationService.serializeWorkItemForAudit(null, config);
        Assert.isNull(nullJson, 'JSON should be null for null input');
    }

    // ============================================================================
    // CONTEXT AND PLAN SERIALIZATION TESTS
    // ============================================================================

    @isTest
    static void test_context_reloadFeatureSettings() {
        // Arrange
        UoWContext ctx = new UoWContext('TestConfigAllMocks');

        // Act - Should not throw
        ctx.reloadFeatureSettings();

        // Assert
        Assert.isNotNull(ctx.getFeatureSettings(), 'Feature settings should be accessible after reload');
    }

    @isTest
    static void test_plan_mapKeys_useStringKeys() {
        // Arrange
        UoWPlan plan = new UoWPlan();
        Account acc = UoWCoreTestDataFactory.createAccount('Test');
        Contact con = UoWCoreTestDataFactory.createContact('Test', null);

        plan.registerDmlWork(new UoWDmlWorkItem(UoWEnums.DmlOperation.INSERT_OP, Account.SObjectType, new List<SObject>{ acc }));
        plan.registerDmlWork(new UoWDmlWorkItem(UoWEnums.DmlOperation.INSERT_OP, Contact.SObjectType, new List<SObject>{ con }));

        // Act - Verify retrieval by Schema.SObjectType works (API converts to string internally)
        UoWDmlWorkItem retrievedAcc = plan.getPlannedInsertWork('Account');
        UoWDmlWorkItem retrievedCon = plan.getPlannedInsertWork('Contact');

        // Assert
        Assert.isNotNull(retrievedAcc, 'Should retrieve Account work item');
        Assert.isNotNull(retrievedCon, 'Should retrieve Contact work item');
    }

    // ============================================================================
    // EMAIL WORK ITEM SERIALIZATION TESTS (SPECIAL CASE - Messaging.Email)
    // ============================================================================

    @isTest
    static void test_emailWorkItem_roundTrip_preservesAllProperties() {
        // Arrange - Create email with comprehensive properties
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ 'to@example.com' });
        email.setCcAddresses(new List<String>{ 'cc@example.com' });
        email.setBccAddresses(new List<String>{ 'bcc@example.com' });
        email.setReplyTo('reply@example.com');
        email.setSubject('Comprehensive Test');
        email.setPlainTextBody('Plain text');
        email.setHtmlBody('<html>HTML</html>');
        email.setSenderDisplayName('Test Sender');
        email.setSaveAsActivity(false);
        email.setUseSignature(true);

        UoWEmailWorkItem workItem = new UoWEmailWorkItem(
            UoWEnums.WorkPhase.ON_SUCCESS,
            new List<Messaging.Email>{ email }
        );

        // Act - Round-trip
        workItem.prepareForSerialization();
        workItem.hydrate();

        // Assert
        List<Messaging.Email> restored = workItem.getEmails();
        Assert.areEqual(1, restored.size(), 'Should restore 1 email');

        Messaging.SingleEmailMessage restoredEmail = (Messaging.SingleEmailMessage) restored[0];
        Assert.areEqual('Comprehensive Test', restoredEmail.getSubject(), 'Subject should match');
        Assert.areEqual('Plain text', restoredEmail.getPlainTextBody(), 'Plain text body should match');
        Assert.areEqual('<html>HTML</html>', restoredEmail.getHtmlBody(), 'HTML body should match');
        Assert.areEqual('Test Sender', restoredEmail.getSenderDisplayName(), 'Sender display name should match');
    }

    @isTest
    static void test_emailWorkItem_multipleEmails_roundTrip() {
        // Arrange
        List<Messaging.Email> emails = new List<Messaging.Email>();
        for (Integer i = 0; i < 5; i++) {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ 'test' + i + '@example.com' });
            email.setSubject('Subject ' + i);
            emails.add(email);
        }

        UoWEmailWorkItem workItem = new UoWEmailWorkItem(UoWEnums.WorkPhase.ON_SUCCESS, emails);

        // Act
        workItem.prepareForSerialization();
        workItem.hydrate();

        // Assert
        List<Messaging.Email> restored = workItem.getEmails();
        Assert.areEqual(5, restored.size(), 'Should restore 5 emails');
        for (Integer i = 0; i < restored.size(); i++) {
            Messaging.SingleEmailMessage restoredEmail = (Messaging.SingleEmailMessage) restored[i];
            Assert.areEqual('Subject ' + i, restoredEmail.getSubject(), 'Subject ' + i + ' should match');
        }
    }

    // ============================================================================
    // EDGE CASES AND NULL HANDLING
    // ============================================================================

    @isTest
    static void test_workItems_emptyLists_handleGracefully() {
        // DML with empty records
        UoWDmlWorkItem dmlItem = new UoWDmlWorkItem(UoWEnums.DmlOperation.INSERT_OP, Account.SObjectType, new List<SObject>());
        dmlItem.prepareForSerialization();
        dmlItem.hydrate();
        Assert.areEqual(0, dmlItem.getOriginalRecords().size(), 'Empty DML records should be handled');

        // Event with empty events
        UoWEventWorkItem eventItem = new UoWEventWorkItem(UoWEnums.WorkPhase.POST_DML, Account.SObjectType, new List<SObject>());
        eventItem.prepareForSerialization();
        eventItem.hydrate();
        Assert.areEqual(0, eventItem.getOriginalEvents().size(), 'Empty events should be handled');

        // Email with empty emails
        UoWEmailWorkItem emailItem = new UoWEmailWorkItem(UoWEnums.WorkPhase.ON_SUCCESS, new List<Messaging.Email>());
        emailItem.prepareForSerialization();
        emailItem.hydrate();
        Assert.areEqual(0, emailItem.getEmails().size(), 'Empty emails should be handled');
    }

    // ============================================================================
    // ERROR CONTEXT SERIALIZATION TESTS
    // ============================================================================

    @isTest
    static void test_errorInfo_contextSerialization_roundTrip() {
        // Arrange
        UoWExceptionService.ErrorInfo error = new UoWExceptionService.ErrorInfo('TEST_ERROR', 'Test message');
        error.addContext('recordId', '001XXXXXXXXXXXX');
        error.addContext('fieldName', 'Name');
        error.addContext('attemptNumber', 3);

        // Act - Capture
        error.captureContextForSerialization();

        // Assert - Captured
        Assert.isNotNull(error.errorContextSerialized, 'errorContextSerialized should not be null');
        Assert.isTrue(error.errorContextSerialized.contains('recordId'), 'Should contain recordId');

        // Simulate serialization - clear transient field
        error.errorContext = null;

        // Act - Restore
        error.restoreContextFromSerialization();

        // Assert - Restored
        Assert.isNotNull(error.errorContext, 'errorContext should be restored');
        Assert.areEqual('001XXXXXXXXXXXX', error.errorContext.get('recordId'), 'recordId should be restored');
        Assert.areEqual('Name', error.errorContext.get('fieldName'), 'fieldName should be restored');
        Assert.areEqual(3, error.errorContext.get('attemptNumber'), 'attemptNumber should be restored');
    }

}