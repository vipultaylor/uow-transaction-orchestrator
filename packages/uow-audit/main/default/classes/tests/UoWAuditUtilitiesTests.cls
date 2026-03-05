//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Test class for UoW Audit utility classes.
 * Covers: UoWAuditParameter, UoWAuditEnums, UoWCompactTimeline, UoWOriginSourceService
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Audit Test Utilities
 */
@isTest
@SuppressWarnings('PMD.MethodNamingConventions')
private class UoWAuditUtilitiesTests {

    // ============================================================================
    // UOWAUDITPARAMETER TESTS
    // ============================================================================

    @isTest
    static void test_parameter_defaultSamplingCount_returnsValue() {
        // Act
        Integer samplingCount = UoWAuditParameter.DEFAULT_SAMPLING_COUNT;

        // Assert
        Assert.isNotNull(samplingCount, 'DEFAULT_SAMPLING_COUNT should return a value');
        Assert.isTrue(samplingCount > 0, 'DEFAULT_SAMPLING_COUNT should be positive');
    }

    @isTest
    static void test_parameter_defaultSamplingStrategy_returnsValue() {
        // Act
        String strategy = UoWAuditParameter.DEFAULT_SAMPLING_STRATEGY;

        // Assert
        Assert.isNotNull(strategy, 'DEFAULT_SAMPLING_STRATEGY should return a value');
        Assert.isTrue(
            new Set<String>{ 'FIRST_N', 'LAST_N', 'RANDOM', 'SPREAD' }.contains(strategy),
            'DEFAULT_SAMPLING_STRATEGY should be a valid strategy'
        );
    }

    @isTest
    static void test_parameter_maxFieldSize_returnsValue() {
        // Act
        Integer maxSize = UoWAuditParameter.MAX_FIELD_SIZE;

        // Assert
        Assert.isNotNull(maxSize, 'MAX_FIELD_SIZE should return a value');
        Assert.isTrue(maxSize > 0, 'MAX_FIELD_SIZE should be positive');
    }

    @isTest
    static void test_parameter_defaultBatchSize_returnsValue() {
        // Act
        Integer batchSize = UoWAuditParameter.DEFAULT_BATCH_SIZE;

        // Assert
        Assert.isNotNull(batchSize, 'DEFAULT_BATCH_SIZE should return a value');
        Assert.isTrue(batchSize > 0, 'DEFAULT_BATCH_SIZE should be positive');
    }

    @isTest
    static void test_parameter_defaultRetentionDays_returnsValue() {
        // Act
        Integer retentionDays = UoWAuditParameter.DEFAULT_RETENTION_DAYS;

        // Assert
        Assert.isNotNull(retentionDays, 'DEFAULT_RETENTION_DAYS should return a value');
        Assert.isTrue(retentionDays > 0, 'DEFAULT_RETENTION_DAYS should be positive');
    }

    @isTest
    static void test_parameter_archiveRetentionYears_returnsValue() {
        // Act
        Integer retentionYears = UoWAuditParameter.ARCHIVE_RETENTION_YEARS;

        // Assert
        Assert.isNotNull(retentionYears, 'ARCHIVE_RETENTION_YEARS should return a value');
        Assert.isTrue(retentionYears > 0, 'ARCHIVE_RETENTION_YEARS should be positive');
    }

    @isTest
    static void test_parameter_eventTypeConstants_exist() {
        // Assert - verify constants exist and have expected values
        Assert.areEqual('TRANSACTION', UoWAuditParameter.EVENT_TYPE_TRANSACTION,
            'EVENT_TYPE_TRANSACTION should be TRANSACTION');
        Assert.areEqual('WORK_ITEM', UoWAuditParameter.EVENT_TYPE_WORK_ITEM,
            'EVENT_TYPE_WORK_ITEM should be WORK_ITEM');
    }

    @isTest
    static void test_parameter_planConstants_exist() {
        // Assert - verify mapping plan constants exist
        Assert.isNotNull(UoWAuditParameter.PLAN_TRANSACTION_TO_BIGOBJECT,
            'PLAN_TRANSACTION_TO_BIGOBJECT should not be null');
        Assert.isNotNull(UoWAuditParameter.PLAN_WORKITEM_TO_BIGOBJECT,
            'PLAN_WORKITEM_TO_BIGOBJECT should not be null');
    }

