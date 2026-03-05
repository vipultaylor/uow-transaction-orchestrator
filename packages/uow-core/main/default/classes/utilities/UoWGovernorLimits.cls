//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Governor limit snapshot for tracking resource consumption.
 * Captures comprehensive governor limit usage including DML, SOQL, CPU, Heap,
 * Callouts, Async operations, and more.
 *
 * EFFICIENCY: Max limits are cached statically since they don't change
 * within a transaction. Use getMaxLimits() to access them.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Statistics
 * @see UoWStatisticsTracker
 * @see UoWResult
 */
public inherited sharing class UoWGovernorLimits {

    // ============================================================================
    // STATIC CACHE - Max limits (captured once per transaction)
    // ============================================================================

    private static UoWGovernorLimits cachedMaxLimits;

    /**
     * Get max limits (cached - captured once per transaction).
     *
     * @return UoWGovernorLimits instance with max limit values
     */
    public static UoWGovernorLimits getMaxLimits() {
        if (cachedMaxLimits == null) {
            cachedMaxLimits = new UoWGovernorLimits(false);
            cachedMaxLimits.captureMax();
        }
        return cachedMaxLimits;
    }

    /**
     * Reset the max limits cache (for testing).
     */
    @TestVisible
    private static void resetCache() {
        cachedMaxLimits = null;
    }

    // ============================================================================
    // PUBLIC PROPERTIES - DML LIMITS
    // ============================================================================

    public Integer dmlStatements;       // DML statements consumed
    public Integer dmlRows;             // DML rows consumed

    // ============================================================================
    // PUBLIC PROPERTIES - SOQL/SOSL LIMITS
    // ============================================================================

    public Integer soqlQueries;         // SOQL queries consumed
    public Integer soqlRows;            // SOQL rows consumed
    public Integer aggregateQueries;    // Aggregate queries consumed
    public Integer queryLocatorRows;    // Query locator rows consumed
    public Integer soslSearches;        // SOSL searches consumed

    // ============================================================================
    // PUBLIC PROPERTIES - APEX CURSOR LIMITS
    // ============================================================================

    public Integer apexCursorFetchCalls; // Apex cursor fetch calls consumed
    public Integer apexCursorRows;       // Apex cursor rows consumed

    // ============================================================================
    // PUBLIC PROPERTIES - RESOURCE LIMITS
    // ============================================================================

    public Integer cpuTime;             // CPU time consumed (ms)
    public Integer heapSize;            // Heap size consumed (bytes)

    // ============================================================================
    // PUBLIC PROPERTIES - ASYNC LIMITS
    // ============================================================================

    public Integer callouts;            // HTTP callouts consumed
    public Integer futureCalls;         // Future calls consumed
    public Integer queueableJobs;       // Queueable jobs consumed
    public Integer emailInvocations;    // Email invocations consumed
    public Integer mobilePushApexCalls; // Mobile push Apex calls consumed

    // ============================================================================
    // PUBLIC PROPERTIES - PUBLISH LIMITS
    // ============================================================================

    public Integer publishImmediateDml; // Immediate publish DML operations

    // ============================================================================
    // PUBLIC PROPERTIES - METADATA
    // ============================================================================

    public DateTime capturedAt;         // Timestamp when snapshot was taken

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    // Default constructor - captures current usage
    public UoWGovernorLimits() {
        this.capturedAt = DateTime.now();
        this.capture();
    }

    // Private constructor - controls whether to auto-capture
    private UoWGovernorLimits(Boolean autoCapture) {
        this.capturedAt = DateTime.now();
        if (autoCapture) {
            this.capture();
        }
    }

    // ============================================================================
    // PUBLIC API - CAPTURE METHODS
    // ============================================================================

    /**
     * Capture current governor limit usage values.
     */
    public void capture() {
        // DML limits
        this.dmlStatements = Limits.getDmlStatements();
        this.dmlRows = Limits.getDmlRows();

        // SOQL/SOSL limits
        this.soqlQueries = Limits.getQueries();
        this.soqlRows = Limits.getQueryRows();
        this.aggregateQueries = Limits.getAggregateQueries();
        this.queryLocatorRows = Limits.getQueryLocatorRows();
        this.soslSearches = Limits.getSoslQueries();

        // Apex cursor limits
        this.apexCursorFetchCalls = Limits.getFetchCallsOnApexCursor();
        this.apexCursorRows = Limits.getApexCursorRows();

        // Resource limits
        this.cpuTime = Limits.getCpuTime();
        this.heapSize = Limits.getHeapSize();

        // Async limits
        this.callouts = Limits.getCallouts();
        this.futureCalls = Limits.getFutureCalls();
        this.queueableJobs = Limits.getQueueableJobs();
        this.emailInvocations = Limits.getEmailInvocations();
        this.mobilePushApexCalls = Limits.getMobilePushApexCalls();

        // Publish limits
        this.publishImmediateDml = Limits.getPublishImmediateDML();
    }

    /**
     * Capture max governor limit values.
     */
    public void captureMax() {
        // DML limits
        this.dmlStatements = Limits.getLimitDmlStatements();
        this.dmlRows = Limits.getLimitDmlRows();

        // SOQL/SOSL limits
        this.soqlQueries = Limits.getLimitQueries();
        this.soqlRows = Limits.getLimitQueryRows();
        this.aggregateQueries = Limits.getLimitAggregateQueries();
        this.queryLocatorRows = Limits.getLimitQueryLocatorRows();
        this.soslSearches = Limits.getLimitSoslQueries();

        // Apex cursor limits
        this.apexCursorFetchCalls = Limits.getLimitFetchCallsOnApexCursor();
        this.apexCursorRows = Limits.getLimitApexCursorRows();

        // Resource limits
        this.cpuTime = Limits.getLimitCpuTime();
        this.heapSize = Limits.getLimitHeapSize();

        // Async limits
        this.callouts = Limits.getLimitCallouts();
        this.futureCalls = Limits.getLimitFutureCalls();
        this.queueableJobs = Limits.getLimitQueueableJobs();
        this.emailInvocations = Limits.getLimitEmailInvocations();
        this.mobilePushApexCalls = Limits.getLimitMobilePushApexCalls();

        // Publish limits
        this.publishImmediateDml = Limits.getLimitPublishImmediateDML();
    }

    // ============================================================================
    // PUBLIC API - STATIC METHODS
    // ============================================================================

    /**
     * Calculate the difference between two snapshots (after - before).
     *
     * @param before Snapshot taken before execution
     * @param after Snapshot taken after execution
     * @return New UoWGovernorLimits instance with consumed values
     */
    public static UoWGovernorLimits getConsumed(UoWGovernorLimits before, UoWGovernorLimits after) {
        if (before == null || after == null) {
            return null;
        }

        UoWGovernorLimits consumed = new UoWGovernorLimits(false);
        consumed.capturedAt = after.capturedAt;

        // DML limits
        consumed.dmlStatements = after.dmlStatements - before.dmlStatements;
        consumed.dmlRows = after.dmlRows - before.dmlRows;

        // SOQL/SOSL limits
        consumed.soqlQueries = after.soqlQueries - before.soqlQueries;
        consumed.soqlRows = after.soqlRows - before.soqlRows;
        consumed.aggregateQueries = after.aggregateQueries - before.aggregateQueries;
        consumed.queryLocatorRows = after.queryLocatorRows - before.queryLocatorRows;
        consumed.soslSearches = after.soslSearches - before.soslSearches;

        // Apex cursor limits
        consumed.apexCursorFetchCalls = after.apexCursorFetchCalls - before.apexCursorFetchCalls;
        consumed.apexCursorRows = after.apexCursorRows - before.apexCursorRows;

        // Resource limits
        consumed.cpuTime = after.cpuTime - before.cpuTime;
        consumed.heapSize = after.heapSize - before.heapSize;

        // Async limits
        consumed.callouts = after.callouts - before.callouts;
        consumed.futureCalls = after.futureCalls - before.futureCalls;
        consumed.queueableJobs = after.queueableJobs - before.queueableJobs;
        consumed.emailInvocations = after.emailInvocations - before.emailInvocations;
        consumed.mobilePushApexCalls = after.mobilePushApexCalls - before.mobilePushApexCalls;

        // Publish limits
        consumed.publishImmediateDml = after.publishImmediateDml - before.publishImmediateDml;

        return consumed;
    }
}