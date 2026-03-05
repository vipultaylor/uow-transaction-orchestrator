//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Flow invocable action to register Flow execution operations in a Unit of Work transaction.
 *
 * Registers autolaunched Flows to be executed as part of the transaction. Enables Flow
 * orchestration where one Flow can trigger others with input parameters.
 *
 * Flow Pattern (Simple):
 * [Register Flow Execution]
 *   Transaction ID: {!transactionId}
 *   Flow API Name: MyAutolauchedFlow
 *
 * Flow Pattern (With Inputs):
 * [Register Flow Execution]
 *   Transaction ID: {!transactionId}
 *   Flow API Name: ProcessRecordFlow
 *   Flow Input Variables: {"recordId":"{!recordId}","status":"Active"}
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Flow Actions
 * @see UoWFlowInitializeAction
 * @see UoWFlowCommitAction
 */
public inherited sharing class UoWFlowRegisterFlowExecutionAction {
    // ============================================================================
    // INVOCABLE METHOD
    // ============================================================================

    /**
     * Register Flow execution for running in Unit of Work transaction
     *
     * @param requests List of Flow execution registration requests (Flow passes single-item list)
     * @return List of registration results
     */
    @InvocableMethod(
        label='UoW: Register Flow Execution'
        description='Register autolaunched Flow to be executed as part of Unit of Work transaction'
        category='Unit of Work'
    )
    public static List<RegistrationResult> registerFlowExecution(List<RegistrationRequest> requests) {
        List<RegistrationResult> results = new List<RegistrationResult>();

        for (RegistrationRequest request : requests) {
            RegistrationResult result = new RegistrationResult();

            try {
                // Validate inputs
                UoWExceptionService.requireNonBlank(request.transactionId, 'Transaction ID');
                UoWExceptionService.requireNonBlank(request.flowApiName, 'Flow API Name');

                // Retrieve UnitOfWork instance
                UnitOfWork uow = UoWFlowTransactionRegistry.get(request.transactionId);

                // Parse execution phase (if specified)
                UoWEnums.WorkPhase phase = String.isNotBlank(request.executionPhase)
                    ? UoWFlowActionHelpers.parseWorkPhase(request.executionPhase)
                    : null;

                // Register Flow execution with phase (or use default)
                UoWFlowWorkItem workItem = uow.registerFlowExecution(request.flowApiName, phase);

                // Set Flow origin for audit tracking
                if (String.isNotBlank(request.flowName)) {
                    workItem.withOrigin(UoWFlowActionHelpers.ORIGIN_TYPE_FLOW, request.flowName);
                }

                // Configure error handling mode
                if (request.continueOnError != null) {
                    workItem.continueOnError = request.continueOnError;
                }

                // Set input variables from JSON
                if (String.isNotBlank(request.flowInputVariablesJson)) {
                    Map<String, Object> inputs = (Map<String, Object>)JSON.deserializeUntyped(request.flowInputVariablesJson);
                    for (String varName : inputs.keySet()) {
                        workItem.withInput(varName, inputs.get(varName));
                    }
                }

                // Success
                result.success = true;
                result.workItemId = workItem.workId;
                result.message = String.format('Flow execution registered: {0}',
                    new String[]{ request.flowApiName });

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
     * Input parameters for Flow execution registration
     */
    public class RegistrationRequest {
        @InvocableVariable(
            label='Transaction ID'
            description='Transaction ID from Initialize Transaction action'
            required=true
        )
        public String transactionId;

        @InvocableVariable(
            label='Flow API Name'
            description='API name of the autolaunched Flow to execute'
            required=true
        )
        public String flowApiName;

        @InvocableVariable(
            label='Flow Input Variables (JSON)'
            description='Flow input variables as JSON object: {"variableName":"value","recordId":"00Qxx000000xxxx"}'
        )
        public String flowInputVariablesJson;

        @InvocableVariable(
            label='Execution Phase'
            description='When to execute Flow: PRE_DML, POST_DML (default), ON_SUCCESS, ON_FAILURE, ON_FINALIZATION'
        )
        public String executionPhase;

        @InvocableVariable(
            label='Continue On Error'
            description='Continue transaction if Flow fails (default: false for Flows)'
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
     * Output results from Flow execution registration
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