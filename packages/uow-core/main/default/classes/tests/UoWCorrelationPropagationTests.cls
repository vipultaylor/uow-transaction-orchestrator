//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Tests for correlation ID propagation across transaction boundaries.
 *
 * Tests cover:
 * - Static ambient context (UoWTransactionState)
 * - UoWTransactionState serialization/deserialization
 * - Auto-detection in UnitOfWork constructors
 * - Flow Initialize action with contextCarrier
 * - asRoot() opt-out behavior
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Tests
 * @see UoWTransactionState
 */
@isTest
@SuppressWarnings('PMD.MethodNamingConventions')
private class UoWCorrelationPropagationTests {

    // ============================================================================
    // TEST SETUP
    // ============================================================================

    @TestSetup
    static void setupTestData() {
        UoWTestHelpers.loadTestConfigurations();
    }

    // ============================================================================
    // TRANSACTION STATE (STATIC AMBIENT CONTEXT) TESTS
    // ============================================================================

    @isTest
    static void test_transactionState_notSetInitially() {
        // Act
        Test.startTest();
        Boolean hasCurrent = UoWTransactionState.hasCurrent();
        UoWTransactionState current = UoWTransactionState.getCurrent();
        Test.stopTest();

        // Assert
        Assert.isFalse(hasCurrent, 'Should not have current state initially');
        Assert.isNull(current, 'Current state should be null when not inside transaction');
    }

    @isTest
    static void test_transactionState_setDuringCommit() {
        // Arrange
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks');

        String expectedCorrelationId = uow.getContext().correlationId;

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - After commit, state should be cleared
        Assert.isFalse(UoWTransactionState.hasCurrent(), 'Transaction state should be cleared after commit');
        Assert.isNull(UoWTransactionState.getCurrent(), 'Current state should be null after commit completes');

        // Result should have the expected correlation ID
        Assert.areEqual(expectedCorrelationId, result.correlationId, 'Result should have original correlation ID');
    }

    @isTest
    static void test_transactionState_clearedOnError() {
        // Configure chaos engine for failure
        UoWChaosEngine.reset();
        UoWChaosEngine.enable();
        UoWChaosEngine.alwaysFail(UoWChaosEngine.Point.DML_INSERT, UoWChaosEngine.sampleInsertDmlException());

        // Arrange
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - State should be cleared even on error
        Assert.isFalse(UoWTransactionState.hasCurrent(), 'Transaction state should be cleared even after error');
        Assert.isNull(UoWTransactionState.getCurrent(), 'Current state should be null after error');

        // Cleanup
        UoWChaosEngine.reset();
    }

    // ============================================================================
    // UOWTRANSACTIONSTATE SERIALIZATION TESTS
    // ============================================================================

    @isTest
    static void test_transactionState_serializationRoundTrip() {
        // Arrange
        String testCorrelationId = UoWUtils.generateUUID();
        String testParentTxnId = UoWUtils.generateTransactionId();
        Integer testAsyncDepth = 2;

        UoWTransactionState state = new UoWTransactionState(
            testCorrelationId,
            testParentTxnId,
            testAsyncDepth
        );

        // Act - Serialize then deserialize
        Test.startTest();
        String json = state.toJson();
        UoWTransactionState restored = UoWTransactionState.fromJson(json);
        Test.stopTest();

        // Assert
        Assert.isNotNull(restored, 'Restored state should not be null');
        Assert.areEqual(testCorrelationId, restored.correlationId, 'Correlation ID should survive serialization');
        Assert.areEqual(testParentTxnId, restored.transactionId, 'Transaction ID should survive serialization');
        Assert.areEqual(testAsyncDepth, restored.asyncDepth, 'Async depth should survive serialization');
        Assert.isNotNull(restored.capturedAt, 'CapturedAt should be set');
    }

    @isTest
    static void test_transactionState_fromJsonWithNull() {
        // Act
        Test.startTest();
        UoWTransactionState state = UoWTransactionState.fromJson(null);
        Test.stopTest();

        // Assert
        Assert.isNull(state, 'Should return null for null JSON');
    }

