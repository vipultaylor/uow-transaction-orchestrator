//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Flow execution work item for invoking flows.
 * Contains flow name and inputs/outputs.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Work Items
 * @see UoWWorkItem
 * @see UoWFlowExecutionService
 */
public inherited sharing class UoWFlowWorkItem extends UoWWorkItem {

    // ============================================================================
    // PUBLIC PROPERTIES - EXECUTION
    // ============================================================================

    public UoWEnums.WorkPhase executionPhase;
    public String flowApiName;

    // ============================================================================
    // PUBLIC PROPERTIES - FLOW DATA
    // ============================================================================

    public Map<String, Object> flowInputs;
    public Map<String, Object> flowOutputs;


    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Create a new Flow work item.
     *
     * @param flowName The API name of the flow to execute
     * @param phase Execution phase (POST_DML, ON_SUCCESS, ON_FAILURE, ON_FINALIZATION)
     */
    public UoWFlowWorkItem(String flowName, UoWEnums.WorkPhase phase) {
        super(UoWEnums.WorkType.FLOW);
        this.flowApiName = flowName;
        this.executionPhase = phase ?? UoWEnums.WorkPhase.POST_DML;
        this.flowInputs = new Map<String, Object>();
        this.statistics.planned = 1;
        this.continueOnError = false;
    }

    // ============================================================================
    // PUBLIC API - FLUENT CONFIGURATION
    // ============================================================================

    /**
     * Add a single flow input variable.
     *
     * @param inputName Flow input variable name
     * @param inputValue Flow input variable value
     * @return This work item for fluent chaining
     */
    public UoWFlowWorkItem withInput(String inputName, Object inputValue) {
        this.flowInputs.put(inputName, inputValue);
        return this;
    }

    /**
     * Add multiple flow input variables.
     *
     * @param inputs Map of input variable names to values
     * @return This work item for fluent chaining
     */
    public UoWFlowWorkItem withInputs(Map<String, Object> inputs) {
        if (inputs != null) {
            this.flowInputs.putAll(inputs);
        }
        return this;
    }

    /**
     * Continue execution even if flow fails (don't re-throw exception).
     *
     * @return This work item for fluent chaining
     */
    public UoWFlowWorkItem continueOnError() {
        this.continueOnError = true;
        return this;
    }

    /**
     * Fail-fast if flow fails (re-throw exception for transaction rollback).
     *
     * @return This work item for fluent chaining
     */
    public UoWFlowWorkItem failFast() {
        this.continueOnError = false;
        return this;
    }

}