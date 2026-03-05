//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Flow invocable action to register delete operations in a Unit of Work transaction.
 *
 * Registers one or more existing records for deletion. Records must have Id field populated.
 * Like updates, relationships are not applicable for deletes.
 *
 * Flow Pattern (Simple):
 * [Get Records] → RecordsToDelete
 * [Register Delete: Records]
 *   Transaction ID: {!transactionId}
 *   Records: {!RecordsToDelete}
 *
 * Example Delete with Continue On Error:
 * [Register Delete: Contacts]
 *   Transaction ID: {!transactionId}
 *   Records: {!ContactsToDelete}
 *   Continue On Error: true
 * → Allows partial success (some deletes may fail due to references)
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Flow Actions
 * @see UoWFlowInitializeAction
 * @see UoWFlowCommitAction
 */
public inherited sharing class UoWFlowRegisterDeleteAction {
    // ============================================================================
    // INVOCABLE METHOD
    // ============================================================================

    /**
     * Register records for delete in Unit of Work transaction
     *
     * @param requests List of delete registration requests (Flow passes single-item list)
     * @return List of registration results with work item ID
     */
    @InvocableMethod(
        label='UoW: Register Delete'
        description='Register records for delete operation in Unit of Work transaction'
        category='Unit of Work'
    )
    public static List<RegistrationResult> registerDelete(List<RegistrationRequest> requests) {
        List<RegistrationResult> results = new List<RegistrationResult>();

        for (RegistrationRequest request : requests) {
            RegistrationResult result = new RegistrationResult();

            try {
                // Validate inputs
                UoWExceptionService.requireNonBlank(request.transactionId, 'Transaction ID');
                UoWExceptionService.requireNonEmpty(request.records, 'Records');

                // Validate records have IDs
                for (SObject record : request.records) {
                    if (record.Id == null) {
                        throw new UoWExceptionService.UoWException('Cannot delete records without Id field. Ensure records are queried or have Id populated.');
                    }
                }

                // Retrieve UnitOfWork instance
                UnitOfWork uow = UoWFlowTransactionRegistry.get(request.transactionId);

                // Register delete operation - returns work item directly
                UoWDmlWorkItem workItem = uow.registerDelete(request.records);

                // Set Flow origin for audit tracking
                if (String.isNotBlank(request.flowName)) {
                    workItem.withOrigin(UoWFlowActionHelpers.ORIGIN_TYPE_FLOW, request.flowName);
                }

                // Configure error handling mode
                if (request.continueOnError != null) {
                    workItem.continueOnError = request.continueOnError;
                }

                // Register records in Flow registry for downstream relationships
                String workItemId = UoWFlowDmlWorkItemRegistry.register(request.records);

                // Success
                result.success = true;
                result.workItemId = workItemId;
                result.message = String.format('{0} record(s) registered for delete',
                    new String[]{ String.valueOf(request.records.size()) });

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
     * Input parameters for delete registration
     */
    public class RegistrationRequest {
        @InvocableVariable(
            label='Transaction ID'
            description='Transaction ID from Initialize Transaction action'
            required=true
        )
        public String transactionId;

        @InvocableVariable(
            label='Records'
            description='Records to delete (must have Id field populated, must all be same SObject type)'
            required=true
        )
        public List<SObject> records;

        @InvocableVariable(
            label='Continue On Error'
            description='Allow partial success - some records can fail without failing entire transaction (default: false)'
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
     * Output results from delete registration
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