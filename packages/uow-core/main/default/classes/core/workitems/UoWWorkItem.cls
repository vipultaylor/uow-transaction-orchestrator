//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Base class for all UnitOfWork work items.
 * Contains common properties and methods shared across all work item types.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Work Items
 * @see UoWDmlWorkItem
 * @see UoWEventWorkItem
 * @see UoWEmailWorkItem
 * @see UoWNotificationWorkItem
 * @see UoWFlowWorkItem
 * @see UoWCalloutWorkItem
 */
public virtual inherited sharing class UoWWorkItem implements Comparable {

    // ============================================================================
    // PUBLIC PROPERTIES - IDENTITY
    // ============================================================================

    public String workId;
    public UoWEnums.WorkType workType;
    public DateTime requestedAt;
    public DateTime startTime;
    public DateTime endTime;
    public Long executionTimeMs;

    // Transaction sequence - assigned during execution or finalization.
    // For executed work items: reflects actual runtime execution order (1, 2, 3...)
    // For non-executed work items: assigned after executed items, reflecting planned order
    // Example: Callouts (1-2) → PRE_DML Events (3) → DML (4-6) → POST_DML (7-8) → [non-executed: 9-10]
    public Integer transactionSequence;

    // ============================================================================
    // PUBLIC PROPERTIES - EXECUTION STATE
    // ============================================================================

    public Boolean isExecuted;
    public UoWEnums.WorkStatus status;
    public String errorMessage;

    // ============================================================================
    // PUBLIC PROPERTIES - ERROR HANDLING
    // ============================================================================

    // Error handling control - if true, exceptions won't re-throw (continue execution)
    // Default varies by work type (set in constructors):
    // - Emails/Notifications: true (auxiliary operations, shouldn't block transaction)
    // - Callouts/Events/Flows/DML: false (fail-fast for data consistency)
    // - For DML: continueOnError controls allOrNone parameter (false → allOrNone=true, true → allOrNone=false)
    public Boolean continueOnError;

    // Exception tracking - captured when Apex exceptions occur
    public List<UoWExceptionService.ErrorInfo> errors;

    // ============================================================================
    // PUBLIC PROPERTIES - AUDIT CONTEXT
    // ============================================================================

    public String requestStackTrace;
    public String requestOriginLocation;
    public String requestOriginType;
    public String requestClassName;        // The actual ApexClass name (outer class when inner exists)

    // ============================================================================
    // PUBLIC PROPERTIES - GOVERNOR LIMITS
    // ============================================================================

    public GovernorLimits governorLimits;

    // ============================================================================
    // PUBLIC PROPERTIES - STATISTICS
    // ============================================================================

    public Statistics statistics;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Create a new work item of the specified type.
     *
     * @param workType The type of work item (DML, EVENT, FLOW, EMAIL, NOTIFICATION, CALLOUT)
     */
    public UoWWorkItem(UoWEnums.WorkType workType) {
        this.workId = UoWUtils.generateWorkId();
        this.workType = workType;
        this.requestedAt = DateTime.now();
        this.isExecuted = false;
        this.status = UoWEnums.WorkStatus.REGISTERED;
        this.errors = new List<UoWExceptionService.ErrorInfo>();
        this.statistics = new Statistics();
        this.governorLimits = new GovernorLimits();

        captureRequestContext();
    }

    // ============================================================================
    // PUBLIC API - ERROR MANAGEMENT
    // ============================================================================

    /**
     * Add error from exception.
     *
     * @param ex The exception to add
     */
    public void addError(Exception ex) {
        if (ex != null) {
            UoWExceptionService.ErrorInfo error = new UoWExceptionService.ErrorInfo(ex);
            error.workItemId = this.workId;
            this.errors.add(error);
        }
    }

    /**
     * Add error from ErrorInfo.
     *
     * @param error The error info to add
     */
    public void addError(UoWExceptionService.ErrorInfo error) {
        if (error != null) {
            error.workItemId = this.workId;
            this.errors.add(error);
        }
    }

    /**
     * Check if work item has errors.
     *
     * @return True if work item has errors
     */
    public Boolean hasErrors() {
        return (this.errors != null && !this.errors.isEmpty()) ||
               String.isNotBlank(this.errorMessage);
    }

    // ============================================================================
    // PUBLIC API - RESULT PROCESSING
    // ============================================================================

    /**
     * Process execution results - extract errors and calculate statistics.
     * Called after execution to process results in a single pass.
     * Override in subclasses for type-specific result processing.
     * Base implementation handles exception-based work types (Flow, Notification, Callout)
     * where success/failure is determined by presence of errors.
     */
    public virtual void processResults() {
        // Base implementation for exception-based work types (no result objects)
        // These work types succeed or fail as a unit (1 processed, 0 or 1 success/failure)
        this.statistics.processed = 1;
        if (this.errors != null && !this.errors.isEmpty()) {
            this.statistics.successes = 0;
            this.statistics.failures = 1;
        } else {
            this.statistics.successes = 1;
            this.statistics.failures = 0;
        }
    }

    /**
     * Finalize work item status based on execution state.
     * Call this after execution completes to set the final status.
     * Override in subclasses for type-specific status logic (e.g., PARTIAL_SUCCESS).
     */
    public virtual void finalizeStatus() {
        if (!this.isExecuted) {
            this.status = UoWEnums.WorkStatus.NOT_EXECUTED;
        } else if (hasErrors()) {
            this.status = UoWEnums.WorkStatus.FAILED;
        } else {
            this.status = UoWEnums.WorkStatus.SUCCESS;
        }
    }

    // ============================================================================
    // PUBLIC API - SERIALIZATION LIFECYCLE
    // ============================================================================

    /**
     * Prepare work item for serialization.
     * Called before platform serialization (e.g., before Queueable enqueue).
     * Override in subclasses to capture non-serializable data as serializable fields.
     *
     * Base implementation prepares errors for serialization.
     * Subclasses should call super.prepareForSerialization() first, then add type-specific logic:
     * - UoWDmlWorkItem: sobjectTypeName already stored
     * - UoWEventWorkItem: sobjectTypeName already stored
     * - UoWEmailWorkItem: capture email metadata from Messaging.Email objects
     */
    public virtual void prepareForSerialization() {
        // Prepare errors for serialization - they contain Map<String, Object> that needs capture
        prepareErrorsForSerialization();
    }

    /**
     * Prepare work item for serialization with configuration.
     * Used for audit snapshots where masking and sampling may be applied.
     * Override in subclasses to apply masking/sampling to their specific data structures.
     *
     * Base implementation prepares errors for serialization.
     * Subclasses should call super.prepareForSerialization(config) first, then add type-specific logic.
     *
     * @param config Serialization configuration controlling masking/sampling behavior
     */
    public virtual void prepareForSerialization(UoWSerializationConfig config) {
        // Prepare errors for serialization - they contain Map<String, Object> that needs capture
        prepareErrorsForSerialization();
        // Subclasses override to apply masking/sampling to their specific data structures
    }

    /**
     * Restore non-serializable data after deserialization.
     * Called after platform deserialization (e.g., after Queueable execution starts).
     * Override in subclasses to restore transient fields from serializable data.
     *
     * Base implementation hydrates errors.
     * Subclasses should call super.hydrate() first, then add type-specific logic:
     * - UoWDmlWorkItem: restore sobjectType from sobjectTypeName
     * - UoWEventWorkItem: restore sobjectType from sobjectTypeName
     * - UoWEmailWorkItem: restore Messaging.Email objects from metadata
     */
    public virtual void hydrate() {
        // Restore errors after deserialization - they contain Map<String, Object> restored from JSON
        hydrateErrors();
    }

    // ============================================================================
    // PUBLIC API - GOVERNOR LIMITS
    // ============================================================================

    /**
     * Capture governor limits before execution.
     */
    public void captureGovernorLimitsBefore() {
        this.governorLimits.before = new UoWGovernorLimits();
    }

    /**
     * Capture governor limits after execution.
     */
    public void captureGovernorLimitsAfter() {
        this.governorLimits.after = new UoWGovernorLimits();
    }

    /**
     * Get governor limits consumed by this work item.
     *
     * @return UoWGovernorLimits with consumed values, or null if limits not captured
     */
    public UoWGovernorLimits getGovernorLimitsConsumed() {
        return UoWGovernorLimits.getConsumed(this.governorLimits.before, this.governorLimits.after);
    }

    // ============================================================================
    // PUBLIC API - COMPARABLE INTERFACE
    // ============================================================================

    /**
     * Comparable implementation - sort by transaction sequence.
     * Work items with null sequence (non-executed) sort after executed items.
     *
     * @param other The other work item to compare to
     * @return Comparison result (-1, 0, or 1)
     */
    public Integer compareTo(Object other) {
        UoWWorkItem otherItem = (UoWWorkItem) other;

        // Handle null sequences - non-executed items sort after executed items
        if (this.transactionSequence == null && otherItem.transactionSequence == null) {
            return 0;
        }
        if (this.transactionSequence == null) {
            return 1; // this sorts after other
        }
        if (otherItem.transactionSequence == null) {
            return -1; // this sorts before other
        }

        // Both have sequences - compare numerically
        return this.transactionSequence > otherItem.transactionSequence ? 1 :
               (this.transactionSequence < otherItem.transactionSequence ? -1 : 0);
    }

    // ============================================================================
    // PUBLIC API - ORIGIN CONTEXT OVERRIDE
    // ============================================================================

    /**
     * Override the request origin context for this work item.
     * Used when the actual origin (e.g., a Flow) cannot be automatically detected
     * from the Apex stack trace. Salesforce does not expose the calling Flow's
     * API name in the stack trace when a Flow invokes an Apex invocable action.
     *
     * @param originType The origin type (e.g., 'Flow', 'Process Builder')
     * @param originName The origin name/API name (e.g., 'MyFlow_DecisionScheduled')
     * @return This work item for fluent chaining
     */
    public UoWWorkItem withOrigin(String originType, String originName) {
        if (String.isNotBlank(originType)) {
            this.requestOriginType = originType;
        }
        if (String.isNotBlank(originName)) {
            this.requestOriginLocation = originName;
            this.requestClassName = originName;
        }
        return this;
    }

    // ============================================================================
    // PRIVATE METHODS - REQUEST CONTEXT
    // ============================================================================

    // Capture stack trace and origin information at registration time
    private void captureRequestContext() {
        // Skip framework classes to find the actual caller
        UoWStackTraceParser.StackTraceInfo stackInfo = UoWStackTraceParser.parse(null, null);

        this.requestStackTrace = stackInfo.fullStackTrace;
        this.requestOriginLocation = stackInfo.originLocation;
        this.requestOriginType = stackInfo.originType;
        this.requestClassName = stackInfo.className;
    }

    // ============================================================================
    // PRIVATE METHODS - SERIALIZATION
    // ============================================================================

    // Prepare errors for serialization - captures errorContext Map to JSON string
    private void prepareErrorsForSerialization() {
        if (this.errors == null) {
            return;
        }
        for (UoWExceptionService.ErrorInfo error : this.errors) {
            error.captureContextForSerialization();
        }
    }

    // Hydrate errors after deserialization - restores errorContext Map from JSON string
    private void hydrateErrors() {
        if (this.errors == null) {
            return;
        }
        for (UoWExceptionService.ErrorInfo error : this.errors) {
            error.restoreContextFromSerialization();
        }
    }

    // ============================================================================
    // INNER CLASSES
    // ============================================================================

    /**
     * Work item statistics - tracks planned, processed, successes, and failures.
     * Virtual to allow subclasses to extend with operation-specific metrics.
     */
    public virtual class Statistics {
        // Planned count - set at registration time, represents intended number of items
        // For DML: records.size(), Events: events.size(), Emails: emails.size()
        // For Notifications/Flows/Callouts: 1 (single item per work item)
        public Integer planned;

        // Actual counts - populated by processResults() after execution
        public Integer processed;
        public Integer successes;
        public Integer failures;

        /**
         * Initialize statistics with zero counts.
         */
        public Statistics() {
            this.planned = 0;
            this.processed = 0;
            this.successes = 0;
            this.failures = 0;
        }
    }

    /**
     * Container for governor limits captured before and after work item execution.
     * Used to calculate resource consumption for this specific work item.
     */
    public class GovernorLimits {
        /** @description Governor limits captured before execution */
        public UoWGovernorLimits before;
        /** @description Governor limits captured after execution */
        public UoWGovernorLimits after;
    }
}