//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Resolver for IFlowChannel implementations (Pattern B: Single-Instance Extensibility).
 *
 * 3-Tier Priority Resolution:
 * 1. Already resolved instance (ctx.getFeatureSettings().resolvedFlowChannel)
 * 2. Configuration class name (ctx.getFeatureSettings().flowChannelClassName)
 * 3. Default fallback (UoWDefaultFlowChannel)
 *
 * Flow channel is REQUIRED - always returns a valid instance.
 * Resolution updates the class name so audit sees the actual class used.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWInterfaces.IFlowChannel
 * @see UoWDefaultFlowChannel
 */
public inherited sharing class UoWFlowChannelResolver {

    // ============================================================================
    // PUBLIC API - RESOLUTION
    // ============================================================================

    /**
     * Resolve flow channel instance using 3-tier priority.
     * Updates featureSettings with resolved instance and class name.
     *
     * @param ctx Execution context
     * @param result Result object for logging warnings (optional)
     * @return Resolved flow channel instance (never null)
     */
    public static UoWInterfaces.IFlowChannel resolve(UoWContext ctx, UoWResult result) {
        UoWFeatureSettings settings = ctx.getFeatureSettings();

        // Priority 1: Already resolved instance
        if (settings.resolvedFlowChannel != null) {
            return settings.resolvedFlowChannel;
        }

        UoWInterfaces.IFlowChannel channel = null;

        // Priority 2: Configuration class name
        String className = settings.flowChannelClassName;
        if (String.isNotBlank(className)) {
            channel = UoWExtensibilityInstantiator.instantiateFlowChannel(
                className, result, 'UoWFlowChannelResolver'
            );
        }

        // Priority 3: Default fallback (always available)
        if (channel == null) {
            channel = new UoWDefaultFlowChannel();
        }

        // Store resolved instance and update class name
        settings.setResolvedFlowChannel(channel);

        return channel;
    }
}