    // ============================================================================
    // UOWAUDITENUMS TESTS
    // ============================================================================

    @isTest
    static void test_auditStorageMode_allValuesExist() {
        // Assert - verify all enum values exist
        Assert.isNotNull(UoWAuditEnums.AuditStorageMode.NONE, 'NONE should exist');
        Assert.isNotNull(UoWAuditEnums.AuditStorageMode.PLATFORM_EVENT, 'PLATFORM_EVENT should exist');
        Assert.isNotNull(UoWAuditEnums.AuditStorageMode.CUSTOM_OBJECT, 'CUSTOM_OBJECT should exist');
        Assert.isNotNull(UoWAuditEnums.AuditStorageMode.BIG_OBJECT, 'BIG_OBJECT should exist');
        Assert.isNotNull(UoWAuditEnums.AuditStorageMode.EXTERNAL, 'EXTERNAL should exist');

        // Verify enum count
        List<UoWAuditEnums.AuditStorageMode> allModes = UoWAuditEnums.AuditStorageMode.values();
        Assert.areEqual(5, allModes.size(), 'Should have 5 storage modes');
    }

    @isTest
    static void test_auditArchivalMode_allValuesExist() {
        // Assert - verify all enum values exist
        Assert.isNotNull(UoWAuditEnums.AuditArchivalMode.PURGE, 'PURGE should exist');
        Assert.isNotNull(UoWAuditEnums.AuditArchivalMode.ARCHIVE, 'ARCHIVE should exist');

        // Verify enum count
        List<UoWAuditEnums.AuditArchivalMode> allModes = UoWAuditEnums.AuditArchivalMode.values();
        Assert.areEqual(2, allModes.size(), 'Should have 2 archival modes');
    }

    @isTest
    static void test_auditStorageMode_ordinalValues() {
        // Assert - verify canonical ordering (per CLAUDE.md)
        Assert.areEqual(0, UoWAuditEnums.AuditStorageMode.NONE.ordinal(), 'NONE should be first');
        Assert.areEqual(1, UoWAuditEnums.AuditStorageMode.PLATFORM_EVENT.ordinal(), 'PLATFORM_EVENT should be second');
        Assert.areEqual(2, UoWAuditEnums.AuditStorageMode.CUSTOM_OBJECT.ordinal(), 'CUSTOM_OBJECT should be third');
        Assert.areEqual(3, UoWAuditEnums.AuditStorageMode.BIG_OBJECT.ordinal(), 'BIG_OBJECT should be fourth');
        Assert.areEqual(4, UoWAuditEnums.AuditStorageMode.EXTERNAL.ordinal(), 'EXTERNAL should be fifth');
    }

    // ============================================================================
    // UOWCOMPACTTIMELINE TESTS - CONVERSION
    // ============================================================================

    @isTest
    static void test_compactTimeline_fromTraceSummary_nullInput_returnsNull() {
        // Act
        UoWCompactTimeline.CompactTrace result = UoWCompactTimeline.fromTraceSummary(null);

        // Assert
        Assert.isNull(result, 'Should return null for null input');
    }

    @isTest
    static void test_compactTimeline_toJson_nullInput_returnsNull() {
        // Act
        String result = UoWCompactTimeline.toJson(null);

        // Assert
        Assert.isNull(result, 'Should return null for null input');
    }

    @isTest
    static void test_compactTimeline_fromJson_nullInput_returnsNull() {
        // Act
        UoWCompactTimeline.CompactTrace result = UoWCompactTimeline.fromJson(null);

        // Assert
        Assert.isNull(result, 'Should return null for null input');
    }

    @isTest
    static void test_compactTimeline_fromJson_emptyString_returnsNull() {
        // Act
        UoWCompactTimeline.CompactTrace result = UoWCompactTimeline.fromJson('');

        // Assert
        Assert.isNull(result, 'Should return null for empty string');
    }

    @isTest
    static void test_compactTimeline_fromJson_blankString_returnsNull() {
        // Act
        UoWCompactTimeline.CompactTrace result = UoWCompactTimeline.fromJson('   ');

        // Assert
        Assert.isNull(result, 'Should return null for blank string');
    }

