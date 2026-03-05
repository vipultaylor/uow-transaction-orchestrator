//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Plugin execution service for UnitOfWork transactions.
 *
 * Responsibilities:
 * 1. Execute plugin lifecycle hooks (onBeforeCommit, onAfterCommit, onError, onFinally)
 * 2. Handle critical vs non-critical plugin failures
 * 3. Support category-based execution filtering
 * 4. Add trace events for plugin execution
 *
 * Plugin REGISTRATION and RETRIEVAL is handled by UoWPluginRegistry.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWInterfaces.IPlugin
 * @see UoWBasePlugin
 * @see UoWPluginRegistry
 */
public inherited sharing class UoWPluginExecutor {

    // ============================================================================
    // ENUMS
    // ============================================================================

    /**
     * Plugin phase execution result.
     * Indicates whether a plugin actually performed work during a lifecycle phase.
     * Used to control trace event generation - only EXECUTED phases create trace events.
     */
    public enum PhaseResult {
        EXECUTED,           // Plugin ran and performed work
        SKIPPED,            // Plugin ran but conditions not met (e.g., dry run, feature disabled)
        NOT_IMPLEMENTED     // Plugin doesn't implement this phase (default from base class)
    }

    // ============================================================================
    // PRIVATE CONSTANTS
    // ============================================================================

    private static final String SOURCE = 'UoWPluginExecutor';

    // ============================================================================
    // PUBLIC API - EXECUTION
    // ============================================================================

    /**
     * Execute onBeforeCommit for all enabled plugins.
     * Throws exception if a critical plugin fails.
     *
     * @param ctx Execution context
     * @param plan Execution plan
     * @param result Result object for logging
     * @return Number of plugins that executed (returned EXECUTED)
     */
    public static Integer executeBeforeCommit(UoWContext ctx, UoWPlan plan, UoWResult result) {
        List<UoWInterfaces.IPlugin> plugins = UoWPluginRegistry.getInstance().getEnabledPlugins(ctx, result);

        // Update PluginSettings with runtime values (isCritical, category) from plugin instances
        // This ensures audit/serialization captures actual values from implementations
        ctx.getFeatureSettings().updatePluginSettingsFromInstances(plugins);

        Integer executedCount = 0;
        for (UoWInterfaces.IPlugin plugin : plugins) {
            try {
                PhaseResult phaseResult = plugin.onBeforeCommit(ctx, plan, result);
                if (phaseResult == UoWPluginExecutor.PhaseResult.EXECUTED) {
                    addPluginTraceEvent(result, plugin, 'BeforeCommit');
                    executedCount++;
                }
            } catch (Exception ex) {
                handlePluginError(plugin, 'onBeforeCommit', ex, result);
            }
        }
        return executedCount;
    }

    /**
     * Execute onAfterCommit for all enabled plugins.
     *
     * @param ctx Execution context
     * @param result Result object for logging
     * @return Number of plugins that executed (returned EXECUTED)
     */
    public static Integer executeAfterCommit(UoWContext ctx, UoWResult result) {
        List<UoWInterfaces.IPlugin> plugins = UoWPluginRegistry.getInstance().getEnabledPlugins(ctx, result);

        Integer executedCount = 0;
        for (UoWInterfaces.IPlugin plugin : plugins) {
            try {
                PhaseResult phaseResult = plugin.onAfterCommit(ctx, result);
                if (phaseResult == UoWPluginExecutor.PhaseResult.EXECUTED) {
                    addPluginTraceEvent(result, plugin, 'AfterCommit');
                    executedCount++;
                }
            } catch (Exception ex) {
                handlePluginError(plugin, 'onAfterCommit', ex, result);
            }
        }
        return executedCount;
    }

    /**
     * Execute onError for all enabled plugins.
     *
     * @param ctx Execution context
     * @param transactionException Exception that occurred
     * @param result Result object for logging
     * @return Number of plugins that executed (returned EXECUTED)
     */
    public static Integer executeOnError(UoWContext ctx, Exception transactionException, UoWResult result) {
        List<UoWInterfaces.IPlugin> plugins = UoWPluginRegistry.getInstance().getEnabledPlugins(ctx, result);

        Integer executedCount = 0;
        for (UoWInterfaces.IPlugin plugin : plugins) {
            try {
                PhaseResult phaseResult = plugin.onError(ctx, transactionException, result);
                if (phaseResult == UoWPluginExecutor.PhaseResult.EXECUTED) {
                    addPluginTraceEvent(result, plugin, 'OnError');
                    executedCount++;
                }
            } catch (Exception ex) {
                handlePluginError(plugin, 'onError', ex, result);
            }
        }
        return executedCount;
    }

    /**
     * Execute onFinally for all enabled plugins (excludes specified category).
     *
     * @param ctx Execution context
     * @param result Result object for logging
     * @param category Plugin category to exclude
     * @return Number of plugins that executed (returned EXECUTED)
     */
    public static Integer executeFinallyExceptCategory(UoWContext ctx, UoWResult result, UoWEnums.PluginCategory category) {
        List<UoWInterfaces.IPlugin> plugins = UoWPluginRegistry.getInstance().getEnabledPlugins(ctx, result);

        Integer executedCount = 0;
        for (UoWInterfaces.IPlugin plugin : plugins) {
            // Skip plugins of the specified category
            if (plugin instanceof UoWBasePlugin) {
                UoWBasePlugin basePlugin = (UoWBasePlugin) plugin;
                if (basePlugin.getCategory() == category) {
                    continue;
                }
            }

            try {
                PhaseResult phaseResult = plugin.onFinally(ctx, result);
                if (phaseResult == UoWPluginExecutor.PhaseResult.EXECUTED) {
                    addPluginTraceEvent(result, plugin, 'Finally');
                    executedCount++;
                }
            } catch (Exception ex) {
                handlePluginError(plugin, 'onFinally', ex, result);
            }
        }
        return executedCount;
    }

    /**
     * Execute onFinally for specific category plugins only.
     *
     * @param ctx Execution context
     * @param result Result object for logging
     * @param category Plugin category to execute
     * @return Number of plugins that executed (returned EXECUTED)
     */
    public static Integer executeFinallyByCategory(UoWContext ctx, UoWResult result, UoWEnums.PluginCategory category) {
        List<UoWInterfaces.IPlugin> plugins = UoWPluginRegistry.getInstance().getEnabledPlugins(ctx, result);

        Integer executedCount = 0;
        for (UoWInterfaces.IPlugin plugin : plugins) {
            // Only execute plugins of the specified category
            if (plugin instanceof UoWBasePlugin) {
                UoWBasePlugin basePlugin = (UoWBasePlugin) plugin;
                if (basePlugin.getCategory() == category) {
                    try {
                        PhaseResult phaseResult = plugin.onFinally(ctx, result);
                        if (phaseResult == UoWPluginExecutor.PhaseResult.EXECUTED) {
                            addPluginTraceEvent(result, plugin, 'Finally');
                            executedCount++;
                        }
                    } catch (Exception ex) {
                        handlePluginError(plugin, 'onFinally[' + category + ']', ex, result);
                    }
                }
            }
        }
        return executedCount;
    }

    // ============================================================================
    // PRIVATE METHODS - ERROR HANDLING
    // ============================================================================

    // Handle plugin execution errors based on criticality
    private static void handlePluginError(UoWInterfaces.IPlugin plugin, String phase, Exception ex, UoWResult result) {
        // Check if plugin is critical - if so, fail the transaction
        if (plugin.isCritical()) {
            String errorMessage = String.format(
                System.Label.UoW_Error_CriticalPluginFailedExecution,
                new List<String>{ plugin.getName(), phase, ex.getMessage() });
            throw new UoWExceptionService.UoWException(errorMessage, ex);
        }

        // Non-critical plugin - log warning and continue
        String errorMessage = String.format(
            System.Label.UoW_Error_NonCriticalPluginFailedExecution,
            new List<String>{ plugin.getName(), phase, ex.getMessage() });
        result.warn(errorMessage, SOURCE);
    }

    // ============================================================================
    // PRIVATE METHODS - TRACING
    // ============================================================================

    // Add trace event for plugin execution
    private static void addPluginTraceEvent(UoWResult result, UoWInterfaces.IPlugin plugin, String phase) {
        result.addTraceEvent('Plugin ' + plugin.getName() + ' executed',
            new Map<String, Object>{
                'phase' => phase,
                'plugin' => plugin.getName(),
                'category' => plugin.getCategory(),
                'isCritical' => plugin.isCritical()
            });
    }

}