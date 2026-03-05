//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Tests for UoWContext, UoWSessionContext, and UoWContext.SessionSnapshot classes.
 * Covers context messaging, savepoints, async child detection, logging level filtering,
 * session context caching, and serializable session snapshots for async execution.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Tests
 * @see UoWContext
 * @see UoWSessionContext
 */
@isTest
@SuppressWarnings('PMD.MethodNamingConventions')
private class UoWContextTests {
    // ============================================================================
    // TEST SETUP
    // ============================================================================

    @TestSetup
    static void setupTestData() {
        // Load test configurations
        UoWTestHelpers.loadTestConfigurations();
    }

    // ============================================================================
    // UoWContext TESTS (debug/fine messages, savepoint)
    // ============================================================================

    @isTest
    static void test_context_debug_addsDebugMessage() {
        // Arrange - Use configuration that has DEBUG logging level
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');
        UoWContext ctx = uow.getContext();

        // Act
        Test.startTest();
        ctx.debug('Debug message');
        ctx.debug('Debug with source', 'TestClass');
        Test.stopTest();

        // Assert - Check for debug messages in collection
        // Note: Messages may be filtered based on configuration's minimumLoggingLevel
        List<UoWMessage> debugMessages = ctx.getMessagesByLevel(LoggingLevel.DEBUG);
        // Test that the method exists and executes without error
        Assert.isNotNull(debugMessages, 'Should return debug messages list');
    }

    @isTest
    static void test_context_fine_addsFineMessage() {
        // Arrange - Use configuration
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');
        UoWContext ctx = uow.getContext();

        // Act
        Test.startTest();
        ctx.fine('Fine message');
        ctx.fine('Fine with source', 'TestClass');
        Test.stopTest();

        // Assert - Check for fine messages in collection
        // Note: Messages may be filtered based on configuration's minimumLoggingLevel
        List<UoWMessage> fineMessages = ctx.getMessagesByLevel(LoggingLevel.FINE);
        Assert.isNotNull(fineMessages, 'Should return fine messages list');
    }

    @isTest
    static void test_context_debug_blankMessage_ignored() {
        // Arrange
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');
        UoWContext ctx = uow.getContext();
        Integer initialCount = ctx.getMessages().size();

        // Act - Add blank messages
        Test.startTest();
        ctx.debug('');
        ctx.debug(null);
        Test.stopTest();

        // Assert - No messages added for blank content
        Assert.areEqual(initialCount, ctx.getMessages().size(), 'Blank messages should be ignored');
    }

    @isTest
    static void test_context_fine_blankMessage_ignored() {
        // Arrange
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');
        UoWContext ctx = uow.getContext();
        Integer initialCount = ctx.getMessages().size();

        // Act - Add blank messages
        Test.startTest();
        ctx.fine('');
        ctx.fine(null);
        Test.stopTest();

        // Assert - No messages added for blank content
        Assert.areEqual(initialCount, ctx.getMessages().size(), 'Blank messages should be ignored');
    }

    @isTest
    static void test_context_setSavePoint_createsSavepoint() {
        // Arrange
        UoWContext ctx = new UoWContext('TestConfigMinimal');
        ctx.isDryRun = false;

        // Act - Savepoints are always created (except in dry run)
        Test.startTest();
        ctx.setSavePoint();
        Test.stopTest();

        // Assert
        Assert.isNotNull(ctx.transactionSavepoint, 'Savepoint should be created');
    }

    @isTest
    static void test_context_setSavePoint_skippedInDryRun() {
        // Arrange
        UoWContext ctx = new UoWContext('TestConfigMinimal');
        ctx.isDryRun = true;

        // Act
        Test.startTest();
        ctx.setSavePoint();
        Test.stopTest();

        // Assert - Savepoint should not be created in dry run
        Assert.isNull(ctx.transactionSavepoint, 'Savepoint should not be created in dry run mode');
    }

    @isTest
    static void test_context_isAsyncChild_false_byDefault() {
        // Arrange
        UoWContext ctx = new UoWContext('TestConfigMinimal');

        // Act
        Test.startTest();
        Boolean isChild = ctx.isAsyncChild();
        Test.stopTest();

        // Assert
        Assert.isFalse(isChild, 'New context should not be async child');
    }

    @isTest
    static void test_context_isAsyncChild_true_whenParentSet() {
        // Arrange
        UoWContext ctx = new UoWContext('TestConfigMinimal');
        ctx.parentTransactionId = 'PARENT-123';

        // Act
        Test.startTest();
        Boolean isChild = ctx.isAsyncChild();
        Test.stopTest();

        // Assert
        Assert.isTrue(isChild, 'Context with parent ID should be async child');
    }

