//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Base class for all work item executors.
 * Provides common lifecycle management and error handling.
 *
 * Design:
 * - Template pattern: Subclasses implement execute()
 * - Shared lifecycle: workId generation, governor limits, finalization
 * - Consistent error handling: continueOnError flag support
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Execution
 * @see UoWDmlExecutionService
 * @see UoWEventExecutionService
 * @see UoWEmailExecutionService
 * @see UoWNotificationExecutionService
 * @see UoWFlowExecutionService
 * @see UoWCalloutExecutionService
 */
public abstract inherited sharing class UoWWorkItemExecutor {

    // ============================================================================
    // PROTECTED FIELDS
    // ============================================================================

    // Execution context for the transaction
    protected UoWContext context;
    // Execution plan containing work items
    protected UoWPlan plan;
    // Result collector for transaction outcomes
    protected UoWResult result;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    protected UoWWorkItemExecutor(UoWContext ctx, UoWPlan plan, UoWResult result) {
        this.context = ctx;
        this.plan = plan;
        this.result = result;
    }

    // ============================================================================
    // PUBLIC API - TEMPLATE METHOD
    // ============================================================================

    /**
     * Template method - Subclasses must implement execution logic.
     *
     * @param phase The phase of execution (null for DMLs and Callouts as they are not phase dependent)
     */
    public abstract void execute(UoWEnums.WorkPhase phase);

    // ============================================================================
    // PROTECTED METHODS - WORK ITEM LIFECYCLE
    // ============================================================================

    /**
     * Prepare work item for execution.
     * - Capture start time for execution duration calculation
     * - Capture governor limits BEFORE execution
     *
     * @param workItem The work item to prepare
     */
    protected void prepareWorkItem(UoWWorkItem workItem) {
        workItem.startTime = DateTime.now();
        workItem.captureGovernorLimitsBefore();
    }

    /**
     * Finalize work item after execution.
     * - Capture governor limits AFTER execution
     * - Mark as executed with end time and sequence
     * - Calculate execution duration (endTime - startTime)
     * - Process results (extract errors + calculate statistics)
     * - Finalize status based on results
     *
     * @param workItem The work item to finalize
     */
    protected void finalizeWorkItem(UoWWorkItem workItem) {
        workItem.captureGovernorLimitsAfter();

        workItem.isExecuted = true;
        workItem.endTime = DateTime.now();
        workItem.executionTimeMs = workItem.endTime.getTime() - workItem.startTime.getTime();
        workItem.transactionSequence = result.getNextExecutionSequence();

        workItem.processResults();
        workItem.finalizeStatus();
    }

    // ============================================================================
    // PROTECTED METHODS - ERROR HANDLING
    // ============================================================================

    /**
     * Handle work item exception based on continueOnError flag.
     * - Always capture error in work item
     * - Re-throw if fail-fast mode (continueOnError = false)
     * - Continue if resilient mode (continueOnError = true)
     *
     * @param workItem The work item that failed
     * @param ex The exception that occurred
     */
    protected void handleWorkItemException(UoWWorkItem workItem, Exception ex) {
        workItem.addError(ex);

        if (!workItem.continueOnError) {
            throw ex;
        }
    }
}