//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Custom Notification work item for sending notifications.
 * Contains notification details.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Work Items
 * @see UoWWorkItem
 * @see UoWNotificationExecutionService
 */
public inherited sharing class UoWNotificationWorkItem extends UoWWorkItem {

    // ============================================================================
    // PUBLIC PROPERTIES - EXECUTION
    // ============================================================================

    public UoWEnums.WorkPhase executionPhase;


    // ============================================================================
    // PUBLIC PROPERTIES - NOTIFICATION DATA
    // ============================================================================

    public String customNotifTypeId;
    public String customNotifTypeName;
    public Set<String> recipientIds;
    public String title;
    public String body;
    public String targetId;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Create a new Notification work item.
     *
     * @param phase Execution phase (POST_DML, ON_SUCCESS, ON_FAILURE, ON_FINALIZATION)
     */
    public UoWNotificationWorkItem(UoWEnums.WorkPhase phase) {
        super(UoWEnums.WorkType.NOTIFICATION);
        this.executionPhase = phase ?? UoWEnums.WorkPhase.ON_SUCCESS;
        this.recipientIds = new Set<String>();
        this.statistics.planned = 1;
        this.continueOnError = true;
    }

    // ============================================================================
    // PUBLIC API - FLUENT CONFIGURATION
    // ============================================================================

    /**
     * Set custom notification type ID and name.
     *
     * @param notifTypeId Custom notification type ID
     * @param notifTypeName Custom notification type developer name (for display/audit)
     * @return This work item for fluent chaining
     */
    public UoWNotificationWorkItem withNotificationType(String notifTypeId, String notifTypeName) {
        this.customNotifTypeId = notifTypeId;
        this.customNotifTypeName = notifTypeName;
        return this;
    }

    /**
     * Add a single recipient user ID.
     *
     * @param userId User ID to notify
     * @return This work item for fluent chaining
     */
    public UoWNotificationWorkItem withRecipient(String userId) {
        this.recipientIds.add(userId);
        return this;
    }

    /**
     * Add multiple recipient user IDs.
     *
     * @param userIds Set of user IDs to notify
     * @return This work item for fluent chaining
     */
    public UoWNotificationWorkItem withRecipients(Set<String> userIds) {
        if (userIds != null) {
            this.recipientIds.addAll(userIds);
        }
        return this;
    }

    /**
     * Set notification title.
     *
     * @param notifTitle Notification title
     * @return This work item for fluent chaining
     */
    public UoWNotificationWorkItem withTitle(String notifTitle) {
        this.title = notifTitle;
        return this;
    }

    /**
     * Set notification body.
     *
     * @param notifBody Notification body text
     * @return This work item for fluent chaining
     */
    public UoWNotificationWorkItem withBody(String notifBody) {
        this.body = notifBody;
        return this;
    }

    /**
     * Set target record ID for navigation.
     *
     * @param recordId Target record ID to navigate to when notification is clicked
     * @return This work item for fluent chaining
     */
    public UoWNotificationWorkItem withTargetId(String recordId) {
        this.targetId = recordId;
        return this;
    }

    /**
     * Continue execution even if notification fails (default behavior for notifications).
     *
     * @return This work item for fluent chaining
     */
    public UoWNotificationWorkItem continueOnError() {
        this.continueOnError = true;
        return this;
    }

    /**
     * Fail-fast if notification fails (override default for critical notifications).
     *
     * @return This work item for fluent chaining
     */
    public UoWNotificationWorkItem failFast() {
        this.continueOnError = false;
        return this;
    }

}