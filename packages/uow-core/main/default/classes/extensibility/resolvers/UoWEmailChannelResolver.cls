//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Resolver for IEmailChannel implementations (Pattern B: Single-Instance Extensibility).
 *
 * 3-Tier Priority Resolution:
 * 1. Already resolved instance (ctx.getFeatureSettings().resolvedEmailChannel)
 * 2. Configuration class name (ctx.getFeatureSettings().emailChannelClassName)
 * 3. Default fallback (UoWDefaultEmailChannel)
 *
 * Email channel is REQUIRED - always returns a valid instance.
 * Resolution updates the class name so audit sees the actual class used.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWInterfaces.IEmailChannel
 * @see UoWDefaultEmailChannel
 */
public inherited sharing class UoWEmailChannelResolver {

    // ============================================================================
    // PUBLIC API - RESOLUTION
    // ============================================================================

    /**
     * Resolve email channel instance using 3-tier priority.
     * Updates featureSettings with resolved instance and class name.
     *
     * @param ctx Execution context
     * @param result Result object for logging warnings (optional)
     * @return Resolved email channel instance (never null)
     */
    public static UoWInterfaces.IEmailChannel resolve(UoWContext ctx, UoWResult result) {
        UoWFeatureSettings settings = ctx.getFeatureSettings();

        // Priority 1: Already resolved instance
        if (settings.resolvedEmailChannel != null) {
            return settings.resolvedEmailChannel;
        }

        UoWInterfaces.IEmailChannel channel = null;

        // Priority 2: Configuration class name
        String className = settings.emailChannelClassName;
        if (String.isNotBlank(className)) {
            channel = UoWExtensibilityInstantiator.instantiateEmailChannel(
                className, result, 'UoWEmailChannelResolver'
            );
        }

        // Priority 3: Default fallback (always available)
        if (channel == null) {
            channel = new UoWDefaultEmailChannel();
        }

        // Store resolved instance and update class name
        settings.setResolvedEmailChannel(channel);

        return channel;
    }
}