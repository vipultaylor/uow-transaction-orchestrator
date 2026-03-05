//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Policy evaluation service and results for UnitOfWork transactions.
 *
 * Responsibilities:
 * 1. Evaluate all policies against a plan (evaluateAll)
 * 2. Short-circuit on DENY action
 * 3. Track evaluation results and summary
 * 4. Handle critical vs non-critical policy failures
 *
 * Contains:
 * - Static evaluation method (evaluateAll)
 * - Evaluation inner class (individual policy result)
 * - Summary inner class (aggregate results)
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWInterfaces.IPolicy
 * @see UoWBasePolicy
 * @see UoWPolicyRegistry
 */
public inherited sharing class UoWPolicyEvaluation {

    // ============================================================================
    // PRIVATE CONSTANTS
    // ============================================================================

    private static final String SOURCE = 'UoWPolicyEvaluation';

    private static final Map<UoWEnums.PolicyAction, Integer> POLICY_ACTION_PRIORITY = new Map<UoWEnums.PolicyAction, Integer>{
        UoWEnums.PolicyAction.ALLOW => 0,
        UoWEnums.PolicyAction.ALLOW_WITH_JUSTIFICATION => 1,
        UoWEnums.PolicyAction.REQUIRE_APPROVAL => 2,
        UoWEnums.PolicyAction.REQUIRE_TRACING => 3,
        UoWEnums.PolicyAction.REQUIRE_MASKING => 4,
        UoWEnums.PolicyAction.DENY => 5
    };

    // ============================================================================
    // PUBLIC API - EVALUATION
    // ============================================================================

    /**
     * Evaluate all policies against a plan with short-circuit on DENY.
     *
     * @param ctx Execution context
     * @param plan Execution plan
     * @param result Result object for logging
     * @return Summary of all policy evaluations
     */
    public static Summary evaluateAll(UoWContext ctx, UoWPlan plan, UoWResult result) {
        List<UoWInterfaces.IPolicy> policies = UoWPolicyRegistry.getInstance().getEnabledPolicies(ctx, result);
        Summary summary = new Summary();

        // Update PolicySettings with runtime values (isCritical) from policy instances
        // This ensures audit/serialization captures actual values from implementations
        ctx.getFeatureSettings().updatePolicySettingsFromInstances(policies);

        if (policies.isEmpty()) {
            result.debug('No policies to evaluate - skipping policy evaluation', SOURCE);
            return summary;
        }

        result.info(String.format('Policy evaluation started - {0} polic{1}',
            new String[]{ String.valueOf(policies.size()), policies.size() == 1 ? 'y' : 'ies' }), SOURCE);

        // Set totalPolicies to the count of policy objects
        summary.totalPolicies = policies.size();

        Integer policyCount = 0;

        for (UoWInterfaces.IPolicy policy : policies) {
            policyCount++;
            String policyEvalStatus = 'PASSED';
            String policyDescription = String.format('Policy {0}/{1}: {2}',
                new String[]{
                    String.valueOf(policyCount),
                    String.valueOf(policies.size()),
                    policy.getName()
                });

            try {
                result.fine('Evaluating ' + policyDescription, SOURCE);

                List<Evaluation> policyEvals = policy.evaluatePlan(ctx, plan);

                if (policyEvals != null && !policyEvals.isEmpty()) {
                    for (Evaluation eval : policyEvals) {
                        summary.addEvaluation(eval);

                        // Log significant policy actions
                        logPolicyAction(result, policy, eval);

                        // SHORT-CIRCUIT: If any policy returns DENY, stop evaluation immediately
                        if (eval.action == UoWEnums.PolicyAction.DENY) {
                            policyEvalStatus = 'DENIED';

                            // Add trace event for the denying policy before short-circuit
                            result.addTraceEvent(policyDescription + ' [DENIED]');
                            result.error('[POLICY] Short-circuit on DENY from policy: ' + policy.getName() + ' - Reason: ' + eval.reason, SOURCE);
                            return summary;
                        }
                    }
                }
            } catch (Exception ex) {
                handlePolicyException(result, summary, policy, ex);
                policyEvalStatus = 'FAILED';
            }

            // Add trace event to result
            result.addTraceEvent(policyDescription + ' [' + policyEvalStatus + ']');
        }

        result.info(String.format('Policy evaluation completed - {0} evaluation(s), strictest action: {1}',
            new String[]{
                String.valueOf(summary.totalEvaluations),
                String.valueOf(summary.strictestPolicyAction)
            }), SOURCE);

        return summary;
    }

    // ============================================================================
    // PRIVATE METHODS - EVALUATION HELPERS
    // ============================================================================

    // Log policy action based on severity
    private static void logPolicyAction(UoWResult result, UoWInterfaces.IPolicy policy, Evaluation eval) {
        if (eval.action == UoWEnums.PolicyAction.DENY) {
            result.error(String.format('Policy DENIED transaction: {0} - Reason: {1}',
                new String[]{ policy.getName(), eval.reason }), SOURCE);
        } else if (eval.action == UoWEnums.PolicyAction.REQUIRE_APPROVAL) {
            result.warn(String.format('Policy requires approval: {0} - Reason: {1}',
                new String[]{ policy.getName(), eval.reason }), SOURCE);
        } else if (eval.action == UoWEnums.PolicyAction.REQUIRE_TRACING) {
            result.info(String.format('Policy requires tracing: {0}',
                new String[]{ policy.getName() }), SOURCE);
        } else if (eval.action == UoWEnums.PolicyAction.REQUIRE_MASKING) {
            result.info(String.format('Policy requires masking: {0}',
                new String[]{ policy.getName() }), SOURCE);
        }
    }

    // Handle policy exception based on criticality
    private static void handlePolicyException(
        UoWResult result,
        Summary summary,
        UoWInterfaces.IPolicy policy,
        Exception ex
    ) {
        // Check if policy is critical - critical policies fail transaction
        if (policy.isCritical()) {
            String errorMessage = String.format(
                System.Label.UoW_Error_CriticalPolicyFailedEvaluation,
                new List<String>{ policy.getName(), ex.getMessage() });
            summary.errorMessages.add(errorMessage);
            result.error(errorMessage, SOURCE);
            throw new UoWExceptionService.UoWException(errorMessage, ex);
        }

        // Non-critical policy - log warning and continue
        String errorMessage = String.format(
            System.Label.UoW_Error_NonCriticalPolicyFailedEvaluation,
            new List<String>{ policy.getName(), ex.getMessage() });
        summary.errorMessages.add(errorMessage);
        result.warn(errorMessage, SOURCE);
    }

    // ============================================================================
    // INNER CLASSES - SUMMARY
    // ============================================================================

    // Aggregate summary of all policy evaluations
    public class Summary {

        // ============================================================================
        // PUBLIC PROPERTIES - EVALUATIONS
        // ============================================================================

        public List<Evaluation> evaluations;
        public UoWEnums.PolicyAction strictestPolicyAction;

        // ============================================================================
        // PUBLIC PROPERTIES - FLAGS
        // ============================================================================

        public Boolean requiresApproval;
        public Boolean requiresMasking;
        public Boolean requiresTracing;

        // ============================================================================
        // PUBLIC PROPERTIES - DENIAL
        // ============================================================================

        public Boolean isDenied;
        public List<String> denialReasons;

        // ============================================================================
        // PUBLIC PROPERTIES - COUNTS
        // ============================================================================

        public Integer totalPolicies;
        public Integer totalEvaluations;
        public Map<UoWEnums.PolicyAction, Integer> policyActionCounts;

        // ============================================================================
        // PUBLIC PROPERTIES - ERRORS
        // ============================================================================

        public List<String> errorMessages;

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public Summary() {
            this.evaluations = new List<Evaluation>();
            this.strictestPolicyAction = UoWEnums.PolicyAction.ALLOW;

            this.requiresApproval = false;
            this.requiresMasking = false;
            this.requiresTracing = false;

            this.isDenied = false;
            this.denialReasons = new List<String>();

            this.totalPolicies = 0;
            this.totalEvaluations = 0;
            this.policyActionCounts = new Map<UoWEnums.PolicyAction, Integer>();
            for (UoWEnums.PolicyAction action : UoWEnums.PolicyAction.values()) {
                this.policyActionCounts.put(action, 0);
            }

            this.errorMessages = new List<String>();
        }

        // ============================================================================
        // PUBLIC API - EVALUATION MANAGEMENT
        // ============================================================================

        /**
         * Add a policy evaluation and update summary counts.
         *
         * @param evaluation The evaluation to add
         */
        public void addEvaluation(Evaluation evaluation) {
            if (evaluation == null) {
                return;
            }

            this.evaluations.add(evaluation);

            this.totalEvaluations++;
            this.policyActionCounts.put(evaluation.action, this.policyActionCounts.get(evaluation.action) + 1);

            if (evaluation.action == UoWEnums.PolicyAction.DENY) {
                this.isDenied = true;
                if (String.isNotBlank(evaluation.reason)) {
                    this.denialReasons.add(evaluation.reason);
                }
            }
            else if (evaluation.action == UoWEnums.PolicyAction.REQUIRE_APPROVAL) {
                this.requiresApproval = true;
            }
            else if (evaluation.action == UoWEnums.PolicyAction.REQUIRE_MASKING) {
                this.requiresMasking = true;
            }
            else if (evaluation.action == UoWEnums.PolicyAction.REQUIRE_TRACING) {
                this.requiresTracing = true;
            }

            this.strictestPolicyAction = getStrictestPolicyAction(evaluation.action);
        }

        // ============================================================================
        // PRIVATE METHODS
        // ============================================================================

        // Get the strictest policy action based on priority
        private UoWEnums.PolicyAction getStrictestPolicyAction(UoWEnums.PolicyAction action) {
            UoWExceptionService.require(
                POLICY_ACTION_PRIORITY.containsKey(action),
                'Policy Action Priority not configured for ' + action
            );

            Integer actionPriority = POLICY_ACTION_PRIORITY.get(action);
            Integer strictestActionPriority = POLICY_ACTION_PRIORITY.get(this.strictestPolicyAction);

            return actionPriority > strictestActionPriority ? action : this.strictestPolicyAction;
        }
    }

    // ============================================================================
    // INNER CLASSES - EVALUATION
    // ============================================================================

    // Individual policy evaluation result
    public class Evaluation {

        // ============================================================================
        // PUBLIC PROPERTIES
        // ============================================================================

        public String policyName;
        public UoWEnums.PolicyAction action;
        public String reason;
        public Map<String, Object> evidence;
        public DateTime evaluatedAt;

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public Evaluation(String name) {
            this.policyName = name;
            this.action = UoWEnums.PolicyAction.ALLOW;
            this.evidence = new Map<String, Object>();
            this.evaluatedAt = DateTime.now();
        }
    }

}