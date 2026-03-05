//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Executes email sending work items.
 *
 * Responsibilities:
 * - Send emails for specified execution phases
 * - Respect continueOnError flag (default: true for emails)
 *
 * Design Note:
 * - Email work item is singleton per phase (not per-email)
 * - Single EmailWorkItem contains multiple emails
 *
 * Execution Phases:
 * - PRE_DML: Emails sent before DML operations
 * - POST_DML: Emails sent after DML operations
 * - ON_SUCCESS: Emails sent on successful transaction
 * - ON_FAILURE: Emails sent on transaction failure
 * - ON_FINALIZATION: Emails sent during finalization
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Execution
 * @see UoWWorkItemExecutor
 * @see UoWEmailChannelResolver
 */
@SuppressWarnings('PMD.CognitiveComplexity')
public inherited sharing class UoWEmailExecutionService extends UoWWorkItemExecutor {

    // ============================================================================
    // PRIVATE FIELDS
    // ============================================================================

    // Email channel resolved for this execution
    private UoWInterfaces.IEmailChannel emailChannel;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Constructor passing the relevant context for executing email sends.
     *
     * @param ctx Context instance
     * @param plan Plan that contains email work items
     * @param result Result instance initialized for this execution
     */
    public UoWEmailExecutionService(UoWContext ctx, UoWPlan plan, UoWResult result) {
        super(ctx, plan, result);
    }

    // ============================================================================
    // PUBLIC API - EXECUTION
    // ============================================================================

    /**
     * Execute emails for a specific phase.
     *
     * @param phase The execution phase
     */
    public override void execute(UoWEnums.WorkPhase phase) {
        UoWEmailWorkItem workItem = plan.getEmailWork(phase);
        List<Messaging.Email> emails = workItem?.getEmails();
        if (emails == null || emails.isEmpty()) {
            result.debug(String.format('{0} phase: No emails to execute - skipping email phase',
                new String[]{ String.valueOf(phase) }), 'UoWEmailExecutionService');
            return;
        }

        result.info(String.format('{0} email execution started - {1} email(s)',
            new String[]{ String.valueOf(phase), String.valueOf(emails.size()) }), 'UoWEmailExecutionService');

        this.emailChannel = UoWEmailChannelResolver.resolve(context, result);

        executeEmailWorkItem(workItem);

        result.info(String.format('{0} email execution completed',
            new String[]{ String.valueOf(phase) }), 'UoWEmailExecutionService');
    }

    // ============================================================================
    // PRIVATE METHODS - WORK ITEM EXECUTION
    // ============================================================================

    // Execute a single email work item.
    private void executeEmailWorkItem(UoWEmailWorkItem workItem) {
        // Start work item span (child of phase span)
        UoWTracer.Span workItemSpan = result.startSpan(workItem, null);

        // Add email-specific attributes
        List<Messaging.Email> emails = workItem.getEmails();
        workItemSpan?.setAttribute('email.count', emails?.size() ?? 0);

        prepareWorkItem(workItem);

        try {
            if (!context.isDryRun) {
                result.debug(String.format('Sending {0} email(s) - workId: {1}',
                    new String[]{
                        String.valueOf(emails?.size() ?? 0),
                        workItem.workId
                    }), 'UoWEmailExecutionService');

                this.emailChannel.sendEmails(workItem, context);
            } else {
                result.fine(String.format('Skipping email send in dry run mode - workId: {0}',
                    new String[]{ workItem.workId }), 'UoWEmailExecutionService');
            }

        } catch (Exception ex) {
            workItemSpan?.setAttribute('error', true);
            workItemSpan?.setAttribute('error.message', ex.getMessage());
            handleWorkItemException(workItem, ex);

        } finally {
            finalizeWorkItem(workItem);

            // End work item span with result summary
            result.endSpan(workItemSpan, workItem, null);

            result.addEmailWork(workItem);
        }
    }
}