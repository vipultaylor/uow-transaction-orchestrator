//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * OpenTelemetry-compatible tracer for UnitOfWork transactions.
 * Provides distributed tracing capabilities following OpenTelemetry standards.
 *
 * OpenTelemetry Specification:
 * - Tracer API: https://opentelemetry.io/docs/specs/otel/trace/api/
 * - Span: https://opentelemetry.io/docs/specs/otel/trace/api/#span
 * - Span Events: https://opentelemetry.io/docs/specs/otel/trace/api/#add-events
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Services
 *
 * @example Phase span tracking:
 * UoWTracer tracer = new UoWTracer(correlationId, transactionId);
 * UoWTracer.Span span = tracer.startSpan(UoWEnums.SpanPhase.DML_EXECUTION, 'Insert Accounts');
 * span.setAttribute('db.operation', 'INSERT')
 *     .setAttribute('db.sobject', 'Account')
 *     .setAttribute('record.count', 50);
 * // ... perform operation ...
 * tracer.endSpan(span, UoWEnums.SpanPhaseResult.SUCCESS, 'Inserted 50 Accounts');
 *
 * @example Work item span tracking:
 * UoWTracer.Span span = tracer.startSpan(workItem, null);
 * // ... execute work item ...
 * tracer.endSpan(span, workItem, null);
 *
 * @example Adding events to spans:
 * UoWTracer.Span span = tracer.startSpan(UoWEnums.SpanPhase.DML_EXECUTION, 'Processing');
 * tracer.addEvent('validation_completed', new Map<String, Object>{'record_count' => 10});
 * tracer.addEvent('security_check_passed', new Map<String, Object>{'mode' => 'ENFORCED'});
 * tracer.endSpan(span, UoWEnums.SpanPhaseResult.SUCCESS, 'Processing complete');
 */
