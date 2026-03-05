//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Resolver for INotificationChannel implementations (Pattern B: Single-Instance Extensibility).
 *
 * 3-Tier Priority Resolution:
 * 1. Already resolved instance (ctx.getFeatureSettings().resolvedNotificationChannel)
 * 2. Configuration class name (ctx.getFeatureSettings().notificationChannelClassName)
 * 3. Default fallback (UoWDefaultNotificationChannel)
 *
 * Notification channel is REQUIRED - always returns a valid instance.
 * Resolution updates the class name so audit sees the actual class used.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWInterfaces.INotificationChannel
 * @see UoWDefaultNotificationChannel
 */
public inherited sharing class UoWNotificationChannelResolver {

    // ============================================================================
    // PUBLIC API - RESOLUTION
    // ============================================================================

    /**
     * Resolve notification channel instance using 3-tier priority.
     * Updates featureSettings with resolved instance and class name.
     *
     * @param ctx Execution context
     * @param result Result object for logging warnings (optional)
     * @return Resolved notification channel instance (never null)
     */
    public static UoWInterfaces.INotificationChannel resolve(UoWContext ctx, UoWResult result) {
        UoWFeatureSettings settings = ctx.getFeatureSettings();

        // Priority 1: Already resolved instance
        if (settings.resolvedNotificationChannel != null) {
            return settings.resolvedNotificationChannel;
        }

        UoWInterfaces.INotificationChannel channel = null;

        // Priority 2: Configuration class name
        String className = settings.notificationChannelClassName;
        if (String.isNotBlank(className)) {
            channel = UoWExtensibilityInstantiator.instantiateNotificationChannel(
                className, result, 'UoWNotificationChannelResolver'
            );
        }

        // Priority 3: Default fallback (always available)
        if (channel == null) {
            channel = new UoWDefaultNotificationChannel();
        }

        // Store resolved instance and update class name
        settings.setResolvedNotificationChannel(channel);

        return channel;
    }
}