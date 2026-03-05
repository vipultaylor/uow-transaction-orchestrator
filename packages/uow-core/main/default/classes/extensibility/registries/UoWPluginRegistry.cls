//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Registry for managing UnitOfWork plugins.
 *
 * Responsibilities:
 * 1. Singleton management
 * 2. Plugin initialization from Custom Metadata
 * 3. Plugin retrieval (getEnabledPlugins)
 *
 * Plugin EXECUTION is handled by UoWPluginExecutor.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWInterfaces.IPlugin
 * @see UoWBasePlugin
 * @see UoWPluginExecutor
 */
public inherited sharing class UoWPluginRegistry {

    // ============================================================================
    // SINGLETON
    // ============================================================================

    private static UoWPluginRegistry instance;

    public static UoWPluginRegistry getInstance() {
        if (instance == null) {
            instance = new UoWPluginRegistry();
        }
        return instance;
    }

    // ============================================================================
    // PRIVATE PROPERTIES
    // ============================================================================

    private Map<String, Integer> pluginExecutionOrder; // Track execution order from metadata
    private Boolean isInitialized;

    @TestVisible
    private Map<String, UoWInterfaces.IPlugin> registeredPlugins;

    @TestVisible
    private static Boolean disableAutoInit = false;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    private UoWPluginRegistry() {
        this.registeredPlugins = new Map<String, UoWInterfaces.IPlugin>();
        this.pluginExecutionOrder = new Map<String, Integer>();
        this.isInitialized = false;
    }

    // ============================================================================
    // PUBLIC API - RETRIEVAL
    // ============================================================================

    /**
     * Get all enabled plugins (metadata + runtime) - Single source of truth.
     * This is the authoritative method for retrieving the complete plugin list.
     * Handles: metadata loading, runtime overrides, disabled plugins, execution order.
     *
     * @param ctx Execution context (provides runtime plugins and disabled list from FeatureSettings)
     * @param result Result object for logging warnings during initialization
     * @return List of all enabled plugins (sorted by execution order)
     */
    public List<UoWInterfaces.IPlugin> getEnabledPlugins(UoWContext ctx, UoWResult result) {
        // Initialize registry with context's configuration if not yet initialized
        if (!isInitialized && !disableAutoInit) {
            initialize(ctx, result);
        }

        // Use map for deduplication by plugin name (runtime overrides metadata)
        Map<String, UoWInterfaces.IPlugin> pluginsByName = new Map<String, UoWInterfaces.IPlugin>();

        // Add registry's metadata-loaded plugins first
        for (UoWInterfaces.IPlugin plugin : registeredPlugins.values()) {
            pluginsByName.put(plugin.getName(), plugin);
        }

        // Add resolved plugins from context (will override metadata plugins with same name)
        if (ctx != null) {
            UoWFeatureSettings settings = ctx.getFeatureSettings();
            if (settings.resolvedPlugins != null) {
                for (UoWInterfaces.IPlugin plugin : settings.resolvedPlugins) {
                    pluginsByName.put(plugin.getName(), plugin);
                }
            }

            // Filter out inactive plugins based on PluginSetting.isActive
            if (settings.plugins != null) {
                for (UoWFeatureSettings.PluginSetting pluginSetting : settings.plugins) {
                    if (pluginSetting.isActive == false) {
                        pluginsByName.remove(pluginSetting.pluginName);
                        pluginsByName.remove(pluginSetting.className);
                    }
                }
            }
        }

        // Convert to list and sort by execution order
        List<UoWInterfaces.IPlugin> plugins = pluginsByName.values();
        sortPluginsByOrder(plugins);

        return plugins;
    }

    // Initialize plugins from Custom Metadata configuration
    private void initialize(UoWContext ctx, UoWResult result) {
        if (isInitialized) {
            return;
        }

        // Load plugin settings from metadata
        UoWConfigurationLoader loader = UoWConfigurationLoader.getInstance();
        List<UoWPluginSetting__mdt> pluginSettings = loader.getPluginSettings(ctx?.configurationName);

        // Dynamically instantiate and register plugins from metadata
        for (UoWPluginSetting__mdt setting : pluginSettings) {
            if (setting.IsEnabled__c && String.isNotBlank(setting.PluginClassName__c)) {
                // Use shared instantiation method with result for warning logging
                UoWInterfaces.IPlugin plugin = UoWExtensibilityInstantiator.instantiatePlugin(
                    setting.PluginClassName__c, result, 'UoWPluginRegistry'
                );
                if (plugin != null) {
                    // Initialize plugin with its settings from metadata
                    plugin.initialize(setting);

                    registeredPlugins.put(plugin.getName(), plugin);

                    // Store execution order from metadata
                    String pluginName = plugin.getName();
                    Integer execOrder = setting.ExecutionOrder__c?.intValue() ?? 100;
                    pluginExecutionOrder.put(pluginName, execOrder);
                }
            }
        }

        isInitialized = true;
    }

    // Sort plugins by execution order from metadata using efficient algorithm
    private void sortPluginsByOrder(List<UoWInterfaces.IPlugin> plugins) {
        // Use built-in sort with custom comparator wrapper
        // Create wrapper list with sort keys for O(n log n) performance
        List<PluginOrderWrapper> wrappers = new List<PluginOrderWrapper>();
        for (UoWInterfaces.IPlugin plugin : plugins) {
            wrappers.add(new PluginOrderWrapper(plugin, getPluginExecutionOrder(plugin)));
        }

        // Sort using merge sort (List.sort underlying algorithm)
        wrappers.sort();

        // Extract sorted plugins back to original list
        plugins.clear();
        for (PluginOrderWrapper wrapper : wrappers) {
            plugins.add(wrapper.plugin);
        }
    }

    // ============================================================================
    // TEST-VISIBLE API - REGISTRATION (for test setup/teardown only)
    // ============================================================================

    // Clear all registered plugins (test use only - resets singleton state)
    @TestVisible
    private void clearAll() {
        registeredPlugins.clear();
        pluginExecutionOrder.clear();
        isInitialized = false;
    }

    // ============================================================================
    // INNER CLASSES
    // ============================================================================

    // Wrapper class for plugin sorting - implements Comparable
    private class PluginOrderWrapper implements Comparable {
        public UoWInterfaces.IPlugin plugin;
        public Integer executionOrder;

        public PluginOrderWrapper(UoWInterfaces.IPlugin plugin, Integer executionOrder) {
            this.plugin = plugin;
            this.executionOrder = executionOrder;
        }

        public Integer compareTo(Object other) {
            PluginOrderWrapper otherWrapper = (PluginOrderWrapper) other;
            return this.executionOrder - otherWrapper.executionOrder;
        }
    }

    // Get execution order for a plugin from registry
    private Integer getPluginExecutionOrder(UoWInterfaces.IPlugin plugin) {
        String pluginName = plugin.getName();
        return pluginExecutionOrder.containsKey(pluginName) ?
            pluginExecutionOrder.get(pluginName) : 100; // Default to 100 if not found
    }

}