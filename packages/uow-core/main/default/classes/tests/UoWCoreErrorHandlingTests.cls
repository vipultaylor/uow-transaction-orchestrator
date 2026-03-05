//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Tests for error handling across all work types in UoW framework.
 * Covers systematic error patterns: complete failure (exception-based),
 * partial failure with fail-fast, partial failure with continueOnError,
 * and all-fail scenarios. Tests error capture, status determination,
 * and rollback behavior.
 *
 * Test Patterns:
 * - Pattern 1: alwaysFail → ROLLED_BACK (exception thrown)
 * - Pattern 2: partialFailure + failFast → ROLLED_BACK (stop on first failure)
 * - Pattern 3: partialFailure + continueOnError → PARTIAL_SUCCESS (some succeed)
 * - Pattern 4: allFail + continueOnError → FAILED (all fail, no exception)
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Tests
 * @see UoWChaosEngine
 * @see UoWResult
 */
@isTest
@SuppressWarnings('PMD.CognitiveComplexity,PMD.MethodNamingConventions,PMD.NcssTypeCount')
private class UoWCoreErrorHandlingTests {
    // ============================================================================
    // TEST SETUP
    // ============================================================================

    @TestSetup
    static void setupTestData() {
        // Load test configurations
        UoWTestHelpers.loadTestConfigurations();
    }

    // ============================================================================
    // INSERT ERROR TESTS
    // ============================================================================

    @isTest
    static void test_insert_alwaysFail_rolledBack() {
        // Arrange
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.alwaysFail(
            UoWChaosEngine.Point.DML_INSERT,
            UoWChaosEngine.sampleInsertDmlException()
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5);

        // Act
        Test.startTest();
        uow.registerInsert(accounts);
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.ROLLED_BACK);

        // Assert aggregate statistics
        // as the dml still executed- ALL records should be marked as processed and failed
        // even if it is an exception
        Assert.areEqual(5, result.statistics.dmlStats.records.processed, 'Should process 5 records');
        Assert.areEqual(0, result.statistics.dmlStats.records.successes, 'Should have 0 successes');
        Assert.areEqual(5, result.statistics.dmlStats.records.errors, 'Should have 5 errors');

        // Assert operation-specific statistics
        Assert.areEqual(5, result.statistics.dmlStats.inserts.records.processed, 'Should process 5 inserts');
        Assert.areEqual(0, result.statistics.dmlStats.inserts.records.successes, 'Should have 0 insert successes');
        Assert.areEqual(5, result.statistics.dmlStats.inserts.records.errors, 'Should have 5 insert errors');

