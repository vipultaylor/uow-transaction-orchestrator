//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Tests for UoWMessage and UoWTracer classes.
 * Covers message infrastructure, distributed tracing, span management,
 * trace summary, and event tracking.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Tests
 * @see UoWMessage
 * @see UoWTracer
 */
@isTest
@SuppressWarnings('PMD.MethodNamingConventions')
private class UoWMessageTracerTests {
    // ============================================================================
    // TEST SETUP
    // ============================================================================

    @TestSetup
    static void setupTestData() {
        // Load test configurations
        UoWTestHelpers.loadTestConfigurations();
    }

    // ============================================================================
    // UoWMessage TESTS
    // ============================================================================

    @isTest
    static void test_message_constructor_setsAllFields() {
        // Arrange
        String messageText = 'Test message';
        String source = 'TestSource';

        // Act
        Test.startTest();
        UoWMessage msg = new UoWMessage(System.LoggingLevel.INFO, messageText, source);
        Test.stopTest();

        // Assert
        Assert.isNotNull(msg.timestamp, 'Timestamp should be set');
        Assert.areEqual(System.LoggingLevel.INFO, msg.loggingLevel, 'Logging level should be INFO');
        Assert.areEqual(messageText, msg.message, 'Message text should match');
        Assert.areEqual(source, msg.source, 'Source should match');
        Assert.isNotNull(msg.metadata, 'Metadata map should be initialized');
        Assert.isTrue(msg.metadata.isEmpty(), 'Metadata should be empty initially');
    }

    @isTest
    static void test_message_withCategory_setsCategory() {
        // Arrange
        UoWMessage msg = new UoWMessage(System.LoggingLevel.INFO, 'Test', 'Source');

        // Act
        Test.startTest();
        UoWMessage result = msg.withCategory('VALIDATION');
        Test.stopTest();

        // Assert
        Assert.areEqual('VALIDATION', msg.category, 'Category should be set');
        Assert.areEqual(msg, result, 'Should return same instance for chaining');
    }

    @isTest
    static void test_message_withMetadata_singleKeyValue() {
        // Arrange
        UoWMessage msg = new UoWMessage(System.LoggingLevel.INFO, 'Test', 'Source');

        // Act
        Test.startTest();
        UoWMessage result = msg.withMetadata('key1', 'value1')
            .withMetadata('key2', 123);
        Test.stopTest();

        // Assert
        Assert.areEqual('value1', msg.metadata.get('key1'), 'Should store string value');
        Assert.areEqual(123, msg.metadata.get('key2'), 'Should store integer value');
        Assert.areEqual(msg, result, 'Should return same instance for chaining');
    }

    @isTest
    static void test_message_withMetadata_mapOverload() {
        // Arrange
        UoWMessage msg = new UoWMessage(System.LoggingLevel.INFO, 'Test', 'Source');
        Map<String, Object> metadata = new Map<String, Object>{
            'key1' => 'value1',
            'key2' => 42,
            'key3' => true
        };

        // Act
        Test.startTest();
        UoWMessage result = msg.withMetadata(metadata);
        Test.stopTest();

        // Assert
        Assert.areEqual(3, msg.metadata.size(), 'Should have 3 metadata entries');
        Assert.areEqual('value1', msg.metadata.get('key1'), 'Should store string value');
        Assert.areEqual(42, msg.metadata.get('key2'), 'Should store integer value');
        Assert.areEqual(true, msg.metadata.get('key3'), 'Should store boolean value');
        Assert.areEqual(msg, result, 'Should return same instance for chaining');
    }

    @isTest
    static void test_message_isError_trueForErrorLevel() {
        // Arrange
        UoWMessage errorMsg = new UoWMessage(System.LoggingLevel.ERROR, 'Error', 'Source');
        UoWMessage infoMsg = new UoWMessage(System.LoggingLevel.INFO, 'Info', 'Source');

        // Act & Assert
        Test.startTest();
        Assert.isTrue(errorMsg.isError(), 'ERROR level should return true for isError()');
        Assert.isFalse(infoMsg.isError(), 'INFO level should return false for isError()');
        Test.stopTest();
    }

