//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Base implementation for UnitOfWork policies.
 * Provides common functionality and default implementations.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWInterfaces.IPolicy, UoWPolicyEvaluation, UoWPolicyRegistry
 */
public virtual inherited sharing class UoWBasePolicy implements UoWInterfaces.IPolicy {

    // ============================================================================
    // PROTECTED PROPERTIES
    // ============================================================================

    protected String policyName; // Policy name for identification
    protected UoWEnums.PolicyCategory policyCategory; // Policy category for categorization

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    public UoWBasePolicy(String name) {
        this(name, UoWEnums.PolicyCategory.BUSINESS_RULES);
    }

    public UoWBasePolicy(String name, UoWEnums.PolicyCategory category) {
        this.policyName = name;
        this.policyCategory = category;
    }

    // ============================================================================
    // PUBLIC API - INTERFACE IMPLEMENTATION
    // ============================================================================

    /**
     * Get policy name
     * @return Policy name
     */
    public virtual String getName() {
        return this.policyName;
    }

    /**
     * Get policy category (determines categorization/priority)
     * Default: BUSINESS_RULES
     * Override to return SECURITY, COMPLIANCE, DATA_QUALITY, ANALYTICS, or CUSTOM
     * @return Policy category
     */
    public virtual UoWEnums.PolicyCategory getCategory() {
        return this.policyCategory;
    }

    /**
     * Indicates if this policy is critical to transaction success.
     * Default: true (fail-safe - policy failures should fail transaction)
     * Override to return false for non-critical policies (analytics, recommendations)
     * - true: Policy exception rolls back transaction
     * - false: Policy exception logged as warning, transaction continues
     * @return True if policy failure should fail the transaction
     */
    public virtual Boolean isCritical() {
        return true;
    }

    /**
     * Evaluate a work item
     * @param ctx Execution context
     * @param workItem Work item to evaluate
     * @return Policy evaluation result
     */
    public virtual UoWPolicyEvaluation.Evaluation evaluate(UoWContext ctx, UoWWorkItem workItem) {
        // Override in subclass
        UoWPolicyEvaluation.Evaluation evaluation = new UoWPolicyEvaluation.Evaluation(policyName);
        evaluation.action = UoWEnums.PolicyAction.ALLOW;
        return evaluation;
    }

    /**
     * Evaluate entire plan
     * @param ctx Execution context
     * @param plan Execution plan
     * @return List of policy evaluations
     */
    public virtual List<UoWPolicyEvaluation.Evaluation> evaluatePlan(UoWContext ctx, UoWPlan plan) {
        List<UoWPolicyEvaluation.Evaluation> evaluations = new List<UoWPolicyEvaluation.Evaluation>();

        // Evaluate all DML work items
        for (UoWDmlWorkItem workItem : plan.getPlannedDmlWork()) {
            UoWPolicyEvaluation.Evaluation eval = evaluate(ctx, workItem);
            if (eval != null) {
                evaluations.add(eval);
            }
        }

        // Evaluate all event work items
        for (UoWEventWorkItem workItem : plan.getPlannedEventWork()) {
            UoWPolicyEvaluation.Evaluation eval = evaluate(ctx, workItem);
            if (eval != null) {
                evaluations.add(eval);
            }
        }

        // Evaluate all email work items
        for (UoWEmailWorkItem workItem : plan.getPlannedEmailWork()) {
            UoWPolicyEvaluation.Evaluation eval = evaluate(ctx, workItem);
            if (eval != null) {
                evaluations.add(eval);
            }
        }

        // Evaluate all notification work items
        for (UoWNotificationWorkItem workItem : plan.getPlannedNotificationWork()) {
            UoWPolicyEvaluation.Evaluation eval = evaluate(ctx, workItem);
            if (eval != null) {
                evaluations.add(eval);
            }
        }

        // Evaluate all flow work items
        for (UoWFlowWorkItem workItem : plan.getPlannedFlowWork()) {
            UoWPolicyEvaluation.Evaluation eval = evaluate(ctx, workItem);
            if (eval != null) {
                evaluations.add(eval);
            }
        }

        // Evaluate all callout work items
        for (UoWCalloutWorkItem workItem : plan.getPlannedCalloutWork()) {
            UoWPolicyEvaluation.Evaluation eval = evaluate(ctx, workItem);
            if (eval != null) {
                evaluations.add(eval);
            }
        }

        return evaluations;
    }

    // ============================================================================
    // PROTECTED METHODS
    // ============================================================================

    // Create ALLOW evaluation
    protected UoWPolicyEvaluation.Evaluation createAllowEvaluation() {
        UoWPolicyEvaluation.Evaluation eval = new UoWPolicyEvaluation.Evaluation(policyName);
        eval.action = UoWEnums.PolicyAction.ALLOW;
        return eval;
    }

    // Create DENY evaluation
    protected UoWPolicyEvaluation.Evaluation createDenyEvaluation(String reason) {
        UoWPolicyEvaluation.Evaluation eval = new UoWPolicyEvaluation.Evaluation(policyName);
        eval.action = UoWEnums.PolicyAction.DENY;
        eval.reason = reason;
        return eval;
    }

    // Create REQUIRE_APPROVAL evaluation
    protected UoWPolicyEvaluation.Evaluation createApprovalRequiredEvaluation(String reason) {
        UoWPolicyEvaluation.Evaluation eval = new UoWPolicyEvaluation.Evaluation(policyName);
        eval.action = UoWEnums.PolicyAction.REQUIRE_APPROVAL;
        eval.reason = reason;
        return eval;
    }

    // Create ALLOW_WITH_JUSTIFICATION evaluation
    protected UoWPolicyEvaluation.Evaluation createWarningEvaluation(String reason) {
        UoWPolicyEvaluation.Evaluation eval = new UoWPolicyEvaluation.Evaluation(policyName);
        eval.action = UoWEnums.PolicyAction.ALLOW_WITH_JUSTIFICATION;
        eval.reason = reason;
        return eval;
    }
}