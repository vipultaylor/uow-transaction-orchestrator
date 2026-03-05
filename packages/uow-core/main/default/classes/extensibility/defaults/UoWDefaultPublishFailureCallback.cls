//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Top-level callback for asynchronous platform event delivery failures.
 * Fires in a SEPARATE transaction when events fail to deliver after commit.
 *
 * IMPORTANT: This must be a top-level class (not an inner class) because
 * the platform serializes the callback instance across transaction boundaries.
 * Inner classes carry an implicit outer class reference that can cause
 * uncatchable serialization exceptions during EventBus.publish().
 *
 * Stores only primitive fields for safe platform serialization across
 * transaction boundaries. The configured handler class name is instantiated
 * dynamically in onFailure() rather than storing an instance reference.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see EventBus.EventPublishFailureCallback
 * @see UoWInterfaces.IEventPublishFailureHandler
 */
public inherited sharing class UoWDefaultPublishFailureCallback implements EventBus.EventPublishFailureCallback {

    // ========================================================================
    // TEST VISIBILITY
    // ========================================================================

    /**
     * Captured failure contexts for test assertions.
     * Populated by onFailure() - accessible in tests after Test.stopTest().
     */
    @TestVisible
    private static List<UoWEventPublishFailureContext> capturedFailures =
        new List<UoWEventPublishFailureContext>();

    // ========================================================================
    // PRIVATE FIELDS - TRANSACTION CONTEXT (primitives only)
    // ========================================================================

    private String correlationId;
    private String transactionId;
    private String workId;
    private Integer eventCount;
    private String failureHandlerClassName;

    // ========================================================================
    // CONSTRUCTORS
    // ========================================================================

    /**
     * Construct callback by extracting primitives from context and work item.
     * Only primitive values are stored for safe platform serialization.
     *
     * @param ctx The execution context (correlationId, transactionId extracted)
     * @param workItem The event work item (workId, event count extracted)
     * @param failureHandlerClassName Optional handler class to delegate to on failure
     */
    public UoWDefaultPublishFailureCallback(
        UoWContext ctx,
        UoWEventWorkItem workItem,
        String failureHandlerClassName
    ) {
        this.correlationId = ctx.correlationId;
        this.transactionId = ctx.transactionId;
        this.workId = workItem.workId;
        this.eventCount = workItem.getOriginalEvents().size();
        this.failureHandlerClassName = failureHandlerClassName;
    }

    // ========================================================================
    // PUBLIC API - CALLBACK
    // ========================================================================

    /**
     * Called by the platform when published events fail to deliver.
     * Delegates to handleFailure() which contains the actual business logic.
     *
     * Note: EventBus.FailureResult indicates the entire batch failed.
     * All events in the publish call are considered failed.
     *
     * @param result The failure result from the platform (unused - context
     *               is built from primitives captured during construction)
     */
    public void onFailure(EventBus.FailureResult result) {
        handleFailure();
    }

    // ========================================================================
    // PRIVATE - FAILURE HANDLING LOGIC
    // ========================================================================

    /**
     * Core failure handling logic, extracted for testability.
     * The platform's onFailure() callback cannot be invoked directly in tests
     * (requires real platform events via Test.getEventBus().fail()), so this
     * method enables direct unit testing of all failure handling paths.
     *
     * Builds failure context, captures for test assertions, delegates to
     * configured handler, and logs the failure.
     */
    @TestVisible
    private void handleFailure() {
        // Build failure context - entire batch fails
        UoWEventPublishFailureContext failureCtx =
            new UoWEventPublishFailureContext();
        failureCtx.correlationId = this.correlationId;
        failureCtx.transactionId = this.transactionId;
        failureCtx.workId = this.workId;
        failureCtx.publishedEventCount = this.eventCount;
        failureCtx.failedEventCount = this.eventCount;
        failureCtx.failedAt = DateTime.now();

        // Capture for test assertions
        capturedFailures.add(failureCtx);

        // Delegate to configured handler if present
        if (String.isNotBlank(this.failureHandlerClassName)) {
            try {
                Type handlerType = Type.forName(this.failureHandlerClassName);
                if (handlerType != null) {
                    UoWInterfaces.IEventPublishFailureHandler handler =
                        (UoWInterfaces.IEventPublishFailureHandler) handlerType.newInstance();
                    handler.handleFailure(failureCtx);
                }
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR,
                    'EventPublishFailureHandler invocation failed: ' + ex.getMessage()
                    + '\n' + ex.getStackTraceString());
            }
        }

        // Always log
        System.debug(LoggingLevel.ERROR, String.format(
            'Platform event async delivery failure | correlationId: {0} | transactionId: {1} | workId: {2} | failed: {3}/{4}',
            new String[]{
                this.correlationId,
                this.transactionId,
                this.workId,
                String.valueOf(failureCtx.failedEventCount),
                String.valueOf(this.eventCount)
            }
        ));
    }
}
