//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Executes Salesforce Flow work items.
 *
 * Responsibilities:
 * - Execute flows for specified execution phases
 * - Pass input variables to flows
 * - Capture output variables from flows
 * - Respect continueOnError flag (default: false for flows)
 *
 * Design Note:
 * - Each FlowWorkItem represents a single flow execution
 * - Multiple flows can be registered per phase
 * - Flow inputs/outputs stored in flowInputs/flowOutputs maps
 *
 * Execution Phases:
 * - PRE_DML: Flows executed before DML operations
 * - POST_DML: Flows executed after DML operations
 * - ON_SUCCESS: Flows executed on successful transaction
 * - ON_FAILURE: Flows executed on transaction failure
 * - ON_FINALIZATION: Flows executed during finalization
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Execution
 * @see UoWWorkItemExecutor
 * @see UoWFlowChannelResolver
 */
public inherited sharing class UoWFlowExecutionService extends UoWWorkItemExecutor {

    // ============================================================================
    // PRIVATE FIELDS
    // ============================================================================

    // Flow channel resolved for this execution
    private UoWInterfaces.IFlowChannel flowChannel;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Constructor passing the relevant context for executing flows.
     *
     * @param ctx Context instance
     * @param plan Plan that contains flow work items
     * @param result Result instance initialized for this execution
     */
    public UoWFlowExecutionService(UoWContext ctx, UoWPlan plan, UoWResult result) {
        super(ctx, plan, result);
    }

    // ============================================================================
    // PUBLIC API - EXECUTION
    // ============================================================================

    /**
     * Execute flows for a specific phase.
     *
     * @param phase The execution phase
     */
    public override void execute(UoWEnums.WorkPhase phase) {
        List<UoWFlowWorkItem> flowWork = plan.getFlowWork(phase);
        if (flowWork == null || flowWork.isEmpty()) {
            result.debug(String.format('No flows to execute - skipping {0} phase',
                new String[]{ String.valueOf(phase) }), 'UoWFlowExecutionService');
            return;
        }

        result.info(String.format('{0} flow execution started - {1} flow(s)',
            new String[]{ String.valueOf(phase), String.valueOf(flowWork.size()) }), 'UoWFlowExecutionService');

        this.flowChannel = UoWFlowChannelResolver.resolve(context, result);

        for (UoWFlowWorkItem workItem : flowWork) {
            executeFlowWorkItem(workItem);
        }

        result.info(String.format('{0} flow execution completed',
            new String[]{ String.valueOf(phase) }), 'UoWFlowExecutionService');
    }

    // ============================================================================
    // PRIVATE METHODS - WORK ITEM EXECUTION
    // ============================================================================

    // Execute a single flow work item.
    private void executeFlowWorkItem(UoWFlowWorkItem workItem) {
        // Start work item span (child of phase span)
        UoWTracer.Span workItemSpan = result.startSpan(workItem, null);

        // Add flow-specific attributes
        workItemSpan?.setAttribute('flow.name', workItem.flowApiName);
        workItemSpan?.setAttribute('flow.inputs', workItem.flowInputs?.size() ?? 0);

        prepareWorkItem(workItem);

        try {
            if (!context.isDryRun) {
                result.debug(String.format('Executing flow: {0} - workId: {1}',
                    new String[]{
                        workItem.flowApiName,
                        workItem.workId
                    }), 'UoWFlowExecutionService');

                this.flowChannel.executeFlow(workItem, context);
            } else {
                result.fine(String.format('Skipping flow execution in dry run mode - workId: {0}, flowApiName: {1}',
                    new String[]{ workItem.workId, workItem.flowApiName }), 'UoWFlowExecutionService');
            }

        } catch (Exception ex) {
            workItemSpan?.setAttribute('error', true);
            workItemSpan?.setAttribute('error.message', ex.getMessage());
            handleWorkItemException(workItem, ex);

        } finally {
            finalizeWorkItem(workItem);

            // End work item span with result summary
            result.endSpan(workItemSpan, workItem, null);

            result.addFlowWork(workItem);
        }
    }
}