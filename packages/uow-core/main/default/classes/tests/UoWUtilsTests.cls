//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Tests for UoWUtils and UoWGovernorLimits utility classes.
 * Covers ID generation, execution context, record utilities, datetime utilities,
 * and governor limits capture.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Tests
 * @see UoWUtils
 * @see UoWGovernorLimits
 */
@isTest
@SuppressWarnings('PMD.MethodNamingConventions')
private class UoWUtilsTests {
    // ============================================================================
    // TEST SETUP
    // ============================================================================

    @TestSetup
    static void setupTestData() {
        // Load test configurations
        UoWTestHelpers.loadTestConfigurations();
    }

    // ============================================================================
    // UoWUtils - ID GENERATION TESTS
    // ============================================================================

    @isTest
    static void test_utils_generateWorkId_createsUniqueId() {
        // Act
        Test.startTest();
        String workId1 = UoWUtils.generateWorkId();
        String workId2 = UoWUtils.generateWorkId();
        Test.stopTest();

        // Assert
        Assert.isNotNull(workId1, 'Work ID should not be null');
        Assert.areNotEqual(workId1, workId2, 'Work IDs should be unique');
    }

    @isTest
    static void test_utils_generateId_withCustomPrefix() {
        // Arrange
        String prefix = 'CUSTOM';

        // Act
        Test.startTest();
        String customId = UoWUtils.generateId(prefix);
        Test.stopTest();

        // Assert
        Assert.isNotNull(customId, 'Custom ID should not be null');
        Assert.isTrue(customId.startsWith(prefix + '-'),
            'Custom ID should start with provided prefix');
    }

    @isTest
    static void test_utils_generateUUID_returnsValidUUID() {
        // Act
        Test.startTest();
        String uuid = UoWUtils.generateUUID();
        Test.stopTest();

        // Assert
        Assert.isNotNull(uuid, 'UUID should not be null');
        // UUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx (36 characters with hyphens)
        Assert.areEqual(36, uuid.length(), 'UUID should be 36 characters');
        Assert.isTrue(uuid.contains('-'), 'UUID should contain hyphens');
    }

    // ============================================================================
    // UoWUtils - EXECUTION CONTEXT TESTS
    // ============================================================================

    @isTest
    static void test_executionContext_inTestMode_returnsRunTestSync() {
        // Arrange
        Assert.isTrue(UoWUtils.isTestContext(), 'Expected execution context to return RUNTEST_* while running tests');
    }

    @isTest
    static void test_utils_isAsyncContext_falseInTestContext() {
        // Act
        Test.startTest();
        Boolean isAsync = UoWUtils.isAsyncContext();
        Test.stopTest();

        // Assert - Test context is synchronous
        Assert.isFalse(isAsync, 'Should not be async in test context');
    }

    // ============================================================================
    // UoWUtils - RECORD UTILITIES TESTS
    // ============================================================================

    @isTest
    static void test_utils_extractIds_returnsIdsFromRecords() {
        // Arrange
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            Account acc = new Account(Name = 'Test ' + i);
            acc.Id = UoWTestHelpers.generateFakeId(Account.SObjectType, i + 1);
            accounts.add(acc);
        }

        // Act
        Test.startTest();
        Set<Id> ids = UoWUtils.extractIds(accounts);
        Test.stopTest();

