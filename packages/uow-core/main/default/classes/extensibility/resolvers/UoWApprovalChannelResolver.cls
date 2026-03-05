//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Resolver for IApprovalChannel implementations (Pattern B: Single-Instance Extensibility).
 *
 * 2-Tier Priority Resolution (NO DEFAULT FALLBACK - approval is optional):
 * 1. Already resolved instance (ctx.getFeatureSettings().resolvedApprovalChannel)
 * 2. Configuration class name (ctx.getFeatureSettings().approvalChannelClassName)
 *
 * Approval is an OPTIONAL extension - returns null if no channel configured.
 * Framework continues without approval when null is returned.
 * Resolution updates the class name so audit sees the actual class used.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWInterfaces.IApprovalChannel
 */
public inherited sharing class UoWApprovalChannelResolver {

    // ============================================================================
    // PUBLIC API - RESOLUTION
    // ============================================================================

    /**
     * Resolve approval channel instance using 2-tier priority.
     * Updates featureSettings with resolved instance and class name if channel is found.
     *
     * @param ctx Execution context
     * @param result Result object for logging warnings (optional)
     * @return Resolved approval channel instance, or null if no channel configured
     */
    public static UoWInterfaces.IApprovalChannel resolve(UoWContext ctx, UoWResult result) {
        UoWFeatureSettings settings = ctx.getFeatureSettings();

        // Priority 1: Already resolved instance
        if (settings.resolvedApprovalChannel != null) {
            return settings.resolvedApprovalChannel;
        }

        UoWInterfaces.IApprovalChannel channel = null;

        // Priority 2: Configuration class name
        String className = settings.approvalChannelClassName;
        if (String.isNotBlank(className)) {
            channel = UoWExtensibilityInstantiator.instantiateApprovalChannel(
                className, result, 'UoWApprovalChannelResolver'
            );
        }

        // Store resolved instance and update class name (only if channel was resolved)
        if (channel != null) {
            settings.setResolvedApprovalChannel(channel);
        }

        // No default fallback - approval is optional
        return channel;
    }
}