//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Queueable job for asynchronous UnitOfWork execution.
 * Executes UoW transactions asynchronously when commitWork is called with ASYNC strategy.
 *
 * DESIGN: Stores UoWContext and UoWPlan directly (not as JSON strings).
 * Salesforce automatically serializes the entire Queueable instance, preserving
 * object references including relationships between records.
 *
 * SERIALIZATION: Transient fields (interface references, Schema types, Messaging.Email)
 * are lost during platform serialization. The UoWSerializationService handles this:
 * - prepareForAsync() in constructor captures non-serializable data as strings
 * - hydrateFromAsync() in execute() restores transient fields from strings
 *
 * Transaction Finalizer Support:
 * If a Transaction Finalizer is configured (via metadata or runtime), it is resolved
 * and attached using System.attachFinalizer(). The platform guarantees the finalizer's
 * execute() method runs even on unhandled exceptions.
 *
 * Finalizer implementations can access UoW state via:
 * - UoWQueueable.getFinalizerState() - FinalizerState containing context and result
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Core
 * @see UnitOfWork
 * @see UoWSerializationService
 */
public inherited sharing class UoWQueueable implements Queueable, Database.AllowsCallouts {

    // ============================================================================
    // PRIVATE PROPERTIES - STORED DIRECTLY (Salesforce serializes automatically)
    // ============================================================================

    private UoWContext context;
    private UoWPlan plan;

    // ============================================================================
    // PRIVATE STATIC PROPERTIES - FINALIZER STATE
    // ============================================================================

    // Combined state holder for finalizer access
    // Uses a single static to pass both context and result to finalizers
    private static FinalizerState finalizerState;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Constructor for async transaction execution.
     * Stores context and plan directly - Salesforce serializes the entire
     * Queueable instance automatically, preserving object references.
     * Prepares non-serializable data before platform serialization.
     *
     * @param context The UoWContext to execute
     * @param plan The UoWPlan to execute
     */
    public UoWQueueable(UoWContext context, UoWPlan plan) {
        this.context = context;
        this.plan = plan;

        // Prepare for serialization - capture non-serializable data as strings
        UoWSerializationService.prepareForAsync(this.context, this.plan);
    }

    // ============================================================================
    // PUBLIC API - QUEUEABLE INTERFACE
    // ============================================================================

    /**
     * Execute the asynchronous transaction.
     * Generates a new transactionId for this execution while preserving the original
     * transactionId as parentTransactionId. The correlationId is preserved for end-to-end tracing.
     * Hydrates transient fields from serialized data before execution.
     */
    public void execute(QueueableContext queueableContext) {
        resetFinalizerState();

        UoWResult result = null;

        try {
            // Hydrate after deserialization - restore transient fields from strings
            UoWSerializationService.hydrateFromAsync(this.context, this.plan);

            // === TRANSACTION BOUNDARY ===
            // The original transaction (parent) enqueued this execution.
            // This execution gets a NEW transactionId while preserving the correlationId
            // for end-to-end distributed tracing across the async boundary.
            this.context.establishAsyncExecutionBoundary();

            // Resolve and attach transaction finalizer (if configured)
            attachTransactionFinalizer(this.context);

            UnitOfWork uow = new UnitOfWork(this.context, this.plan);
            result = uow.commitWork(UoWEnums.CommitMode.SYNC);

        } catch (Exception ex) {
            throw ex;  // Let platform capture for finalizer
        } finally {
            // Make state available to finalizer via static accessor
            finalizerState = new FinalizerState(this.context, result);
        }
    }

    // ============================================================================
    // PUBLIC API - FINALIZER STATE ACCESSOR
    // ============================================================================

    /**
     * Get finalizer state containing both context and result.
     * Call this from your ITransactionFinalizer.execute() method to access
     * the UoWContext and UoWResult from the async transaction.
     *
     * This state is set in the finally block of UoWQueueable.execute(),
     * so it's available even if the transaction fails.
     *
     * @return FinalizerState with context and result, or null if Queueable hasn't executed
     */
    public static FinalizerState getFinalizerState() {
        return finalizerState;
    }

    // Reset finalizer state (called at start of each Queueable execution)
    @TestVisible
    private static void resetFinalizerState() {
        finalizerState = null;
    }

    // ============================================================================
    // PRIVATE METHODS - FINALIZER ATTACHMENT
    // ============================================================================

    // Resolve and attach transaction finalizer if configured
    private void attachTransactionFinalizer(UoWContext ctx) {
        try {
            UoWInterfaces.ITransactionFinalizer finalizer = UoWTransactionFinalizerResolver.getInstance().resolve(ctx);

            if (finalizer != null) {
                System.attachFinalizer(finalizer);
            }
        } catch (Exception ex) {
            // Log but don't fail - finalizer attachment is not critical
            System.debug(LoggingLevel.WARN, 'UoWQueueable: Failed to attach transaction finalizer: ' +
                ex.getMessage());
        }
    }

    // ============================================================================
    // INNER CLASSES
    // ============================================================================

    /**
     * State holder for finalizer access.
     * Combines context and result into a single object to reduce static variable count.
     */
    public class FinalizerState {
        public UoWContext context { get; private set; }
        public UoWResult result { get; private set; }

        public FinalizerState(UoWContext context, UoWResult result) {
            this.context = context;
            this.result = result;
        }
    }
}