        // Validate exception type
        Boolean hasDmlException = false;
        for (UoWExceptionService.ErrorInfo error : result.getErrors()) {
            if (error.errorType.contains('DmlException')) {
                hasDmlException = true;
                break;
            }
        }
        Assert.isTrue(hasDmlException, 'Should have DmlException');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'DML work item should have FAILED status');
        }
    }

    @isTest
    static void test_insert_partialFailure_failFast_rolledBack() {
        // Arrange - 5 records, indexes 1 and 3 fail
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_INSERT,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{1, 3},
                'Validation rule failed',
                System.StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION
            )
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5);

        // Act
        Test.startTest();
        uow.registerInsert(accounts).failFast();  // Explicit failFast
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.ROLLED_BACK);

        // Assert aggregate statistics - transaction rolled back, no successes
        Assert.areEqual(5, result.statistics.dmlStats.records.processed, 'Should process 5 records');
        Assert.areEqual(0, result.statistics.dmlStats.records.successes, 'Should have 0 successes');
        Assert.areEqual(5, result.statistics.dmlStats.records.errors, 'Should have 5 errors');

        // Assert operation-specific statistics
        Assert.areEqual(5, result.statistics.dmlStats.inserts.records.processed, 'Should process 5 inserts');
        Assert.areEqual(0, result.statistics.dmlStats.inserts.records.successes, 'Should have 0 insert successes');
        Assert.areEqual(5, result.statistics.dmlStats.inserts.records.errors, 'Should have 5 insert errors');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'DML work item should have FAILED status');
        }
    }

    @isTest
    static void test_insert_partialFailure_continueOnError_partialSuccess() {
        // Arrange - 5 records, indexes 1 and 3 fail
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_INSERT,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{1, 3},
                'Duplicate value found',
                System.StatusCode.DUPLICATE_VALUE
            )
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5);

        // Act
        Test.startTest();
        uow.registerInsert(accounts).continueOnError();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.PARTIAL_SUCCESS);

        // Assert aggregate statistics - 5 processed, 3 succeeded, 2 failed
        Assert.areEqual(5, result.statistics.dmlStats.records.processed, 'Should process 5 records');
        Assert.areEqual(3, result.statistics.dmlStats.records.successes, 'Should have 3 successes');

        // Assert operation-specific statistics
        Assert.areEqual(5, result.statistics.dmlStats.inserts.records.processed, 'Should process 5 inserts');
        Assert.areEqual(3, result.statistics.dmlStats.inserts.records.successes, 'Should have 3 insert successes');

        // Assert byType statistics
        Assert.isTrue(result.statistics.dmlStats.inserts.byType.containsKey('Account'), 'Should have Account stats');
        Assert.areEqual(5, result.statistics.dmlStats.inserts.byType.get('Account').processed, 'Should process 5 Accounts');
        Assert.areEqual(3, result.statistics.dmlStats.inserts.byType.get('Account').successes, 'Should have 3 Account successes');

        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Validate error statusCode
        Integer duplicateErrors = 0;
        for (UoWExceptionService.ErrorInfo error : result.getErrors()) {
            if (error.errorType == 'DUPLICATE_VALUE') {
                duplicateErrors++;
            }
        }
        Assert.areEqual(2, duplicateErrors, 'Should have 2 duplicate errors');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.PARTIAL_SUCCESS, workItem.status, 'DML work item should have PARTIAL_SUCCESS status');
        }
    }

    @isTest
    static void test_insert_allFail_continueOnError_failed() {
        // Arrange - 5 records, ALL fail
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_INSERT,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{0, 1, 2, 3, 4},
                'Required field missing',
                System.StatusCode.REQUIRED_FIELD_MISSING
            )
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5);

        // Act
        Test.startTest();
        uow.registerInsert(accounts).continueOnError();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.FAILED);

        // Assert aggregate statistics - 5 processed, 0 succeeded, all failed
        Assert.areEqual(5, result.statistics.dmlStats.records.processed, 'Should process 5 records');
        Assert.areEqual(0, result.statistics.dmlStats.records.successes, 'Should have 0 successes');

        // Assert operation-specific statistics
        Assert.areEqual(5, result.statistics.dmlStats.inserts.records.processed, 'Should process 5 inserts');
        Assert.areEqual(0, result.statistics.dmlStats.inserts.records.successes, 'Should have 0 insert successes');

        // Assert byType statistics
        Assert.isTrue(result.statistics.dmlStats.inserts.byType.containsKey('Account'), 'Should have Account stats');
        Assert.areEqual(5, result.statistics.dmlStats.inserts.byType.get('Account').processed, 'Should process 5 Accounts');
        Assert.areEqual(0, result.statistics.dmlStats.inserts.byType.get('Account').successes, 'Should have 0 Account successes');

        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Validate all errors captured
        Integer requiredFieldErrors = 0;
        for (UoWExceptionService.ErrorInfo error : result.getErrors()) {
            if (error.errorType == 'REQUIRED_FIELD_MISSING') {
                requiredFieldErrors++;
            }
        }
        Assert.areEqual(5, requiredFieldErrors, 'Should have 5 required field errors');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'DML work item should have FAILED status');
        }
    }

    @isTest
    static void test_insert_circularDependency_rolledBack() {
        // Arrange - 5 records
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        Account acc = UoWCoreTestDataFactory.createAccount('Test Account');
        Contact con = UoWCoreTestDataFactory.createContact('Test Contact', null);

        uow.registerInsert(acc);
        uow.registerInsert(con);
        uow.relate(con, Contact.AccountId, acc);
        uow.relate(acc, Account.ParentId, con); // since we dont have a circular relationship in standard objects, manufacturing one for testing

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.ROLLED_BACK);

        Boolean circularDependencyDetected = false;
        for (UoWExceptionService.ErrorInfo error : result.getErrors()) {
            if(error.errorMessage.contains(System.Label.UoW_Error_CircularDependency)){
                circularDependencyDetected = true;
            }
        }

        Assert.isTrue(circularDependencyDetected, 'Should have CIRCULAR_DEPENDENCY error');
    }

    // ============================================================================
    // UPSERT ERROR TESTS
    // ============================================================================

    @isTest
    static void test_upsert_alwaysFail_rolledBack() {
        // Arrange
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.alwaysFail(
            UoWChaosEngine.Point.DML_UPSERT,
            UoWChaosEngine.sampleInsertDmlException()
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5);
        // Mix with and without IDs for upsert
        accounts[0].Id = UoWTestHelpers.generateFakeId(Account.SObjectType, 1);
        accounts[2].Id = UoWTestHelpers.generateFakeId(Account.SObjectType, 2);

        // Act
        Test.startTest();
        uow.registerUpsert(accounts, Account.Id);
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.ROLLED_BACK);

        // Assert aggregate statistics
        Assert.areEqual(5, result.statistics.dmlStats.records.processed, 'Should process 5 records');
        Assert.areEqual(0, result.statistics.dmlStats.records.successes, 'Should have 0 successes');
        Assert.areEqual(5, result.statistics.dmlStats.records.errors, 'Should have 5 errors');

        // Assert operation-specific statistics
        Assert.areEqual(5, result.statistics.dmlStats.upserts.records.processed, 'Should process 5 upserts');
        Assert.areEqual(0, result.statistics.dmlStats.upserts.records.successes, 'Should have 0 upsert successes');
        Assert.areEqual(5, result.statistics.dmlStats.upserts.records.errors, 'Should have 5 upsert errors');

        // Validate exception type
        Boolean hasDmlException = false;
        for (UoWExceptionService.ErrorInfo error : result.getErrors()) {
            if (error.errorType.contains('DmlException')) {
                hasDmlException = true;
                break;
            }
        }
        Assert.isTrue(hasDmlException, 'Should have DmlException');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'DML work item should have FAILED status');
        }
    }

    @isTest
    static void test_upsert_partialFailure_failFast_rolledBack() {
        // Arrange - 5 records, indexes 1 and 3 fail
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_UPSERT,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{1, 3},
                'Duplicate external ID',
                System.StatusCode.DUPLICATE_EXTERNAL_ID
            )
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5);

        // Act
        Test.startTest();
        uow.registerUpsert(accounts, Account.Id).failFast();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.ROLLED_BACK);

        // Assert aggregate statistics - transaction rolled back, no successes
        Assert.areEqual(5, result.statistics.dmlStats.records.processed, 'Should process 5 records');
        Assert.areEqual(0, result.statistics.dmlStats.records.successes, 'Should have 0 successes');
        Assert.areEqual(5, result.statistics.dmlStats.records.errors, 'Should have 5 errors');

        // Assert operation-specific statistics
        Assert.areEqual(5, result.statistics.dmlStats.upserts.records.processed, 'Should process 5 upserts');
        Assert.areEqual(0, result.statistics.dmlStats.upserts.records.successes, 'Should have 0 upsert successes');
        Assert.areEqual(5, result.statistics.dmlStats.upserts.records.errors, 'Should have 5 upsert errors');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'DML work item should have FAILED status');
        }
    }

    @isTest
    static void test_upsert_partialFailure_continueOnError_partialSuccess() {
        // Arrange - 5 records, indexes 1 and 3 fail
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_UPSERT,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{1, 3},
                'Invalid field value',
                System.StatusCode.INVALID_FIELD  // Valid DML StatusCode for invalid field errors
            )
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5);

        // Act
        Test.startTest();
        uow.registerUpsert(accounts, Account.Id).continueOnError();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.PARTIAL_SUCCESS);

        // Assert aggregate statistics - 5 processed, 3 succeeded, 2 failed
        Assert.areEqual(5, result.statistics.dmlStats.records.processed, 'Should process 5 records');
        Assert.areEqual(3, result.statistics.dmlStats.records.successes, 'Should have 3 successes');

        // Assert operation-specific statistics (upsert uses UpsertRecordStatistics)
        Assert.areEqual(5, result.statistics.dmlStats.upserts.records.processed, 'Should process 5 upserts');
        Assert.areEqual(3, result.statistics.dmlStats.upserts.records.successes, 'Should have 3 upsert successes');

        // Assert byType statistics
        Assert.isTrue(result.statistics.dmlStats.upserts.byType.containsKey('Account'), 'Should have Account stats');
        Assert.areEqual(5, result.statistics.dmlStats.upserts.byType.get('Account').processed, 'Should process 5 Accounts');
        Assert.areEqual(3, result.statistics.dmlStats.upserts.byType.get('Account').successes, 'Should have 3 Account successes');

        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Validate error statusCode
        Integer invalidFieldErrors = 0;
        for (UoWExceptionService.ErrorInfo error : result.getErrors()) {
            if (error.errorType == 'INVALID_FIELD') {
                invalidFieldErrors++;
            }
        }
        Assert.areEqual(2, invalidFieldErrors, 'Should have 2 invalid field errors');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.PARTIAL_SUCCESS, workItem.status, 'DML work item should have PARTIAL_SUCCESS status');
        }
    }

    @isTest
    static void test_upsert_allFail_continueOnError_failed() {
        // Arrange - 5 records, ALL fail
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_UPSERT,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{0, 1, 2, 3, 4},
                'External ID field required',
                System.StatusCode.REQUIRED_FIELD_MISSING
            )
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5);

        // Act
        Test.startTest();
        uow.registerUpsert(accounts, Account.Id).continueOnError();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.FAILED);

        // Assert aggregate statistics - 5 processed, 0 succeeded, all failed
        Assert.areEqual(5, result.statistics.dmlStats.records.processed, 'Should process 5 records');
        Assert.areEqual(0, result.statistics.dmlStats.records.successes, 'Should have 0 successes');

        // Assert operation-specific statistics
        Assert.areEqual(5, result.statistics.dmlStats.upserts.records.processed, 'Should process 5 upserts');
        Assert.areEqual(0, result.statistics.dmlStats.upserts.records.successes, 'Should have 0 upsert successes');

        // Assert byType statistics
        Assert.isTrue(result.statistics.dmlStats.upserts.byType.containsKey('Account'), 'Should have Account stats');
        Assert.areEqual(5, result.statistics.dmlStats.upserts.byType.get('Account').processed, 'Should process 5 Accounts');
        Assert.areEqual(0, result.statistics.dmlStats.upserts.byType.get('Account').successes, 'Should have 0 Account successes');

        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Validate all errors captured
        Integer requiredFieldErrors = 0;
        for (UoWExceptionService.ErrorInfo error : result.getErrors()) {
            if (error.errorType == 'REQUIRED_FIELD_MISSING') {
                requiredFieldErrors++;
            }
        }
        Assert.areEqual(5, requiredFieldErrors, 'Should have 5 required field errors');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'DML work item should have FAILED status');
        }
    }

    // ============================================================================
    // UPDATE ERROR TESTS
    // ============================================================================

    @isTest
    static void test_update_alwaysFail_rolledBack() {
        // Arrange
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.alwaysFail(
            UoWChaosEngine.Point.DML_UPDATE,
            UoWChaosEngine.sampleInsertDmlException()
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5);
        for (Integer i = 0; i < accounts.size(); i++) {
            accounts[i].Id = UoWTestHelpers.generateFakeId(Account.SObjectType, i + 1);
        }

        // Act
        Test.startTest();
        uow.registerUpdate(accounts);
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.ROLLED_BACK);

        // Assert aggregate statistics
        Assert.areEqual(5, result.statistics.dmlStats.records.processed, 'Should process 5 records');
        Assert.areEqual(0, result.statistics.dmlStats.records.successes, 'Should have 0 successes');
        Assert.areEqual(5, result.statistics.dmlStats.records.errors, 'Should have 5 errors');

        // Assert operation-specific statistics
        Assert.areEqual(5, result.statistics.dmlStats.updates.records.processed, 'Should process 5 updates');
        Assert.areEqual(0, result.statistics.dmlStats.updates.records.successes, 'Should have 0 update successes');
        Assert.areEqual(5, result.statistics.dmlStats.updates.records.errors, 'Should have 5 update errors');

        // Validate exception type
        Boolean hasDmlException = false;
        for (UoWExceptionService.ErrorInfo error : result.getErrors()) {
            if (error.errorType.contains('DmlException')) {
                hasDmlException = true;
                break;
            }
        }
        Assert.isTrue(hasDmlException, 'Should have DmlException');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'DML work item should have FAILED status');
        }
    }

    @isTest
    static void test_update_partialFailure_failFast_rolledBack() {
        // Arrange - 5 records, indexes 1 and 3 fail
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_UPDATE,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{1, 3},
                'Record locked by another user',
                System.StatusCode.UNABLE_TO_LOCK_ROW
            )
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5);
        for (Integer i = 0; i < accounts.size(); i++) {
            accounts[i].Id = UoWTestHelpers.generateFakeId(Account.SObjectType, i + 1);
        }

        // Act
        Test.startTest();
        uow.registerUpdate(accounts).failFast();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.ROLLED_BACK);

        // Assert aggregate statistics - rolled back after processing
        Assert.areEqual(5, result.statistics.dmlStats.records.processed, 'Should process 5 records');
        Assert.areEqual(0, result.statistics.dmlStats.records.successes, 'Should have 0 successes');
        Assert.areEqual(5, result.statistics.dmlStats.records.errors, 'Should have 5 errors');

        // Assert operation-specific statistics
        Assert.areEqual(5, result.statistics.dmlStats.updates.records.processed, 'Should process 5 updates');
        Assert.areEqual(0, result.statistics.dmlStats.updates.records.successes, 'Should have 0 update successes');
        Assert.areEqual(5, result.statistics.dmlStats.updates.records.errors, 'Should have 5 update errors');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'DML work item should have FAILED status');
        }
    }

    @isTest
    static void test_update_partialFailure_continueOnError_partialSuccess() {
        // Arrange - 5 records, indexes 1 and 3 fail
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_UPDATE,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{1, 3},
                'Validation failed',
                System.StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION
            )
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5);
        for (Integer i = 0; i < accounts.size(); i++) {
            accounts[i].Id = UoWTestHelpers.generateFakeId(Account.SObjectType, i + 1);
        }

        // Act
        Test.startTest();
        uow.registerUpdate(accounts).continueOnError();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.PARTIAL_SUCCESS);

        // Assert aggregate statistics - 5 processed, 3 succeeded, 2 failed
        Assert.areEqual(5, result.statistics.dmlStats.records.processed, 'Should process 5 records');
        Assert.areEqual(3, result.statistics.dmlStats.records.successes, 'Should have 3 successes');

        // Assert operation-specific statistics
        Assert.areEqual(5, result.statistics.dmlStats.updates.records.processed, 'Should process 5 updates');
        Assert.areEqual(3, result.statistics.dmlStats.updates.records.successes, 'Should have 3 update successes');

        // Assert byType statistics
        Assert.isTrue(result.statistics.dmlStats.updates.byType.containsKey('Account'), 'Should have Account stats');
        Assert.areEqual(5, result.statistics.dmlStats.updates.byType.get('Account').processed, 'Should process 5 Accounts');
        Assert.areEqual(3, result.statistics.dmlStats.updates.byType.get('Account').successes, 'Should have 3 Account successes');

        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Validate error statusCode
        Integer validationErrors = 0;
        for (UoWExceptionService.ErrorInfo error : result.getErrors()) {
            if (error.errorType == 'FIELD_CUSTOM_VALIDATION_EXCEPTION') {
                validationErrors++;
            }
        }
        Assert.areEqual(2, validationErrors, 'Should have 2 validation errors');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.PARTIAL_SUCCESS, workItem.status, 'DML work item should have PARTIAL_SUCCESS status');
        }
    }

    @isTest
    static void test_update_allFail_continueOnError_failed() {
        // Arrange - 5 records, ALL fail
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_UPDATE,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{0, 1, 2, 3, 4},
                'Record not found',
                System.StatusCode.ENTITY_IS_DELETED
            )
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5);
        for (Integer i = 0; i < accounts.size(); i++) {
            accounts[i].Id = UoWTestHelpers.generateFakeId(Account.SObjectType, i + 1);
        }

        // Act
        Test.startTest();
        uow.registerUpdate(accounts).continueOnError();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.FAILED);

        // Assert aggregate statistics - 5 processed, 0 succeeded, all failed
        Assert.areEqual(5, result.statistics.dmlStats.records.processed, 'Should process 5 records');
        Assert.areEqual(0, result.statistics.dmlStats.records.successes, 'Should have 0 successes');

        // Assert operation-specific statistics
        Assert.areEqual(5, result.statistics.dmlStats.updates.records.processed, 'Should process 5 updates');
        Assert.areEqual(0, result.statistics.dmlStats.updates.records.successes, 'Should have 0 update successes');

        // Assert byType statistics
        Assert.isTrue(result.statistics.dmlStats.updates.byType.containsKey('Account'), 'Should have Account stats');
        Assert.areEqual(5, result.statistics.dmlStats.updates.byType.get('Account').processed, 'Should process 5 Accounts');
        Assert.areEqual(0, result.statistics.dmlStats.updates.byType.get('Account').successes, 'Should have 0 Account successes');

        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Validate all errors captured
        Integer deletedErrors = 0;
        for (UoWExceptionService.ErrorInfo error : result.getErrors()) {
            if (error.errorType == 'ENTITY_IS_DELETED') {
                deletedErrors++;
            }
        }
        Assert.areEqual(5, deletedErrors, 'Should have 5 deleted entity errors');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'DML work item should have FAILED status');
        }
    }

    // ============================================================================
    // DELETE ERROR TESTS
    // ============================================================================

    @isTest
    static void test_delete_alwaysFail_rolledBack() {
        // Arrange
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.alwaysFail(
            UoWChaosEngine.Point.DML_DELETE,
            UoWChaosEngine.sampleInsertDmlException()
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5);
        for (Integer i = 0; i < accounts.size(); i++) {
            accounts[i].Id = UoWTestHelpers.generateFakeId(Account.SObjectType, i + 1);
        }

        // Act
        Test.startTest();
        uow.registerDelete(accounts);
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.ROLLED_BACK);

        // Assert aggregate statistics
        // as the dml still executed- ALL records should be marked as processed and failed
        // even if it is an exception
        Assert.areEqual(5, result.statistics.dmlStats.records.processed, 'Should process 5 records');
        Assert.areEqual(0, result.statistics.dmlStats.records.successes, 'Should have 0 successes');
        Assert.areEqual(5, result.statistics.dmlStats.records.errors, 'Should have 5 errors');

        // Assert operation-specific statistics
        Assert.areEqual(5, result.statistics.dmlStats.deletes.records.processed, 'Should process 5 deletes');
        Assert.areEqual(0, result.statistics.dmlStats.deletes.records.successes, 'Should have 0 delete successes');
        Assert.areEqual(5, result.statistics.dmlStats.deletes.records.errors, 'Should have 5 delete errors');

        // Validate exception type
        Boolean hasDmlException = false;
        for (UoWExceptionService.ErrorInfo error : result.getErrors()) {
            if (error.errorType.contains('DmlException')) {
                hasDmlException = true;
                break;
            }
        }
        Assert.isTrue(hasDmlException, 'Should have DmlException');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'DML work item should have FAILED status');
        }
    }

    @isTest
    static void test_delete_partialFailure_failFast_rolledBack() {
        // Arrange - 5 records, indexes 1 and 3 fail
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_DELETE,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{1, 3},
                'Cannot delete record with children',
                System.StatusCode.DELETE_FAILED
            )
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5);
        for (Integer i = 0; i < accounts.size(); i++) {
            accounts[i].Id = UoWTestHelpers.generateFakeId(Account.SObjectType, i + 1);
        }

        // Act
        Test.startTest();
        uow.registerDelete(accounts).failFast();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.ROLLED_BACK);

        // Assert aggregate statistics - transaction rolled back, no successes
        Assert.areEqual(5, result.statistics.dmlStats.records.processed, 'Should process 5 records');
        Assert.areEqual(0, result.statistics.dmlStats.records.successes, 'Should have 0 successes');
        Assert.areEqual(5, result.statistics.dmlStats.records.errors, 'Should have 5 errors');

        // Assert operation-specific statistics
        Assert.areEqual(5, result.statistics.dmlStats.deletes.records.processed, 'Should process 5 deletes');
        Assert.areEqual(0, result.statistics.dmlStats.deletes.records.successes, 'Should have 0 delete successes');
        Assert.areEqual(5, result.statistics.dmlStats.deletes.records.errors, 'Should have 5 delete errors');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'DML work item should have FAILED status');
        }
    }

    @isTest
    static void test_delete_partialFailure_continueOnError_partialSuccess() {
        // Arrange - 5 records, indexes 1 and 3 fail
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_DELETE,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{1, 3},
                'Record has child records',
                System.StatusCode.DELETE_FAILED
            )
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5);
        for (Integer i = 0; i < accounts.size(); i++) {
            accounts[i].Id = UoWTestHelpers.generateFakeId(Account.SObjectType, i + 1);
        }

        // Act
        Test.startTest();
        uow.registerDelete(accounts).continueOnError();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.PARTIAL_SUCCESS);

        // Assert aggregate statistics - 5 processed, 3 succeeded, 2 failed
        Assert.areEqual(5, result.statistics.dmlStats.records.processed, 'Should process 5 records');
        Assert.areEqual(3, result.statistics.dmlStats.records.successes, 'Should have 3 successes');

        // Assert operation-specific statistics
        Assert.areEqual(5, result.statistics.dmlStats.deletes.records.processed, 'Should process 5 deletes');
        Assert.areEqual(3, result.statistics.dmlStats.deletes.records.successes, 'Should have 3 delete successes');

        // Assert byType statistics
        Assert.isTrue(result.statistics.dmlStats.deletes.byType.containsKey('Account'), 'Should have Account stats');
        Assert.areEqual(5, result.statistics.dmlStats.deletes.byType.get('Account').processed, 'Should process 5 Accounts');
        Assert.areEqual(3, result.statistics.dmlStats.deletes.byType.get('Account').successes, 'Should have 3 Account successes');

        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Validate error statusCode
        Integer deleteErrors = 0;
        for (UoWExceptionService.ErrorInfo error : result.getErrors()) {
            if (error.errorType == 'DELETE_FAILED') {
                deleteErrors++;
            }
        }
        Assert.areEqual(2, deleteErrors, 'Should have 2 delete errors');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.PARTIAL_SUCCESS, workItem.status, 'DML work item should have PARTIAL_SUCCESS status');
        }
    }

    @isTest
    static void test_delete_allFail_continueOnError_failed() {
        // Arrange - 5 records, ALL fail
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_DELETE,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{0, 1, 2, 3, 4},
                'Record already deleted',
                System.StatusCode.ENTITY_IS_DELETED
            )
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5);
        for (Integer i = 0; i < accounts.size(); i++) {
            accounts[i].Id = UoWTestHelpers.generateFakeId(Account.SObjectType, i + 1);
        }

        // Act
        Test.startTest();
        uow.registerDelete(accounts).continueOnError();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.FAILED);

        // Assert aggregate statistics - 5 processed, 0 succeeded, all failed
        Assert.areEqual(5, result.statistics.dmlStats.records.processed, 'Should process 5 records');
        Assert.areEqual(0, result.statistics.dmlStats.records.successes, 'Should have 0 successes');

        // Assert operation-specific statistics
        Assert.areEqual(5, result.statistics.dmlStats.deletes.records.processed, 'Should process 5 deletes');
        Assert.areEqual(0, result.statistics.dmlStats.deletes.records.successes, 'Should have 0 delete successes');

        // Assert byType statistics
        Assert.isTrue(result.statistics.dmlStats.deletes.byType.containsKey('Account'), 'Should have Account stats');
        Assert.areEqual(5, result.statistics.dmlStats.deletes.byType.get('Account').processed, 'Should process 5 Accounts');
        Assert.areEqual(0, result.statistics.dmlStats.deletes.byType.get('Account').successes, 'Should have 0 Account successes');

        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Validate all errors captured
        Integer deletedErrors = 0;
        for (UoWExceptionService.ErrorInfo error : result.getErrors()) {
            if (error.errorType == 'ENTITY_IS_DELETED') {
                deletedErrors++;
            }
        }
        Assert.areEqual(5, deletedErrors, 'Should have 5 deleted entity errors');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'DML work item should have FAILED status');
        }
    }

    // ============================================================================
    // UNDELETE ERROR TESTS
    // ============================================================================

    @isTest
    static void test_undelete_alwaysFail_rolledBack() {
        // Arrange
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.alwaysFail(
            UoWChaosEngine.Point.DML_UNDELETE,
            UoWChaosEngine.sampleInsertDmlException()
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5);
        for (Integer i = 0; i < accounts.size(); i++) {
            accounts[i].Id = UoWTestHelpers.generateFakeId(Account.SObjectType, i + 1);
        }

        // Act
        Test.startTest();
        uow.registerUndelete(accounts);
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.ROLLED_BACK);

        // Assert aggregate statistics
        Assert.areEqual(5, result.statistics.dmlStats.records.processed, 'Should process 5 records');
        Assert.areEqual(0, result.statistics.dmlStats.records.successes, 'Should have 0 successes');
        Assert.areEqual(5, result.statistics.dmlStats.records.errors, 'Should have 5 errors');

        // Assert operation-specific statistics
        Assert.areEqual(5, result.statistics.dmlStats.undeletes.records.processed, 'Should process 5 undeletes');
        Assert.areEqual(0, result.statistics.dmlStats.undeletes.records.successes, 'Should have 0 undelete successes');
        Assert.areEqual(5, result.statistics.dmlStats.undeletes.records.errors, 'Should have 5 undelete errors');

        // Validate exception type
        Boolean hasDmlException = false;
        for (UoWExceptionService.ErrorInfo error : result.getErrors()) {
            if (error.errorType.contains('DmlException')) {
                hasDmlException = true;
                break;
            }
        }
        Assert.isTrue(hasDmlException, 'Should have DmlException');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'DML work item should have FAILED status');
        }
    }

    @isTest
    static void test_undelete_partialFailure_failFast_rolledBack() {
        // Arrange - 5 records, indexes 1 and 3 fail
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_UNDELETE,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{1, 3},
                'Record not deleted',
                System.StatusCode.UNDELETE_FAILED
            )
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5);
        for (Integer i = 0; i < accounts.size(); i++) {
            accounts[i].Id = UoWTestHelpers.generateFakeId(Account.SObjectType, i + 1);
        }

        // Act
        Test.startTest();
        uow.registerUndelete(accounts).failFast();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.ROLLED_BACK);

        // Assert aggregate statistics - transaction rolled back, no successes
        Assert.areEqual(5, result.statistics.dmlStats.records.processed, 'Should process 5 records');
        Assert.areEqual(0, result.statistics.dmlStats.records.successes, 'Should have 0 successes');
        Assert.areEqual(5, result.statistics.dmlStats.records.errors, 'Should process 5 errors');

        // Assert operation-specific statistics
        Assert.areEqual(5, result.statistics.dmlStats.undeletes.records.processed, 'Should process 5 undeletes');
        Assert.areEqual(0, result.statistics.dmlStats.undeletes.records.successes, 'Should have 0 undelete successes');
        Assert.areEqual(5, result.statistics.dmlStats.undeletes.records.errors, 'Should have 5 undelete errors');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'DML work item should have FAILED status');
        }
    }

    @isTest
    static void test_undelete_partialFailure_continueOnError_partialSuccess() {
        // Arrange - 5 records, indexes 1 and 3 fail
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_UNDELETE,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{1, 3},
                'Record no longer in recycle bin',
                System.StatusCode.UNDELETE_FAILED
            )
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5);
        for (Integer i = 0; i < accounts.size(); i++) {
            accounts[i].Id = UoWTestHelpers.generateFakeId(Account.SObjectType, i + 1);
        }

        // Act
        Test.startTest();
        uow.registerUndelete(accounts).continueOnError();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.PARTIAL_SUCCESS);

        // Assert aggregate statistics - 5 processed, 3 succeeded, 2 failed
        Assert.areEqual(5, result.statistics.dmlStats.records.processed, 'Should process 5 records');
        Assert.areEqual(3, result.statistics.dmlStats.records.successes, 'Should have 3 successes');

        // Assert operation-specific statistics
        Assert.areEqual(5, result.statistics.dmlStats.undeletes.records.processed, 'Should process 5 undeletes');
        Assert.areEqual(3, result.statistics.dmlStats.undeletes.records.successes, 'Should have 3 undelete successes');

        // Assert byType statistics
        Assert.isTrue(result.statistics.dmlStats.undeletes.byType.containsKey('Account'), 'Should have Account stats');
        Assert.areEqual(5, result.statistics.dmlStats.undeletes.byType.get('Account').processed, 'Should process 5 Accounts');
        Assert.areEqual(3, result.statistics.dmlStats.undeletes.byType.get('Account').successes, 'Should have 3 Account successes');

        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Validate error statusCode
        Integer undeleteErrors = 0;
        for (UoWExceptionService.ErrorInfo error : result.getErrors()) {
            if (error.errorType == 'UNDELETE_FAILED') {
                undeleteErrors++;
            }
        }
        Assert.areEqual(2, undeleteErrors, 'Should have 2 undelete errors');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.PARTIAL_SUCCESS, workItem.status, 'DML work item should have PARTIAL_SUCCESS status');
        }
    }

    @isTest
    static void test_undelete_allFail_continueOnError_failed() {
        // Arrange - 5 records, ALL fail
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_UNDELETE,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{0, 1, 2, 3, 4},
                'Record not in recycle bin',
                System.StatusCode.UNDELETE_FAILED
            )
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5);
        for (Integer i = 0; i < accounts.size(); i++) {
            accounts[i].Id = UoWTestHelpers.generateFakeId(Account.SObjectType, i + 1);
        }

        // Act
        Test.startTest();
        uow.registerUndelete(accounts).continueOnError();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.FAILED);

        // Assert aggregate statistics - 5 processed, 0 succeeded, all failed
        Assert.areEqual(5, result.statistics.dmlStats.records.processed, 'Should process 5 records');
        Assert.areEqual(0, result.statistics.dmlStats.records.successes, 'Should have 0 successes');

        // Assert operation-specific statistics
        Assert.areEqual(5, result.statistics.dmlStats.undeletes.records.processed, 'Should process 5 undeletes');
        Assert.areEqual(0, result.statistics.dmlStats.undeletes.records.successes, 'Should have 0 undelete successes');

        // Assert byType statistics
        Assert.isTrue(result.statistics.dmlStats.undeletes.byType.containsKey('Account'), 'Should have Account stats');
        Assert.areEqual(5, result.statistics.dmlStats.undeletes.byType.get('Account').processed, 'Should process 5 Accounts');
        Assert.areEqual(0, result.statistics.dmlStats.undeletes.byType.get('Account').successes, 'Should have 0 Account successes');

        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Validate all errors captured
        Integer undeleteErrors = 0;
        for (UoWExceptionService.ErrorInfo error : result.getErrors()) {
            if (error.errorType == 'UNDELETE_FAILED') {
                undeleteErrors++;
            }
        }
        Assert.areEqual(5, undeleteErrors, 'Should have 5 undelete errors');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'DML work item should have FAILED status');
        }
    }

    // ============================================================================
    // PLATFORM EVENT ERROR TESTS
    // ============================================================================

    @isTest
    static void test_platformEvent_alwaysFail_rolledBack() {
        // Arrange
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.alwaysFail(
            UoWChaosEngine.Point.PLATFORM_EVENT_PUBLISH,
            new UoWChaosEngine.ChaosChannelException('Event publishing failed')
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        // Register DML to ensure transaction happens
        Account acc = UoWCoreTestDataFactory.createAccount('Event Test');

        // Act
        Test.startTest();
        uow.registerPlatformEvent(acc).failfast();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.ROLLED_BACK);
        Assert.areEqual(0, result.statistics.eventStats.events.published, 'No events published');
        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Verify work item statuses
        for (UoWEventWorkItem workItem : result.getAllEventWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'Event work item should have FAILED status');
        }
    }

    @isTest
    static void test_platformEvent_partialFailure_continueOnError_partialSuccess() {
        // Arrange - 5 events, indexes 1 and 3 fail
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.PLATFORM_EVENT_PUBLISH,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{1, 3},
                'You must enter a value: RequiredField__c',
                System.StatusCode.REQUIRED_FIELD_MISSING
            )
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5);

        // Act
        Test.startTest();
        uow.registerPlatformEvent(accounts).continueOnError();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.PARTIAL_SUCCESS);
        Assert.areEqual(5, result.statistics.eventStats.events.processed, '5 events processed');
        Assert.areEqual(3, result.statistics.eventStats.events.published, '3 events published');
        Assert.areEqual(2, result.statistics.eventStats.events.errors, '2 errors reported');
        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Verify work item statuses
        UoWTestHelpers.debugResult(result);
        for (UoWEventWorkItem workItem : result.getAllEventWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.PARTIAL_SUCCESS, workItem.status, 'Event work item should have PARTIAL_SUCCESS status');
        }
    }

    @isTest
    static void test_platformEvent_allFail_continueOnError_failed() {
        // Arrange - All events fail
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.PLATFORM_EVENT_PUBLISH,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{0, 1, 2, 3, 4},
                'You must enter a value: RequiredField__c',
                System.StatusCode.REQUIRED_FIELD_MISSING
            )
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(5);

        // Act
        Test.startTest();
        uow.registerPlatformEvent(accounts).continueOnError();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.FAILED);
        Assert.areEqual(5, result.statistics.eventStats.events.processed, '5 events processed');
        Assert.areEqual(0, result.statistics.eventStats.events.published, 'No events published');
        Assert.areEqual(5, result.statistics.eventStats.events.errors, '5 errors reported');
        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Verify work item statuses
        for (UoWEventWorkItem workItem : result.getAllEventWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'Event work item should have FAILED status');
        }
    }

    // ============================================================================
    // FLOW ERROR TESTS
    // ============================================================================

    @isTest
    static void test_flow_alwaysFail_rolledBack() {
        // Arrange
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.alwaysFail(
            UoWChaosEngine.Point.FLOW_INVOKE,
            new UoWChaosEngine.ChaosChannelException('Flow not found')
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        // Act
        Test.startTest();
        uow.registerFlowExecution('TestFlow')
            .withInput('recordId', 'test123')
            .failFast();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.ROLLED_BACK);
        Assert.areEqual(0, result.statistics.flowStats.flows.executed, 'No flows executed');
        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Verify work item statuses
        for (UoWFlowWorkItem workItem : result.getAllFlowWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'Flow work item should have FAILED status');
        }
    }

    @isTest
    static void test_flow_singleFailure_continueOnError_failed() {
        // Arrange
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.alwaysFail(
            UoWChaosEngine.Point.FLOW_INVOKE,
            new UoWChaosEngine.ChaosChannelException('Flow execution error')
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        // Act
        Test.startTest();
        uow.registerFlowExecution('TestFlow')
            .withInput('recordId', 'test123')
            .continueOnError();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.FAILED);
        Assert.areEqual(0, result.statistics.flowStats.flows.executed, 'No flows executed');
        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Verify work item statuses
        for (UoWFlowWorkItem workItem : result.getAllFlowWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'Flow work item should have FAILED status');
        }
    }

    // ============================================================================
    // EMAIL ERROR TESTS (4 patterns)
    // ============================================================================

    @isTest
    static void test_email_alwaysFail_rolledBack() {
        // Arrange
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.alwaysFail(
            UoWChaosEngine.Point.EMAIL_SEND,
            UoWChaosEngine.sampleEmailException()
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Integer i = 0; i < 5; i++) {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{'test' + i + '@example.com'});
            email.setSubject('Test Email ' + i);
            emails.add(email);
        }

        // Act
        Test.startTest();
        uow.registerEmail(emails).failFast();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.ROLLED_BACK);
        Assert.areEqual(0, result.statistics.emailStats.emails.sent, 'No emails sent');
        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Verify work item statuses
        for (UoWEmailWorkItem workItem : result.getAllEmailWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'Email work item should have FAILED status');
        }
    }

    @isTest
    static void test_email_partialFailure_failFast_rolledBack() {
        // Arrange - 5 emails, indexes 1 and 3 fail
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.EMAIL_SEND,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{1, 3},
                'Invalid email address',
                System.StatusCode.INVALID_EMAIL_ADDRESS
            )
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Integer i = 0; i < 5; i++) {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{'test' + i + '@example.com'});
            email.setSubject('Test Email ' + i);
            emails.add(email);
        }

        // Act
        Test.startTest();
        uow.registerEmail(emails).failFast();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.ROLLED_BACK);
        Assert.areEqual(0, result.statistics.emailStats.emails.sent, 'No emails sent');
        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Verify work item statuses
        for (UoWEmailWorkItem workItem : result.getAllEmailWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'Email work item should have FAILED status');
        }
    }

    @isTest
    static void test_email_partialFailure_continueOnError_partialSuccess() {
        // Arrange - 5 emails, indexes 1 and 3 fail
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.EMAIL_SEND,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{1, 3},
                'Email limit exceeded'  // Email errors use 2-param constructor (no StatusCode)
            )
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Integer i = 0; i < 5; i++) {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{'test' + i + '@example.com'});
            email.setSubject('Test Email ' + i);
            emails.add(email);
        }

        // Act
        Test.startTest();
        uow.registerEmail(emails).continueOnError();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.PARTIAL_SUCCESS);
        Assert.areEqual(5, result.statistics.emailStats.emails.processed, '5 emails processed');
        Assert.areEqual(3, result.statistics.emailStats.emails.sent, '3 emails sent');
        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Validate error statusCode
        Integer emailErrors = 0;
        for (UoWExceptionService.ErrorInfo error : result.getErrors()) {
            if (error.errorType == 'INVALID_EMAIL_ADDRESS' || error.errorType == 'EMAIL_SEND_FAILED') {
                emailErrors++;
            }
        }
        System.debug('emailErrors: ' + emailErrors);
        Assert.isTrue(emailErrors >= 2, 'Should have at least 2 email errors');

        // Verify work item statuses
        for (UoWEmailWorkItem workItem : result.getAllEmailWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.PARTIAL_SUCCESS, workItem.status, 'Email work item should have PARTIAL_SUCCESS status');
        }
    }

    @isTest
    static void test_email_allFail_continueOnError_failed() {
        // Arrange - 5 emails, ALL fail
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.EMAIL_SEND,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{0, 1, 2, 3, 4},
                'Email configuration error',
                System.StatusCode.INVALID_EMAIL_ADDRESS
            )
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Integer i = 0; i < 5; i++) {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{'test' + i + '@example.com'});
            email.setSubject('Test Email ' + i);
            emails.add(email);
        }

        // Act
        Test.startTest();
        uow.registerEmail(emails).continueOnError();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.FAILED);
        Assert.areEqual(0, result.statistics.emailStats.emails.sent, 'No emails sent');
        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Validate all errors captured
        Integer emailErrors = 0;
        for (UoWExceptionService.ErrorInfo error : result.getErrors()) {
            if (error.errorType == 'INVALID_EMAIL_ADDRESS' || error.errorType == 'EMAIL_SEND_FAILED') {
                emailErrors++;
            }
        }
        Assert.isTrue(emailErrors >= 5, 'Should have at least 5 email errors');

        // Verify work item statuses
        for (UoWEmailWorkItem workItem : result.getAllEmailWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'Email work item should have FAILED status');
        }
    }

    // ============================================================================
    // NOTIFICATION ERROR TESTS
    // ============================================================================

    @isTest
    static void test_notification_alwaysFail_rolledBack() {
        // Arrange
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.alwaysFail(
            UoWChaosEngine.Point.CUSTOM_NOTIFICATION_SEND,
            new UoWChaosEngine.ChaosChannelException('Notification type not found')
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        // Act
        Test.startTest();
        uow.registerNotification()
            .withNotificationType(UoWTestHelpers.generateFakeId(CustomNotificationType.SObjectType, 1), 'TestNotification')
            .withRecipients(new Set<String> { UserInfo.getUserId() })
            .failFast();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.ROLLED_BACK);
        Assert.areEqual(0, result.statistics.notificationStats.notifications.sent, 'No notifications sent');
        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Verify work item statuses
        for (UoWNotificationWorkItem workItem : result.getAllNotificationWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'Notification work item should have FAILED status');
        }
    }

    @isTest
    static void test_notification_singleFailure_continueOnError_failed() {
        // Arrange
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.alwaysFail(
            UoWChaosEngine.Point.CUSTOM_NOTIFICATION_SEND,
            new UoWChaosEngine.ChaosChannelException('Invalid recipient')
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        // Act
        Test.startTest();
        uow.registerNotification()
            .withNotificationType(UoWTestHelpers.generateFakeId(CustomNotificationType.SObjectType, 1), 'TestNotification')
            .withRecipients(new Set<String> { UserInfo.getUserId() })
            .continueOnError();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.FAILED);
        Assert.areEqual(0, result.statistics.notificationStats.notifications.sent, 'No notifications sent');
        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Verify work item statuses
        for (UoWNotificationWorkItem workItem : result.getAllNotificationWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'Notification work item should have FAILED status');
        }
    }

    // ============================================================================
    // CALLOUT ERROR TESTS (3 patterns)
    // ============================================================================

    @isTest
    static void test_callout_GET_returnsError() {
        // Arrange - Setup mock callout strategy (preferred org-independent approach)
        UoWTestMocks.MockCalloutStrategy mockCalloutStrategy = new UoWTestMocks.MockCalloutStrategy();
        mockCalloutStrategy.mockStatusCode = 404;
        mockCalloutStrategy.mockStatus = 'Resource Not Found';
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks')
                            .withCalloutStrategy(mockCalloutStrategy);

        // Act
        Test.startTest();
        uow.registerCallout('callout:TestEndpoint/api/resource', 'GET');
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Framework behavior
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.FAILED);
        Assert.areEqual(1, result.statistics.calloutStats.callouts.processed, 'Should process 1 callout');
        Assert.areEqual(0, result.statistics.calloutStats.callouts.executed, 'Should execute 0 callouts');
        Assert.areEqual(1, result.statistics.calloutStats.callouts.errors, 'Should have 1 callout errors');

        // Verify work item statuses
        for (UoWCalloutWorkItem workItem : result.getAllCalloutWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'Callout work item should have FAILED status');
        }
    }

    @isTest
    static void test_callout_alwaysFail_failed() {
        // Arrange
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.alwaysFail(
            UoWChaosEngine.Point.CALLOUT,
            new UoWChaosEngine.ChaosChannelException('Failed Callout')
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        // Act
        Test.startTest();
        uow.registerCallout('callout:TestEndpoint/api/resource/')
                .failFast();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.FAILED);
        Assert.areEqual(0, result.statistics.calloutStats.callouts.executed, 'No callouts executed (callouts dont support rollback)');
        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Verify work item statuses
        for (UoWCalloutWorkItem workItem : result.getAllCalloutWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'Callout work item should have FAILED status');
        }
    }

    @isTest
    static void test_callout_singleFailure_continueOnError_failed() {
        // Arrange - 5 callouts, fail 1st
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.addFailure(
            UoWChaosEngine.Point.CALLOUT,
            new UoWChaosEngine.ChaosChannelException('Failed Callout')
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        // Act
        Test.startTest();
        for (Integer i = 0; i < 5; i++) {
            uow.registerCallout('callout:TestEndpoint/api/resource/' + i, 'POST')
                .withBody('{"index": ' + i + '}')
                .continueOnError();
        }
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.PARTIAL_SUCCESS);
        Assert.areEqual(5, result.statistics.calloutStats.callouts.processed, 'Should process 5 callouts');
        Assert.areEqual(4, result.statistics.calloutStats.callouts.executed, 'Should execute 4 callouts');
        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Verify work item statuses
        for (Integer i=0; i < result.getAllCalloutWork().size(); i++) {
            UoWCalloutWorkItem workItem = result.getAllCalloutWork()[i];
            if (i == 0) {
                Assert.areEqual(UoWEnums.WorkStatus.FAILED, workItem.status, 'First callout work item should have FAILED status');
            } else {
                Assert.areEqual(UoWEnums.WorkStatus.SUCCESS, workItem.status, 'Subsequent callout work items should have SUCCESS status');
            }
        }
    }

    // ============================================================================
    // MIXED WORK TYPES TESTS
    // ============================================================================

    @isTest
    static void test_mixedWorkTypes_allContinueOnError_partialSuccess() {
        // Test: All work types with continueOnError, mixed success/failure
        // Validates: PARTIAL_SUCCESS status when all allow partial success

        // Arrange - Configure partial failures for each work type
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();

        // DML: 5 accounts, indexes 1 and 3 fail
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_INSERT,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{1, 3},
                'Validation failed',
                System.StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION
            )
        );

        // Emails: 4 emails, indexes 0 and 2 fail
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.EMAIL_SEND,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{0, 2},
                'Email limit exceeded'  // Email errors use 2-param constructor (no StatusCode)
            )
        );

        // Setup mocks
        UoWTestHelpers.TestUoWOptions options = new UoWTestHelpers.TestUoWOptions(true, true);
        UnitOfWork uow = UoWTestHelpers.generateUoW('TestConfigAllMocks', options);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.PARTIAL_SUCCESS);
        Assert.areEqual(6, result.statistics.dmlStats.inserts.records.successes, '6 successful inserts');
        Assert.areEqual(3, result.statistics.emailStats.emails.sent, '3 successful emails');
        Assert.isTrue(result.hasErrors(), 'Should have errors');

        // Verify both DML and email errors exist
        Boolean hasDmlError = false;
        Boolean hasEmailError = false;
        for (UoWExceptionService.ErrorInfo error : result.getErrors()) {
            if (error.errorType == 'FIELD_CUSTOM_VALIDATION_EXCEPTION') {
                hasDmlError = true;
            }
            if (error.errorType == 'INVALID_EMAIL_ADDRESS' || error.errorType == 'EMAIL_SEND_FAILED') {
                hasEmailError = true;
            }
        }
        Assert.isTrue(hasDmlError, 'Should have DML error');
        Assert.isTrue(hasEmailError, 'Should have email error');
    }

    @isTest
    static void test_mixedWorkTypes_oneFailsFast_rolledBack() {
        // Test: Mixed work types, one uses failFast and fails
        // Validates: ROLLED_BACK status when one failFast work item fails

        // Arrange - DML fails with failFast, email uses continueOnError
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_INSERT,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{1},
                'Validation failed',
                System.StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION
            )
        );

        // Setup mocks
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        // Register DML with failFast (will fail)
        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(3);
        uow.registerInsert(accounts).failFast();  // First failure rolls back

        // Register email with continueOnError (would succeed)
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{'test@example.com'});
        email.setSubject('Test');
        uow.registerEmail(email).continueOnError();

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.ROLLED_BACK);
        Assert.areEqual(0, result.statistics.dmlStats.inserts.records.successes, 'No successful inserts');
        Assert.areEqual(0, result.statistics.emailStats.emails.sent, 'No emails sent (rolled back)');
        Assert.isTrue(result.hasErrors(), 'Should have errors');
    }

    // ============================================================================
    // MULTI-LEVEL HIERARCHY TESTS
    // ============================================================================

    @isTest
    static void test_multiLevelHierarchy_parentFails_childrenNotProcessed() {
        // Test: Account → Contact → Case, Account fails
        // Validates: Dependent children not processed when parent fails

        // Arrange
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.alwaysFail(
            UoWChaosEngine.Point.DML_INSERT,
            UoWChaosEngine.sampleInsertDmlException()
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        Account acc = new Account(Name = 'Parent Account');
        Contact con = new Contact(LastName = 'Test Contact');
        Case supportCase = new Case(Subject = 'Test Case');

        // Act
        Test.startTest();
        uow.registerInsert(acc);
        uow.registerInsert(con);
        uow.relate(con, Contact.AccountId, acc);
        uow.registerInsert(supportCase);
        uow.relate(supportCase, Case.ContactId, con);

        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.ROLLED_BACK);
        Assert.areEqual(0, result.statistics.dmlStats.inserts.records.successes, 'No successful inserts');
        UoWTestHelpers.assertNoId(acc);
        UoWTestHelpers.assertNoId(con);
        UoWTestHelpers.assertNoId(supportCase);
    }

    @isTest
    static void test_multiLevelHierarchy_mixedSuccessFailure_partialSuccess() {
        // Test: Account succeeds, 2 Contacts (1 fails), 2 Cases (1 fails)
        // Validates: Partial success in multi-level hierarchy

        // Arrange - Index 1 fails for each batch
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_INSERT,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{1},
                'Validation failed',
                System.StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION
            )
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        Account acc = new Account(Name = 'Parent Account');
        Contact con1 = new Contact(LastName = 'Contact 1');
        Contact con2 = new Contact(LastName = 'Contact 2');
        Case case1 = new Case(Subject = 'Case 1');
        Case case2 = new Case(Subject = 'Case 2');

        // Act
        Test.startTest();
        uow.registerInsert(acc).continueOnError();
        uow.registerInsert(con1).continueOnError();
        uow.relate(con1, Contact.AccountId, acc);
        uow.registerInsert(con2).continueOnError();
        uow.relate(con2, Contact.AccountId, acc);

        uow.registerInsert(case1).continueOnError();
        uow.relate(case1, Case.ContactId, con1);
        uow.registerInsert(case2).continueOnError();
        uow.relate(case2, Case.ContactId, con2);

        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.PARTIAL_SUCCESS);
        Assert.isTrue(result.statistics.dmlStats.inserts.records.successes >= 1, 'At least 1 successful insert');
        Assert.isTrue(result.hasErrors(), 'Should have errors');
    }

    // ============================================================================
    // ASYNC ERROR TEST
    // ============================================================================

    @isTest
    static void test_asyncChild_dmlError_handlesCorrectly() {
        // Arrange - Configure failure in async child execution
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.alwaysFail(
            UoWChaosEngine.Point.DML_INSERT,
            UoWChaosEngine.sampleInsertDmlException()
        );

        // Arrange
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks');

        // Act - Request async execution
        Test.startTest();
        UoWResult originalResult = uow.commitWork(UoWEnums.CommitMode.ASYNC);
        Test.stopTest();

        // Assert - Parent transaction returns early with ENQUEUED status
        UoWTestHelpers.assertSuccess(originalResult);
        UoWTestHelpers.assertAsyncEnqueued(originalResult);
        Assert.areEqual(0, originalResult.statistics.dmlStats.records.processed, 'Parent should process 0 records (DML happens in async child)');

        // Assert - Async child execution completed
        // UoWQueueable sets finalizerState in its finally block, accessible after Test.stopTest()
        UoWQueueable.FinalizerState asyncState = UoWQueueable.getFinalizerState();
        Assert.isNotNull(asyncState, 'Async execution should set finalizer state');
        Assert.isNotNull(asyncState.result, 'Async execution should produce a result');
        Assert.isNotNull(asyncState.context, 'Async execution should have context');

        // Verify async child processed the work
        UoWResult asyncResult = asyncState.result;
        UoWTestHelpers.assertStatus(asyncResult, UoWEnums.TransactionStatus.ROLLED_BACK);
        Assert.isTrue(asyncResult.hasErrors(), 'Should have errors for failed records');
    }

    @isTest
    static void test_asyncChild_partialFailure_continueOnError() {
        // Arrange
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_INSERT,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{1, 3},
                'Async validation error',
                System.StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION
            )
        );

        // Arrange
        UoWTestHelpers.TestUoWOptions options = new UoWTestHelpers.TestUoWOptions(false, true);
        options.registerInserts = true;
        UnitOfWork uow = UoWTestHelpers.generateUoW('TestConfigAllMocks', options);

        // Act - Request async execution
        Test.startTest();
        UoWResult originalResult = uow.commitWork(UoWEnums.CommitMode.ASYNC);
        Test.stopTest();

        // Assert - Parent transaction returns early with ENQUEUED status
        UoWTestHelpers.assertSuccess(originalResult);
        UoWTestHelpers.assertAsyncEnqueued(originalResult);
        Assert.areEqual(0, originalResult.statistics.dmlStats.records.processed, 'Parent should process 0 records (DML happens in async child)');

        // Assert - Async child execution completed
        // UoWQueueable sets finalizerState in its finally block, accessible after Test.stopTest()
        UoWQueueable.FinalizerState asyncState = UoWQueueable.getFinalizerState();
        Assert.isNotNull(asyncState, 'Async execution should set finalizer state');
        Assert.isNotNull(asyncState.result, 'Async execution should produce a result');
        Assert.isNotNull(asyncState.context, 'Async execution should have context');

        // Verify async child processed the work
        UoWResult asyncResult = asyncState.result;
        UoWTestHelpers.assertStatus(asyncResult, UoWEnums.TransactionStatus.PARTIAL_SUCCESS);
        Assert.areEqual(10, asyncResult.statistics.dmlStats.inserts.records.processed, 'Should process all 5 accounts and all 5 contacts');
        Assert.areEqual(6, asyncResult.statistics.dmlStats.inserts.records.successes, 'Should have 3 successful Accounts and 3 successful contacts');
        Assert.isTrue(asyncResult.hasErrors(), 'Should have errors for failed records');
    }

    // ============================================================================
    // RETRYABLE ERROR TEST
    // ============================================================================

    @isTest
    static void test_retryableError_flaggedCorrectly() {
        // Arrange - Use ChaosEngine to simulate retryable error
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.configurePartialFailure(
            UoWChaosEngine.Point.DML_UPDATE,
            new UoWChaosEngine.PartialFailureConfig(
                new List<Integer>{0},
                'Record locked',
                System.StatusCode.UNABLE_TO_LOCK_ROW
            )
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        Account acc = UoWCoreTestDataFactory.createAccount('Test Account');
        acc.Id = UoWTestHelpers.generateFakeId(Account.SObjectType, 1);

        // Act
        Test.startTest();
        uow.registerUpdate(acc).continueOnError();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Error should be flagged as retryable
        List<UoWExceptionService.ErrorInfo> errors = result.getErrors();
        Boolean hasRetryableError = false;
        for (UoWExceptionService.ErrorInfo error : errors) {
            if (error.errorType == 'UNABLE_TO_LOCK_ROW' && error.isRetryable) {
                hasRetryableError = true;
                break;
            }
        }
        Assert.isTrue(hasRetryableError, 'UNABLE_TO_LOCK_ROW should be retryable');
    }
}