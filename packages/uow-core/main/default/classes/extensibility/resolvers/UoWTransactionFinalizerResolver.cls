//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Resolver for ITransactionFinalizer implementations (Pattern B: Single-Instance Extensibility).
 *
 * 2-Tier Priority Resolution (NO DEFAULT FALLBACK - finalizer is optional):
 * 1. Already resolved instance (ctx.getFeatureSettings().resolvedTransactionFinalizer)
 * 2. Configuration class name (ctx.getFeatureSettings().transactionFinalizerClassName)
 *
 * Transaction Finalizer is an OPTIONAL extension - returns null if no finalizer configured.
 * Framework continues without finalization when null is returned.
 * Resolution updates the class name so audit sees the actual class used.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWInterfaces.ITransactionFinalizer
 */
public inherited sharing class UoWTransactionFinalizerResolver {

    // ============================================================================
    // SINGLETON
    // ============================================================================

    private static UoWTransactionFinalizerResolver instance;

    public static UoWTransactionFinalizerResolver getInstance() {
        if (instance == null) {
            instance = new UoWTransactionFinalizerResolver();
        }
        return instance;
    }

    // ============================================================================
    // PUBLIC API - RESOLUTION
    // ============================================================================

    /**
     * Resolve transaction finalizer instance using 2-tier priority.
     * Updates featureSettings with resolved instance and class name if finalizer is found.
     *
     * @param ctx Execution context
     * @param result Result object for logging warnings (optional)
     * @return Resolved transaction finalizer instance, or null if no finalizer configured
     */
    public UoWInterfaces.ITransactionFinalizer resolve(UoWContext ctx, UoWResult result) {
        UoWFeatureSettings settings = ctx.getFeatureSettings();

        // Priority 1: Already resolved instance
        if (settings.resolvedTransactionFinalizer != null) {
            return settings.resolvedTransactionFinalizer;
        }

        UoWInterfaces.ITransactionFinalizer finalizer = null;

        // Priority 2: Configuration class name
        String className = settings.transactionFinalizerClassName;
        if (String.isNotBlank(className)) {
            finalizer = UoWExtensibilityInstantiator.instantiateTransactionFinalizer(
                className, result, 'UoWTransactionFinalizerResolver'
            );
        }

        // Store resolved instance and update class name (only if finalizer was resolved)
        if (finalizer != null) {
            settings.setResolvedTransactionFinalizer(finalizer);
        }

        // No default fallback - transaction finalizer is optional
        return finalizer;
    }

    /**
     * Resolve transaction finalizer instance (convenience overload for test usage).
     *
     * @param ctx Execution context
     * @return Resolved transaction finalizer instance, or null if no finalizer configured
     */
    public UoWInterfaces.ITransactionFinalizer resolve(UoWContext ctx) {
        return resolve(ctx, null);
    }
}