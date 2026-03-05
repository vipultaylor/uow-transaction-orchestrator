//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Callback for asynchronous audit platform event delivery failures.
 * Fires in a SEPARATE transaction when audit events fail to deliver after commit.
 *
 * Stores only primitive fields for safe platform serialization across
 * transaction boundaries.
 *
 * Delegates persistence to the appropriate writer based on storage mode:
 * - BIG_OBJECT: UoWAuditBigObjectWriter
 * - CUSTOM_OBJECT: UoWAuditCustomObjectWriter
 * - Other modes (PLATFORM_EVENT, EXTERNAL): No local persistence needed
 *
 * @author Vipul Taylor
 * @see EventBus.EventPublishFailureCallback
 */
public class UoWAuditPublishFailureCallback implements EventBus.EventPublishFailureCallback {

    // ============================================================================
    // INNER CLASS - FAILURE CONTEXT
    // ============================================================================

    /**
     * Context object containing all data needed for failure persistence.
     * Passed to writer classes to create tombstone records and work items.
     */
    public class FailureContext {
        public String correlationId;
        public String transactionId;
        public String parentTransactionId;
        public Integer eventCount;
        public String storageMode;
        public String transactionStatus;
        public String serializedEventsJson;
        public String errorMessage;
        public DateTime failedAt;
        public List<String> eventUuids;
    }

    // ============================================================================
    // PUBLIC FIELDS - TRANSACTION CONTEXT (primitives only for serialization)
    // ============================================================================

    public String correlationId;
    public String transactionId;
    public String parentTransactionId;
    public Integer eventCount;
    public String storageMode;
    public String transactionStatus;

    // Serialized audit events for fallback persistence when async delivery fails.
    // Enables work item capture even when parent transaction rolls back.
    public String serializedEventsJson;

    // ============================================================================
    // TEST VISIBILITY
    // ============================================================================

    /**
     * Captured audit failure contexts for test assertions.
     * Populated by onFailure() - accessible in tests after Test.stopTest().
     */
    @TestVisible
    private static List<UoWEventPublishFailureContext> capturedAuditFailures =
        new List<UoWEventPublishFailureContext>();

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Construct callback with core identifiers.
     *
     * @param correlationId Correlation ID from the publishing transaction
     * @param transactionId Transaction ID from the publishing transaction
     */
    public UoWAuditPublishFailureCallback(String correlationId, String transactionId) {
        this.correlationId = correlationId;
        this.transactionId = transactionId;
    }

    // ============================================================================
    // PUBLIC API - CALLBACK
    // ============================================================================

    /**
     * Called by the platform when audit events fail to deliver.
     * Builds failure context and delegates to appropriate writer based on storage mode.
     *
     * @param result The failure result from the platform
     */
    public void onFailure(EventBus.FailureResult result) {
        try {
            // Build failure context
            FailureContext ctx = buildFailureContext(result);

            // Capture for test assertions
            captureForTesting(ctx);

            // Delegate to appropriate writer based on storage mode
            if (this.storageMode == UoWAuditEnums.AuditStorageMode.BIG_OBJECT.name()) {
                // BIG_OBJECT: everything goes to UoWAuditHistory__b (no custom object records)
                UoWAuditBigObjectWriter.writeFromFailure(ctx);
            } else if (this.storageMode == UoWAuditEnums.AuditStorageMode.CUSTOM_OBJECT.name()) {
                UoWAuditCustomObjectWriter.writeFromFailure(ctx);
            }
            // Other modes (PLATFORM_EVENT, EXTERNAL, NONE) don't need local persistence

        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'UoWAuditPublishFailureCallback.onFailure failed: ' + ex.getMessage()
                + '\n' + ex.getStackTraceString()
                + ' | CorrelationId: ' + this.correlationId);
        }

        // Always log
        System.debug(LoggingLevel.ERROR, String.format(
            'Audit event async delivery failure | correlationId: {0} | transactionId: {1} | storageMode: {2} | transactionStatus: {3}',
            new String[]{
                this.correlationId,
                this.transactionId,
                this.storageMode,
                this.transactionStatus ?? 'UNKNOWN'
            }
        ));
    }

    // ============================================================================
    // PRIVATE HELPER METHODS
    // ============================================================================

    /**
     * Build failure context from callback fields and platform result.
     */
    private FailureContext buildFailureContext(EventBus.FailureResult result) {
        FailureContext ctx = new FailureContext();
        ctx.correlationId = this.correlationId;
        ctx.transactionId = this.transactionId;
        ctx.parentTransactionId = this.parentTransactionId;
        ctx.eventCount = this.eventCount;
        ctx.storageMode = this.storageMode;
        ctx.transactionStatus = determineEffectiveStatus();
        ctx.serializedEventsJson = this.serializedEventsJson;
        ctx.failedAt = DateTime.now();
        ctx.eventUuids = result.getEventUuids();

        // Build error message
        ctx.errorMessage = buildErrorMessage(ctx);

        return ctx;
    }

    /**
     * Build error message with available context.
     */
    private String buildErrorMessage(FailureContext ctx) {
        String errorMessage = 'Audit event async delivery failure: ' + ctx.eventCount +
            ' of ' + this.eventCount + ' audit events failed to deliver.' +
            '\nTransaction status at publish time: ' + (this.transactionStatus ?? 'UNKNOWN') +
            '\nEffective status: ' + ctx.transactionStatus +
            '\nStorage mode: ' + ctx.storageMode;

        if (ctx.eventUuids != null && !ctx.eventUuids.isEmpty()) {
            errorMessage += '\nFailed event UUIDs: ' + String.join(ctx.eventUuids, ', ');
        }

        return errorMessage;
    }

    /**
     * Capture failure context for test assertions.
     */
    private void captureForTesting(FailureContext ctx) {
        UoWEventPublishFailureContext testCtx = new UoWEventPublishFailureContext();
        testCtx.correlationId = ctx.correlationId;
        testCtx.transactionId = ctx.transactionId;
        testCtx.workId = null; // audit events have no individual work item
        testCtx.failedEventCount = ctx.eventCount;
        testCtx.publishedEventCount = this.eventCount;
        testCtx.failedAt = ctx.failedAt;
        testCtx.metadata = new Map<String, String>{ 'storageMode' => ctx.storageMode };
        capturedAuditFailures.add(testCtx);
    }

    /**
     * Determine the effective status for the tombstone transaction.
     * If this is a child transaction (has parentTransactionId), use ROLLED_BACK_BY_PARENT
     * since events failing to deliver for a child almost always means parent rolled back.
     * Otherwise, use the original transaction status or FAILED as fallback.
     *
     * @return The effective transaction status string
     */
    private String determineEffectiveStatus() {
        // If no parent, use original status or FAILED
        if (String.isBlank(this.parentTransactionId)) {
            return this.transactionStatus ?? UoWEnums.TransactionStatus.FAILED.name();
        }

        // Child transaction with parent: events failing to deliver means parent rolled back.
        // We can't rely on parent's DB status because parent also published with SUCCESS
        // before the rollback occurred. The fact that child's events failed + having a parent
        // is sufficient evidence that parent rolled back.
        return 'ROLLED_BACK_BY_PARENT';
    }
}
