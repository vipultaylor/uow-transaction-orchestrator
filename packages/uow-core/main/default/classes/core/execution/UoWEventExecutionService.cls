//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Executes platform event publishing work items.
 *
 * Responsibilities:
 * - Publish platform events for specified execution phases
 * - Respect continueOnError flag for resilient vs fail-fast behavior
 *
 * Execution Phases:
 * - PRE_DML: Events published before DML operations
 * - POST_DML: Events published after DML operations
 * - ON_SUCCESS: Events published on successful transaction
 * - ON_FAILURE: Events published on transaction failure
 * - ON_FINALIZATION: Events published during finalization
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Execution
 * @see UoWWorkItemExecutor
 * @see UoWEventChannelResolver
 */
public inherited sharing class UoWEventExecutionService extends UoWWorkItemExecutor {

    // ============================================================================
    // PRIVATE FIELDS
    // ============================================================================

    // Event channel resolved for this execution
    private UoWInterfaces.IEventChannel eventChannel;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Constructor passing the relevant context for executing platform events.
     *
     * @param ctx Context instance
     * @param plan Plan that contains platform event work items
     * @param result Result instance initialized for this execution
     */
    public UoWEventExecutionService(UoWContext ctx, UoWPlan plan, UoWResult result) {
        super(ctx, plan, result);
    }

    // ============================================================================
    // PUBLIC API - EXECUTION
    // ============================================================================

    /**
     * Execute platform events for a specific phase.
     *
     * @param phase The execution phase
     */
    public override void execute(UoWEnums.WorkPhase phase) {
        List<UoWEventWorkItem> eventWork = plan.getEventWork(phase);
        if (eventWork == null || eventWork.isEmpty()) {
            result.debug(String.format('No events to execute for phase {0} - skipping phase',
                new String[]{ String.valueOf(phase) }), 'UoWEventExecutionService');
            return;
        }

        result.info(String.format('Event execution started - {0} event(s) for phase {1}',
            new String[]{ String.valueOf(eventWork.size()), String.valueOf(phase) }), 'UoWEventExecutionService');

        this.eventChannel = UoWEventChannelResolver.resolve(context, result);

        for (UoWEventWorkItem workItem : eventWork) {
            executeEventWorkItem(workItem);
        }

        result.info(String.format('Event execution completed for phase {0}',
            new String[]{ String.valueOf(phase) }), 'UoWEventExecutionService');
    }

    // ============================================================================
    // PRIVATE METHODS - WORK ITEM EXECUTION
    // ============================================================================

    // Execute a single event work item.
    private void executeEventWorkItem(UoWEventWorkItem workItem) {
        // Start work item span (child of phase span)
        UoWTracer.Span workItemSpan = result.startSpan(workItem, null);

        // Get events using accessor method
        List<SObject> events = workItem.getOriginalEvents();

        // Add event-specific attributes
        workItemSpan?.setAttribute('event.type', workItem.sobjectTypeName);
        workItemSpan?.setAttribute('event.count', events?.size() ?? 0);

        prepareWorkItem(workItem);

        try {
            if (!context.isDryRun) {
                result.debug(String.format('Publishing {0} event(s) - workId: {1}',
                    new String[]{
                        String.valueOf(events.size()),
                        workItem.workId
                    }), 'UoWEventExecutionService');

                this.eventChannel.publishEvents(workItem, context);
            } else {
                result.fine(String.format('Skipping event publishing in dry run mode - workId: {0}',
                    new String[]{ workItem.workId }), 'UoWEventExecutionService');
            }

        } catch (Exception ex) {
            workItemSpan?.setAttribute('error', true);
            workItemSpan?.setAttribute('error.message', ex.getMessage());
            handleWorkItemException(workItem, ex);

        } finally {
            finalizeWorkItem(workItem);

            // End work item span with result summary
            result.endSpan(workItemSpan, workItem, null);

            result.addEventWork(workItem);
        }
    }
}