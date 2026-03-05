//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Default channel for executing flows via Flow.Interview API.
 * Maintains current behavior of direct Flow.Interview calls.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWInterfaces.IFlowChannel
 */
public inherited sharing class UoWDefaultFlowChannel implements UoWInterfaces.IFlowChannel {

    // ============================================================================
    // PUBLIC API - INTERFACE IMPLEMENTATION
    // ============================================================================

    /**
     * Get channel name.
     *
     * @return Channel name
     */
    public String getName() {
        return 'Default Salesforce Flow Engine';
    }

    /**
     * Execute flow via Flow.Interview API.
     *
     * @param workItem The flow work item to execute
     * @param ctx The execution context
     */
    public void executeFlow(UoWFlowWorkItem workItem, UoWContext ctx) {
        // Flow execution logic
        Flow.Interview flowInterview = Flow.Interview.createInterview(
            workItem.flowApiName,
            workItem.flowInputs
        );
        flowInterview.start();

        // Initialize outputs map (actual outputs would require getVariableValue calls)
        workItem.flowOutputs = new Map<String, Object>();
    }
}