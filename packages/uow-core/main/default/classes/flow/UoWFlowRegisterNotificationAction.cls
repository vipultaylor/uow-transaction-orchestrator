//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Flow invocable action to register custom notification operations in a Unit of Work transaction.
 *
 * Registers Salesforce custom notifications to be sent as part of the transaction.
 * Custom notifications appear in the bell icon and can navigate to specific records.
 *
 * Flow Pattern (Simple):
 * [Register Notification]
 *   Transaction ID: {!transactionId}
 *   Notification Type Id: {!notificationTypeId}
 *   Notification Type Name: MyNotificationType
 *   Recipient User ID: {!userId}
 *   Title: Record Updated
 *   Body: Your record has been updated successfully.
 *   Target Record ID: {!recordId}
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Flow Actions
 * @see UoWFlowInitializeAction
 * @see UoWFlowCommitAction
 */
public inherited sharing class UoWFlowRegisterNotificationAction {
    // ============================================================================
    // INVOCABLE METHOD
    // ============================================================================

    /**
     * Register custom notification for sending in Unit of Work transaction
     *
     * @param requests List of notification registration requests (Flow passes single-item list)
     * @return List of registration results
     */
    @InvocableMethod(
        label='UoW: Register Notification'
        description='Register custom notification to be sent as part of Unit of Work transaction'
        category='Unit of Work'
    )
    public static List<RegistrationResult> registerNotification(List<RegistrationRequest> requests) {
        List<RegistrationResult> results = new List<RegistrationResult>();

        for (RegistrationRequest request : requests) {
            RegistrationResult result = new RegistrationResult();

            try {
                // Validate inputs
                UoWExceptionService.requireNonBlank(request.transactionId, 'Transaction ID');
                UoWExceptionService.requireNonBlank(request.notificationTypeId, 'Notification Type Id');
                UoWExceptionService.requireNonBlank(request.notificationTypeName, 'Notification Type Name');
                UoWExceptionService.requireNonBlank(request.title, 'Title');
                UoWExceptionService.requireNonBlank(request.body, 'Body');
                UoWExceptionService.requireNonEmpty(request.recipientUserIds, 'Recipient Ids');

                // Retrieve UnitOfWork instance
                UnitOfWork uow = UoWFlowTransactionRegistry.get(request.transactionId);

                // Parse execution phase (if specified)
                UoWEnums.WorkPhase phase = String.isNotBlank(request.executionPhase)
                    ? UoWFlowActionHelpers.parseWorkPhase(request.executionPhase)
                    : null;

                // Register notification with phase (or use default)
                UoWNotificationWorkItem workItem = uow.registerNotification(phase);

                // Set Flow origin for audit tracking
                if (String.isNotBlank(request.flowName)) {
                    workItem.withOrigin(UoWFlowActionHelpers.ORIGIN_TYPE_FLOW, request.flowName);
                }

                // Configure error handling mode
                if (request.continueOnError != null) {
                    workItem.continueOnError = request.continueOnError;
                }

                // Set notification details
                workItem.withNotificationType(request.notificationTypeId, request.notificationTypeName)
                    .withRecipients(new Set<String>(request.recipientUserIds))
                    .withTitle(request.title)
                    .withBody(request.body);

                // Set target record
                if (String.isNotBlank(request.targetRecordId)) {
                    workItem.withTargetId(request.targetRecordId);
                }

                // Success
                result.success = true;
                result.workItemId = workItem.workId;
                result.message = 'Notification registered successfully';

            } catch (Exception ex) {
                result.success = false;
                result.message = UoWFlowActionHelpers.formatException(ex);
            }

            results.add(result);
        }

        return results;
    }

    // ============================================================================
    // INNER CLASSES - REQUEST/RESPONSE
    // ============================================================================

    /**
     * Input parameters for notification registration
     */
    public class RegistrationRequest {
        @InvocableVariable(
            label='Transaction ID'
            description='Transaction ID from Initialize Transaction action'
            required=true
        )
        public String transactionId;

        @InvocableVariable(
            label='Notification Type Id'
            description='Custom Notification Type Id (from Setup > Custom Notifications)'
            required=true
        )
        public String notificationTypeId;

        @InvocableVariable(
            label='Notification Type Name'
            description='Custom Notification Type Developer Name (for display/audit)'
            required=true
        )
        public String notificationTypeName;

        // ========================================================================
        // RECIPIENTS
        // ========================================================================

        @InvocableVariable(
            label='Recipient User IDs'
            description='User IDs for multiple recipients'
            required=true
        )
        public List<String> recipientUserIds;

        // ========================================================================
        // CONTENT
        // ========================================================================

        @InvocableVariable(
            label='Title'
            description='Notification title'
            required=true
        )
        public String title;

        @InvocableVariable(
            label='Body'
            description='Notification body text'
            required=true
        )
        public String body;

        @InvocableVariable(
            label='Target Record ID'
            description='Record ID to navigate to when notification is clicked'
        )
        public String targetRecordId;

        // ========================================================================
        // OPTIONS
        // ========================================================================

        @InvocableVariable(
            label='Execution Phase'
            description='When to send notification: POST_DML, ON_SUCCESS (default), ON_FAILURE, ON_FINALIZATION'
        )
        public String executionPhase;

        @InvocableVariable(
            label='Continue On Error'
            description='Continue transaction if notification fails'
        )
        public Boolean continueOnError;

        @InvocableVariable(
            label='Origin Flow Name'
            description='Name of the calling Flow (for audit origin tracking). Due to Salesforce limitations, this cannot be automatically determined.'
            required=true
        )
        public String flowName;
    }

    /**
     * Output results from notification registration
     */
    public class RegistrationResult {
        @InvocableVariable(
            label='Success'
            description='True if registration succeeded'
        )
        public Boolean success;

        @InvocableVariable(
            label='Work Item ID'
            description='Unique ID for this work item'
        )
        public String workItemId;

        @InvocableVariable(
            label='Message'
            description='Success or error message'
        )
        public String message;
    }
}