    @isTest
    static void test_compactTimeline_toJson_serializesCorrectly() {
        // Arrange
        UoWCompactTimeline.CompactTrace trace = new UoWCompactTimeline.CompactTrace();
        trace.td = 150L;
        trace.sc = 2;
        trace.sp = new List<UoWCompactTimeline.CompactSpan>();

        UoWCompactTimeline.CompactSpan span = new UoWCompactTimeline.CompactSpan();
        span.id = 1;
        span.n = 'Test Span';
        span.s = 1704067200000L;
        span.e = 1704067200150L;
        span.d = 150L;
        span.l = 1;
        span.p = 'TRANSACTION';
        span.c = 'FRAMEWORK';
        span.st = 'OK';
        trace.sp.add(span);

        // Act
        String json = UoWCompactTimeline.toJson(trace);

        // Assert
        Assert.isNotNull(json, 'Should return JSON string');
        Assert.isTrue(json.contains('"td":150'), 'Should contain totalDurationMs');
        Assert.isTrue(json.contains('"sc":2'), 'Should contain spanCount');
        Assert.isTrue(json.contains('"n":"Test Span"'), 'Should contain span name');
    }

    @isTest
    static void test_compactTimeline_fromJson_deserializesCorrectly() {
        // Arrange
        String json = '{"td":150,"sc":2,"sp":[' +
            '{"id":1,"n":"Root Span","s":1704067200000,"e":1704067200150,"d":150,"l":1,"p":"TRANSACTION","c":"FRAMEWORK","st":"OK"}' +
            ']}';

        // Act
        UoWCompactTimeline.CompactTrace result = UoWCompactTimeline.fromJson(json);

        // Assert
        Assert.isNotNull(result, 'Should deserialize successfully');
        Assert.areEqual(150L, result.td, 'Should have correct totalDurationMs');
        Assert.areEqual(2, result.sc, 'Should have correct spanCount');
        Assert.areEqual(1, result.sp.size(), 'Should have 1 span');

        UoWCompactTimeline.CompactSpan span = result.sp[0];
        Assert.areEqual(1, span.id, 'Should have correct span ID');
        Assert.areEqual('Root Span', span.n, 'Should have correct span name');
        Assert.areEqual('OK', span.st, 'Should have correct status');
    }

    @isTest
    static void test_compactTimeline_roundTrip_preservesData() {
        // Arrange
        UoWCompactTimeline.CompactTrace original = new UoWCompactTimeline.CompactTrace();
        original.td = 250L;
        original.sc = 3;
        original.sp = new List<UoWCompactTimeline.CompactSpan>();

        UoWCompactTimeline.CompactSpan span1 = new UoWCompactTimeline.CompactSpan();
        span1.id = 1;
        span1.n = 'Root';
        span1.s = 1000L;
        span1.e = 1250L;
        span1.d = 250L;
        span1.l = 1;
        span1.st = 'OK';
        original.sp.add(span1);

        UoWCompactTimeline.CompactSpan span2 = new UoWCompactTimeline.CompactSpan();
        span2.id = 2;
        span2.pid = 1;
        span2.n = 'Child';
        span2.s = 1050L;
        span2.e = 1150L;
        span2.d = 100L;
        span2.l = 2;
        span2.st = 'OK';
        original.sp.add(span2);

        // Act
        String json = UoWCompactTimeline.toJson(original);
        UoWCompactTimeline.CompactTrace restored = UoWCompactTimeline.fromJson(json);

        // Assert
        Assert.areEqual(original.td, restored.td, 'totalDurationMs should be preserved');
        Assert.areEqual(original.sc, restored.sc, 'spanCount should be preserved');
        Assert.areEqual(original.sp.size(), restored.sp.size(), 'span count should be preserved');
        Assert.areEqual(original.sp[1].pid, restored.sp[1].pid, 'parentSpanId should be preserved');
    }

    @isTest
    static void test_compactTimeline_toCompactJson_nullInput_returnsNull() {
        // Act
        String result = UoWCompactTimeline.toCompactJson(null);

        // Assert
        Assert.isNull(result, 'Should return null for null input');
    }

    @isTest
    static void test_compactTimeline_eventTypeConstants_exist() {
        // Assert - verify all event type constants exist
        Assert.areEqual('S', UoWCompactTimeline.EVENT_TYPE_STATE, 'STATE should be S');
        Assert.areEqual('D', UoWCompactTimeline.EVENT_TYPE_DECISION, 'DECISION should be D');
        Assert.areEqual('R', UoWCompactTimeline.EVENT_TYPE_RISK, 'RISK should be R');
        Assert.areEqual('E', UoWCompactTimeline.EVENT_TYPE_ERROR, 'ERROR should be E');
        Assert.areEqual('W', UoWCompactTimeline.EVENT_TYPE_WARNING, 'WARNING should be W');
        Assert.areEqual('I', UoWCompactTimeline.EVENT_TYPE_INFO, 'INFO should be I');
    }