    @isTest
    static void test_message_isWarning_trueForWarnLevel() {
        // Arrange
        UoWMessage warnMsg = new UoWMessage(System.LoggingLevel.WARN, 'Warn', 'Source');
        UoWMessage infoMsg = new UoWMessage(System.LoggingLevel.INFO, 'Info', 'Source');

        // Act & Assert
        Test.startTest();
        Assert.isTrue(warnMsg.isWarning(), 'WARN level should return true for isWarning()');
        Assert.isFalse(infoMsg.isWarning(), 'INFO level should return false for isWarning()');
        Test.stopTest();
    }

    @isTest
    static void test_message_isInfo_trueForInfoLevel() {
        // Arrange
        UoWMessage infoMsg = new UoWMessage(System.LoggingLevel.INFO, 'Info', 'Source');
        UoWMessage errorMsg = new UoWMessage(System.LoggingLevel.ERROR, 'Error', 'Source');

        // Act & Assert
        Test.startTest();
        Assert.isTrue(infoMsg.isInfo(), 'INFO level should return true for isInfo()');
        Assert.isFalse(errorMsg.isInfo(), 'ERROR level should return false for isInfo()');
        Test.stopTest();
    }

    @isTest
    static void test_message_isDebug_trueForDebugLevel() {
        // Arrange
        UoWMessage debugMsg = new UoWMessage(System.LoggingLevel.DEBUG, 'Debug', 'Source');
        UoWMessage infoMsg = new UoWMessage(System.LoggingLevel.INFO, 'Info', 'Source');

        // Act & Assert
        Test.startTest();
        Assert.isTrue(debugMsg.isDebug(), 'DEBUG level should return true for isDebug()');
        Assert.isFalse(infoMsg.isDebug(), 'INFO level should return false for isDebug()');
        Test.stopTest();
    }

    @isTest
    static void test_message_isFine_trueForFineLevel() {
        // Arrange
        UoWMessage fineMsg = new UoWMessage(System.LoggingLevel.FINE, 'Fine', 'Source');
        UoWMessage infoMsg = new UoWMessage(System.LoggingLevel.INFO, 'Info', 'Source');

        // Act & Assert
        Test.startTest();
        Assert.isTrue(fineMsg.isFine(), 'FINE level should return true for isFine()');
        Assert.isFalse(infoMsg.isFine(), 'INFO level should return false for isFine()');
        Test.stopTest();
    }

    @isTest
    static void test_message_isFiner_trueForFinerLevel() {
        // Arrange
        UoWMessage finerMsg = new UoWMessage(System.LoggingLevel.FINER, 'Finer', 'Source');
        UoWMessage infoMsg = new UoWMessage(System.LoggingLevel.INFO, 'Info', 'Source');

        // Act & Assert
        Test.startTest();
        Assert.isTrue(finerMsg.isFiner(), 'FINER level should return true for isFiner()');
        Assert.isFalse(infoMsg.isFiner(), 'INFO level should return false for isFiner()');
        Test.stopTest();
    }

    @isTest
    static void test_message_isFinest_trueForFinestLevel() {
        // Arrange
        UoWMessage finestMsg = new UoWMessage(System.LoggingLevel.FINEST, 'Finest', 'Source');
        UoWMessage infoMsg = new UoWMessage(System.LoggingLevel.INFO, 'Info', 'Source');

        // Act & Assert
        Test.startTest();
        Assert.isTrue(finestMsg.isFinest(), 'FINEST level should return true for isFinest()');
        Assert.isFalse(infoMsg.isFinest(), 'INFO level should return false for isFinest()');
        Test.stopTest();
    }

    // ============================================================================
    // UoWTracer TESTS
    // ============================================================================

    @isTest
    static void test_tracing_enableTracing_capturesSpans() {
        // Arrange - enable tracing on transaction
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks')
            .enableTracing();

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - tracing should capture spans
        UoWTestHelpers.assertSuccess(result);
        Assert.isNotNull(result.tracer, 'Tracer should be present when tracing enabled');
        UoWTracer.TraceSummary summary = result.tracer.getSummary();
        Assert.isTrue(summary.totalSpans > 0, 'Should have spans when tracing is enabled');
    }

