//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Executes custom notification work items.
 *
 * Responsibilities:
 * - Send custom notifications for specified execution phases
 * - Respect continueOnError flag (default: true for notifications)
 *
 * Design Note:
 * - Notifications use CustomNotificationsHandler (not API like emails)
 * - Each NotificationWorkItem represents a single notification
 * - Multiple notifications can be registered per phase
 *
 * Execution Phases:
 * - PRE_DML: Notifications sent before DML operations
 * - POST_DML: Notifications sent after DML operations
 * - ON_SUCCESS: Notifications sent on successful transaction
 * - ON_FAILURE: Notifications sent on transaction failure
 * - ON_FINALIZATION: Notifications sent during finalization
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Execution
 * @see UoWWorkItemExecutor
 * @see UoWNotificationChannelResolver
 */
public inherited sharing class UoWNotificationExecutionService extends UoWWorkItemExecutor {

    // ============================================================================
    // PRIVATE FIELDS
    // ============================================================================

    // Notification channel resolved for this execution
    private UoWInterfaces.INotificationChannel notificationChannel;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Constructor passing the relevant context for executing custom notifications.
     *
     * @param ctx Context instance
     * @param plan Plan that contains notification work items
     * @param result Result instance initialized for this execution
     */
    public UoWNotificationExecutionService(UoWContext ctx, UoWPlan plan, UoWResult result) {
        super(ctx, plan, result);
    }

    // ============================================================================
    // PUBLIC API - EXECUTION
    // ============================================================================

    /**
     * Execute notifications for a specific phase.
     *
     * @param phase The execution phase
     */
    public override void execute(UoWEnums.WorkPhase phase) {
        List<UoWNotificationWorkItem> notificationWork = plan.getNotificationWork(phase);
        if (notificationWork == null || notificationWork.isEmpty()) {
            result.debug(String.format('No notifications to execute for {0} phase - skipping notification phase',
                new String[]{ String.valueOf(phase) }), 'UoWNotificationExecutionService');
            return;
        }

        result.info(String.format('{0} notification execution started - {1} notification(s)',
            new String[]{ String.valueOf(phase), String.valueOf(notificationWork.size()) }), 'UoWNotificationExecutionService');

        this.notificationChannel = UoWNotificationChannelResolver.resolve(context, result);

        for (UoWNotificationWorkItem workItem : notificationWork) {
            executeNotificationWorkItem(workItem);
        }

        result.info(String.format('{0} notification execution completed',
            new String[]{ String.valueOf(phase) }), 'UoWNotificationExecutionService');
    }

    // ============================================================================
    // PRIVATE METHODS - WORK ITEM EXECUTION
    // ============================================================================

    // Execute a single notification work item.
    private void executeNotificationWorkItem(UoWNotificationWorkItem workItem) {
        // Start work item span (child of phase span)
        UoWTracer.Span workItemSpan = result.startSpan(workItem, null);

        // Add notification-specific attributes
        workItemSpan?.setAttribute('notification.type', workItem.customNotifTypeName);
        workItemSpan?.setAttribute('notification.recipients', workItem.recipientIds?.size() ?? 0);

        prepareWorkItem(workItem);

        try {
            if (!context.isDryRun) {
                result.debug(String.format('Sending notification - workId: {0}, recipients: {1}',
                    new String[]{
                        workItem.workId,
                        String.valueOf(workItem.recipientIds.size())
                    }), 'UoWNotificationExecutionService');

                this.notificationChannel.sendNotification(workItem, context);
            } else {
                result.fine(String.format('Skipping notification in dry run mode - workId: {0}, recipients: {1}',
                    new String[]{
                        workItem.workId,
                        String.valueOf(workItem.recipientIds.size())
                    }), 'UoWNotificationExecutionService');
            }

        } catch (Exception ex) {
            workItemSpan?.setAttribute('error', true);
            workItemSpan?.setAttribute('error.message', ex.getMessage());
            handleWorkItemException(workItem, ex);

        } finally {
            finalizeWorkItem(workItem);

            // End work item span with result summary
            result.endSpan(workItemSpan, workItem, null);

            result.addNotificationWork(workItem);
        }
    }
}