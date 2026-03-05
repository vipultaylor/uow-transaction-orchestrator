//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Flow invocable action to register platform event publishing in a Unit of Work transaction.
 *
 * Registers platform events to be published as part of the transaction. Events are published
 * in the specified execution phase (default: POST_DML).
 *
 * Flow Pattern (Simple):
 * [Create Platform Event Record] → eventRecord
 * [Register Platform Event]
 *   Transaction ID: {!transactionId}
 *   Platform Events: {!eventRecord}
 *
 * Example Publishing after DML:
 * [Register Insert: Accounts]
 * [Create RecordCreated__e Event]
 *   RecordId__c: {!AccountId}
 *   ObjectType__c: Account
 * [Register Platform Event]
 *   Execution Phase: POST_DML
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Flow Actions
 * @see UoWFlowInitializeAction
 * @see UoWFlowCommitAction
 */
public inherited sharing class UoWFlowRegisterPlatformEventAction {
    // ============================================================================
    // INVOCABLE METHOD
    // ============================================================================

    /**
     * Register platform events for publishing in Unit of Work transaction
     *
     * @param requests List of event registration requests (Flow passes single-item list)
     * @return List of registration results
     */
    @InvocableMethod(
        label='UoW: Register Platform Event'
        description='Register platform events to be published as part of Unit of Work transaction'
        category='Unit of Work'
    )
    public static List<RegistrationResult> registerPlatformEvent(List<RegistrationRequest> requests) {
        List<RegistrationResult> results = new List<RegistrationResult>();

        for (RegistrationRequest request : requests) {
            RegistrationResult result = new RegistrationResult();

            try {
                // Validate inputs
                UoWExceptionService.requireNonBlank(request.transactionId, 'Transaction ID');
                UoWExceptionService.requireNonEmpty((List<Object>)request.platformEvents, 'Platform Events');

                // Retrieve UnitOfWork instance
                UnitOfWork uow = UoWFlowTransactionRegistry.get(request.transactionId);

                // Parse execution phase (if specified)
                UoWEnums.WorkPhase phase = String.isNotBlank(request.executionPhase)
                    ? UoWFlowActionHelpers.parseWorkPhase(request.executionPhase)
                    : null;

                // Register platform events with phase (or use default)
                UoWEventWorkItem workItem = uow.registerPlatformEvent(request.platformEvents, phase);

                // Set Flow origin for audit tracking
                if (String.isNotBlank(request.flowName)) {
                    workItem.withOrigin(UoWFlowActionHelpers.ORIGIN_TYPE_FLOW, request.flowName);
                }

                // Configure error handling mode
                if (request.continueOnError != null) {
                    workItem.continueOnError = request.continueOnError;
                }

                // Success
                result.success = true;
                result.workItemId = workItem.workId;
                result.message = String.format('{0} platform event(s) registered for publishing',
                    new String[]{ String.valueOf(request.platformEvents.size()) });

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
     * Input parameters for platform event registration
     */
    public class RegistrationRequest {
        @InvocableVariable(
            label='Transaction ID'
            description='Transaction ID from Initialize Transaction action'
            required=true
        )
        public String transactionId;

        @InvocableVariable(
            label='Platform Events'
            description='Platform event records to publish (e.g., RecordCreated__e)'
            required=true
        )
        public List<SObject> platformEvents;

        @InvocableVariable(
            label='Execution Phase'
            description='When to publish events: PRE_DML, POST_DML (default), ON_SUCCESS, ON_FAILURE, ON_FINALIZATION'
        )
        public String executionPhase;

        @InvocableVariable(
            label='Continue On Error'
            description='Continue transaction if event publishing fails (default: false for events)'
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
     * Output results from platform event registration
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