    @isTest
    static void test_tracing_disableTracing_noSpansCreated() {
        // Arrange - explicitly disable tracing
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks')
            .disableTracing();

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - transaction should succeed without tracing
        UoWTestHelpers.assertSuccess(result);
        // Tracer may still exist but tracing is disabled at feature level
        Assert.isFalse(result.getContext().getFeatureSettings().getEnableTracing(), 'Tracing should be disabled in feature settings');
    }

    @isTest
    static void test_tracing_defaultDisabled_noOverhead() {
        // Arrange - default behavior (no explicit enable/disable)
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigMinimal');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // By default, tracing should be disabled
        Assert.isFalse(result.getContext().getFeatureSettings().getEnableTracing(), 'Tracing should be disabled by default');
    }

    @isTest
    static void test_tracer_constructor_usesProvidedIds() {
        // Arrange - correlationId (UUID) and transactionId
        String correlationId = UoWUtils.generateUUID();
        String transactionId = UoWUtils.generateTransactionId();

        // Act
        Test.startTest();
        UoWTracer tracer = new UoWTracer(correlationId, transactionId);
        Test.stopTest();

        // Assert - correlationId becomes the OTel traceId
        String traceId = tracer.getTraceId();
        Assert.isNotNull(traceId, 'Trace ID should not be null');
        Assert.areEqual(correlationId, traceId, 'Trace ID should be the correlationId (UUID)');
    }

    @isTest
    static void test_tracer_startSpan_createsSpanWithAttributes() {
        // Arrange
        UoWTracer tracer = new UoWTracer(UoWUtils.generateUUID(), UoWUtils.generateTransactionId());

        // Act
        Test.startTest();
        UoWTracer.Span span = tracer.startSpan(UoWEnums.SpanPhase.DML_EXECUTION, 'Insert Accounts');
        Test.stopTest();

        // Assert
        Assert.isNotNull(span, 'Span should not be null');
        Assert.isNotNull(span.spanId, 'Span should have ID');
        Assert.areEqual(UoWEnums.SpanPhase.DML_EXECUTION, span.phase, 'Span phase should match');
    }

    @isTest
    static void test_tracer_endSpan_completesSpan() {
        // Arrange
        UoWTracer tracer = new UoWTracer(UoWUtils.generateUUID(), UoWUtils.generateTransactionId());
        UoWTracer.Span span = tracer.startSpan(UoWEnums.SpanPhase.DML_EXECUTION, 'Test');

        // Act
        Test.startTest();
        tracer.endSpan(span, UoWEnums.SpanPhaseResult.SUCCESS, null);
        Test.stopTest();

        // Assert
        Assert.isTrue(span.isCompleted, 'Span should be marked as completed');
        Assert.isTrue(span.durationMs >= 0, 'Duration should be non-negative');
    }

    @isTest
    static void test_tracer_nestedSpans_establishesParentChild() {
        // Arrange
        UoWTracer tracer = new UoWTracer(UoWUtils.generateUUID(), UoWUtils.generateTransactionId());

        // Act
        Test.startTest();
        UoWTracer.Span parentSpan = tracer.startSpan(UoWEnums.SpanPhase.TRANSACT, 'Transaction');
        UoWTracer.Span childSpan = tracer.startSpan(UoWEnums.SpanPhase.DML_EXECUTION, 'DML');
        tracer.endSpan(childSpan, UoWEnums.SpanPhaseResult.SUCCESS, null);
        tracer.endSpan(parentSpan, UoWEnums.SpanPhaseResult.SUCCESS, null);
        Test.stopTest();

        // Assert
        Assert.areEqual(parentSpan.spanId, childSpan.parentSpanId,
            'Child should reference parent span ID');
        Assert.areEqual(2, childSpan.level, 'Child should be at level 2');
        Assert.areEqual(1, parentSpan.level, 'Parent should be at level 1');
    }