@SuppressWarnings('PMD.CognitiveComplexity')
public inherited sharing class UoWTracer {

    // ============================================================================
    // PRIVATE FIELDS
    // ============================================================================

    private TraceSummary summary;
    private Span currentSpan;
    // OTel traceId - UUID format for distributed tracing (correlationId from context)
    private String traceId;
    // UoW transactionId - internal identifier (TXN-timestamp-random)
    private String transactionId;
    private Boolean committed;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Constructor with correlationId (as OTel traceId) and transactionId.
     *
     * @param correlationId UUID for distributed tracing - becomes OTel traceId
     * @param transactionId Internal transaction ID (TXN-timestamp-random)
     */
    public UoWTracer(String correlationId, String transactionId) {
        this.traceId = correlationId;
        this.transactionId = transactionId;
        this.summary = new TraceSummary(this.traceId, this.transactionId);
        this.currentSpan = null;
        this.committed = false;
    }

    // ============================================================================
    // PUBLIC API - CONFIGURATION
    // ============================================================================

    /**
     * Reset all spans and start fresh.
     */
    public void reset() {
        this.summary = new TraceSummary(this.traceId, this.transactionId);
        this.currentSpan = null;
    }

    /**
     * Get the trace ID for this tracer.
     *
     * @return Trace ID
     */
    public String getTraceId() {
        return this.traceId;
    }

    // ============================================================================
    // PUBLIC API - TRACE LIFECYCLE
    // ============================================================================

    /**
     * Commit buffered spans (make them "real").
     * Called AFTER policy decision if tracing should be enabled.
     * Optimistic tracing pattern: Buffer early spans, commit if needed.
     */
    public void commitTrace() {
        this.committed = true;
    }

    /**
     * Discard buffered spans (tracing not needed).
     * Called AFTER policy decision if tracing should NOT be enabled.
     * Clears all buffered spans to free memory.
     */
    public void discardTrace() {
        this.summary = new TraceSummary(this.traceId, this.transactionId);
        this.currentSpan = null;
        this.committed = false;
    }

    /**
     * Check if tracer has been committed.
     *
     * @return True if commitTrace() was called
     */
    public Boolean isCommitted() {
        return this.committed;
    }

    // ============================================================================
    // PUBLIC API - SPAN LIFECYCLE (OTel-compatible)
    // ============================================================================

    /**
     * Start a new phase span.
     *
     * @param phase UoW phase (used for categorization and default naming)
     * @param name Human-readable span name (optional - auto-generated from phase if null)
     * @return Started span instance
     */
    public Span startSpan(UoWEnums.SpanPhase phase, String name) {
        if (phase == null) {
            phase = UoWEnums.SpanPhase.TRANSACT;
        }

        // Create phase span and register it
        Span span = new Span(this.traceId, phase, UoWEnums.SpanEventType.SPAN, name);
        return registerSpan(span);
    }

    /**
     * Start a new work item span.
     *
     * @param workItem The work item being executed
     * @param name Human-readable span name (optional - auto-generated from work item if null)
     * @return Started span instance
     */
    public Span startSpan(UoWWorkItem workItem, String name) {
        if (workItem == null) {
            return null;
        }

        // Auto-generate name from work item if not provided
        String spanName = String.isNotBlank(name) ? name : buildWorkItemSpanName(workItem);

        // Create work item span and register it
        Span span = new Span(this.traceId, workItem.workType, spanName);
        span = registerSpan(span);

        // Store work item reference in span attributes
        span.setAttribute('work.id', workItem.workId);
        span.setAttribute('work.type', workItem.workType.name());
        span.setAttribute('work.planned', workItem.statistics.planned);

        return span;
    }

    /**
     * Register a span in the trace hierarchy.
     * Sets up parent-child relationships and tracks the span.
     * This is the single source of truth for span registration logic.
     *
     * @param span The span to register
     * @return The registered span (same instance, for fluent API)
     */
    private Span registerSpan(Span span) {
        if (span == null) {
            return null;
        }

        // Set up parent-child relationship
        if (currentSpan == null) {
            span.level = 1;
        } else {
            // Set parent relationship - spans are explicitly ended via endSpan()
            span.parentSpan = currentSpan;
            span.parentSpanId = currentSpan.spanId;
            span.level = currentSpan.level + 1;
            currentSpan.childSpans.add(span);
        }

        // Add to root spans if top-level
        if (span.level == 1) {
            this.summary.rootSpans.add(span);
        }

        // Track span in summary
        this.summary.spans.add(span);

        // Set as current span
        currentSpan = span;

        return span;
    }

    /**
     * End a phase span with result.
     * Sets the phase result before completing the span.
     *
     * @param span Span to end
     * @param phaseResult The result of the phase execution
     * @param name Optional final span name (null to keep original)
     */
    public void endSpan(Span span, UoWEnums.SpanPhaseResult phaseResult, String name) {
        if (span == null || span.isCompleted) {
            return;
        }

        // Set the phase result before completing
        span.setPhaseResult(phaseResult);

        // Set OTel status code based on phase result
        if (phaseResult == UoWEnums.SpanPhaseResult.FAILED) {
            span.markAsError('Phase failed');
        } else if (phaseResult == UoWEnums.SpanPhaseResult.SUCCESS) {
            span.markAsOk();
        }
        // NOT_APPLICABLE remains UNSET

        // Complete and update pointer
        completeSpan(span, name);
    }

    /**
     * End a work item span with result.
     * Captures final statistics and status from the executed work item.
     *
     * @param span Span to end
     * @param workItem The executed work item (for result data)
     * @param name Optional final span name (null to auto-generate from work item)
     */
    public void endSpan(Span span, UoWWorkItem workItem, String name) {
        if (span == null || workItem == null) {
            return;
        }

        // Capture result attributes
        span.setAttribute('work.processed', workItem.statistics.processed);
        span.setAttribute('work.successes', workItem.statistics.successes);
        span.setAttribute('work.failures', workItem.statistics.failures);
        span.setAttribute('work.status', workItem.status?.name());

        // Set OTel status code based on work item status
        UoWEnums.WorkStatus status = workItem.status;
        if (status == UoWEnums.WorkStatus.FAILED || status == UoWEnums.WorkStatus.PARTIAL_SUCCESS) {
            span.markAsError(status == UoWEnums.WorkStatus.FAILED ? 'Work item failed' : 'Partial failure');
        } else if (status == UoWEnums.WorkStatus.SUCCESS) {
            span.markAsOk();
        }
        // SKIPPED, NOT_EXECUTED, REGISTERED remain UNSET

        // Auto-generate name from work item if not provided
        String spanName = String.isNotBlank(name) ? name : buildWorkItemSpanName(workItem);

        // Complete and update pointer
        completeSpan(span, spanName);
    }

    /**
     * End all active spans.
     */
    public void endAllSpans() {
        for (Span span : this.summary.rootSpans) {
            if (!span.isCompleted) {
                span.complete(null);
            }
        }
        currentSpan = null;
    }

    /**
     * Complete a span and update the current span pointer.
     * Private helper - single source of truth for span completion logic.
     *
     * @param span Span to complete
     * @param name Optional final span name
     */
    private void completeSpan(Span span, String name) {
        if (span == null || span.isCompleted) {
            return;
        }

        // Complete the span
        span.complete(name);

        // Update current span pointer
        if (currentSpan?.spanId == span.spanId) {
            currentSpan = span.parentSpan;
        }
    }

    // Build span name for a work item
    private String buildWorkItemSpanName(UoWWorkItem workItem) {
        switch on workItem.workType {
            when DML {
                UoWDmlWorkItem dml = (UoWDmlWorkItem) workItem;
                return dml.sobjectTypeName + ' ' + formatDmlOperation(dml.operation);
            }
            when EVENT {
                UoWEventWorkItem evt = (UoWEventWorkItem) workItem;
                return evt.sobjectTypeName ?? 'Platform Event';
            }
            when EMAIL {
                return 'Email Send';
            }
            when NOTIFICATION {
                UoWNotificationWorkItem notif = (UoWNotificationWorkItem) workItem;
                return notif.customNotifTypeName ?? 'Custom Notification';
            }
            when FLOW {
                UoWFlowWorkItem flow = (UoWFlowWorkItem) workItem;
                return flow.flowApiName ?? 'Flow';
            }
            when CALLOUT {
                UoWCalloutWorkItem callout = (UoWCalloutWorkItem) workItem;
                return callout.httpMethod + ' ' + extractEndpointPath(callout.endpoint);
            }
            when else {
                return workItem.workType.name();
            }
        }
    }

    // Format DML operation for display
    private String formatDmlOperation(UoWEnums.DmlOperation operation) {
        if (operation == null) {
            return 'DML';
        }
        // Remove _OP suffix: INSERT_OP → INSERT
        String opName = operation.name();
        return opName.endsWith('_OP') ? opName.removeEnd('_OP') : opName;
    }

    // Extract path from endpoint URL
    private String extractEndpointPath(String endpoint) {
        if (String.isBlank(endpoint)) {
            return '';
        }

        // Handle named credentials: callout:MyService/api/orders → /api/orders
        if (endpoint.startsWith('callout:')) {
            Integer slashIndex = endpoint.indexOf('/', 8);
            return slashIndex > 0 ? endpoint.substring(slashIndex) : endpoint;
        }

        // Handle full URLs: extract path only
        try {
            Url parsedUrl = new Url(endpoint);
            String path = parsedUrl.getPath();
            return String.isNotBlank(path) ? path : endpoint;
        } catch (Exception e) {
            // If parsing fails, truncate long endpoints
            return endpoint.length() > 40 ? endpoint.substring(0, 40) + '...' : endpoint;
        }
    }

    // ============================================================================
    // PUBLIC API - SPAN EVENTS (OTel-compatible)
    // ============================================================================

    /**
     * Add an event to the current span.
     *
     * @param name Event name
     */
    public void addEvent(String name) {
        addEvent(currentSpan, name, null);
    }

    /**
     * Add an event with attributes to the current span.
     *
     * @param name Event name
     * @param attributes Event attributes
     */
    public void addEvent(String name, Map<String, Object> attributes) {
        addEvent(currentSpan, name, attributes);
    }

    /**
     * Add an event to a specific span.
     *
     * @param parentSpan Parent span for this event
     * @param name Event name
     * @param attributes Event attributes
     */
    public void addEvent(Span parentSpan, String name, Map<String, Object> attributes) {
        if (parentSpan == null) {
            return;
        }

        Integer sequence = this.summary.allEvents.size() + 1;
        SpanEvent event = new SpanEvent(parentSpan, name, attributes, sequence);
        this.summary.allEvents.add(event);

        // Also add to parent span's events list
        parentSpan.events.add(event);
    }

    // ============================================================================
    // PUBLIC API - RESULTS
    // ============================================================================

    /**
     * Get trace summary with all spans.
     *
     * @return TraceSummary instance
     */
    public TraceSummary getSummary() {
        // Only return summary if committed (optimistic tracing pattern)
        if (!this.committed) {
            return null;
        }

        // End any active spans
        this.endAllSpans();

        // Build summary statistics
        this.buildSummary();

        return this.summary;
    }

    // ============================================================================
    // PRIVATE METHODS
    // ============================================================================

    // Build summary statistics from all spans
    private void buildSummary() {
        // Flatten all spans into chronological order
        List<Span> allSpans = new List<Span>();
        for (Span span : this.summary.rootSpans) {
            flattenSpans(span, allSpans);
        }

        // Sort by startTime
        allSpans.sort();
        this.summary.spans = allSpans;

        // Calculate metrics
        Integer spanCount = 0;
        Long totalDuration = 0;

        for (Span span : allSpans) {
            // Count spans (exclude events)
            if (span.eventType == UoWEnums.SpanEventType.SPAN) {
                spanCount++;
            }

            // Calculate total duration from root spans only
            if (span.level == 1 && span.durationMs != null) {
                totalDuration += span.durationMs;
            }
        }

        this.summary.totalSpans = spanCount;
        this.summary.totalDurationMs = totalDuration;
    }

    // Recursively flatten spans into a single list
    private void flattenSpans(Span span, List<Span> result) {
        if (span == null) { return; }

        result.add(span);

        if (span.childSpans != null && !span.childSpans.isEmpty()) {
            for (Span child : span.childSpans) {
                flattenSpans(child, result);
            }
        }
    }

    // ============================================================================
    // INNER CLASSES - TRACE SUMMARY
    // ============================================================================

    /**
     * Summary of all spans in a trace.
     * Contains trace-level statistics and complete span collection.
     */
    public class TraceSummary {

        // ============================================================================
        // PUBLIC PROPERTIES
        // ============================================================================

        // OTel trace ID (UUID) - for distributed tracing correlation
        public String traceId { get; private set; }
        // UoW transaction ID (TXN-xxx) - internal identifier
        public String transactionId { get; private set; }
        public List<Span> rootSpans { get; private set; }      // Top-level spans (level=1)
        public List<Span> spans { get; private set; }          // All spans (flattened, chronological)
        public List<SpanEvent> allEvents { get; private set; } // All events across all spans
        public Integer totalSpans { get; private set; }
        public Long totalDurationMs { get; private set; }

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public TraceSummary(String traceId, String transactionId) {
            this.traceId = traceId;
            this.transactionId = transactionId;
            this.rootSpans = new List<Span>();
            this.spans = new List<Span>();
            this.allEvents = new List<SpanEvent>();
            this.totalSpans = 0;
            this.totalDurationMs = 0;
        }

        // ============================================================================
        // PUBLIC API - JSON EXPORT
        // ============================================================================

        /**
         * Get JSON for spans only (excludes events).
         *
         * @return JSON string containing all spans
         */
        public String getSpansJson() {
            List<Span> spanList = new List<Span>();
            if (spans != null) {
                for (Span span : spans) {
                    if (span.eventType == UoWEnums.SpanEventType.SPAN) {
                        spanList.add(span);
                    }
                }
            }
            return JSON.serialize(spanList);
        }

        /**
         * Get JSON for events only.
         *
         * @return JSON string containing all events
         */
        public String getEventsJson() {
            List<UoWTracer.SpanEvent> eventList = new List<UoWTracer.SpanEvent>();
            if (allEvents != null) {
                allEvents.sort();
                eventList = allEvents;
            }

            //serialize
            return JSON.serialize(eventList);
        }
    }

    // ============================================================================
    // INNER CLASSES - SPAN (OTel-compatible)
    // ============================================================================

    /**
     * Represents a single span (operation) in a trace.
     * Maps directly to OpenTelemetry Span specification.
     *
     * OTel Span Fields:
     * - spanId: Unique identifier for this span
     * - traceId: Trace this span belongs to
     * - parentSpanId: Parent span ID (null for root spans)
     * - name: Human-readable span name
     * - kind: Span kind (INTERNAL, SERVER, CLIENT, PRODUCER, CONSUMER)
     * - startTimeUnixNano: Start timestamp in nanoseconds
     * - endTimeUnixNano: End timestamp in nanoseconds
     * - attributes: Key-value pairs describing this span
     * - events: List of events that occurred during this span
     * - status: Span status (OK, ERROR, UNSET)
     */
    @SuppressWarnings('PMD.ExcessivePublicCount')
    public class Span implements Comparable {

        // ============================================================================
        // PUBLIC PROPERTIES - OTEL IDENTITY
        // ============================================================================

        public String spanId { get; private set; }
        public String traceId { get; private set; }
        public String parentSpanId { get; private set; }

        // ============================================================================
        // PUBLIC PROPERTIES - OTEL METADATA
        // ============================================================================

        public String name { get; private set; }
        public String kind { get; private set; }  // INTERNAL, SERVER, CLIENT, PRODUCER, CONSUMER
        public Map<String, Object> attributes { get; private set; }

        // ============================================================================
        // PUBLIC PROPERTIES - OTEL EVENTS
        // ============================================================================

        public List<SpanEvent> events { get; private set; }

        // ============================================================================
        // PUBLIC PROPERTIES - OTEL STATUS
        // ============================================================================

        public String statusCode { get; private set; }  // OK, ERROR, UNSET
        public String statusMessage { get; private set; }

        // ============================================================================
        // PUBLIC PROPERTIES - TIMING
        // ============================================================================

        public Long startTimeMs { get; private set; }
        public Long endTimeMs { get; private set; }
        public DateTime startTimestamp { get; private set; }
        public DateTime endTimestamp { get; private set; }
        public Long durationMs { get; private set; }

        // ============================================================================
        // PUBLIC PROPERTIES - STATE
        // ============================================================================

        public Boolean isCompleted { get; set; }

        // ============================================================================
        // PUBLIC PROPERTIES - UOW-SPECIFIC (stored as attributes for OTel export)
        // ============================================================================

        // Transient for audit JSON serialization - restored from attributes during hydration
        public transient UoWEnums.SpanPhase phase { get; private set; }
        public transient UoWEnums.PhaseCategory category { get; private set; }
        public transient UoWEnums.SpanEventType eventType { get; private set; }
        public transient UoWEnums.SpanSubType subType { get; private set; }

        // ============================================================================
        // PUBLIC PROPERTIES - HIERARCHY
        // ============================================================================

        public Integer level { get; set; }
         // Parent reference is transient to avoid circular references during serialization
        public transient Span parentSpan { get; set; }
        public List<Span> childSpans { get; set; }
        public Boolean hasChildren { get; set; }

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        /**
         * Constructor for phase spans.
         *
         * @param traceId Trace ID this span belongs to
         * @param phase UoW phase (for categorization)
         * @param eventType Event type (SPAN vs EVENT)
         * @param name Span name (optional - auto-generated if null)
         */
        @SuppressWarnings('PMD.ExcessiveParameterList')
        public Span(String traceId, UoWEnums.SpanPhase phase, UoWEnums.SpanEventType eventType, String name) {
            initializeCommon(traceId, eventType, name);

            // Phase-specific fields
            this.phase = phase;
            this.category = getCategoryForPhase(phase);
            this.subType = UoWEnums.SpanSubType.PHASE;

            // Store in attributes
            this.attributes.put('uow.phase', phase.name());
            this.attributes.put('uow.category', category.name());
            this.attributes.put('uow.span_subtype', subType.name());

            // Auto-generate name from phase if not provided
            if (String.isBlank(this.name) && this.eventType == UoWEnums.SpanEventType.SPAN) {
                String formattedPhaseName = phase.name().replace('_', ' ').toLowerCase().capitalize();
                this.name = 'Starting ' + formattedPhaseName;
            }
        }

        /**
         * Constructor for work item spans.
         * Uses WorkType directly instead of mapping through SpanPhase.
         *
         * @param traceId Trace ID this span belongs to
         * @param workType Work type (DML, EVENT, EMAIL, etc.)
         * @param name Span name
         */
        public Span(String traceId, UoWEnums.WorkType workType, String name) {
            initializeCommon(traceId, UoWEnums.SpanEventType.SPAN, name);

            // Work item specific fields - no SpanPhase needed
            this.phase = null;  // Work items don't need a SpanPhase
            this.category = getCategoryForWorkType(workType);
            this.subType = UoWEnums.SpanSubType.WORK_ITEM;

            // Store in attributes - use work.type instead of uow.phase
            this.attributes.put('uow.work_type', workType.name());
            this.attributes.put('uow.category', category.name());
            this.attributes.put('uow.span_subtype', subType.name());
        }

        // Common initialization for all span types
        private void initializeCommon(String traceId, UoWEnums.SpanEventType eventType, String name) {
            // OTel-standard fields
            this.spanId = UoWUtils.generateId(eventType.name());
            this.traceId = traceId;
            this.kind = 'INTERNAL';
            this.attributes = new Map<String, Object>();
            this.events = new List<SpanEvent>();
            this.statusCode = 'UNSET';

            // Common UoW fields
            this.eventType = eventType;
            this.name = name;

            // Initialize timing
            this.startTimeMs = System.currentTimeMillis();
            this.startTimestamp = System.now();
            this.isCompleted = false;
            this.childSpans = new List<Span>();

            // Store event type in attributes
            this.attributes.put('uow.event_type', eventType.name());
        }

        // ============================================================================
        // PUBLIC API - OTEL-COMPATIBLE METHODS
        // ============================================================================

        /**
         * Set a single attribute (OTel-compatible).
         *
         * @param key Attribute key (use dot notation: 'db.operation', 'http.status_code')
         * @param value Attribute value (String, Number, Boolean)
         * @return This span (fluent API)
         */
        public Span setAttribute(String key, Object value) {
            this.attributes.put(key, value);
            return this;
        }

        /**
         * Set span status (OTel-compatible).
         *
         * @param code Status code: OK, ERROR, UNSET
         * @param message Optional status message
         * @return This span (fluent API)
         */
        public Span setStatus(String code, String message) {
            this.statusCode = code;
            this.statusMessage = message;
            return this;
        }

        /**
         * Mark span as OK (successful completion).
         *
         * @return This span (fluent API)
         */
        public Span markAsOk() {
            return setStatus('OK', null);
        }

        /**
         * Mark span as ERROR.
         *
         * @param message Error message
         * @return This span (fluent API)
         */
        public Span markAsError(String message) {
            return setStatus('ERROR', message);
        }

        /**
         * Set the phase result for PHASE subtype spans.
         * Use when ending a phase span to indicate outcome.
         *
         * @param phaseResult The result of the phase execution
         * @return This span (fluent API)
         */
        public Span setPhaseResult(UoWEnums.SpanPhaseResult phaseResult) {
            if (phaseResult != null) {
                this.setAttribute('phase.result', phaseResult.name());
            }
            return this;
        }

        // ============================================================================
        // PUBLIC API - OTEL TIMING
        // ============================================================================

        /**
         * Get start time in Unix nanoseconds (OTel format).
         *
         * @return Start time in nanoseconds
         */
        public Long getStartTimeUnixNano() {
            return this.startTimeMs != null ? this.startTimeMs * 1000000 : null;
        }

        /**
         * Get end time in Unix nanoseconds (OTel format).
         *
         * @return End time in nanoseconds
         */
        public Long getEndTimeUnixNano() {
            return this.endTimeMs != null ? this.endTimeMs * 1000000 : null;
        }

        // ============================================================================
        // PUBLIC API - SPAN LIFECYCLE
        // ============================================================================

        /**
         * Complete this span.
         *
         * @param endName Optional final span name
         */
        public void complete(String endName) {
            if (isCompleted) {
                return;
            }

            // Complete child spans first
            for (Span childSpan : childSpans) {
                childSpan.complete(null);
            }

            this.endTimeMs = System.currentTimeMillis();
            this.endTimestamp = System.now();

            // Calculate duration
            this.durationMs = this.endTimeMs - this.startTimeMs;

            // Update span name if provided (endName replaces initial name with result summary)
            if (String.isNotBlank(endName)) {
                this.name = endName;
            }

            // Add duration to attributes
            this.attributes.put('duration_ms', this.durationMs);

            // Note: statusCode is set by endSpan() based on SpanPhaseResult or WorkStatus
            // If still UNSET here, it means the span wasn't properly ended through the API

            this.hasChildren = !this.childSpans.isEmpty();
            this.isCompleted = true;
        }

        // ============================================================================
        // PUBLIC API - COMPARABLE INTERFACE
        // ============================================================================

        /**
         * Comparable implementation - sort by start time.
         *
         * @param other The other span to compare to
         * @return Comparison result
         */
        public Integer compareTo(Object other) {
            Span otherSpan = (Span) other;
            return this.startTimeMs > otherSpan.startTimeMs ? 1 :
                   (this.startTimeMs < otherSpan.startTimeMs ? -1 : 0);
        }

        // ============================================================================
        // PRIVATE METHODS
        // ============================================================================

        // Get category for a phase span
        private UoWEnums.PhaseCategory getCategoryForPhase(UoWEnums.SpanPhase phase) {
            return UoWEnums.SPAN_TO_CATEGORY.containsKey(phase) ?
                   UoWEnums.SPAN_TO_CATEGORY.get(phase) :
                   UoWEnums.PhaseCategory.TRANSACT;
        }

        // Get category for a work item span - direct mapping from WorkType
        private UoWEnums.PhaseCategory getCategoryForWorkType(UoWEnums.WorkType workType) {
            switch on workType {
                when DML { return UoWEnums.PhaseCategory.DML; }
                when EVENT { return UoWEnums.PhaseCategory.PLATFORM_EVENT; }
                when EMAIL { return UoWEnums.PhaseCategory.EMAIL; }
                when NOTIFICATION { return UoWEnums.PhaseCategory.NOTIFICATION; }
                when FLOW { return UoWEnums.PhaseCategory.FLOW; }
                when CALLOUT { return UoWEnums.PhaseCategory.CALLOUT; }
                when else { return UoWEnums.PhaseCategory.TRANSACT; }
            }
        }
    }

    // ============================================================================
    // INNER CLASSES - SPAN EVENT (OTel-compatible)
    // ============================================================================

    /**
     * Represents an instant event within a span.
     * Maps to OpenTelemetry Span Event specification.
     *
     * OTel Event: https://opentelemetry.io/docs/specs/otel/trace/api/#add-events
     */
    public class SpanEvent implements Comparable {

        // ============================================================================
        // PUBLIC PROPERTIES - OTEL STANDARD
        // ============================================================================

        public String name { get; private set; }
        public Long timestampMs { get; private set; }
        public DateTime timestamp { get; private set; }
        public Map<String, Object> attributes { get; private set; }

        // ============================================================================
        // PUBLIC PROPERTIES - UOW CONTEXT
        // ============================================================================

        public String eventId { get; private set; }
        // Transient for audit JSON serialization - restored from attributes during hydration
        public transient UoWEnums.SpanPhase phase { get; private set; }
        public transient UoWEnums.PhaseCategory category { get; private set; }
        public String parentSpanId { get; private set; }
        public Integer level { get; private set; }
        public Integer sequence { get; private set; }

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        /**
         * Constructor.
         *
         * @param parentSpan Parent span this event belongs to
         * @param name Event name
         * @param attributes Event attributes
         * @param sequence Sequence number within trace
         */
        @SuppressWarnings('PMD.ExcessiveParameterList')
        public SpanEvent(Span parentSpan, String name, Map<String, Object> attributes, Integer sequence) {
            this.eventId = UoWUtils.generateId('EVENT');
            this.name = name;
            this.attributes = attributes ?? new Map<String, Object>();
            this.sequence = sequence;

            // Copy context from parent span
            this.phase = parentSpan.phase;
            this.category = parentSpan.category;
            this.parentSpanId = parentSpan.spanId;
            this.level = parentSpan.level + 1;

            // Store UoW context in attributes
            this.attributes.put('uow.phase', this.phase.name());
            this.attributes.put('uow.category', this.category.name());

            // Record timing
            this.timestampMs = System.currentTimeMillis();
            this.timestamp = System.now();
        }

        // ============================================================================
        // PUBLIC API - OTEL TIMING
        // ============================================================================

        /**
         * Get timestamp in Unix nanoseconds (OTel format).
         *
         * @return Timestamp in nanoseconds
         */
        public Long getTimestampUnixNano() {
            return this.timestampMs != null ? this.timestampMs * 1000000 : null;
        }

        // ============================================================================
        // PUBLIC API - COMPARABLE INTERFACE
        // ============================================================================

        /**
         * Comparable implementation - sort by timestamp.
         *
         * @param other The other event to compare to
         * @return Comparison result
         */
        public Integer compareTo(Object other) {
            SpanEvent otherEvent = (SpanEvent) other;
            return this.timestampMs > otherEvent.timestampMs ? 1 :
                   (this.timestampMs < otherEvent.timestampMs ? -1 : 0);
        }
    }
}