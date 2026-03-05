//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Resolver for ICalloutStrategy implementations (Pattern B: Single-Instance Extensibility).
 *
 * 3-Tier Priority Resolution:
 * 1. Already resolved instance (ctx.getFeatureSettings().resolvedCalloutStrategy)
 * 2. Configuration class name (ctx.getFeatureSettings().calloutStrategyClassName)
 * 3. Default fallback (UoWBaseCalloutStrategy)
 *
 * Callout strategy is REQUIRED - always returns a valid instance.
 * Resolution updates the class name so audit sees the actual class used.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWInterfaces.ICalloutStrategy
 * @see UoWBaseCalloutStrategy
 */
public inherited sharing class UoWCalloutStrategyResolver {

    // ============================================================================
    // PUBLIC API - RESOLUTION
    // ============================================================================

    /**
     * Resolve callout strategy instance using 3-tier priority.
     * Updates featureSettings with resolved instance and class name.
     *
     * @param ctx Execution context
     * @param result Result object for logging warnings (optional)
     * @return Resolved callout strategy instance (never null)
     */
    public static UoWInterfaces.ICalloutStrategy resolve(UoWContext ctx, UoWResult result) {
        UoWFeatureSettings settings = ctx.getFeatureSettings();

        // Priority 1: Already resolved instance
        if (settings.resolvedCalloutStrategy != null) {
            return settings.resolvedCalloutStrategy;
        }

        UoWInterfaces.ICalloutStrategy strategy = null;

        // Priority 2: Configuration class name
        String className = settings.calloutStrategyClassName;
        if (String.isNotBlank(className)) {
            strategy = UoWExtensibilityInstantiator.instantiateCalloutStrategy(
                className, result, 'UoWCalloutStrategyResolver'
            );
        }

        // Priority 3: Default fallback (always available)
        if (strategy == null) {
            strategy = new UoWBaseCalloutStrategy();
        }

        // Store resolved instance and update class name
        settings.setResolvedCalloutStrategy(strategy);

        return strategy;
    }
}