    @isTest
    static void test_compactTimeline_compactSpan_workItemIds() {
        // Arrange
        UoWCompactTimeline.CompactSpan span = new UoWCompactTimeline.CompactSpan();
        span.id = 1;
        span.n = 'DML Phase';
        span.wk = new List<String>{ 'WORK-001', 'WORK-002', 'WORK-003' };

        UoWCompactTimeline.CompactTrace trace = new UoWCompactTimeline.CompactTrace();
        trace.td = 100L;
        trace.sc = 1;
        trace.sp = new List<UoWCompactTimeline.CompactSpan>{ span };

        // Act
        String json = UoWCompactTimeline.toJson(trace);
        UoWCompactTimeline.CompactTrace restored = UoWCompactTimeline.fromJson(json);

        // Assert
        Assert.areEqual(3, restored.sp[0].wk.size(), 'Should preserve 3 work item IDs');
        Assert.areEqual('WORK-001', restored.sp[0].wk[0], 'First work item ID should be preserved');
    }

    @isTest
    static void test_compactTimeline_compactEvent_serialization() {
        // Arrange
        UoWCompactTimeline.CompactEvent event = new UoWCompactTimeline.CompactEvent();
        event.n = 'Transaction started';
        event.t = 1704067200000L;
        event.ty = 'S';
        event.seq = 1;

        UoWCompactTimeline.CompactSpan span = new UoWCompactTimeline.CompactSpan();
        span.id = 1;
        span.n = 'Root';
        span.ev = new List<UoWCompactTimeline.CompactEvent>{ event };

        UoWCompactTimeline.CompactTrace trace = new UoWCompactTimeline.CompactTrace();
        trace.td = 100L;
        trace.sc = 1;
        trace.sp = new List<UoWCompactTimeline.CompactSpan>{ span };

        // Act
        String json = UoWCompactTimeline.toJson(trace);
        UoWCompactTimeline.CompactTrace restored = UoWCompactTimeline.fromJson(json);

        // Assert
        Assert.areEqual(1, restored.sp[0].ev.size(), 'Should have 1 event');
        UoWCompactTimeline.CompactEvent restoredEvent = restored.sp[0].ev[0];
        Assert.areEqual('Transaction started', restoredEvent.n, 'Event name should be preserved');
        Assert.areEqual('S', restoredEvent.ty, 'Event type should be preserved');
        Assert.areEqual(1, restoredEvent.seq, 'Event sequence should be preserved');
    }

    // ============================================================================
    // UOWCOMPACTTIMELINE TESTS - extractEventType / cleanEventName VIA TRACER
    // ============================================================================

    @isTest
    static void test_compactTimeline_extractEventType_allTypes_viaTracer() {
        // Arrange - Create a tracer with events of each type prefix
        UoWTracer tracer = new UoWTracer('CORR-EXTRACT', 'TXN-EXTRACT');
        UoWTracer.Span span = tracer.startSpan(UoWEnums.SpanPhase.TRANSACT, 'Root Span');

        // Add events with all known prefixes
        tracer.addEvent('[STATE] STARTED: Transaction initialized');
        tracer.addEvent('[DECISION] Savepoint created');
        tracer.addEvent('[RISK FACTOR] DELETE operation detected');
        tracer.addEvent('[ERROR] DML operation failed');
        tracer.addEvent('[WARNING] Large batch size exceeded');
        tracer.addEvent('Generic info event'); // No prefix = INFO

        tracer.endSpan(span, UoWEnums.SpanPhaseResult.SUCCESS, 'Root completed');
        tracer.commitTrace();
        UoWTracer.TraceSummary summary = tracer.getSummary();

        // Act
        UoWCompactTimeline.CompactTrace compact = UoWCompactTimeline.fromTraceSummary(summary);

        // Assert
        Assert.isNotNull(compact, 'Should return compact trace');
        Assert.isFalse(compact.sp.isEmpty(), 'Should have spans');

        // Find the span that has events
        UoWCompactTimeline.CompactSpan spanWithEvents = null;
        for (UoWCompactTimeline.CompactSpan cs : compact.sp) {
            if (cs.ev != null && !cs.ev.isEmpty()) {
                spanWithEvents = cs;
                break;
            }
        }

        Assert.isNotNull(spanWithEvents, 'Should find span with events');
        Assert.areEqual(6, spanWithEvents.ev.size(), 'Should have 6 events');

        // Verify event type extraction
        Assert.areEqual('S', spanWithEvents.ev[0].ty, 'STATE prefix should map to S');
        Assert.areEqual('D', spanWithEvents.ev[1].ty, 'DECISION prefix should map to D');
        Assert.areEqual('R', spanWithEvents.ev[2].ty, 'RISK FACTOR prefix should map to R');
        Assert.areEqual('E', spanWithEvents.ev[3].ty, 'ERROR prefix should map to E');
        Assert.areEqual('W', spanWithEvents.ev[4].ty, 'WARNING prefix should map to W');
        Assert.areEqual('I', spanWithEvents.ev[5].ty, 'No prefix should map to I (INFO)');
    }

