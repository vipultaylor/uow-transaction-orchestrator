//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Resolver for IRiskAssessor implementations (Pattern B: Single-Instance Extensibility).
 *
 * 2-Tier Priority Resolution:
 * 1. Already resolved instance (ctx.getFeatureSettings().resolvedRiskAssessor)
 * 2. Configuration class name (ctx.getFeatureSettings().riskAssessorClassName)
 *
 * Risk assessor is OPTIONAL - returns null when not configured.
 * This allows risk assessment to be skipped entirely if not needed.
 * Resolution updates the class name so audit sees the actual class used.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWInterfaces.IRiskAssessor
 * @see UoWStandardRiskAssessor
 */
public inherited sharing class UoWRiskAssessorResolver {

    // ============================================================================
    // PUBLIC API - RESOLUTION
    // ============================================================================

    /**
     * Resolve risk assessor instance using 2-tier priority.
     * Updates featureSettings with resolved instance and class name.
     *
     * @param ctx Execution context
     * @param result Result object for logging warnings (optional)
     * @return Resolved risk assessor instance (null if not configured)
     */
    public static UoWInterfaces.IRiskAssessor resolve(UoWContext ctx, UoWResult result) {
        UoWFeatureSettings settings = ctx.getFeatureSettings();

        // Priority 1: Already resolved instance
        if (settings.resolvedRiskAssessor != null) {
            return settings.resolvedRiskAssessor;
        }

        UoWInterfaces.IRiskAssessor assessor = null;

        // Priority 2: Configuration class name
        String className = settings.riskAssessorClassName;
        if (String.isNotBlank(className)) {
            assessor = UoWExtensibilityInstantiator.instantiateRiskAssessor(
                className, result, 'UoWRiskAssessorResolver'
            );
        }

        // No default fallback - risk assessment is optional
        // If no assessor configured, return null and caller should skip assessment

        // Store resolved instance and update class name (if assessor was found)
        if (assessor != null) {
            settings.setResolvedRiskAssessor(assessor);
        }

        return assessor;
    }
}