//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Transaction registry for managing active UnitOfWork instances across Flow actions.
 *
 * IMPORTANT LIMITATION: This registry uses static maps which are transaction-scoped in Salesforce.
 * This means it ONLY supports **single-transaction, autolaunched flows** (no screens, no pauses).
 *
 * Supported: Autolaunched flows that initialize → register work → commit in one execution
 * Not Supported: Screen flows, flows with waits/pauses (static state is lost between transactions)
 *
 * Flow invocable actions are stateless - each action invocation is independent. This registry
 * maintains a map of active UnitOfWork instances keyed by transaction ID, enabling Flow to build
 * up a transaction across multiple action calls within the same execution.
 *
 * Lifecycle (single transaction):
 * 1. Initialize action creates UnitOfWork and registers it → returns transaction ID
 * 2. Registration actions retrieve UoW by transaction ID → add work items
 * 3. Commit action retrieves UoW → executes → removes from registry
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Flow Actions
 * @see UoWFlowInitializeAction
 * @see UoWFlowCommitAction
 */
public inherited sharing class UoWFlowTransactionRegistry {
    // ============================================================================
    // PRIVATE FIELDS
    // ============================================================================

    private static Map<String, UnitOfWork> activeTransactions = new Map<String, UnitOfWork>();

    // ============================================================================
    // PUBLIC API - REGISTRATION
    // ============================================================================

    /**
     * Register a new UnitOfWork instance and return its transaction ID
     *
     * @param uow The UnitOfWork instance to register
     * @return Transaction ID from UoWContext for use in subsequent Flow actions
     */
    public static String register(UnitOfWork uow) {
        String transactionId = uow.getContext().transactionId;
        activeTransactions.put(transactionId, uow);
        return transactionId;
    }

    /**
     * Retrieve a UnitOfWork instance by transaction ID
     *
     * @param transactionId The transaction ID returned from register()
     * @return UnitOfWork instance
     * @throws UoWException if transaction not found (may have been committed or invalid ID)
     */
    public static UnitOfWork get(String transactionId) {
        UoWExceptionService.require(activeTransactions.containsKey(transactionId),
            'Transaction not found: ' + transactionId + '. Transaction may have already been committed or ID is invalid.');

        return activeTransactions.get(transactionId);
    }

    /**
     * Remove a transaction from the registry (cleanup after commit)
     *
     * @param transactionId The transaction ID to remove
     */
    public static void remove(String transactionId) {
        activeTransactions.remove(transactionId);
    }
}