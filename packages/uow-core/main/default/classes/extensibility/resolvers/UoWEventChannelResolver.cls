//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Resolver for IEventChannel implementations (Pattern B: Single-Instance Extensibility).
 *
 * 3-Tier Priority Resolution:
 * 1. Already resolved instance (ctx.getFeatureSettings().resolvedEventChannel)
 * 2. Configuration class name (ctx.getFeatureSettings().eventChannelClassName)
 * 3. Default fallback (UoWDefaultPlatformEventChannel)
 *
 * Event channel is REQUIRED - always returns a valid instance.
 * Resolution updates the class name so audit sees the actual class used.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWInterfaces.IEventChannel
 * @see UoWDefaultPlatformEventChannel
 */
public inherited sharing class UoWEventChannelResolver {

    // ============================================================================
    // PUBLIC API - RESOLUTION
    // ============================================================================

    /**
     * Resolve event channel instance using 3-tier priority.
     * Updates featureSettings with resolved instance and class name.
     *
     * @param ctx Execution context
     * @param result Result object for logging warnings (optional)
     * @return Resolved event channel instance (never null)
     */
    public static UoWInterfaces.IEventChannel resolve(UoWContext ctx, UoWResult result) {
        UoWFeatureSettings settings = ctx.getFeatureSettings();

        // Priority 1: Already resolved instance
        if (settings.resolvedEventChannel != null) {
            return settings.resolvedEventChannel;
        }

        UoWInterfaces.IEventChannel channel = null;

        // Priority 2: Configuration class name
        String className = settings.eventChannelClassName;
        if (String.isNotBlank(className)) {
            channel = UoWExtensibilityInstantiator.instantiateEventChannel(
                className, result, 'UoWEventChannelResolver'
            );
        }

        // Priority 3: Default fallback (always available)
        if (channel == null) {
            channel = new UoWDefaultPlatformEventChannel();
        }

        // Store resolved instance and update class name
        settings.setResolvedEventChannel(channel);

        return channel;
    }
}