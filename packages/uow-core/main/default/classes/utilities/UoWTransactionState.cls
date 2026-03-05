//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Represents UoW transaction state for correlation propagation across boundaries.
 *
 * This class serves dual purposes:
 * 1. Static ambient context: Holds current transaction state during UoW execution
 * 2. Serializable carrier: Passes correlation context across async boundaries
 *
 * Sync Boundary Pattern (auto-detection):
 * Triggers and flows running during UoW commitWork() can access the ambient state
 * via getCurrent(). New UnitOfWork instances auto-inherit when ambient exists.
 *
 * Async Boundary Pattern (explicit passing):
 * For @future, Queueable, Platform Events - serialize state to JSON or store in
 * fields, then reconstruct with fromJson() or fromValues() in the async context.
 *
 * @example Sync boundary (trigger)
 * trigger AccountTrigger on Account (after insert) {
 *     // Auto-detects ambient - inherits correlation if inside UoW
 *     UnitOfWork uow = new UnitOfWork();
 *     uow.registerInsert(contacts);
 *     uow.commitWork();
 * }
 *
 * @example Async boundary (@future)
 * // In trigger - capture state
 * String stateJson = UoWTransactionState.getCurrentJson();
 * MyService.processAsync(stateJson, recordIds);
 *
 * // In @future method - restore state
 * public static void processAsync(String stateJson, Set<Id> ids) {
 *     UoWTransactionState state = UoWTransactionState.fromJson(stateJson);
 *     UnitOfWork uow = new UnitOfWork(state);
 *     uow.commitWork();
 * }
 *
 * @example Platform Event boundary
 * // Publisher - populate event fields
 * evt.CorrelationId__c = UoWTransactionState.getCurrent()?.correlationId;
 * evt.ParentTransactionId__c = UoWTransactionState.getCurrent()?.transactionId;
 *
 * // Subscriber - reconstruct state
 * UoWTransactionState state = UoWTransactionState.fromValues(
 *     evt.CorrelationId__c,
 *     evt.ParentTransactionId__c
 * );
 * UnitOfWork uow = new UnitOfWork(state);
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Core
 * @see UnitOfWork
 * @see UoWContext
 */
public inherited sharing class UoWTransactionState {

    // ============================================================================
    // STATIC AMBIENT CONTEXT (with stack for nested transactions)
    // ============================================================================

    private static UoWTransactionState currentAmbient;
    private static List<UoWTransactionState> ambientStack = new List<UoWTransactionState>();

    /**
     * Check if currently executing inside a UoW transaction.
     *
     * @return True if ambient transaction state exists
     */
    public static Boolean hasCurrent() {
        return currentAmbient != null;
    }

    /**
     * Get the current ambient transaction state.
     *
     * @return Current state or null if not inside UoW transaction
     */
    public static UoWTransactionState getCurrent() {
        return currentAmbient;
    }

    /**
     * Get current ambient state as JSON for @future parameters.
     *
     * @return JSON string or null if not inside transaction
     */
    public static String getCurrentJson() {
        return currentAmbient?.toJson();
    }

    /**
     * Push current ambient state onto stack and set new state (framework-internal).
     * Called by UoWTransactionStateService at commitWork() start.
     * Enables nested UoW transactions to restore parent's ambient state on completion.
     *
     * @param state The transaction state to set as ambient
     */
    @TestVisible
    public static void setCurrent(UoWTransactionState state) {
        // Push current ambient onto stack before replacing (enables restore on completion)
        if (currentAmbient != null) {
            ambientStack.add(currentAmbient);
        }
        currentAmbient = state;
    }

    /**
     * Restore previous ambient state from stack (framework-internal).
     * Called by UoWTransactionStateService in finally block.
     * Pops the stack to restore parent transaction's ambient state.
     */
    @TestVisible
    public static void restorePrevious() {
        if (!ambientStack.isEmpty()) {
            // Pop the stack to restore parent's ambient state
            currentAmbient = ambientStack.remove(ambientStack.size() - 1);
        } else {
            // No parent state - clear ambient
            currentAmbient = null;
        }
    }

    /**
     * Clear the ambient transaction state (framework-internal).
     * Clears both current ambient and entire stack.
     * Use for test cleanup or full reset scenarios.
     */
    @TestVisible
    public static void clearCurrent() {
        currentAmbient = null;
        ambientStack.clear();
    }

    // ============================================================================
    // INSTANCE PROPERTIES
    // ============================================================================

    /** UUID linking all related transactions in a chain */
    public String correlationId { get; private set; }

    /** Unique ID for this specific transaction */
    public String transactionId { get; private set; }

    /** Depth in async chain (0 = root, increments across async boundaries) */
    public Integer asyncDepth { get; private set; }

    /** When this state was captured */
    public DateTime capturedAt { get; private set; }

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Construct from UoWContext (framework-internal).
     * Used by UoWTransactionStateService to capture ambient state.
     *
     * @param ctx The UoWContext to capture state from
     */
    public UoWTransactionState(UoWContext ctx) {
        this.correlationId = ctx.correlationId;
        this.transactionId = ctx.transactionId;
        this.asyncDepth = ctx.asyncDepth ?? 0;
        this.capturedAt = DateTime.now();
    }

    /**
     * Construct with explicit values.
     *
     * @param correlationId Correlation ID to propagate
     * @param transactionId Transaction ID (becomes parentTransactionId in child)
     * @param asyncDepth Current async depth
     */
    public UoWTransactionState(String correlationId, String transactionId, Integer asyncDepth) {
        this.correlationId = correlationId;
        this.transactionId = transactionId;
        this.asyncDepth = asyncDepth ?? 0;
        this.capturedAt = DateTime.now();
    }

    // ============================================================================
    // FACTORY METHODS
    // ============================================================================

    /**
     * Create state from JSON string.
     * Use for @future method parameters.
     *
     * @param jsonString JSON from toJson() or getCurrentJson()
     * @return UoWTransactionState or null if blank
     */
    public static UoWTransactionState fromJson(String jsonString) {
        if (String.isBlank(jsonString)) {
            return null;
        }
        return (UoWTransactionState) JSON.deserialize(jsonString, UoWTransactionState.class);
    }

    /**
     * Create state from explicit values.
     * Use for Platform Event triggers where correlation is stored in event fields.
     *
     * @param correlationId Correlation ID from event field
     * @param parentTransactionId Parent transaction ID from event field
     * @return UoWTransactionState with values set
     */
    public static UoWTransactionState fromValues(String correlationId, String parentTransactionId) {
        return new UoWTransactionState(correlationId, parentTransactionId, 0);
    }

    // ============================================================================
    // SERIALIZATION
    // ============================================================================

    /**
     * Serialize to JSON for async boundary passing.
     *
     * @return JSON string representation
     */
    public String toJson() {
        return JSON.serialize(this);
    }

    // ============================================================================
    // APPLICATION TO UNITOFWORK
    // ============================================================================

    /**
     * Apply this state's correlation context to a UnitOfWork.
     *
     * When applied:
     * - correlationId is inherited (same chain)
     * - transactionId becomes parentTransactionId (linking)
     * - asyncDepth is incremented (depth tracking)
     *
     * @param uow The UnitOfWork to configure
     * @return The configured UnitOfWork for chaining
     */
    public UnitOfWork applyTo(UnitOfWork uow) {
        if (uow == null) {
            return uow;
        }
        UoWContext ctx = uow.getContext();
        ctx.inheritCorrelation(this.correlationId, this.transactionId, this.asyncDepth);
        return uow;
    }
}
