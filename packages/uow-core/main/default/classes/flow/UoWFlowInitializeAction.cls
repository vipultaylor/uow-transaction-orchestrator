//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Flow invocable action to initialize a Unit of Work transaction.
 *
 * This is the first action in the Flow UoW pattern. It creates a UnitOfWork instance,
 * applies configuration settings, and returns a transaction ID that subsequent actions
 * use to register work items.
 *
 * Flow Pattern:
 * 1. Initialize Transaction → returns transactionId
 * 2. Register Insert/Update/Delete (using transactionId)
 * 3. Commit Transaction (using transactionId)
 *
 * Example Basic Flow usage:
 * [Initialize Transaction]
 *   Configuration Name: Default
 *   ↓ outputs: transactionId
 * [Register Insert: Accounts]
 *   Transaction ID: {!transactionId}
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Flow Actions
 * @see UoWFlowCommitAction
 * @see UoWFlowRegisterInsertAction
 * @see UoWFlowTransactionRegistry
 */
public inherited sharing class UoWFlowInitializeAction {
    // ============================================================================
    // INVOCABLE METHOD
    // ============================================================================

    /**
     * Initialize a new Unit of Work transaction
     *
     * @param requests List of initialization requests (Flow passes single-item list)
     * @return List of initialization results with transaction ID
     */
    @InvocableMethod(
        label='UoW: Initialize Transaction'
        description='Initialize a new Unit of Work transaction for registering DML and other operations'
        category='Unit of Work'
    )
    public static List<InitializeResult> initialize(List<InitializeRequest> requests) {
        List<InitializeResult> results = new List<InitializeResult>();

        for (InitializeRequest request : requests) {
            InitializeResult result = new InitializeResult();

            try {
                // Determine correlation source
                UoWTransactionState state = null;

                if (String.isNotBlank(request.contextCarrier)) {
                    // Explicit carrier provided - use it
                    state = UoWTransactionState.fromJson(request.contextCarrier);
                } else if (UoWTransactionState.hasCurrent()) {
                    // Auto-detect: inside UoW transaction, inherit from ambient
                    state = UoWTransactionState.getCurrent();
                }

                // Create UnitOfWork instance with state (null = fresh root)
                String configName = String.isBlank(request.configurationName) ? 'Default' : request.configurationName;
                UnitOfWork uow = new UnitOfWork(configName, state);

                // Apply configuration
                if (request.isDryRun == true) {
                    uow.asDryRun();
                }

                // Apply scenario for audit categorization
                if (String.isNotBlank(request.scenarioName)) {
                    uow.setScenario(request.scenarioName);
                }

                // Apply description
                if (String.isNotBlank(request.description)) {
                    uow.setDescription(request.description);
                }

                // Apply agent context
                if (String.isNotBlank(request.agentId) || String.isNotBlank(request.agentName)) {
                    UoWContext.AgentContext agentCtx = new UoWContext.AgentContext();
                    agentCtx.agentId = request.agentId;
                    agentCtx.agentName = request.agentName;
                    agentCtx.modelId = request.modelId;
                    agentCtx.confidenceScore = request.confidenceScore;
                    agentCtx.intent = request.intent;

                    uow.withAgent(agentCtx);
                }

                // Register transaction and get ID
                String transactionId = UoWFlowTransactionRegistry.register(uow);

                // Success
                result.success = true;
                result.transactionId = transactionId;
                result.correlationId = uow.getContext().correlationId;
                result.contextCarrier = new UoWTransactionState(uow.getContext()).toJson();
                result.message = state != null ?
                    'Transaction initialized (inherited correlation from parent)' :
                    'Transaction initialized successfully';

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
     * Input parameters for transaction initialization
     */
    public class InitializeRequest {
        @InvocableVariable(
            label='Configuration Name'
            description='UoW configuration to use (default: Default)'
        )
        public String configurationName;

        @InvocableVariable(
            label='Dry Run'
            description='Test mode - no actual DML/callouts executed (default: false)'
        )
        public Boolean isDryRun;

        @InvocableVariable(
            label='Scenario Name'
            description='Business scenario for audit categorization (e.g., Standard Mortgage, High Loan Amount)'
        )
        public String scenarioName;

        @InvocableVariable(
            label='Description'
            description='Brief description of transaction purpose (e.g., Create loan application with documents)'
        )
        public String description;

        @InvocableVariable(
            label='Context Carrier'
            description='JSON carrier from parent transaction. Leave blank for auto-detection (inherits if inside UoW transaction).'
        )
        public String contextCarrier;

        // ========================================================================
        // AGENT CONTEXT
        // ========================================================================

        @InvocableVariable(
            label='Agent ID'
            description='Salesforce agent ID (for AgentForce integration)'
        )
        public String agentId;

        @InvocableVariable(
            label='Agent Name'
            description='Agent name (for logging/auditing)'
        )
        public String agentName;

        @InvocableVariable(
            label='Model ID'
            description='AI model ID (for tracing)'
        )
        public String modelId;

        @InvocableVariable(
            label='Confidence Score'
            description='Agent confidence score (0.0 to 1.0, for approval thresholds)'
        )
        public Decimal confidenceScore;

        @InvocableVariable(
            label='Business Intent'
            description='Purpose of this transaction (for auditing)'
        )
        public String intent;
    }

    /**
     * Output results from transaction initialization
     */
    public class InitializeResult {
        @InvocableVariable(
            label='Success'
            description='True if transaction initialized successfully'
        )
        public Boolean success;

        @InvocableVariable(
            label='Transaction ID'
            description='Use this ID in all subsequent UoW actions (Register Insert/Update/Delete, Commit)'
        )
        public String transactionId;

        @InvocableVariable(
            label='Correlation ID'
            description='UUID for distributed tracing across async boundaries'
        )
        public String correlationId;

        @InvocableVariable(
            label='Context Carrier'
            description='JSON carrier for passing to async paths or child transactions'
        )
        public String contextCarrier;

        @InvocableVariable(
            label='Message'
            description='Success or error message'
        )
        public String message;
    }
}