    @isTest
    static void test_transactionState_fromJsonWithBlank() {
        // Act
        Test.startTest();
        UoWTransactionState state = UoWTransactionState.fromJson('');
        Test.stopTest();

        // Assert
        Assert.isNull(state, 'Should return null for blank JSON');
    }

    @isTest
    static void test_transactionState_fromValues() {
        // Arrange
        String testCorrelationId = UoWUtils.generateUUID();
        String testParentTxnId = UoWUtils.generateTransactionId();

        // Act
        Test.startTest();
        UoWTransactionState state = UoWTransactionState.fromValues(
            testCorrelationId,
            testParentTxnId
        );
        Test.stopTest();

        // Assert
        Assert.areEqual(testCorrelationId, state.correlationId, 'Correlation ID should be set');
        Assert.areEqual(testParentTxnId, state.transactionId, 'Transaction ID should be set');
        Assert.areEqual(0, state.asyncDepth, 'Async depth should default to 0');
    }

    @isTest
    static void test_transactionState_constructorWithContext() {
        // Arrange
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks');
        UoWContext ctx = uow.getContext();

        // Act
        Test.startTest();
        UoWTransactionState state = new UoWTransactionState(ctx);
        Test.stopTest();

        // Assert
        Assert.areEqual(ctx.correlationId, state.correlationId, 'Correlation ID should match context');
        Assert.areEqual(ctx.transactionId, state.transactionId, 'Transaction ID should match context');
        Assert.areEqual(ctx.asyncDepth, state.asyncDepth, 'Async depth should match context');
    }

    @isTest
    static void test_transactionState_applyToUnitOfWork() {
        // Arrange
        String testCorrelationId = UoWUtils.generateUUID();
        String testParentTxnId = UoWUtils.generateTransactionId();

        UoWTransactionState state = new UoWTransactionState(
            testCorrelationId,
            testParentTxnId,
            1  // Initial depth
        );

        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks');

        // Act
        Test.startTest();
        state.applyTo(uow);
        Test.stopTest();

        // Assert
        Assert.areEqual(testCorrelationId, uow.getContext().correlationId, 'Correlation ID should be applied');
        Assert.areEqual(testParentTxnId, uow.getContext().parentTransactionId, 'Parent transaction ID should be applied');
        Assert.areEqual(2, uow.getContext().asyncDepth, 'Async depth should be incremented');
    }

    // ============================================================================
    // UNITOFWORK CONSTRUCTOR AUTO-DETECTION TESTS
    // ============================================================================

    @isTest
    static void test_constructor_outsideTransaction_createsRoot() {
        // Arrange - Ensure not inside transaction
        UoWTransactionState.clearCurrent();

        // Act
        Test.startTest();
        UnitOfWork uow = new UnitOfWork('TestConfigAllMocks');
        Test.stopTest();

        // Assert
        Assert.isNotNull(uow.getContext().correlationId, 'Should have correlation ID');
        Assert.isNotNull(uow.getContext().transactionId, 'Should have transaction ID');
        Assert.isNull(uow.getContext().parentTransactionId, 'Should not have parent (is root)');
        Assert.areEqual(0, uow.getContext().asyncDepth, 'Async depth should be 0');
    }

    @isTest
    static void test_constructor_withExplicitState_usesState() {
        // Arrange
        String testCorrelationId = UoWUtils.generateUUID();
        String testParentTxnId = UoWUtils.generateTransactionId();

        UoWTransactionState state = new UoWTransactionState(
            testCorrelationId,
            testParentTxnId,
            0
        );

        // Act
        Test.startTest();
        UnitOfWork uow = new UnitOfWork('TestConfigAllMocks', state);
        Test.stopTest();

        // Assert
        Assert.areEqual(testCorrelationId, uow.getContext().correlationId, 'Should use state correlation ID');
        Assert.areEqual(testParentTxnId, uow.getContext().parentTransactionId, 'Should use state transaction ID as parent');
        Assert.areEqual(1, uow.getContext().asyncDepth, 'Async depth should be incremented from state');
    }