    @isTest
    static void test_compactTimeline_cleanEventName_removesPrefixes_viaTracer() {
        // Arrange - Create a tracer with prefixed event names
        UoWTracer tracer = new UoWTracer('CORR-CLEAN', 'TXN-CLEAN');
        UoWTracer.Span span = tracer.startSpan(UoWEnums.SpanPhase.TRANSACT, 'Root');

        tracer.addEvent('[STATE] STARTED: Transaction initialized');
        tracer.addEvent('[DECISION] Savepoint created');
        tracer.addEvent('[RISK FACTOR] DELETE operation');
        tracer.addEvent('[ERROR] DML failed');
        tracer.addEvent('[WARNING] Batch size');
        tracer.addEvent('[RISK] Low risk');
        tracer.addEvent('[WARN] Deprecated API');

        tracer.endSpan(span, UoWEnums.SpanPhaseResult.SUCCESS, 'Done');
        tracer.commitTrace();
        UoWTracer.TraceSummary summary = tracer.getSummary();

        // Act
        UoWCompactTimeline.CompactTrace compact = UoWCompactTimeline.fromTraceSummary(summary);

        // Assert
        UoWCompactTimeline.CompactSpan spanWithEvents = null;
        for (UoWCompactTimeline.CompactSpan cs : compact.sp) {
            if (cs.ev != null && !cs.ev.isEmpty()) {
                spanWithEvents = cs;
                break;
            }
        }

        Assert.isNotNull(spanWithEvents, 'Should find span with events');

        // Verify prefix removal (cleanEventName)
        Assert.areEqual('STARTED: Transaction initialized', spanWithEvents.ev[0].n, 'Should remove [STATE] prefix');
        Assert.areEqual('Savepoint created', spanWithEvents.ev[1].n, 'Should remove [DECISION] prefix');
        Assert.areEqual('DELETE operation', spanWithEvents.ev[2].n, 'Should remove [RISK FACTOR] prefix');
        Assert.areEqual('DML failed', spanWithEvents.ev[3].n, 'Should remove [ERROR] prefix');
        Assert.areEqual('Batch size', spanWithEvents.ev[4].n, 'Should remove [WARNING] prefix');
        Assert.areEqual('Low risk', spanWithEvents.ev[5].n, 'Should remove [RISK] prefix');
        Assert.areEqual('Deprecated API', spanWithEvents.ev[6].n, 'Should remove [WARN] prefix');
    }

    // ============================================================================
    // UOWORIGINSOURCESERVICE TESTS
    // ============================================================================

    @isTest
    static void test_originSource_captureOriginMetadata_nullClassName_returnsNull() {
        // Act
        UoWOriginSourceService.CaptureResult result =
            UoWOriginSourceService.captureOriginMetadata(null, 'SomeClass.method:10', 'Apex');

        // Assert
        Assert.isNull(result, 'Should return null for null class name');
    }

    @isTest
    static void test_originSource_captureOriginMetadata_nullLocation_returnsNull() {
        // Act
        UoWOriginSourceService.CaptureResult result =
            UoWOriginSourceService.captureOriginMetadata('SomeClass', null, 'Apex');

        // Assert
        Assert.isNull(result, 'Should return null for null location');
    }

