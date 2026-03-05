//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Base implementation for UnitOfWork plugins.
 * Provides common functionality and default implementations.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWInterfaces.IPlugin, UoWPluginExecutor, UoWPluginRegistry
 */
public virtual inherited sharing class UoWBasePlugin implements UoWInterfaces.IPlugin {

    // ============================================================================
    // PROTECTED PROPERTIES
    // ============================================================================

    protected String pluginName; // Plugin name for identification
    protected UoWEnums.PluginCategory pluginCategory; // Plugin category for execution order
    protected UoWPluginSetting__mdt pluginSetting; // Plugin configuration from metadata

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    public UoWBasePlugin(String name) {
        this(name, UoWEnums.PluginCategory.STANDARD);
    }

    public UoWBasePlugin(String name, UoWEnums.PluginCategory category) {
        this.pluginName = name;
        this.pluginCategory = category;
    }

    // ============================================================================
    // PUBLIC API - INTERFACE IMPLEMENTATION
    // ============================================================================

    /**
     * Initialize plugin with settings from metadata.
     * Called after instantiation by the plugin registry.
     * Override in subclasses to parse and use custom settings.
     * @param pluginSetting The plugin setting CMT record (may be null for runtime-registered plugins)
     */
    public virtual void initialize(UoWPluginSetting__mdt pluginSetting) {
        this.pluginSetting = pluginSetting;
    }

    /**
     * Get plugin name
     * @return Plugin name
     */
    public virtual String getName() {
        return this.pluginName;
    }

    /**
     * Get plugin category (determines execution order)
     * Default: STANDARD (executes first)
     * Override to return AUDIT for audit/logging plugins (executes last)
     * @return Plugin category
     */
    public virtual UoWEnums.PluginCategory getCategory() {
        return this.pluginCategory;
    }

    /**
     * Indicates if this plugin is critical to transaction success.
     * Default: false (non-critical - failures logged as warnings)
     * Override to return true for critical plugins (e.g., idempotency, security)
     * - true: Plugin failure rolls back transaction
     * - false: Plugin failure logged as warning, transaction continues
     * @return True if plugin failure should fail the transaction
     */
    public virtual Boolean isCritical() {
        return false;
    }

    /**
     * Called before commit
     * @param ctx Execution context
     * @param plan Execution plan
     * @param result Execution result (for logging)
     * @return PhaseResult.NOT_IMPLEMENTED by default - override to return EXECUTED or SKIPPED
     */
    public virtual UoWPluginExecutor.PhaseResult onBeforeCommit(UoWContext ctx, UoWPlan plan, UoWResult result) {
        return UoWPluginExecutor.PhaseResult.NOT_IMPLEMENTED;
    }

    /**
     * Called after commit
     * @param ctx Execution context
     * @param result Execution result
     * @return PhaseResult.NOT_IMPLEMENTED by default - override to return EXECUTED or SKIPPED
     */
    public virtual UoWPluginExecutor.PhaseResult onAfterCommit(UoWContext ctx, UoWResult result) {
        return UoWPluginExecutor.PhaseResult.NOT_IMPLEMENTED;
    }

    /**
     * Called on error
     * @param ctx Execution context
     * @param ex Exception that occurred
     * @param result Execution result (for logging)
     * @return PhaseResult.NOT_IMPLEMENTED by default - override to return EXECUTED or SKIPPED
     */
    public virtual UoWPluginExecutor.PhaseResult onError(UoWContext ctx, Exception ex, UoWResult result) {
        return UoWPluginExecutor.PhaseResult.NOT_IMPLEMENTED;
    }

    /**
     * Called in finally block
     * @param ctx Execution context
     * @param result Execution result
     * @return PhaseResult.NOT_IMPLEMENTED by default - override to return EXECUTED or SKIPPED
     */
    public virtual UoWPluginExecutor.PhaseResult onFinally(UoWContext ctx, UoWResult result) {
        return UoWPluginExecutor.PhaseResult.NOT_IMPLEMENTED;
    }
}