    @isTest
    static void test_asRoot_ignoresAmbientContext() {
        // Arrange - Manually set transaction state to simulate being inside a UoW
        UnitOfWork parentUow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks');
        UoWTransactionState.setCurrent(new UoWTransactionState(parentUow.getContext()));

        String parentCorrelationId = parentUow.getContext().correlationId;

        // Act - Create new UoW as root
        Test.startTest();
        UnitOfWork childUow = new UnitOfWork('TestConfigAllMocks').asRoot();
        Test.stopTest();

        // Assert
        Assert.areNotEqual(parentCorrelationId, childUow.getContext().correlationId, 'Should have new correlation ID (not inherited)');
        Assert.isNull(childUow.getContext().parentTransactionId, 'Should not have parent transaction ID');
        Assert.areEqual(0, childUow.getContext().asyncDepth, 'Async depth should be 0');

        // Cleanup
        UoWTransactionState.clearCurrent();
    }

    // ============================================================================
    // AMBIENT TRANSACTION ACCESS TESTS
    // ============================================================================

    @isTest
    static void test_ambientAccess_outsideTransaction() {
        // Arrange - Ensure not inside transaction
        Test.startTest();
        UoWTransactionState.clearCurrent();
        Test.stopTest();

        // Act & Assert
        Assert.isFalse(UoWTransactionState.hasCurrent(), 'Should not have current transaction');
        Assert.isNull(UoWTransactionState.getCurrent(), 'Current transaction should be null');
        Assert.isNull(UoWTransactionState.getCurrentJson(), 'Current JSON should be null');
    }

    @isTest
    static void test_ambientAccess_insideTransaction() {
        // Arrange - Manually set transaction state
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks');
        UoWTransactionState.setCurrent(new UoWTransactionState(uow.getContext()));

        String expectedCorrelationId = uow.getContext().correlationId;
        String expectedTransactionId = uow.getContext().transactionId;

        // Act
        Test.startTest();
        Boolean hasCurrent = UoWTransactionState.hasCurrent();
        UoWTransactionState current = UoWTransactionState.getCurrent();
        String currentJson = UoWTransactionState.getCurrentJson();
        Test.stopTest();

        // Assert
        Assert.isTrue(hasCurrent, 'Should have current transaction');
        Assert.isNotNull(current, 'Current transaction should not be null');
        Assert.areEqual(expectedCorrelationId, current.correlationId, 'Should return correlation ID');
        Assert.areEqual(expectedTransactionId, current.transactionId, 'Should return transaction ID');
        Assert.isNotNull(currentJson, 'Current JSON should not be null');

        // Cleanup
        UoWTransactionState.clearCurrent();
    }

    // ============================================================================
    // FLOW INITIALIZE ACTION TESTS
    // ============================================================================

    @isTest
    static void test_flowInitialize_outsideTransaction_createsRoot() {
        // Arrange - Ensure not inside transaction
        UoWTransactionState.clearCurrent();

        UoWFlowInitializeAction.InitializeRequest request = new UoWFlowInitializeAction.InitializeRequest();
        request.configurationName = 'TestConfigAllMocks';

        // Act
        Test.startTest();
        List<UoWFlowInitializeAction.InitializeResult> results =
            UoWFlowInitializeAction.initialize(new List<UoWFlowInitializeAction.InitializeRequest>{ request });
        Test.stopTest();

        // Assert
        Assert.areEqual(1, results.size(), 'Should return one result');
        UoWFlowInitializeAction.InitializeResult result = results[0];
        Assert.isTrue(result.success, 'Should succeed');
        Assert.isNotNull(result.transactionId, 'Should have transaction ID');
        Assert.isNotNull(result.correlationId, 'Should have correlation ID');
        Assert.isNotNull(result.contextCarrier, 'Should have context carrier');
        Assert.isTrue(result.message.contains('successfully'), 'Message should indicate success');
    }

