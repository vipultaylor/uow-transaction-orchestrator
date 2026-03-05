//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Executes HTTP callout work items.
 *
 * Callouts support two execution phases due to Salesforce platform limitations:
 * - PRE_DML: Executes BEFORE savepoint creation (standard callout timing)
 * - ON_FAILURE: Executes AFTER rollback + savepoint release (error notification/compensation)
 *
 * POST_DML, ON_SUCCESS, ON_FINALIZATION are NOT supported because:
 * - Cannot make callouts after Database.setSavepoint()
 * - Cannot make callouts after DML commits
 *
 * Responsibilities:
 * - Execute HTTP requests for registered callout work items for the given phase
 * - Handle HTTP errors and timeouts
 * - Respect continueOnError flag for resilient vs fail-fast behavior
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Execution
 * @see UoWWorkItemExecutor
 * @see UoWCalloutStrategyResolver
 */
public inherited sharing class UoWCalloutExecutionService extends UoWWorkItemExecutor {

    // ============================================================================
    // PRIVATE FIELDS
    // ============================================================================

    // Callout strategy resolved for this execution
    private UoWInterfaces.ICalloutStrategy calloutStrategy;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Constructor passing the relevant context for executing callouts.
     *
     * @param ctx Context instance
     * @param plan Plan that contains callout work items
     * @param result Result instance initialized for this execution
     */
    public UoWCalloutExecutionService(UoWContext ctx, UoWPlan plan, UoWResult result) {
        super(ctx, plan, result);
    }

    // ============================================================================
    // PUBLIC API - EXECUTION
    // ============================================================================

    /**
     * Execute callout work items for the specified phase.
     * Callouts support PRE_DML and ON_FAILURE phases only.
     *
     * @param phase The execution phase (PRE_DML or ON_FAILURE)
     */
    public override void execute(UoWEnums.WorkPhase phase) {
        List<UoWCalloutWorkItem> callouts = plan.getCalloutWork(phase);

        if (callouts.isEmpty()) {
            result.debug(String.format('No callouts to execute for phase {0} - skipping',
                new String[]{ String.valueOf(phase) }), 'UoWCalloutExecutionService');
            return;
        }

        result.info(String.format('Callout execution started - {0} callout(s) for phase {1}',
            new String[]{ String.valueOf(callouts.size()), String.valueOf(phase) }), 'UoWCalloutExecutionService');

        // Use phase-specific SpanPhase for distinct timeline entries
        UoWEnums.SpanPhase spanPhase = phase == UoWEnums.WorkPhase.PRE_DML
            ? UoWEnums.SpanPhase.PRE_DML_CALLOUTS
            : UoWEnums.SpanPhase.ON_FAILURE_CALLOUTS;
        String phaseName = phase == UoWEnums.WorkPhase.PRE_DML ? 'Pre-DML Callouts' : 'On Failure Callouts';
        UoWTracer.Span calloutPhaseSpan = result.startSpan(
            spanPhase,
            phaseName
        );

        try {
            this.calloutStrategy = UoWCalloutStrategyResolver.resolve(context, result);

            for (UoWCalloutWorkItem workItem : callouts) {
                executeCalloutWorkItem(workItem);
            }

            result.info(String.format('Callout execution completed for phase {0}',
                new String[]{ String.valueOf(phase) }), 'UoWCalloutExecutionService');
        } finally {
            result.endSpan(calloutPhaseSpan, UoWEnums.SpanPhaseResult.SUCCESS,
                String.format(System.Label.UoW_Span_CalloutsCompleted,
                    new String[]{ String.valueOf(callouts.size()) }));
        }
    }

    // ============================================================================
    // PRIVATE METHODS - WORK ITEM EXECUTION
    // ============================================================================

    // Execute a single callout work item.
    private void executeCalloutWorkItem(UoWCalloutWorkItem workItem) {
        // Start work item span (child of CALLOUTS phase span)
        UoWTracer.Span workItemSpan = result.startSpan(workItem, null);

        // Add callout-specific attributes
        workItemSpan?.setAttribute('http.method', workItem.httpMethod);
        workItemSpan?.setAttribute('http.url', workItem.endpoint);

        prepareWorkItem(workItem);

        try {
            executeHttpCallout(workItem);

            // Add response attributes if available
            if (workItem.response != null) {
                workItemSpan?.setAttribute('http.status_code', workItem.response.getStatusCode());
            }

        } catch (Exception ex) {
            workItemSpan?.setAttribute('error', true);
            workItemSpan?.setAttribute('error.message', ex.getMessage());
            handleWorkItemException(workItem, ex);

        } finally {
            finalizeWorkItem(workItem);

            // End work item span with result summary
            result.endSpan(workItemSpan, workItem, null);

            result.addCalloutWork(workItem);
        }
    }

    // ============================================================================
    // PRIVATE METHODS - HTTP EXECUTION
    // ============================================================================

    // Execute HTTP callout (respects dry run mode).
    private void executeHttpCallout(UoWCalloutWorkItem workItem) {
        if (context.isDryRun) {
            result.fine(String.format('Skipping callout in dry run mode: {0} {1}',
                new String[]{ workItem.httpMethod, workItem.endpoint }), 'UoWCalloutExecutionService');
            return;
        }

        result.debug(String.format('Executing callout: {0} {1} (timeout: {2}ms)',
            new String[]{
                workItem.httpMethod,
                workItem.endpoint,
                String.valueOf(workItem.timeoutMs)
            }), 'UoWCalloutExecutionService');

        this.calloutStrategy.executeCallout(workItem, context);

        if (workItem.response != null) {
            result.debug(String.format('Callout response: {0} {1}',
                new String[]{
                    String.valueOf(workItem.response.getStatusCode()),
                    workItem.response.getStatus()
                }), 'UoWCalloutExecutionService');
        }
    }
}