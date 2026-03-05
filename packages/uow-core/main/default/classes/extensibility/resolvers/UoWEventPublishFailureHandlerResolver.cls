//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Resolver for IEventPublishFailureHandler implementations (Pattern B: Single-Instance Extensibility).
 *
 * 2-Tier Priority Resolution (NO DEFAULT FALLBACK - failure handler is optional):
 * 1. Already resolved instance (ctx.getFeatureSettings().resolvedEventPublishFailureHandler)
 * 2. Configuration class name (ctx.getFeatureSettings().eventPublishFailureHandlerClassName)
 *
 * Event publish failure handling is an OPTIONAL extension - returns null if no handler configured.
 * Framework continues without failure handling when null is returned.
 * Resolution updates the class name so audit sees the actual class used.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWInterfaces.IEventPublishFailureHandler
 */
public inherited sharing class UoWEventPublishFailureHandlerResolver {

    // ============================================================================
    // PUBLIC API - RESOLUTION
    // ============================================================================

    /**
     * Resolve event publish failure handler instance using 2-tier priority.
     * Updates featureSettings with resolved instance and class name if handler is found.
     *
     * @param ctx Execution context
     * @param result Result object for logging warnings (optional)
     * @return Resolved event publish failure handler instance, or null if no handler configured
     */
    public static UoWInterfaces.IEventPublishFailureHandler resolve(UoWContext ctx, UoWResult result) {
        UoWFeatureSettings settings = ctx.getFeatureSettings();

        // Priority 1: Already resolved instance
        if (settings.resolvedEventPublishFailureHandler != null) {
            return settings.resolvedEventPublishFailureHandler;
        }

        UoWInterfaces.IEventPublishFailureHandler handler = null;

        // Priority 2: Configuration class name
        String className = settings.eventPublishFailureHandlerClassName;
        if (String.isNotBlank(className)) {
            handler = UoWExtensibilityInstantiator.instantiateEventPublishFailureHandler(
                className, result, 'UoWEventPublishFailureHandlerResolver'
            );
        }

        // Store resolved instance and update class name (only if handler was resolved)
        if (handler != null) {
            settings.setResolvedEventPublishFailureHandler(handler);
        }

        // No default fallback - event publish failure handling is optional
        return handler;
    }
}