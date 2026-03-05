//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Result of a UnitOfWork transaction execution.
 * Contains success/failure status, statistics, and outcomes.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Core
 * @see UnitOfWork
 * @see UoWContext
 * @see UoWPlan
 */
public inherited sharing class UoWResult {

    // ============================================================================
    // PROPERTIES - IDENTITY
    // ============================================================================

    // Internal transaction identifier (TXN-timestamp-random) - for internal tracking
    public String transactionId { get; private set; }
    // Distributed correlation identifier (UUID) - for external tracing and async linking
    public String correlationId { get; private set; }

    // ============================================================================
    // PROPERTIES - TRANSACTION STATE
    // ============================================================================

    public UoWEnums.TransactionStatus transactionStatus { get; private set; }
    public UoWEnums.CommitMode commitMode { get; private set; }
    public Boolean isDryRun { get; private set; }
    public Boolean requiresApproval { get; private set; }

    // ============================================================================
    // PROPERTIES - TIMESTAMPS
    // ============================================================================

    public DateTime startedAt { get; private set; }
    public DateTime completedAt { get; private set; }
    public Long executionTimeMs { get; private set; }

    // ============================================================================
    // PROPERTIES - ASSESSMENTS
    // ============================================================================

    public UoWPolicyEvaluation.Summary policyEvalSummary { get; private set; }
    public UoWRiskTypes.RiskAssessment riskAssessment { get; private set; }

    // ============================================================================
    // PROPERTIES - STATISTICS
    // ============================================================================

    private transient UoWStatisticsTracker tracker;

    public UoWStatisticsTracker.TransactionStats statistics {
        get {
            return this.tracker?.stats;
        }
        private set;
    }

    // ============================================================================
    // PROPERTIES - GOVERNOR LIMITS
    // ============================================================================

    public GovernorLimits governorLimits { get; private set; }

    // ============================================================================
    // PROPERTIES - MASKING
    // ============================================================================

    public UoWMaskingService.MaskingResult maskingResult { get; private set; }

    // ============================================================================
    // PROPERTIES - DISTRIBUTED TRACING
    // ============================================================================

    public transient UoWTracer tracer;

    // ============================================================================
    // PRIVATE FIELDS - COLLECTIONS
    // ============================================================================

    private List<UoWExceptionService.ErrorInfo> errors;
    private List<UoWMessage> messages;
    private Map<String, String> metadata;

    // ============================================================================
    // PRIVATE FIELDS - WORK ITEM RESULTS (TRANSIENT)
    // ============================================================================

    private transient List<UoWDmlWorkItem> allDmlWork;
    private transient List<UoWEventWorkItem> allEventWork;
    private transient List<UoWEmailWorkItem> allEmailWork;
    private transient List<UoWNotificationWorkItem> allNotificationWork;
    private transient List<UoWFlowWorkItem> allFlowWork;
    private transient List<UoWCalloutWorkItem> allCalloutWork;

    // Execution sequence counter - tracks runtime execution order across all work types.
    // Incremented each time a work item completes execution.
    private transient Integer executionSequenceCounter;

    // ============================================================================
    // PRIVATE FIELDS - CONTEXT
    // ============================================================================

    private transient UoWContext executionContext;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    public UoWResult(UoWContext ctx) {
        this(ctx, null);
    }

    public UoWResult(UoWContext ctx, String correlationId) {
        UoWExceptionService.requireNonNull(ctx, 'Execution Context');

        // Identity - inherit from context
        this.executionContext = ctx;
        this.transactionId = ctx.transactionId;
        this.correlationId = correlationId ?? ctx.correlationId;

        // Transaction state
        this.transactionStatus = UoWEnums.TransactionStatus.IN_PROGRESS;
        this.isDryRun = ctx.isDryRun;
        this.requiresApproval = false;

        // Timestamps
        this.startedAt = DateTime.now();

        // Statistics
        this.tracker = new UoWStatisticsTracker();

        // Collections
        this.errors = new List<UoWExceptionService.ErrorInfo>();
        this.messages = new List<UoWMessage>();
        this.metadata = new Map<String, String>();

        // Copy messages from context
        this.messages.addAll(ctx.getMessages());

        // Work item results
        this.allDmlWork = new List<UoWDmlWorkItem>();
        this.allEventWork = new List<UoWEventWorkItem>();
        this.allEmailWork = new List<UoWEmailWorkItem>();
        this.allNotificationWork = new List<UoWNotificationWorkItem>();
        this.allFlowWork = new List<UoWFlowWorkItem>();
        this.allCalloutWork = new List<UoWCalloutWorkItem>();
        this.executionSequenceCounter = 0;

        // Governor limits
        this.governorLimits = new GovernorLimits();

        // Masking
        this.maskingResult = new UoWMaskingService.MaskingResult();

        // Distributed tracing (optimistic - commit/discard after policy evaluation)
        this.tracer = new UoWTracer(this.correlationId, this.transactionId);
    }

    // ============================================================================
    // PUBLIC API - CONTEXT
    // ============================================================================

    /**
     * Get execution context.
     *
     * @return Execution context
     */
    public UoWContext getContext() {
        return this.executionContext;
    }

    // ============================================================================
    // PUBLIC API - TRANSACTION STATE
    // ============================================================================

    /**
     * Set commit mode.
     *
     * @param mode Commit mode to set
     * @return This result for fluent chaining
     */
    public UoWResult withCommitMode(UoWEnums.CommitMode mode) {
        this.commitMode = mode;
        return this;
    }

    /**
     * Set transaction status.
     *
     * @param status Status to set
     */
    public void setTransactionStatus(UoWEnums.TransactionStatus status) {
        this.transactionStatus = status;
    }

    /**
     * Mark result as completed with status.
     * NOTE: consolidateErrors() must be called BEFORE this method.
     *
     * @param status Final transaction status
     */
    public void markComplete(UoWEnums.TransactionStatus status) {
        this.transactionStatus = status;
        finalizeResult();
    }

    /**
     * Check if result is successful.
     * For SYNC mode: SUCCESS means all work completed successfully.
     * For ASYNC mode: ENQUEUED means the job was successfully queued.
     * For empty plans: SKIPPED means no work items were registered (not an error).
     *
     * @return True if transaction succeeded, was enqueued, or was skipped (no work)
     */
    public Boolean isSuccess() {
        return this.transactionStatus == UoWEnums.TransactionStatus.SUCCESS
            || this.transactionStatus == UoWEnums.TransactionStatus.ENQUEUED
            || this.transactionStatus == UoWEnums.TransactionStatus.SKIPPED;
    }

    /**
     * Check if there was any successful work.
     *
     * @return True if at least one operation succeeded
     */
    public Boolean hasSuccessfulWork() {
        return this.tracker.hasSuccessfulWork();
    }

    // ============================================================================
    // PUBLIC API - TIMESTAMPS
    // ============================================================================

    /**
     * Set start time to current time.
     */
    public void setStartTime() {
        this.startedAt = DateTime.now();
    }

    // ============================================================================
    // PUBLIC API - ERRORS
    // ============================================================================

    /**
     * Add error from exception.
     *
     * @param ex Exception to add
     * @param source Source identifier
     */
    public void addError(Exception ex, String source) {
        addError(new UoWExceptionService.ErrorInfo(ex), source);
    }

    /**
     * Add error and create corresponding ERROR severity message.
     * IMPORTANT: This does NOT change transaction status.
     *
     * @param error Error info to add
     * @param source Source identifier
     */
    public void addError(UoWExceptionService.ErrorInfo error, String source) {
        if (error != null) {
            this.errors.add(error);
            this.addMessage(new UoWMessage(LoggingLevel.ERROR, error.errorMessage, source));
        }
    }

    /**
     * Get all errors.
     *
     * @return List of all errors
     */
    public List<UoWExceptionService.ErrorInfo> getErrors() {
        return this.errors;
    }

    /**
     * Check if has errors.
     *
     * @return True if errors exist
     */
    public Boolean hasErrors() {
        return !this.errors.isEmpty();
    }

    /**
     * Consolidate errors from all work items and sort chronologically.
     * CRITICAL: Must be called BEFORE determineFinalStatus().
     */
    public void consolidateErrors() {
        consolidateWorkItemErrors();
        this.errors.sort();
    }

    // ============================================================================
    // PUBLIC API - MESSAGES
    // ============================================================================

    /**
     * Add a structured message.
     * Applies minimum logging level filtering.
     *
     * @param message Message to add
     */
    public void addMessage(UoWMessage message) {
        System.LoggingLevel minLevel = executionContext.getFeatureSettings().getMinimumLoggingLevel();
        if (message.loggingLevel.ordinal() >= minLevel.ordinal()) {
            this.messages.add(message);
        }
    }

    /**
     * Get all messages.
     *
     * @return List of all messages
     */
    public List<UoWMessage> getMessages() {
        return this.messages;
    }

    /**
     * Get all messages of a specific logging level.
     *
     * @param level Logging level to filter by
     * @return List of messages matching the level
     */
    public List<UoWMessage> getMessagesByLevel(System.LoggingLevel level) {
        List<UoWMessage> filtered = new List<UoWMessage>();
        for (UoWMessage msg : this.messages) {
            if (msg.loggingLevel == level) {
                filtered.add(msg);
            }
        }
        return filtered;
    }

    /**
     * Check if has warnings.
     *
     * @return True if warning messages exist
     */
    public Boolean hasWarnings() {
        return !getMessagesByLevel(LoggingLevel.WARN).isEmpty();
    }

    // ============================================================================
    // PUBLIC API - MESSAGE CONVENIENCE METHODS
    // ============================================================================

    /**
     * Add debug message.
     *
     * @param message Message text
     */
    public void debug(String message) {
        debug(message, 'Result');
    }

    /**
     * Add debug message with source.
     *
     * @param message Message text
     * @param source Source identifier
     */
    public void debug(String message, String source) {
        if (String.isNotBlank(message)) {
            addMessage(new UoWMessage(LoggingLevel.DEBUG, message, source));
        }
    }

    /**
     * Add fine message.
     *
     * @param message Message text
     */
    public void fine(String message) {
        fine(message, 'Result');
    }

    /**
     * Add fine message with source.
     *
     * @param message Message text
     * @param source Source identifier
     */
    public void fine(String message, String source) {
        if (String.isNotBlank(message)) {
            addMessage(new UoWMessage(LoggingLevel.FINE, message, source));
        }
    }

    /**
     * Add finer message.
     *
     * @param message Message text
     */
    public void finer(String message) {
        finer(message, 'Result');
    }

    /**
     * Add finer message with source.
     *
     * @param message Message text
     * @param source Source identifier
     */
    public void finer(String message, String source) {
        if (String.isNotBlank(message)) {
            addMessage(new UoWMessage(LoggingLevel.FINER, message, source));
        }
    }

    /**
     * Add finest message.
     *
     * @param message Message text
     */
    public void finest(String message) {
        finest(message, 'Result');
    }

    /**
     * Add finest message with source.
     *
     * @param message Message text
     * @param source Source identifier
     */
    public void finest(String message, String source) {
        if (String.isNotBlank(message)) {
            addMessage(new UoWMessage(LoggingLevel.FINEST, message, source));
        }
    }

    /**
     * Add info message.
     *
     * @param message Message text
     */
    public void info(String message) {
        info(message, 'Result');
    }

    /**
     * Add info message with source.
     *
     * @param message Message text
     * @param source Source identifier
     */
    public void info(String message, String source) {
        if (String.isNotBlank(message)) {
            addMessage(new UoWMessage(LoggingLevel.INFO, message, source));
        }
    }

    /**
     * Add warning message.
     *
     * @param message Message text
     */
    public void warn(String message) {
        warn(message, 'Result');
    }

    /**
     * Add warning message with source.
     *
     * @param message Message text
     * @param source Source identifier
     */
    public void warn(String message, String source) {
        if (String.isNotBlank(message)) {
            addMessage(new UoWMessage(LoggingLevel.WARN, message, source));
        }
    }

    /**
     * Add error message.
     *
     * @param message Message text
     */
    public void error(String message) {
        error(message, 'Result');
    }

    /**
     * Add error message with source.
     *
     * @param message Message text
     * @param source Source identifier
     */
    public void error(String message, String source) {
        if (String.isNotBlank(message)) {
            addMessage(new UoWMessage(LoggingLevel.ERROR, message, source));
        }
    }

    // ============================================================================
    // PUBLIC API - EXECUTION SEQUENCE
    // ============================================================================

    /**
     * Get the next execution sequence number.
     * Called by work items when they complete execution.
     * Sequence numbers start at 1 and increment for each executed work item.
     *
     * @return The next sequence number
     */
    public Integer getNextExecutionSequence() {
        this.executionSequenceCounter++;
        return this.executionSequenceCounter;
    }

    // ============================================================================
    // PUBLIC API - WORK ITEM REGISTRATION
    // ============================================================================

    /**
     * Add DML work item to result.
     *
     * @param workItem Work item to add
     */
    public void addDmlWork(UoWDmlWorkItem workItem) {
        if (workItem != null) {
            this.allDmlWork.add(workItem);
            if (workItem.isExecuted) {
                this.tracker.trackStats(workItem);
            }
        }
    }

    /**
     * Add event work item to result.
     *
     * @param workItem Work item to add
     */
    public void addEventWork(UoWEventWorkItem workItem) {
        if (workItem != null) {
            this.allEventWork.add(workItem);
            if (workItem.isExecuted) {
                this.tracker.trackStats(workItem);
            }
        }
    }

    /**
     * Add email work item to result.
     *
     * @param workItem Work item to add
     */
    public void addEmailWork(UoWEmailWorkItem workItem) {
        if (workItem != null) {
            this.allEmailWork.add(workItem);
            if (workItem.isExecuted) {
                this.tracker.trackStats(workItem);
            }
        }
    }

    /**
     * Add notification work item to result.
     *
     * @param workItem Work item to add
     */
    public void addNotificationWork(UoWNotificationWorkItem workItem) {
        if (workItem != null) {
            this.allNotificationWork.add(workItem);
            if (workItem.isExecuted) {
                this.tracker.trackStats(workItem);
            }
        }
    }

    /**
     * Add flow work item to result.
     *
     * @param workItem Work item to add
     */
    public void addFlowWork(UoWFlowWorkItem workItem) {
        if (workItem != null) {
            this.allFlowWork.add(workItem);
            if (workItem.isExecuted) {
                this.tracker.trackStats(workItem);
            }
        }
    }

    /**
     * Add callout work item to result.
     *
     * @param workItem Work item to add
     */
    public void addCalloutWork(UoWCalloutWorkItem workItem) {
        if (workItem != null) {
            this.allCalloutWork.add(workItem);
            if (workItem.isExecuted) {
                this.tracker.trackStats(workItem);
            }
        }
    }

    // ============================================================================
    // PUBLIC API - WORK ITEM GETTERS
    // ============================================================================

    /**
     * Get all DML work items (executed and non-executed).
     *
     * @return List of all DML work items
     */
    public List<UoWDmlWorkItem> getAllDmlWork() {
        return this.allDmlWork;
    }

    /**
     * Get all event work items (executed and non-executed).
     *
     * @return List of all event work items
     */
    public List<UoWEventWorkItem> getAllEventWork() {
        return this.allEventWork;
    }

    /**
     * Get all email work items (executed and non-executed).
     *
     * @return List of all email work items
     */
    public List<UoWEmailWorkItem> getAllEmailWork() {
        return this.allEmailWork;
    }

    /**
     * Get all notification work items (executed and non-executed).
     *
     * @return List of all notification work items
     */
    public List<UoWNotificationWorkItem> getAllNotificationWork() {
        return this.allNotificationWork;
    }

    /**
     * Get all flow work items (executed and non-executed).
     *
     * @return List of all flow work items
     */
    public List<UoWFlowWorkItem> getAllFlowWork() {
        return this.allFlowWork;
    }

    /**
     * Get all callout work items (executed and non-executed).
     *
     * @return List of all callout work items
     */
    public List<UoWCalloutWorkItem> getAllCalloutWork() {
        return this.allCalloutWork;
    }

    /**
     * Get all work items sorted by transaction sequence.
     * Executed items have sequence reflecting actual runtime order:
     * 1. Callouts (before savepoint)
     * 2. PRE_DML phase work (Events, Emails, Notifications, Flows)
     * 3. DML operations (dependency graph order)
     * 4. POST_DML phase work
     * 5. ON_SUCCESS/ON_FAILURE phase work
     * 6. ON_FINALIZATION phase work
     *
     * Non-executed items have sequence assigned after executed items
     * in canonical work type order.
     *
     * @return List of all work items sorted by transaction sequence
     */
    public List<UoWWorkItem> getAllWorkItems() {
        List<UoWWorkItem> allWork = new List<UoWWorkItem>();
        allWork.addAll(getAllDmlWork());
        allWork.addAll(getAllEventWork());
        allWork.addAll(getAllEmailWork());
        allWork.addAll(getAllNotificationWork());
        allWork.addAll(getAllFlowWork());
        allWork.addAll(getAllCalloutWork());

        allWork.sort();
        return allWork;
    }

    // ============================================================================
    // PUBLIC API - ASSESSMENTS
    // ============================================================================

    /**
     * Set risk assessment results.
     *
     * @param assessment Risk assessment to set
     */
    public void setRiskAssessment(UoWRiskTypes.RiskAssessment assessment) {
        if (assessment != null) {
            this.riskAssessment = assessment;
        }
    }

    /**
     * Set policy evaluation summary.
     *
     * @param summary Summary to set
     */
    public void setPolicyEvaluationSummary(UoWPolicyEvaluation.Summary summary) {
        if (summary != null) {
            this.policyEvalSummary = summary;

            if (summary.errorMessages != null && !summary.errorMessages.isEmpty()) {
                for (String msg : summary.errorMessages) {
                    warn(msg, 'Policy');
                }
            }
            if (summary.denialReasons != null && !summary.denialReasons.isEmpty()) {
                for (String msg : summary.denialReasons) {
                    warn(msg, 'Policy');
                }
            }
        }
    }

    /**
     * Calculate if approval is required based on risk, policy, and agent confidence.
     *
     * @return True if approval is required
     */
    public Boolean checkIfApprovalRequired() {
        UoWContext ctx = this.executionContext;

        // Check risk assessment (using safe navigation for null safety)
        if (riskAssessment?.requiresApproval == true ||
                (riskAssessment?.riskScore ?? 0) >= ctx.getFeatureSettings().getRiskApprovalThreshold()) {
            this.requiresApproval = true;
        }

        // Check agent confidence
        if (ctx.isAgentTransaction() &&
            ctx.agentContext.confidenceScore < ctx.getFeatureSettings().getConfidenceThreshold()) {
            this.requiresApproval = true;
        }

        // Check policy evaluation (using safe navigation for null safety)
        if (policyEvalSummary?.requiresApproval == true) {
            this.requiresApproval = true;
        }

        return this.requiresApproval;
    }

    // ============================================================================
    // PUBLIC API - MASKING
    // ============================================================================

    /**
     * Set masking result.
     *
     * @param result Masking result to set
     */
    public void setMaskingResult(UoWMaskingService.MaskingResult result) {
        this.maskingResult = result;
    }

    // ============================================================================
    // PUBLIC API - METADATA
    // ============================================================================

    /**
     * Set metadata with string value.
     *
     * @param key Metadata key
     * @param value Metadata value
     */
    public void setMetadata(String key, String value) {
        metadata.put(key, value);
    }

    /**
     * Set metadata with ID value.
     *
     * @param key Metadata key
     * @param value Metadata value
     */
    public void setMetadata(String key, Id value) {
        metadata.put(key, String.valueOf(value));
    }

    /**
     * Get metadata by key.
     *
     * @param key Metadata key
     * @return Metadata value or null
     */
    public Object getMetadata(String key) {
        if (this.metadata.containsKey(key)) {
            return this.metadata.get(key);
        }
        return null;
    }

    /**
     * Get all metadata.
     *
     * @return Map of all metadata
     */
    public Map<String, Object> getMetadata() {
        return this.metadata;
    }

    // ============================================================================
    // PUBLIC API - DISTRIBUTED TRACING
    // ============================================================================

    /**
     * Get trace summary with all spans.
     *
     * @return TraceSummary instance
     */
    public UoWTracer.TraceSummary getTraceSummary() {
        return this.tracer?.getSummary();
    }

    /**
     * Start a new span.
     *
     * @param phase Span phase
     * @param name Span name
     * @return Started span
     */
    public UoWTracer.Span startSpan(UoWEnums.SpanPhase phase, String name) {
        return this.tracer?.startSpan(phase, name);
    }

    /**
     * Start a work item span.
     *
     * @param workItem Work item to create span for
     * @param name Span name (optional - auto-generated from work item if null)
     * @return Started span or null if tracer is null
     */
    public UoWTracer.Span startSpan(UoWWorkItem workItem, String name) {
        return this.tracer?.startSpan(workItem, name);
    }

    /**
     * End a phase span with result.
     *
     * @param span Span to end
     * @param phaseResult The result of the phase execution
     * @param name Optional final span name (null to keep original)
     */
    public void endSpan(UoWTracer.Span span, UoWEnums.SpanPhaseResult phaseResult, String name) {
        this.tracer?.endSpan(span, phaseResult, name);
    }

    /**
     * End a work item span with result.
     *
     * @param span Span to end
     * @param workItem Work item with execution results
     * @param name Optional final span name (null to auto-generate from work item)
     */
    public void endSpan(UoWTracer.Span span, UoWWorkItem workItem, String name) {
        this.tracer?.endSpan(span, workItem, name);
    }

    /**
     * Add a trace event to the current span.
     *
     * @param name Event name
     */
    public void addTraceEvent(String name) {
        this.tracer?.addEvent(name);
    }

    /**
     * Add a trace event with attributes.
     *
     * @param name Event name
     * @param attributes Event attributes
     */
    public void addTraceEvent(String name, Map<String, Object> attributes) {
        this.tracer?.addEvent(name, attributes);
    }

    /**
     * Commit buffered trace spans (optimistic tracing pattern).
     */
    public void commitTrace() {
        this.tracer?.commitTrace();
    }

    /**
     * Discard buffered trace spans (optimistic tracing pattern).
     */
    public void discardTrace() {
        if (this.tracer != null) {
            this.tracer.discardTrace();
            this.tracer = null;
        }
    }

    /**
     * Get spans JSON (OTel-compatible).
     *
     * @return JSON string of all spans
     */
    public String getSpansJson() {
        return this.tracer?.getSummary()?.getSpansJson();
    }

    /**
     * Get events JSON (OTel-compatible).
     *
     * @return JSON string of all events
     */
    public String getEventsJson() {
        return this.tracer?.getSummary()?.getEventsJson();
    }

    // ============================================================================
    // PRIVATE HELPER METHODS
    // ============================================================================

    // Consolidate errors from all work items into result error collection
    private void consolidateWorkItemErrors() {
        for (UoWWorkItem workItem : getAllWorkItems()) {
            for (UoWExceptionService.ErrorInfo error : workItem.errors) {
                this.addError(error, 'WorkItemExecution');
            }
        }
    }

    // Finalize result with completion time and governor limits
    private void finalizeResult() {
        this.tracer?.endAllSpans();

        this.completedAt = DateTime.now();
        this.executionTimeMs = this.completedAt.getTime() - this.startedAt.getTime();
        this.tracker.setExecutionTime(this.executionTimeMs);

        this.governorLimits.captureFinish();
    }

    // ============================================================================
    // INNER CLASSES
    // ============================================================================

    /**
     * Governor limits container for transaction-level tracking.
     * Captures start, finish, and max limits.
     */
    public class GovernorLimits {
        public UoWGovernorLimits start;
        public UoWGovernorLimits finish;
        public UoWGovernorLimits max;

        public GovernorLimits() {
            this.start = new UoWGovernorLimits();
            this.max = UoWGovernorLimits.getMaxLimits();
        }

        /**
         * Capture finish limits.
         */
        public void captureFinish() {
            this.finish = new UoWGovernorLimits();
        }

        /**
         * Get consumed limits (finish - start).
         *
         * @return UoWGovernorLimits with consumed values
         */
        public UoWGovernorLimits getConsumed() {
            return UoWGovernorLimits.getConsumed(this.start, this.finish);
        }
    }
}