    @isTest
    static void test_originSource_captureOriginMetadata_blankClassName_returnsNull() {
        // Act
        UoWOriginSourceService.CaptureResult result =
            UoWOriginSourceService.captureOriginMetadata('', 'SomeClass.method:10', 'Apex');

        // Assert
        Assert.isNull(result, 'Should return null for blank class name');
    }

    @isTest
    static void test_originSource_captureOriginMetadata_blankLocation_returnsNull() {
        // Act
        UoWOriginSourceService.CaptureResult result =
            UoWOriginSourceService.captureOriginMetadata('SomeClass', '', 'Apex');

        // Assert
        Assert.isNull(result, 'Should return null for blank location');
    }

    @isTest
    static void test_originSource_captureOriginMetadata_anonymousApex_returnsNull() {
        // Act
        UoWOriginSourceService.CaptureResult result =
            UoWOriginSourceService.captureOriginMetadata('AnonymousBlock', 'AnonymousBlock:10', 'Anonymous Apex');

        // Assert
        Assert.isNull(result, 'Should return null for anonymous apex');
    }

    @isTest
    static void test_originSource_captureOriginMetadata_flowType_returnsMinimalResult() {
        // Act
        UoWOriginSourceService.CaptureResult result =
            UoWOriginSourceService.captureOriginMetadata('MyTestFlow', 'MyTestFlow:1', 'Flow');

        // Assert
        Assert.isNotNull(result, 'Should return result for Flow');
        Assert.areEqual('Flow', result.metadataType, 'Metadata type should be Flow');
        Assert.areEqual('MyTestFlow', result.className, 'Class name should be flow name');
        Assert.isNull(result.sourceSnippet, 'Source snippet should be null for Flow');
    }

    @isTest
    static void test_originSource_captureOriginMetadata_apexClass_queriesMetadata() {
        // Arrange - Use a class that definitely exists in our package
        String className = 'UoWOriginSourceService';
        String location = 'UoWOriginSourceService.captureOriginMetadata:36';

        // Act
        UoWOriginSourceService.CaptureResult result =
            UoWOriginSourceService.captureOriginMetadata(className, location, 'Apex');

        // Assert
        Assert.isNotNull(result, 'Should return result for existing class');
        Assert.areEqual('ApexClass', result.metadataType, 'Metadata type should be ApexClass');
        Assert.areEqual('UoWOriginSourceService', result.className, 'Class name should match');
        Assert.isNotNull(result.apiVersion, 'API version should be populated');
        Assert.isNotNull(result.lastModifiedDate, 'Last modified date should be populated');
        Assert.isNotNull(result.sourceSnippet, 'Source snippet should be populated');
    }

    @isTest
    static void test_originSource_captureOriginMetadata_nonExistentClass_returnsNull() {
        // Arrange
        String className = 'NonExistentClass12345XYZ';
        String location = 'NonExistentClass12345XYZ.method:10';

        // Act
        UoWOriginSourceService.CaptureResult result =
            UoWOriginSourceService.captureOriginMetadata(className, location, 'Apex');

        // Assert
        Assert.isNull(result, 'Should return null for non-existent class');
    }

    @isTest
    static void test_originSource_captureOriginMetadata_cachingWorks() {
        // Arrange
        String className = 'UoWOriginSourceService';
        String location = 'UoWOriginSourceService.captureOriginMetadata:36';

        // Clear cache first
        UoWOriginSourceService.clearCache();

        // Act - Call twice, second should use cache
        UoWOriginSourceService.CaptureResult result1 =
            UoWOriginSourceService.captureOriginMetadata(className, location, 'Apex');
        UoWOriginSourceService.CaptureResult result2 =
            UoWOriginSourceService.captureOriginMetadata(className, location, 'Apex');

        // Assert - Both should return valid results
        Assert.isNotNull(result1, 'First call should return result');
        Assert.isNotNull(result2, 'Second call should return result (from cache)');
        Assert.areEqual(result1.className, result2.className, 'Class names should match');
    }

    @isTest
    static void test_originSource_clearCache_clearsAllCaches() {
        // Arrange - Populate cache
        String className = 'UoWOriginSourceService';
        String location = 'UoWOriginSourceService.captureOriginMetadata:36';
        UoWOriginSourceService.captureOriginMetadata(className, location, 'Apex');

        // Act
        UoWOriginSourceService.clearCache();

        // Assert - No exception thrown, cache cleared
        // Next call should re-query (but we can't easily verify query count without SeeAllData)
        UoWOriginSourceService.CaptureResult result =
            UoWOriginSourceService.captureOriginMetadata(className, location, 'Apex');
        Assert.isNotNull(result, 'Should work after cache clear');
    }