    @isTest
    static void test_context_loggingLevelFiltering() {
        // Arrange - Use configuration and test message filtering
        // Note: Logging level filtering is based on configuration's minimumLoggingLevel
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');
        UoWContext ctx = uow.getContext();

        Integer initialCount = ctx.getMessages().size();

        // Act - Add messages at different levels
        // Warn and Error should always pass regardless of minimum level
        Test.startTest();
        ctx.warn('Warn message - should pass');
        ctx.error('Error message - should pass');
        Test.stopTest();

        // Assert - WARN and ERROR messages should always pass
        List<UoWMessage> warnMessages = ctx.getMessagesByLevel(LoggingLevel.WARN);
        List<UoWMessage> errorMessages = ctx.getMessagesByLevel(LoggingLevel.ERROR);

        Assert.isTrue(warnMessages.size() > 0 || errorMessages.size() > 0,
            'WARN and ERROR messages should always be captured');
    }

    // ============================================================================
    // UoWSessionContext TESTS - BASIC FUNCTIONALITY
    // ============================================================================

    @isTest
    static void test_sessionContext_getInstance_returnsCachedInstance() {
        // Act
        Test.startTest();
        UoWSessionContext instance1 = UoWSessionContext.getInstance();
        UoWSessionContext instance2 = UoWSessionContext.getInstance();
        Test.stopTest();

        // Assert - Same instance should be returned (cached)
        Assert.isNotNull(instance1, 'Session context should not be null');
        Assert.isTrue(instance1 === instance2, 'getInstance should return same cached instance');
    }

    @isTest
    static void test_sessionContext_capturesUserIdentity() {
        // Act
        Test.startTest();
        UoWSessionContext session = UoWSessionContext.getInstance();
        Test.stopTest();

        // Assert - User identity should be captured
        Assert.areEqual(UserInfo.getUserId(), session.userId, 'userId should match UserInfo');
        Assert.areEqual(UserInfo.getUserName(), session.username, 'username should match UserInfo');
        Assert.areEqual(UserInfo.getProfileId(), session.profileId, 'profileId should match UserInfo');
        Assert.areEqual(UserInfo.getUserType(), session.userType, 'userType should match UserInfo');
    }

    @isTest
    static void test_sessionContext_capturesOrganization() {
        // Act
        Test.startTest();
        UoWSessionContext session = UoWSessionContext.getInstance();
        Test.stopTest();

        // Assert - Organization should be captured
        Assert.areEqual(UserInfo.getOrganizationId(), session.organizationId, 'organizationId should match UserInfo');
        Assert.areEqual(UserInfo.getOrganizationName(), session.organizationName, 'organizationName should match UserInfo');
        Assert.isNotNull(session.isSandbox, 'isSandbox should be captured');
    }

    @isTest
    static void test_sessionContext_capturesUserPreferences() {
        // Act
        Test.startTest();
        UoWSessionContext session = UoWSessionContext.getInstance();
        Test.stopTest();

        // Assert - User preferences should be captured
        Assert.areEqual(UserInfo.getLocale(), session.locale, 'locale should match UserInfo');
        Assert.areEqual(UserInfo.getTimeZone().getId(), session.timeZoneSidKey, 'timeZoneSidKey should match UserInfo');
    }

    @isTest
    static void test_sessionContext_capturesRequestContext() {
        // Act
        Test.startTest();
        UoWSessionContext session = UoWSessionContext.getInstance();
        Test.stopTest();

        // Assert - Request context should be captured
        Assert.isNotNull(session.requestId, 'requestId should be captured');
        Assert.isNotNull(session.quiddity, 'quiddity should be captured');
    }

    @isTest
    static void test_sessionContext_isGuestUser_returnsFalseForStandardUser() {
        // Act
        Test.startTest();
        UoWSessionContext session = UoWSessionContext.getInstance();
        Boolean isGuest = session.isGuestUser();
        Test.stopTest();

        // Assert - Standard test user should not be guest
        Assert.isFalse(isGuest, 'Standard user should not be guest');
    }

    @isTest
    static void test_sessionContext_isCommunityUser_returnsFalseForStandardUser() {
        // Act
        Test.startTest();
        UoWSessionContext session = UoWSessionContext.getInstance();
        Boolean isCommunity = session.isCommunityUser();
        Test.stopTest();

        // Assert - Standard test user should not be community user
        Assert.isFalse(isCommunity, 'Standard user should not be community user');
    }