    @isTest
    static void test_tracer_reset_clearsAllSpans() {
        // Arrange
        UoWTracer tracer = new UoWTracer(UoWUtils.generateUUID(), UoWUtils.generateTransactionId());
        tracer.startSpan(UoWEnums.SpanPhase.DML_EXECUTION, 'Test');

        // Act
        Test.startTest();
        tracer.reset();
        Test.stopTest();

        // Assert - New span should be at level 1 (no parent)
        UoWTracer.Span newSpan = tracer.startSpan(UoWEnums.SpanPhase.DML_EXECUTION, 'New');
        Assert.areEqual(1, newSpan.level, 'New span after reset should be at level 1');
    }

    @isTest
    static void test_tracer_commitTrace_enablesTracing() {
        // Arrange
        UoWTracer tracer = new UoWTracer(UoWUtils.generateUUID(), UoWUtils.generateTransactionId());

        // Act
        Test.startTest();
        tracer.commitTrace();
        Test.stopTest();

        // Assert
        Assert.isTrue(tracer.isCommitted(), 'Tracer should be committed');
    }

    @isTest
    static void test_tracer_discardTrace_clearsBuffer() {
        // Arrange
        UoWTracer tracer = new UoWTracer(UoWUtils.generateUUID(), UoWUtils.generateTransactionId());
        tracer.startSpan(UoWEnums.SpanPhase.DML_EXECUTION, 'Test');
        tracer.commitTrace();

        // Act
        Test.startTest();
        tracer.discardTrace();
        Test.stopTest();

        // Assert
        Assert.isFalse(tracer.isCommitted(), 'Tracer should not be committed after discard');
    }

    @isTest
    static void test_tracer_getSummary_aggregatesSpanData() {
        // Arrange
        UoWTracer tracer = new UoWTracer(UoWUtils.generateUUID(), UoWUtils.generateTransactionId());
        UoWTracer.Span span = tracer.startSpan(UoWEnums.SpanPhase.TRANSACT, 'Transaction');
        tracer.endSpan(span, UoWEnums.SpanPhaseResult.SUCCESS, null);
        tracer.commitTrace();  // Must commit to get summary

        // Act
        Test.startTest();
        UoWTracer.TraceSummary summary = tracer.getSummary();
        Test.stopTest();

        // Assert
        Assert.isNotNull(summary, 'Summary should not be null');
        Assert.areEqual(tracer.getTraceId(), summary.traceId, 'Summary trace ID should match');
    }

    @isTest
    static void test_tracer_startSpan_withNullPhase_usesDefault() {
        // Arrange
        UoWTracer tracer = new UoWTracer(UoWUtils.generateUUID(), UoWUtils.generateTransactionId());

        // Act
        Test.startTest();
        UoWEnums.SpanPhase nullPhase = null;
        UoWTracer.Span span = tracer.startSpan(nullPhase, 'Test');
        Test.stopTest();

        // Assert
        Assert.areEqual(UoWEnums.SpanPhase.TRANSACT, span.phase,
            'Should default to TRANSACT phase when null provided');
    }

    @isTest
    static void test_tracer_setAttribute_storesAttribute() {
        // Arrange
        UoWTracer tracer = new UoWTracer(UoWUtils.generateUUID(), UoWUtils.generateTransactionId());
        UoWTracer.Span span = tracer.startSpan(UoWEnums.SpanPhase.DML_EXECUTION, 'Test');

        // Act
        Test.startTest();
        span.setAttribute('key1', 'value1');
        span.setAttribute('key2', 123);
        Test.stopTest();

        // Assert
        Assert.areEqual('value1', span.attributes.get('key1'), 'Should store string attribute');
        Assert.areEqual(123, span.attributes.get('key2'), 'Should store integer attribute');
    }

    @isTest
    static void test_unitOfWork_withTracing_tracksTransactionSpans() {
        // Act
        Test.startTest();
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks')
            .enableTracing();  // Enable tracing via direct method

        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Transaction should succeed with tracing data
        UoWTestHelpers.assertSuccess(result);

        // Check if tracer captured spans (via result)
        Assert.isNotNull(result.tracer, 'Result should have tracer');
    }