    @isTest
    static void test_originSource_captureOriginMetadata_invalidLocationFormat_returnsNull() {
        // Arrange - Location without line number
        String className = 'SomeClass';
        String location = 'SomeClassWithoutLineNumber';

        // Act
        UoWOriginSourceService.CaptureResult result =
            UoWOriginSourceService.captureOriginMetadata(className, location, 'Apex');

        // Assert
        Assert.isNull(result, 'Should return null for invalid location format');
    }

    @isTest
    static void test_originSource_captureOriginMetadata_triggerType_queriesTriggers() {
        // Arrange - Use trigger-style parameters
        String triggerName = 'NonExistentTrigger12345XYZ';
        String location = 'Trigger.NonExistentTrigger12345XYZ:10';

        // Act - The trigger path is activated by location starting with 'Trigger.'
        UoWOriginSourceService.CaptureResult result =
            UoWOriginSourceService.captureOriginMetadata(triggerName, location, 'Trigger');

        // Assert - Trigger doesn't exist so returns null, but exercises trigger query path
        Assert.isNull(result, 'Should return null for non-existent trigger');
    }

    @isTest
    static void test_originSource_captureOriginMetadata_triggerLocationPrefix() {
        // Arrange - Use 'Trigger.' prefix in location to exercise trigger path
        String triggerName = 'TestTrigger';
        String location = 'Trigger.TestTrigger:5';

        // Act
        UoWOriginSourceService.CaptureResult result =
            UoWOriginSourceService.captureOriginMetadata(triggerName, location, 'Trigger');

        // Assert - Trigger doesn't exist but exercises trigger code path
        Assert.isNull(result, 'Should return null for non-existent trigger');
    }

    @isTest
    static void test_originSource_captureOriginMetadata_existingTrigger() {
        // Arrange - Use UoWScenarioTrigger which is part of the uow-audit package
        String triggerName = 'UoWScenarioTrigger';
        String location = 'Trigger.' + triggerName + ':1';

        // Act
        UoWOriginSourceService.CaptureResult result =
            UoWOriginSourceService.captureOriginMetadata(triggerName, location, 'Trigger');

        // Assert - Should find the trigger and build capture result
        Assert.isNotNull(result, 'Should return result for existing trigger');
        Assert.areEqual('ApexTrigger', result.metadataType, 'Metadata type should be ApexTrigger');
        Assert.areEqual(triggerName, result.className, 'Should use trigger name');
        Assert.isNotNull(result.apiVersion, 'API version should be populated');
        Assert.isNotNull(result.lastModifiedDate, 'Last modified date should be populated');
        Assert.isNotNull(result.sourceSnippet, 'Source snippet should be populated');
        Assert.isNotNull(result.snippetStartLine, 'Snippet start line should be populated');
    }

    @isTest
    static void test_originSource_captureResult_allFieldsAccessible() {
        // Arrange
        UoWOriginSourceService.CaptureResult result = new UoWOriginSourceService.CaptureResult();

        // Act - Set all fields
        result.metadataType = 'ApexClass';
        result.apiVersion = '65.0';
        result.className = 'TestClass';
        result.methodName = 'testMethod';
        result.lineNumber = 42;
        result.lastModifiedDate = DateTime.now();
        result.sourceSnippet = 'public void testMethod() {}';
        result.snippetStartLine = 40;

        // Assert - All fields should be accessible
        Assert.areEqual('ApexClass', result.metadataType, 'metadataType should be accessible');
        Assert.areEqual('65.0', result.apiVersion, 'apiVersion should be accessible');
        Assert.areEqual('TestClass', result.className, 'className should be accessible');
        Assert.areEqual('testMethod', result.methodName, 'methodName should be accessible');
        Assert.areEqual(42, result.lineNumber, 'lineNumber should be accessible');
        Assert.isNotNull(result.lastModifiedDate, 'lastModifiedDate should be accessible');
        Assert.areEqual('public void testMethod() {}', result.sourceSnippet, 'sourceSnippet should be accessible');
        Assert.areEqual(40, result.snippetStartLine, 'snippetStartLine should be accessible');
    }
}