        // Assert
        Assert.areEqual(3, ids.size(), 'Should extract 3 IDs');
        for (Account acc : accounts) {
            Assert.isTrue(ids.contains(acc.Id), 'Should contain account ID: ' + acc.Id);
        }
    }

    @isTest
    static void test_utils_extractIds_skipsNullIds() {
        // Arrange
        List<Account> accounts = new List<Account>{
            new Account(Name = 'No ID'),
            new Account(Name = 'Has ID', Id = UoWTestHelpers.generateFakeId(Account.SObjectType, 1))
        };

        // Act
        Test.startTest();
        Set<Id> ids = UoWUtils.extractIds(accounts);
        Test.stopTest();

        // Assert
        Assert.areEqual(1, ids.size(), 'Should extract 1 ID (skipping null)');
    }

    @isTest
    static void test_utils_extractIds_handlesNullInput() {
        // Act
        Test.startTest();
        Set<Id> ids = UoWUtils.extractIds(null);
        Test.stopTest();

        // Assert
        Assert.isNotNull(ids, 'Should return empty set, not null');
        Assert.isTrue(ids.isEmpty(), 'Should return empty set for null input');
    }

    @isTest
    static void test_utils_extractIds_handlesEmptyList() {
        // Act
        Test.startTest();
        Set<Id> ids = UoWUtils.extractIds(new List<Account>());
        Test.stopTest();

        // Assert
        Assert.isTrue(ids.isEmpty(), 'Should return empty set for empty list');
    }

    // ============================================================================
    // UoWUtils - DATE/TIME UTILITIES TESTS
    // ============================================================================

    @isTest
    static void test_utils_getCurrentTimestampMs_returnsTimestamp() {
        // Act
        Test.startTest();
        Long timestamp = UoWUtils.getCurrentTimestampMs();
        Test.stopTest();

        // Assert
        Assert.isTrue(timestamp > 0, 'Timestamp should be positive');
        Assert.isTrue(timestamp >= DateTime.now().getTime() - 1000,
            'Timestamp should be recent (within 1 second)');
    }

    @isTest
    static void test_utils_getElapsedTimeMs_calculatesCorrectly() {
        // Arrange
        Long startTime = UoWUtils.getCurrentTimestampMs();

        // Act - Small delay to ensure elapsed time > 0
        Test.startTest();
        Long elapsedTime = UoWUtils.getElapsedTimeMs(startTime);
        Test.stopTest();

        // Assert
        Assert.isTrue(elapsedTime >= 0, 'Elapsed time should be non-negative');
    }

    @isTest
    static void test_utils_formatDuration_milliseconds() {
        // Act
        Test.startTest();
        String formatted = UoWUtils.formatDuration(500);
        Test.stopTest();

        // Assert
        Assert.areEqual('500ms', formatted, 'Should format as milliseconds');
    }

    @isTest
    static void test_utils_formatDuration_seconds() {
        // Act
        Test.startTest();
        String formatted = UoWUtils.formatDuration(2500);
        Test.stopTest();

        // Assert
        Assert.areEqual('2.50s', formatted, 'Should format as seconds with decimals');
    }

    @isTest
    static void test_utils_formatDuration_minutes() {
        // Act
        Test.startTest();
        String formatted = UoWUtils.formatDuration(125000); // 2m 5s
        Test.stopTest();

        // Assert
        Assert.areEqual('2m 5s', formatted, 'Should format as minutes and seconds');
    }

    @isTest
    static void test_utils_formatDuration_nullOrNegative() {
        // Act
        Test.startTest();
        String formattedNull = UoWUtils.formatDuration(null);
        String formattedNegative = UoWUtils.formatDuration(-100);
        Test.stopTest();

        // Assert
        Assert.areEqual('0ms', formattedNull, 'Should return 0ms for null');
        Assert.areEqual('0ms', formattedNegative, 'Should return 0ms for negative');
    }

    // ============================================================================
    // UoWGovernorLimits TESTS
    // ============================================================================

    @isTest
    static void test_governorLimits_capture_updatesValues() {
        // Arrange
        Test.startTest();
        UnitOfWork uow = UoWTestHelpers.generateUoW_AllWorkItems('TestConfigAllMocks');
        UoWResult result = uow.commitWork();
        UoWGovernorLimits consumed = result.governorLimits.getConsumed();
        Test.stopTest();

        // Assert - verify capture worked and values are consistent
        Assert.isTrue(consumed.dmlStatements >= 0, 'DML statements should be same or greater after capture');
        Assert.isTrue(consumed.dmlRows >= 0, 'DML Rows should be same or greater after capture');
        Assert.isTrue(consumed.soqlQueries >= 0, 'SOQL Queries should be same or greater after capture');
        Assert.isTrue(consumed.soqlRows >= 0, 'SOQL Rows should be same or greater after capture');
        Assert.isTrue(consumed.cpuTime >= 0, 'CPU Time should be same or greater after capture');
        Assert.isTrue(consumed.heapSize >= 0, 'Heap Size should be same or greater after capture');
        Assert.isTrue(consumed.callouts == 0, 'Callouts should be zero');
        Assert.isTrue(consumed.futureCalls == 0, 'Future Calls should be zero');
        Assert.isTrue(consumed.queueableJobs == 0, 'Queueable Jobs should be zero');
        Assert.isTrue(consumed.emailInvocations == 0, 'Email Invocations should be zero');
    }

    @isTest
    static void test_governorLimits_consumed_returnsNull() {
        // Arrange
        Test.startTest();
        UoWGovernorLimits consumed = UoWGovernorLimits.getConsumed(null, null);
        Test.stopTest();

        // Assert - verify capture worked and values are consistent
        Assert.isNull(consumed, 'Consumed Limits should be null');
    }
}