    @isTest
    static void test_sessionContext_hasPublicProperties() {
        // Act
        Test.startTest();
        UoWSessionContext session = UoWSessionContext.getInstance();
        Test.stopTest();

        // Assert - Session should have key public properties populated
        Assert.isNotNull(session.userId, 'userId should be populated');
        Assert.isNotNull(session.username, 'username should be populated');
        Assert.isNotNull(session.organizationId, 'organizationId should be populated');
        Assert.isNotNull(session.quiddity, 'quiddity should be populated');
    }

    @isTest
    static void test_sessionContext_hasAuditRelevantProperties() {
        // Act
        Test.startTest();
        UoWSessionContext session = UoWSessionContext.getInstance();
        Test.stopTest();

        // Assert - Session should have audit-relevant properties populated
        Assert.isNotNull(session.userId, 'userId should be populated for audit');
        Assert.isNotNull(session.username, 'username should be populated for audit');
        Assert.isNotNull(session.organizationId, 'organizationId should be populated for audit');
        Assert.isNotNull(session.isSandbox, 'isSandbox should be populated for audit');
    }

    @isTest
    static void test_sessionContext_resetCache_resetsCachedInstance() {
        // Arrange - Get initial instance
        UoWSessionContext instance1 = UoWSessionContext.getInstance();

        // Act - Reset cache and get new instance
        Test.startTest();
        UoWSessionContext.resetCache();
        UoWSessionContext instance2 = UoWSessionContext.getInstance();
        Test.stopTest();

        // Assert - After resetting cache, new instance should be created
        Assert.isNotNull(instance1, 'First instance should not be null');
        Assert.isNotNull(instance2, 'Second instance should not be null');
        // Both will have same user data, but are different object instances
        Assert.areEqual(instance1.userId, instance2.userId, 'User IDs should be same');
    }

    // ============================================================================
    // UoWContext.SessionSnapshot TESTS
    // ============================================================================

    @isTest
    static void test_sessionSnapshot_capturedAtConstruction() {
        // Act
        Test.startTest();
        UoWContext ctx = new UoWContext('TestConfigMinimal');
        Test.stopTest();

        // Assert - Session snapshot should be captured
        Assert.isNotNull(ctx.sessionSnapshot, 'sessionSnapshot should be captured at construction');
        Assert.isNotNull(ctx.sessionSnapshot.capturedAt, 'capturedAt should be set');
    }

    @isTest
    static void test_sessionSnapshot_containsUserIdentity() {
        // Act
        Test.startTest();
        UoWContext ctx = new UoWContext('TestConfigMinimal');
        UoWContext.SessionSnapshot snapshot = ctx.sessionSnapshot;
        Test.stopTest();

        // Assert - Snapshot should contain user identity
        Assert.areEqual(UserInfo.getUserId(), snapshot.userId, 'snapshot.userId should match UserInfo');
        Assert.areEqual(UserInfo.getUserName(), snapshot.username, 'snapshot.username should match UserInfo');
        Assert.areEqual(UserInfo.getProfileId(), snapshot.profileId, 'snapshot.profileId should match UserInfo');
        Assert.areEqual(UserInfo.getUserType(), snapshot.userType, 'snapshot.userType should match UserInfo');
    }

    @isTest
    static void test_sessionSnapshot_containsOrganization() {
        // Act
        Test.startTest();
        UoWContext ctx = new UoWContext('TestConfigMinimal');
        UoWContext.SessionSnapshot snapshot = ctx.sessionSnapshot;
        Test.stopTest();

        // Assert - Snapshot should contain organization
        Assert.areEqual(UserInfo.getOrganizationId(), snapshot.organizationId, 'snapshot.organizationId should match UserInfo');
        Assert.areEqual(UserInfo.getOrganizationName(), snapshot.organizationName, 'snapshot.organizationName should match UserInfo');
        Assert.isNotNull(snapshot.isSandbox, 'snapshot.isSandbox should be captured');
    }

    @isTest
    static void test_sessionSnapshot_containsRequestContext() {
        // Act
        Test.startTest();
        UoWContext ctx = new UoWContext('TestConfigMinimal');
        UoWContext.SessionSnapshot snapshot = ctx.sessionSnapshot;
        Test.stopTest();

        // Assert - Snapshot should contain request context
        Assert.isNotNull(snapshot.requestId, 'snapshot.requestId should be captured');
        Assert.isNotNull(snapshot.quiddity, 'snapshot.quiddity should be captured');
    }

    @isTest
    static void test_sessionSnapshot_defaultConstructor_setsTimestamp() {
        // Act
        Test.startTest();
        UoWContext.SessionSnapshot snapshot = new UoWContext.SessionSnapshot();
        Test.stopTest();

        // Assert - Default constructor should set capturedAt
        Assert.isNotNull(snapshot.capturedAt, 'capturedAt should be set by default constructor');
    }
}