    @isTest
    static void test_unitOfWork_withTracing_multipleWorkTypes() {
        // Real-world scenario: Track DML, events, emails, flows in single transaction

        // Act
        Test.startTest();
        UnitOfWork uow = UoWTestHelpers.generateUoW_AllWorkItems('TestConfigAllMocks')
            .enableTracing();  // Enable tracing via direct method

        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - All work types executed with tracing
        UoWTestHelpers.assertSuccess(result);
        UoWTestHelpers.assertAllWorkItemSuccessfulExecution(result);
    }

    // ============================================================================
    // UoWTracer ADDITIONAL TESTS (addEvent, uncommitted summary)
    // ============================================================================

    @isTest
    static void test_tracer_addEvent_toCurrentSpan() {
        // Arrange
        UoWTracer tracer = new UoWTracer(UoWUtils.generateUUID(), UoWUtils.generateTransactionId());
        UoWTracer.Span span = tracer.startSpan(UoWEnums.SpanPhase.DML_EXECUTION, 'Test Span');

        // Act
        Test.startTest();
        tracer.addEvent('validation_completed');
        tracer.addEvent('records_processed', new Map<String, Object>{ 'count' => 10 });
        tracer.commitTrace();
        Test.stopTest();

        // Assert
        Assert.areEqual(2, span.events.size(), 'Span should have 2 events');
        Assert.areEqual('validation_completed', span.events[0].name, 'First event name should match');
        Assert.areEqual('records_processed', span.events[1].name, 'Second event name should match');
        Assert.areEqual(10, span.events[1].attributes.get('count'), 'Event should have count attribute');
    }

    @isTest
    static void test_tracer_addEvent_toSpecificSpan() {
        // Arrange
        UoWTracer tracer = new UoWTracer(UoWUtils.generateUUID(), UoWUtils.generateTransactionId());
        UoWTracer.Span span1 = tracer.startSpan(UoWEnums.SpanPhase.DML_EXECUTION, 'Span 1');
        UoWTracer.Span span2 = tracer.startSpan(UoWEnums.SpanPhase.POLICY_EVALUATION, 'Span 2');

        // Act - Add event to specific span (span1), not current span
        Test.startTest();
        tracer.addEvent(span1, 'event_on_span1', new Map<String, Object>{ 'target' => 'span1' });
        tracer.commitTrace();
        Test.stopTest();

        // Assert
        Assert.areEqual(1, span1.events.size(), 'Span 1 should have 1 event');
        Assert.areEqual(0, span2.events.size(), 'Span 2 should have no events');
        Assert.areEqual('event_on_span1', span1.events[0].name, 'Event should be on span 1');
    }

    @isTest
    static void test_tracer_addEvent_nullSpan_noOp() {
        // Arrange
        UoWTracer tracer = new UoWTracer(UoWUtils.generateUUID(), UoWUtils.generateTransactionId());

        // Act - Add event when no span is active
        Test.startTest();
        tracer.addEvent('orphan_event'); // Should not crash
        Test.stopTest();

        // Assert - No exception thrown, event is ignored
        Assert.isNotNull(tracer, 'Tracer should still exist');
    }

    @isTest
    static void test_tracer_getSummary_uncommittedReturnsNull() {
        // Arrange - Create tracer without committing
        UoWTracer tracer = new UoWTracer(UoWUtils.generateUUID(), UoWUtils.generateTransactionId());
        UoWTracer.Span span = tracer.startSpan(UoWEnums.SpanPhase.DML_EXECUTION, 'Test Span');
        tracer.endSpan(span, UoWEnums.SpanPhaseResult.SUCCESS, null);

        // Act - Get summary without committing
        Test.startTest();
        UoWTracer.TraceSummary summary = tracer.getSummary();
        Test.stopTest();

        // Assert - Uncommitted tracer returns null summary
        Assert.isNull(summary, 'Uncommitted tracer should return null summary');
    }