    @isTest
    static void test_flowInitialize_withExplicitState_inheritsCorrelation() {
        // Arrange
        String testCorrelationId = UoWUtils.generateUUID();
        String testParentTxnId = UoWUtils.generateTransactionId();

        UoWTransactionState state = new UoWTransactionState(
            testCorrelationId,
            testParentTxnId,
            0
        );

        UoWFlowInitializeAction.InitializeRequest request = new UoWFlowInitializeAction.InitializeRequest();
        request.configurationName = 'TestConfigAllMocks';
        request.contextCarrier = state.toJson();

        // Act
        Test.startTest();
        List<UoWFlowInitializeAction.InitializeResult> results =
            UoWFlowInitializeAction.initialize(new List<UoWFlowInitializeAction.InitializeRequest>{ request });
        Test.stopTest();

        // Assert
        Assert.areEqual(1, results.size(), 'Should return one result');
        UoWFlowInitializeAction.InitializeResult result = results[0];
        Assert.isTrue(result.success, 'Should succeed');
        Assert.areEqual(testCorrelationId, result.correlationId, 'Should inherit correlation ID from state');
        Assert.isTrue(result.message.contains('inherited'), 'Message should indicate inheritance');
    }

    @isTest
    static void test_flowInitialize_insideTransaction_autoInherits() {
        // Arrange - Manually set transaction state to simulate being inside a UoW
        UnitOfWork parentUow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks');
        UoWTransactionState.setCurrent(new UoWTransactionState(parentUow.getContext()));

        String expectedCorrelationId = parentUow.getContext().correlationId;

        UoWFlowInitializeAction.InitializeRequest request = new UoWFlowInitializeAction.InitializeRequest();
        request.configurationName = 'TestConfigAllMocks';
        // No contextCarrier - should auto-detect

        // Act
        Test.startTest();
        List<UoWFlowInitializeAction.InitializeResult> results =
            UoWFlowInitializeAction.initialize(new List<UoWFlowInitializeAction.InitializeRequest>{ request });
        Test.stopTest();

        // Assert
        Assert.areEqual(1, results.size(), 'Should return one result');
        UoWFlowInitializeAction.InitializeResult result = results[0];
        Assert.isTrue(result.success, 'Should succeed');
        Assert.areEqual(expectedCorrelationId, result.correlationId, 'Should auto-inherit correlation ID from ambient context');
        Assert.isTrue(result.message.contains('inherited'), 'Message should indicate inheritance');

        // Cleanup
        UoWTransactionState.clearCurrent();
    }

    // ============================================================================
    // END-TO-END CORRELATION CHAIN TESTS
    // ============================================================================

    @isTest
    static void test_correlationChain_parentToChild() {
        // Arrange - Create parent UoW
        UnitOfWork parentUow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks');
        String parentCorrelationId = parentUow.getContext().correlationId;
        String parentTransactionId = parentUow.getContext().transactionId;

        // Simulate being inside parent UoW
        UoWTransactionState.setCurrent(new UoWTransactionState(parentUow.getContext()));

        // Act - Create child UoW (should auto-inherit)
        UnitOfWork childUow = new UnitOfWork('TestConfigAllMocks');

        // Assert
        Assert.areEqual(parentCorrelationId, childUow.getContext().correlationId, 'Child should inherit parent correlation ID');
        Assert.areEqual(parentTransactionId, childUow.getContext().parentTransactionId, 'Child should have parent as parentTransactionId');
        Assert.areNotEqual(parentTransactionId, childUow.getContext().transactionId, 'Child should have different transaction ID');
        Assert.areEqual(1, childUow.getContext().asyncDepth, 'Child async depth should be 1');

        // Cleanup
        UoWTransactionState.clearCurrent();
    }

    @isTest
    static void test_correlationChain_asyncBoundary() {
        // Arrange - Create parent UoW and commit
        UnitOfWork parentUow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks');
        UoWResult parentResult = parentUow.commitWork();

        String parentCorrelationId = parentResult.correlationId;
        String parentTransactionId = parentResult.transactionId;

        // Simulate getting state from parent and passing across async boundary
        UoWTransactionState state = new UoWTransactionState(
            parentCorrelationId,
            parentTransactionId,
            0
        );

        // Act - Create async child UoW with state
        UnitOfWork asyncChildUow = new UnitOfWork('TestConfigAllMocks', state);

        // Assert
        Assert.areEqual(parentCorrelationId, asyncChildUow.getContext().correlationId, 'Async child should inherit parent correlation ID');
        Assert.areEqual(parentTransactionId, asyncChildUow.getContext().parentTransactionId, 'Async child should have parent as parentTransactionId');
        Assert.areEqual(1, asyncChildUow.getContext().asyncDepth, 'Async child async depth should be 1');
    }
}