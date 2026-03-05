//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Flow invocable action to register upsert operations in a Unit of Work transaction.
 *
 * Registers one or more records for upsert (insert if new, update if exists). Requires an
 * external ID field to determine whether records already exist.
 *
 * Flow Pattern (Simple):
 * [Register Upsert: Accounts]
 *   Transaction ID: {!transactionId}
 *   Records: {!AccountCollection}
 *   External ID Field: External_Id__c
 *
 * Example Upsert with relationship:
 * [Register Upsert: Accounts] → workItemId
 * [Register Insert: Contacts]
 *   Parent Work Item ID: {!workItemId}
 *   Relationship Field: AccountId
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Flow Actions
 * @see UoWFlowInitializeAction
 * @see UoWFlowCommitAction
 * @see UoWFlowDmlWorkItemRegistry
 */
public inherited sharing class UoWFlowRegisterUpsertAction {
    // ============================================================================
    // INVOCABLE METHOD
    // ============================================================================

    /**
     * Register records for upsert in Unit of Work transaction
     *
     * @param requests List of upsert registration requests (Flow passes single-item list)
     * @return List of registration results with work item ID
     */
    @InvocableMethod(
        label='UoW: Register Upsert'
        description='Register records for upsert operation (insert or update) in Unit of Work transaction'
        category='Unit of Work'
    )
    public static List<RegistrationResult> registerUpsert(List<RegistrationRequest> requests) {
        List<RegistrationResult> results = new List<RegistrationResult>();

        for (RegistrationRequest request : requests) {
            RegistrationResult result = new RegistrationResult();

            try {
                // Validate inputs
                UoWExceptionService.requireNonBlank(request.transactionId, 'Transaction ID');
                UoWExceptionService.requireNonEmpty((List<Object>)request.records, 'Records');
                UoWExceptionService.requireNonBlank(request.externalIdField, 'External ID Field');

                // Retrieve UnitOfWork instance
                UnitOfWork uow = UoWFlowTransactionRegistry.get(request.transactionId);

                // Resolve external ID field
                Schema.SObjectField externalIdFieldObj = UoWFlowActionHelpers.resolveFieldFromRecords(
                    request.records,
                    request.externalIdField
                );

                // Register upsert operation - returns work item directly
                UoWDmlWorkItem workItem = uow.registerUpsert(request.records, externalIdFieldObj);

                // Set Flow origin for audit tracking
                if (String.isNotBlank(request.flowName)) {
                    workItem.withOrigin(UoWFlowActionHelpers.ORIGIN_TYPE_FLOW, request.flowName);
                }

                // Configure error handling mode
                if (request.continueOnError != null) {
                    workItem.continueOnError = request.continueOnError;
                }

                // Establish relationship if parent specified
                if (String.isNotBlank(request.parentWorkItemId)) {
                    UoWExceptionService.requireNonBlank(request.relationshipField, 'Relationship Field');

                    // Retrieve parent record from registry
                    SObject parentRecord = UoWFlowDmlWorkItemRegistry.getParentRecord(request.parentWorkItemId);

                    // Resolve relationship field
                    Schema.SObjectField field = UoWFlowActionHelpers.resolveFieldFromRecords(
                        request.records,
                        request.relationshipField
                    );

                    // Establish relationship using UnitOfWork.relate()
                    uow.relate(request.records, field, parentRecord);
                }

                // Register records in Flow registry for downstream relationships
                String workItemId = UoWFlowDmlWorkItemRegistry.register(request.records);

                // Success
                result.success = true;
                result.workItemId = workItemId;
                result.message = String.format('{0} record(s) registered for upsert',
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
     * Input parameters for upsert registration
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
            description='Records to upsert (must all be same SObject type)'
            required=true
        )
        public List<SObject> records;

        @InvocableVariable(
            label='External ID Field'
            description='External ID field to use for matching (e.g., External_Id__c, Email). Required for upsert.'
            required=true
        )
        public String externalIdField;

        @InvocableVariable(
            label='Continue On Error'
            description='Allow partial success - some records can fail without failing entire transaction (default: false)'
        )
        public Boolean continueOnError;

        // ========================================================================
        // RELATIONSHIP FIELDS (Optional)
        // ========================================================================

        @InvocableVariable(
            label='Parent Work Item ID'
            description='Work Item ID from parent registration action (for establishing relationships)'
        )
        public String parentWorkItemId;

        @InvocableVariable(
            label='Relationship Field'
            description='Field on child record pointing to parent (e.g., AccountId on Contact). Required if Parent Work Item ID is specified.'
        )
        public String relationshipField;

        @InvocableVariable(
            label='Origin Flow Name'
            description='Name of the calling Flow (for audit origin tracking). Due to Salesforce limitations, this cannot be automatically determined.'
            required=true
        )
        public String flowName;
    }

    /**
     * Output results from upsert registration
     */
    public class RegistrationResult {
        @InvocableVariable(
            label='Success'
            description='True if registration succeeded'
        )
        public Boolean success;

        @InvocableVariable(
            label='Work Item ID'
            description='Unique ID for this work item - use as Parent Work Item ID in child registration actions'
        )
        public String workItemId;

        @InvocableVariable(
            label='Message'
            description='Success or error message'
        )
        public String message;
    }
}