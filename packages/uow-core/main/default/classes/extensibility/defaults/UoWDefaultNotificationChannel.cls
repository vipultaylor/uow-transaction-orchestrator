//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Default channel for sending custom notifications via Messaging API.
 * Maintains current behavior of direct Messaging.CustomNotification calls.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWInterfaces.INotificationChannel
 */
public inherited sharing class UoWDefaultNotificationChannel implements UoWInterfaces.INotificationChannel {

    // ============================================================================
    // PUBLIC API - INTERFACE IMPLEMENTATION
    // ============================================================================

    /**
     * Get channel name.
     *
     * @return Channel name
     */
    public String getName() {
        return 'Default Custom Notifications';
    }

    /**
     * Send custom notification via Messaging API.
     *
     * @param workItem The notification work item to execute
     * @param ctx The execution context
     */
    public void sendNotification(UoWNotificationWorkItem workItem, UoWContext ctx) {
        // Notification sending logic
        if (String.isNotBlank(workItem.customNotifTypeId)) {
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setNotificationTypeId(workItem.customNotifTypeId);
            notification.setTitle(workItem.title);
            notification.setBody(workItem.body);

            if (String.isNotBlank(workItem.targetId)) {
                notification.setTargetId(workItem.targetId);
            }

            notification.send(workItem.recipientIds);
        }
    }
}