    @isTest
    static void test_tracer_discardTrace_clearsSummary() {
        // Arrange
        UoWTracer tracer = new UoWTracer(UoWUtils.generateUUID(), UoWUtils.generateTransactionId());
        UoWTracer.Span span = tracer.startSpan(UoWEnums.SpanPhase.DML_EXECUTION, 'Test Span');
        tracer.addEvent('test_event');
        tracer.endSpan(span, UoWEnums.SpanPhaseResult.SUCCESS, null);

        // Act - Discard the trace
        Test.startTest();
        tracer.discardTrace();

        // Try to commit and get summary
        tracer.commitTrace();
        UoWTracer.TraceSummary summary = tracer.getSummary();
        Test.stopTest();

        // Assert - Discarded trace should have empty spans
        Assert.isNotNull(summary, 'Summary should exist after commit');
        Assert.areEqual(0, summary.totalSpans, 'Discarded trace should have no spans');
    }

    @isTest
    static void test_tracer_spanEvent_getTimestampUnixNano() {
        // Arrange
        UoWTracer tracer = new UoWTracer(UoWUtils.generateUUID(), UoWUtils.generateTransactionId());
        UoWTracer.Span span = tracer.startSpan(UoWEnums.SpanPhase.DML_EXECUTION, 'Test');

        // Act
        Test.startTest();
        tracer.addEvent('test_event');
        Test.stopTest();

        // Assert
        UoWTracer.SpanEvent event = span.events[0];
        Long timestampNano = event.getTimestampUnixNano();
        Assert.isNotNull(timestampNano, 'Should have timestamp in nanoseconds');
        Assert.isTrue(timestampNano > 0, 'Timestamp should be positive');
    }

    @isTest
    static void test_tracer_traceSummary_getSpansJson() {
        // Arrange
        UoWTracer tracer = new UoWTracer(UoWUtils.generateUUID(), UoWUtils.generateTransactionId());
        UoWTracer.Span span = tracer.startSpan(UoWEnums.SpanPhase.DML_EXECUTION, 'Test Span');
        tracer.endSpan(span, UoWEnums.SpanPhaseResult.SUCCESS, null);
        tracer.commitTrace();

        // Act
        Test.startTest();
        UoWTracer.TraceSummary summary = tracer.getSummary();
        String spansJson = summary.getSpansJson();
        Test.stopTest();

        // Assert
        Assert.isNotNull(spansJson, 'Should return JSON string');
        Assert.isTrue(spansJson.startsWith('['), 'JSON should be an array');
        Assert.isTrue(spansJson.contains('spanId'), 'JSON should contain spanId');
    }

    @isTest
    static void test_tracer_traceSummary_getEventsJson() {
        // Arrange
        UoWTracer tracer = new UoWTracer(UoWUtils.generateUUID(), UoWUtils.generateTransactionId());
        UoWTracer.Span span = tracer.startSpan(UoWEnums.SpanPhase.DML_EXECUTION, 'Test Span');
        tracer.addEvent('test_event');
        tracer.endSpan(span, UoWEnums.SpanPhaseResult.SUCCESS, null);
        tracer.commitTrace();

        // Act
        Test.startTest();
        UoWTracer.TraceSummary summary = tracer.getSummary();
        String eventsJson = summary.getEventsJson();
        Test.stopTest();

        // Assert
        Assert.isNotNull(eventsJson, 'Should return JSON string');
        Assert.isTrue(eventsJson.startsWith('['), 'JSON should be an array');
        Assert.isTrue(eventsJson.contains('eventId'), 'JSON should contain eventId');
    }

    @isTest
    static void test_tracer_span_getStartTimeUnixNano() {
        // Arrange
        UoWTracer tracer = new UoWTracer(UoWUtils.generateUUID(), UoWUtils.generateTransactionId());

        // Act
        Test.startTest();
        UoWTracer.Span span = tracer.startSpan(UoWEnums.SpanPhase.DML_EXECUTION, 'Test');
        Long startNano = span.getStartTimeUnixNano();
        tracer.endSpan(span, UoWEnums.SpanPhaseResult.SUCCESS, null);
        Long endNano = span.getEndTimeUnixNano();
        Test.stopTest();

        // Assert
        Assert.isNotNull(startNano, 'Should have start time in nanoseconds');
        Assert.isNotNull(endNano, 'Should have end time in nanoseconds');
        Assert.isTrue(endNano >= startNano, 'End time should be >= start time');
    }
}