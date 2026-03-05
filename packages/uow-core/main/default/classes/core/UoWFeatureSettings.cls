//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Framework-level configuration settings for UnitOfWork.
 *
 * Architecture:
 * - Scalar Settings: Read directly from stored UoWConfiguration__mdt metadata reference
 * - Extensibility Points: Class names that can be mutated during resolution
 * - Resolved Instances: Transient fields for runtime instances (not serialized)
 * - Plugins & Policies: Lists with metadata (execution order, isActive, isCritical)
 * - Object Settings: Per-SObjectType configuration
 *
 * Design Principle:
 * - Scalar settings (thresholds, batch sizes, flags) come ONLY from metadata
 * - Extensibility points (channels, strategies) support runtime injection for testing
 * - No runtime override for scalar settings - use different configuration instead
 *
 * LWC Consumption:
 * - Getter methods provide @AuraEnabled access to scalar settings
 * - Collections and class names are @AuraEnabled properties
 *
 * @author Vipul Taylor
 * @group UoW Core
 */
public inherited sharing class UoWFeatureSettings {

    // ============================================================================
    // PROPERTIES - CONFIGURATION METADATA REFERENCE
    // ============================================================================

    /**
     * The underlying configuration metadata record.
     * All scalar settings are read from this record via getter methods.
     * This is the single source of truth for configuration values.
     *
     * Note: Not @AuraEnabled - LWCs should use getter methods instead.
     */
    public UoWConfiguration__mdt configuration { get; private set; }

    /**
     * Configuration name for serialization/deserialization.
     * Used to reload configuration after async execution.
     */
    @AuraEnabled public String configurationName { get; private set; }

    // ============================================================================
    // PROPERTIES - SINGLE-INSTANCE EXTENSIBILITY (class names - mutated during resolution)
    // ============================================================================

    @AuraEnabled public String riskAssessorClassName;                    // Risk assessor class name
    @AuraEnabled public String eventChannelClassName;                    // Event channel class name
    @AuraEnabled public String emailChannelClassName;                    // Email channel class name
    @AuraEnabled public String notificationChannelClassName;             // Notification channel class name
    @AuraEnabled public String flowChannelClassName;                     // Flow channel class name
    @AuraEnabled public String calloutStrategyClassName;                 // Callout strategy class name
    @AuraEnabled public String approvalChannelClassName;                 // Approval channel class name
    @AuraEnabled public String transactionFinalizerClassName;            // Transaction finalizer class name (for async execution)
    @AuraEnabled public String eventPublishFailureHandlerClassName;     // Event publish failure handler class name

    // ============================================================================
    // PROPERTIES - DML STRATEGIES (global + per-object overrides)
    // ============================================================================

    @AuraEnabled public String dmlStrategyClassName;                     // Global default/fallback DML strategy class name
    @AuraEnabled public Map<String, String> dmlStrategyOverrides;        // SObjectType API name -> class name overrides

    // ============================================================================
    // PROPERTIES - PLUGINS & POLICIES (with metadata from CMT)
    // ============================================================================

    @AuraEnabled public List<PluginSetting> plugins;                     // Plugin configurations with execution order
    @AuraEnabled public List<PolicySetting> policies;                    // Policy configurations with execution order

    // ============================================================================
    // PROPERTIES - OBJECT SETTINGS (per-SObjectType configuration)
    // ============================================================================

    @AuraEnabled public Map<String, ObjectSetting> objectSettings;       // SObjectType API name -> settings

    // ============================================================================
    // PROPERTIES - RESOLVED INSTANCES (transient - for execution only, not serialized)
    // ============================================================================

    public transient Map<Schema.SObjectType, UoWInterfaces.IDmlStrategy> resolvedDmlStrategies;
    public transient UoWInterfaces.IRiskAssessor resolvedRiskAssessor;
    public transient UoWInterfaces.IEventChannel resolvedEventChannel;
    public transient UoWInterfaces.IEmailChannel resolvedEmailChannel;
    public transient UoWInterfaces.INotificationChannel resolvedNotificationChannel;
    public transient UoWInterfaces.IFlowChannel resolvedFlowChannel;
    public transient UoWInterfaces.ICalloutStrategy resolvedCalloutStrategy;
    public transient UoWInterfaces.IApprovalChannel resolvedApprovalChannel;
    public transient UoWInterfaces.ITransactionFinalizer resolvedTransactionFinalizer;
    public transient UoWInterfaces.IEventPublishFailureHandler resolvedEventPublishFailureHandler;
    public transient List<UoWInterfaces.IPlugin> resolvedPlugins;
    public transient List<UoWInterfaces.IPolicy> resolvedPolicies;

    // ============================================================================
    // PROPERTIES - RUNTIME OVERRIDES (limited to observability features)
    // ============================================================================

    /**
     * Runtime override for tracing. When set, overrides the configuration value.
     * Useful for debugging specific transactions or when policies require tracing.
     */
    @TestVisible
    private Boolean tracingOverride;

    /**
     * Runtime override for masking. When set, overrides the configuration value.
     * Used when policies require masking for specific transactions.
     */
    @TestVisible
    private Boolean maskingOverride;

    /**
     * Runtime override for security mode. Used primarily for testing.
     * Allows tests to set PERMISSIVE mode without requiring metadata configuration.
     */
    @TestVisible
    private UoWEnums.SecurityMode securityModeOverride;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Constructor with configuration metadata.
     * All settings are loaded from the configuration record.
     * Use loadFromConfiguration() for the standard loading path.
     *
     * @param config The configuration metadata record
     */
    public UoWFeatureSettings(UoWConfiguration__mdt config) {
        initializeCollections();
        this.configuration = config;
        this.configurationName = config?.DeveloperName;
        loadExtensibilityClassNames(config);
    }

    // Initialize all collections to prevent null pointer exceptions
    private void initializeCollections() {
        this.dmlStrategyOverrides = new Map<String, String>();
        this.plugins = new List<PluginSetting>();
        this.policies = new List<PolicySetting>();
        this.objectSettings = new Map<String, ObjectSetting>();
        this.resolvedDmlStrategies = new Map<Schema.SObjectType, UoWInterfaces.IDmlStrategy>();
        this.resolvedPlugins = new List<UoWInterfaces.IPlugin>();
        this.resolvedPolicies = new List<UoWInterfaces.IPolicy>();
    }

    // Load extensibility class names from configuration
    private void loadExtensibilityClassNames(UoWConfiguration__mdt config) {
        if (config == null) {
            return;
        }

        this.dmlStrategyClassName = config.DmlStrategyClassName__c;
        this.riskAssessorClassName = config.RiskAssessorClassName__c;
        this.eventChannelClassName = config.EventChannelClassName__c;
        this.emailChannelClassName = config.EmailChannelClassName__c;
        this.notificationChannelClassName = config.NotificationChannelClassName__c;
        this.flowChannelClassName = config.FlowChannelClassName__c;
        this.calloutStrategyClassName = config.CalloutStrategyClassName__c;
        this.approvalChannelClassName = config.ApprovalChannelClassName__c;
        this.transactionFinalizerClassName = config.TransactionFinalizerClassName__c;
        this.eventPublishFailureHandlerClassName = config.EventPublishFailureHandlerClassName__c;
    }

    // ============================================================================
    // PUBLIC API - METADATA LOADING
    // ============================================================================

    /**
     * Load settings from configuration by name (uses cached configuration).
     * Loads parent configuration AND all child records (plugins, policies, object settings).
     *
     * @param configName Configuration name to load
     * @return UoWFeatureSettings instance populated with metadata values
     * @throws UoWException if configuration not found
     */
    public static UoWFeatureSettings loadFromConfiguration(String configName) {
        UoWConfigurationLoader loader = UoWConfigurationLoader.getInstance();
        UoWConfiguration__mdt config = loader.getConfiguration(configName);

        UoWFeatureSettings settings = new UoWFeatureSettings(config);

        // Load child records (plugins, policies, object settings)
        loadPluginSettings(settings, loader.getPluginSettings(configName));
        loadPolicySettings(settings, loader.getPolicySettings(configName));
        loadObjectSettings(settings, loader.getAllObjectSettings(configName));

        return settings;
    }

    // ============================================================================
    // PUBLIC API - SCALAR SETTING GETTERS (read from metadata)
    // ============================================================================

    /**
     * Get the DML security mode.
     */
    @AuraEnabled
    public UoWEnums.SecurityMode getDmlSecurityMode() {
        // Test override takes precedence
        if (this.securityModeOverride != null) {
            return this.securityModeOverride;
        }
        if (configuration?.DmlSecurityMode__c != null) {
            return UoWEnums.SecurityMode.valueOf(configuration.DmlSecurityMode__c);
        }
        return UoWEnums.SecurityMode.ENFORCED;
    }

    /**
     * Get the low risk threshold.
     */
    @AuraEnabled
    public Decimal getRiskLowThreshold() {
        return configuration?.RiskLowThreshold__c ?? UoWCoreParameter.DEFAULT_RISK_LOW_THRESHOLD;
    }

    /**
     * Get the medium risk threshold.
     */
    @AuraEnabled
    public Decimal getRiskMediumThreshold() {
        return configuration?.RiskMediumThreshold__c ?? UoWCoreParameter.DEFAULT_RISK_MEDIUM_THRESHOLD;
    }

    /**
     * Get the high risk threshold.
     */
    @AuraEnabled
    public Decimal getRiskHighThreshold() {
        return configuration?.RiskHighThreshold__c ?? UoWCoreParameter.DEFAULT_RISK_HIGH_THRESHOLD;
    }

    /**
     * Get the critical risk threshold.
     */
    @AuraEnabled
    public Decimal getRiskCriticalThreshold() {
        return configuration?.RiskCriticalThreshold__c ?? UoWCoreParameter.DEFAULT_RISK_CRITICAL_THRESHOLD;
    }

    /**
     * Get the risk approval threshold (nullable - null means disabled).
     */
    @AuraEnabled
    public Decimal getRiskApprovalThreshold() {
        return configuration?.RiskApprovalThreshold__c ?? UoWCoreParameter.DEFAULT_RISK_APPROVAL_THRESHOLD;
    }

    /**
     * Get the risk block threshold (nullable - null means disabled).
     */
    @AuraEnabled
    public Decimal getRiskBlockThreshold() {
        return configuration?.RiskBlockThreshold__c ?? UoWCoreParameter.DEFAULT_RISK_BLOCK_THRESHOLD;
    }

    /**
     * Get the maximum async depth.
     */
    @AuraEnabled
    public Integer getMaxAsyncDepth() {
        return configuration?.MaxAsyncDepth__c != null
            ? Integer.valueOf(configuration.MaxAsyncDepth__c)
            : UoWCoreParameter.DEFAULT_MAX_ASYNC_DEPTH;
    }

    /**
     * Check if tracing is enabled.
     * This is the only scalar setting that supports runtime override.
     */
    @AuraEnabled
    public Boolean getEnableTracing() {
        // Runtime override takes precedence
        if (this.tracingOverride != null) {
            return this.tracingOverride;
        }
        return configuration?.EnableTracing__c ?? false;
    }

    /**
     * Check if masking is enabled.
     * Supports runtime override for policy-driven masking requirements.
     */
    @AuraEnabled
    public Boolean getEnableMasking() {
        // Runtime override takes precedence
        if (this.maskingOverride != null) {
            return this.maskingOverride;
        }
        return configuration?.EnableMasking__c ?? false;
    }

    /**
     * Get the minimum logging level.
     */
    @AuraEnabled
    public System.LoggingLevel getMinimumLoggingLevel() {
        if (String.isNotBlank(configuration?.MinimumLoggingLevel__c)) {
            return LoggingLevel.valueOf(configuration.MinimumLoggingLevel__c);
        }
        return LoggingLevel.INFO;
    }

    /**
     * Get the confidence threshold for agent approval.
     */
    @AuraEnabled
    public Decimal getConfidenceThreshold() {
        return configuration?.ConfidenceThreshold__c ?? UoWCoreParameter.DEFAULT_CONFIDENCE_THRESHOLD;
    }

    // ============================================================================
    // PUBLIC API - RUNTIME TRACING OVERRIDE
    // ============================================================================

    /**
     * Enable tracing for this transaction (overrides configuration).
     */
    public void enableTracing() {
        this.tracingOverride = true;
    }

    /**
     * Disable tracing for this transaction (overrides configuration).
     */
    public void disableTracing() {
        this.tracingOverride = false;
    }

    /**
     * Enable masking for this transaction (overrides configuration).
     * Typically called by policies that require data masking.
     */
    public void enableMasking() {
        this.maskingOverride = true;
    }

    /**
     * Set security mode override (for testing purposes).
     * Allows tests to bypass security without metadata configuration.
     *
     * @param securityMode The security mode to use
     */
    @TestVisible
    public void setSecurityMode(UoWEnums.SecurityMode securityMode) {
        this.securityModeOverride = securityMode;
    }

    // ============================================================================
    // PUBLIC API - DML STRATEGY SETTERS
    // ============================================================================

    /**
     * Set resolved DML strategy for a specific SObjectType (runtime override).
     * Used by UnitOfWork.withDmlStrategy() to register object-specific overrides.
     * Updates both the override map (serializable) and resolved instance (transient).
     *
     * @param sObjectType The SObjectType to apply the strategy to
     * @param strategy The DML strategy instance
     */
    public void setResolvedDmlStrategy(Schema.SObjectType sObjectType, UoWInterfaces.IDmlStrategy strategy) {
        if (sObjectType != null && strategy != null) {
            // Update resolved instance (transient, for runtime reuse)
            this.resolvedDmlStrategies.put(sObjectType, strategy);

            // Update override map (serializable, for audit)
            String sobjectTypeName = UoWCacheService.getDescribe(sObjectType).getName();
            this.dmlStrategyOverrides.put(sobjectTypeName, extractClassName(strategy));
        }
    }

    /**
     * Get the DML strategy class name for a specific SObjectType.
     * Returns override if exists, otherwise global fallback.
     *
     * @param sobjectTypeName The SObjectType API name
     * @return Class name or null
     */
    public String getDmlStrategyClassName(String sobjectTypeName) {
        if (this.dmlStrategyOverrides != null && this.dmlStrategyOverrides.containsKey(sobjectTypeName)) {
            return this.dmlStrategyOverrides.get(sobjectTypeName);
        }
        return this.dmlStrategyClassName;
    }

    // ============================================================================
    // PUBLIC API - PLUGIN & POLICY SETTERS
    // ============================================================================

    /**
     * Add a resolved plugin instance.
     * Updates both the plugins list (serializable) and resolved instances (transient).
     *
     * @param plugin The plugin instance to register
     */
    public void addResolvedPlugin(UoWInterfaces.IPlugin plugin) {
        if (plugin == null) {
            return;
        }

        // Add to resolved instances (transient)
        if (!this.resolvedPlugins.contains(plugin)) {
            this.resolvedPlugins.add(plugin);
        }

        // Add to plugins list (serializable) if not already present
        String pluginName = plugin.getName();
        Boolean exists = false;
        for (PluginSetting setting : this.plugins) {
            if (setting.className == pluginName || setting.pluginName == pluginName) {
                exists = true;
                break;
            }
        }
        if (!exists) {
            PluginSetting setting = new PluginSetting();
            setting.className = String.valueOf(plugin).substringBefore(':');
            setting.pluginName = pluginName;
            setting.executionOrder = this.plugins.size() + 1000; // Runtime plugins at end
            setting.isActive = true;
            setting.isCritical = plugin.isCritical();
            this.plugins.add(setting);
        }
    }

    /**
     * Add a resolved policy instance.
     * Updates both the policies list (serializable) and resolved instances (transient).
     *
     * @param policy The policy instance to register
     */
    public void addResolvedPolicy(UoWInterfaces.IPolicy policy) {
        if (policy == null) {
            return;
        }

        // Add to resolved instances (transient)
        if (!this.resolvedPolicies.contains(policy)) {
            this.resolvedPolicies.add(policy);
        }

        // Add to policies list (serializable) if not already present
        String policyName = policy.getName();
        Boolean exists = false;
        for (PolicySetting setting : this.policies) {
            if (setting.className == policyName || setting.policyName == policyName) {
                exists = true;
                break;
            }
        }
        if (!exists) {
            PolicySetting setting = new PolicySetting();
            setting.className = String.valueOf(policy).substringBefore(':');
            setting.policyName = policyName;
            setting.executionOrder = this.policies.size() + 1000; // Runtime policies at end
            setting.isActive = true;
            setting.isCritical = policy.isCritical();
            this.policies.add(setting);
        }
    }

    /**
     * Disable a specific plugin by name.
     *
     * @param pluginName The name of the plugin to disable
     */
    public void disablePlugin(String pluginName) {
        if (String.isNotBlank(pluginName)) {
            for (PluginSetting setting : this.plugins) {
                if (setting.pluginName == pluginName || setting.className == pluginName) {
                    setting.isActive = false;
                    break;
                }
            }
        }
    }

    /**
     * Update plugin settings with runtime-resolved values from plugin instances.
     *
     * @param pluginInstances List of instantiated plugin instances
     */
    public void updatePluginSettingsFromInstances(List<UoWInterfaces.IPlugin> pluginInstances) {
        if (pluginInstances == null || this.plugins == null) {
            return;
        }

        Map<String, UoWInterfaces.IPlugin> instanceMap = new Map<String, UoWInterfaces.IPlugin>();
        for (UoWInterfaces.IPlugin plugin : pluginInstances) {
            instanceMap.put(plugin.getName(), plugin);
            String className = String.valueOf(plugin).substringBefore(':');
            instanceMap.put(className, plugin);
        }

        for (PluginSetting setting : this.plugins) {
            UoWInterfaces.IPlugin plugin = instanceMap.get(setting.pluginName);
            if (plugin == null) {
                plugin = instanceMap.get(setting.className);
            }
            if (plugin != null) {
                setting.isCritical = plugin.isCritical();
                UoWEnums.PluginCategory categoryEnum = plugin.getCategory();
                setting.category = categoryEnum != null ? categoryEnum.name() : null;
            }
        }
    }

    /**
     * Update policy settings with runtime-resolved values from policy instances.
     *
     * @param policyInstances List of instantiated policy instances
     */
    public void updatePolicySettingsFromInstances(List<UoWInterfaces.IPolicy> policyInstances) {
        if (policyInstances == null || this.policies == null) {
            return;
        }

        Map<String, UoWInterfaces.IPolicy> instanceMap = new Map<String, UoWInterfaces.IPolicy>();
        for (UoWInterfaces.IPolicy policy : policyInstances) {
            instanceMap.put(policy.getName(), policy);
            String className = String.valueOf(policy).substringBefore(':');
            instanceMap.put(className, policy);
        }

        for (PolicySetting setting : this.policies) {
            UoWInterfaces.IPolicy policy = instanceMap.get(setting.policyName);
            if (policy == null) {
                policy = instanceMap.get(setting.className);
            }
            if (policy != null) {
                setting.isCritical = policy.isCritical();
            }
        }
    }

    // ============================================================================
    // PUBLIC API - SINGLE-INSTANCE EXTENSIBILITY SETTERS
    // ============================================================================

    /**
     * Set resolved risk assessor.
     */
    public void setResolvedRiskAssessor(UoWInterfaces.IRiskAssessor assessor) {
        this.resolvedRiskAssessor = assessor;
        this.riskAssessorClassName = extractClassName(assessor);
    }

    /**
     * Set resolved event channel.
     */
    public void setResolvedEventChannel(UoWInterfaces.IEventChannel channel) {
        this.resolvedEventChannel = channel;
        this.eventChannelClassName = extractClassName(channel);
    }

    /**
     * Set resolved email channel.
     */
    public void setResolvedEmailChannel(UoWInterfaces.IEmailChannel channel) {
        this.resolvedEmailChannel = channel;
        this.emailChannelClassName = extractClassName(channel);
    }

    /**
     * Set resolved notification channel.
     */
    public void setResolvedNotificationChannel(UoWInterfaces.INotificationChannel channel) {
        this.resolvedNotificationChannel = channel;
        this.notificationChannelClassName = extractClassName(channel);
    }

    /**
     * Set resolved flow channel.
     */
    public void setResolvedFlowChannel(UoWInterfaces.IFlowChannel channel) {
        this.resolvedFlowChannel = channel;
        this.flowChannelClassName = extractClassName(channel);
    }

    /**
     * Set resolved callout strategy.
     */
    public void setResolvedCalloutStrategy(UoWInterfaces.ICalloutStrategy strategy) {
        this.resolvedCalloutStrategy = strategy;
        this.calloutStrategyClassName = extractClassName(strategy);
    }

    /**
     * Set resolved approval channel.
     */
    public void setResolvedApprovalChannel(UoWInterfaces.IApprovalChannel channel) {
        this.resolvedApprovalChannel = channel;
        this.approvalChannelClassName = extractClassName(channel);
    }

    /**
     * Set resolved transaction finalizer.
     */
    public void setResolvedTransactionFinalizer(UoWInterfaces.ITransactionFinalizer finalizer) {
        this.resolvedTransactionFinalizer = finalizer;
        this.transactionFinalizerClassName = extractClassName(finalizer);
    }

    /**
     * Set resolved event publish failure handler.
     */
    public void setResolvedEventPublishFailureHandler(UoWInterfaces.IEventPublishFailureHandler handler) {
        this.resolvedEventPublishFailureHandler = handler;
        this.eventPublishFailureHandlerClassName = extractClassName(handler);
    }

    // ============================================================================
    // PUBLIC API - SERIALIZATION LIFECYCLE
    // ============================================================================

    /**
     * Prepare feature settings for serialization.
     * For the new architecture, we just need to ensure configurationName is set.
     */
    public void prepareForSerialization() {
        // Configuration name is already set, nothing special needed
        // Enum values are handled by getter methods
    }

    /**
     * Hydrate feature settings after deserialization.
     * Reloads the configuration from metadata and restores transient instances.
     */
    public void hydrate() {
        // Reload configuration from metadata if we have a configuration name
        if (String.isNotBlank(this.configurationName)) {
            try {
                UoWConfigurationLoader loader = UoWConfigurationLoader.getInstance();
                this.configuration = loader.getConfiguration(this.configurationName);
            } catch (Exception ex) {
                // Configuration may not exist in this org - continue with defaults
                this.configuration = null;
            }
        }

        // Initialize transient collections if null
        if (this.resolvedDmlStrategies == null) {
            this.resolvedDmlStrategies = new Map<Schema.SObjectType, UoWInterfaces.IDmlStrategy>();
        }
        if (this.resolvedPlugins == null) {
            this.resolvedPlugins = new List<UoWInterfaces.IPlugin>();
        }
        if (this.resolvedPolicies == null) {
            this.resolvedPolicies = new List<UoWInterfaces.IPolicy>();
        }

        // Resolve extensibility points from class names
        hydrateExtensibilityPoints();
    }

    /**
     * Resolve extensibility points after deserialization.
     */
    public void hydrateExtensibilityPoints() {
        // Resolve DML strategies from override map
        if (this.dmlStrategyOverrides != null) {
            for (String sobjectTypeName : this.dmlStrategyOverrides.keySet()) {
                String className = this.dmlStrategyOverrides.get(sobjectTypeName);
                if (String.isNotBlank(className)) {
                    Schema.SObjectType sType = UoWCacheService.getSobjectTypeFromGlobalDescribe(sobjectTypeName);
                    if (sType != null) {
                        UoWInterfaces.IDmlStrategy strategy = instantiateDmlStrategy(className);
                        if (strategy != null) {
                            this.resolvedDmlStrategies.put(sType, strategy);
                        }
                    }
                }
            }
        }

        // Resolve plugins from settings list
        if (this.plugins != null) {
            for (PluginSetting setting : this.plugins) {
                if (setting.isActive && String.isNotBlank(setting.className)) {
                    UoWInterfaces.IPlugin plugin = instantiatePlugin(setting.className);
                    if (plugin != null) {
                        this.resolvedPlugins.add(plugin);
                    }
                }
            }
        }

        // Resolve policies from settings list
        if (this.policies != null) {
            for (PolicySetting setting : this.policies) {
                if (setting.isActive && String.isNotBlank(setting.className)) {
                    UoWInterfaces.IPolicy policy = instantiatePolicy(setting.className);
                    if (policy != null) {
                        this.resolvedPolicies.add(policy);
                    }
                }
            }
        }

        // Resolve single-instance extensibility points
        this.resolvedRiskAssessor = instantiateRiskAssessor(this.riskAssessorClassName);
        this.resolvedEventChannel = instantiateEventChannel(this.eventChannelClassName);
        this.resolvedEmailChannel = instantiateEmailChannel(this.emailChannelClassName);
        this.resolvedNotificationChannel = instantiateNotificationChannel(this.notificationChannelClassName);
        this.resolvedFlowChannel = instantiateFlowChannel(this.flowChannelClassName);
        this.resolvedCalloutStrategy = instantiateCalloutStrategy(this.calloutStrategyClassName);
        this.resolvedApprovalChannel = instantiateApprovalChannel(this.approvalChannelClassName);
        this.resolvedTransactionFinalizer = instantiateTransactionFinalizer(this.transactionFinalizerClassName);
    }

    // ============================================================================
    // PRIVATE HELPER METHODS - INSTANTIATION
    // ============================================================================

    private UoWInterfaces.IDmlStrategy instantiateDmlStrategy(String className) {
        if (String.isBlank(className)) {
            return null;
        }
        try {
            Type strategyType = Type.forName(className);
            if (strategyType != null) {
                return (UoWInterfaces.IDmlStrategy) strategyType.newInstance();
            }
        } catch (Exception ex) {
            // Silent failure
        }
        return null;
    }

    private UoWInterfaces.IPlugin instantiatePlugin(String className) {
        if (String.isBlank(className)) {
            return null;
        }
        try {
            Type pluginType = Type.forName(className);
            if (pluginType != null) {
                return (UoWInterfaces.IPlugin) pluginType.newInstance();
            }
        } catch (Exception ex) {
            // Silent failure
        }
        return null;
    }

    private UoWInterfaces.IPolicy instantiatePolicy(String className) {
        if (String.isBlank(className)) {
            return null;
        }
        try {
            Type policyType = Type.forName(className);
            if (policyType != null) {
                return (UoWInterfaces.IPolicy) policyType.newInstance();
            }
        } catch (Exception ex) {
            // Silent failure
        }
        return null;
    }

    private UoWInterfaces.IRiskAssessor instantiateRiskAssessor(String className) {
        if (String.isBlank(className)) {
            return null;
        }
        try {
            Type assessorType = Type.forName(className);
            if (assessorType != null) {
                return (UoWInterfaces.IRiskAssessor) assessorType.newInstance();
            }
        } catch (Exception ex) {
            // Silent failure
        }
        return null;
    }

    private UoWInterfaces.IEventChannel instantiateEventChannel(String className) {
        if (String.isBlank(className)) {
            return null;
        }
        try {
            Type channelType = Type.forName(className);
            if (channelType != null) {
                return (UoWInterfaces.IEventChannel) channelType.newInstance();
            }
        } catch (Exception ex) {
            // Silent failure
        }
        return null;
    }

    private UoWInterfaces.IEmailChannel instantiateEmailChannel(String className) {
        if (String.isBlank(className)) {
            return null;
        }
        try {
            Type channelType = Type.forName(className);
            if (channelType != null) {
                return (UoWInterfaces.IEmailChannel) channelType.newInstance();
            }
        } catch (Exception ex) {
            // Silent failure
        }
        return null;
    }

    private UoWInterfaces.INotificationChannel instantiateNotificationChannel(String className) {
        if (String.isBlank(className)) {
            return null;
        }
        try {
            Type channelType = Type.forName(className);
            if (channelType != null) {
                return (UoWInterfaces.INotificationChannel) channelType.newInstance();
            }
        } catch (Exception ex) {
            // Silent failure
        }
        return null;
    }

    private UoWInterfaces.IFlowChannel instantiateFlowChannel(String className) {
        if (String.isBlank(className)) {
            return null;
        }
        try {
            Type channelType = Type.forName(className);
            if (channelType != null) {
                return (UoWInterfaces.IFlowChannel) channelType.newInstance();
            }
        } catch (Exception ex) {
            // Silent failure
        }
        return null;
    }

    private UoWInterfaces.ICalloutStrategy instantiateCalloutStrategy(String className) {
        if (String.isBlank(className)) {
            return null;
        }
        try {
            Type strategyType = Type.forName(className);
            if (strategyType != null) {
                return (UoWInterfaces.ICalloutStrategy) strategyType.newInstance();
            }
        } catch (Exception ex) {
            // Silent failure
        }
        return null;
    }

    private UoWInterfaces.IApprovalChannel instantiateApprovalChannel(String className) {
        if (String.isBlank(className)) {
            return null;
        }
        try {
            Type channelType = Type.forName(className);
            if (channelType != null) {
                return (UoWInterfaces.IApprovalChannel) channelType.newInstance();
            }
        } catch (Exception ex) {
            // Silent failure
        }
        return null;
    }

    private UoWInterfaces.ITransactionFinalizer instantiateTransactionFinalizer(String className) {
        if (String.isBlank(className)) {
            return null;
        }
        try {
            Type finalizerType = Type.forName(className);
            if (finalizerType != null) {
                return (UoWInterfaces.ITransactionFinalizer) finalizerType.newInstance();
            }
        } catch (Exception ex) {
            // Silent failure
        }
        return null;
    }

    // Extract the Apex class name from an object instance
    private static String extractClassName(Object obj) {
        if (obj == null) {
            return null;
        }
        return String.valueOf(obj).split(':')[0];
    }

    // ============================================================================
    // PRIVATE METHODS - CHILD RECORD LOADING
    // ============================================================================

    private static void loadPluginSettings(UoWFeatureSettings settings, List<UoWPluginSetting__mdt> pluginMdts) {
        if (pluginMdts == null || pluginMdts.isEmpty()) {
            return;
        }

        for (UoWPluginSetting__mdt mdt : pluginMdts) {
            PluginSetting pluginSetting = createPluginSettingFromMetadata(mdt);
            settings.plugins.add(pluginSetting);
        }
    }

    private static void loadPolicySettings(UoWFeatureSettings settings, List<UoWPolicySetting__mdt> policyMdts) {
        if (policyMdts == null || policyMdts.isEmpty()) {
            return;
        }

        for (UoWPolicySetting__mdt mdt : policyMdts) {
            PolicySetting policySetting = createPolicySettingFromMetadata(mdt);
            settings.policies.add(policySetting);
        }
    }

    private static void loadObjectSettings(UoWFeatureSettings settings, Map<String, UoWObjectSetting__mdt> objectMdts) {
        if (objectMdts == null || objectMdts.isEmpty()) {
            return;
        }

        for (String sobjectType : objectMdts.keySet()) {
            UoWObjectSetting__mdt mdt = objectMdts.get(sobjectType);
            ObjectSetting objectSetting = createObjectSettingFromMetadata(mdt);
            settings.objectSettings.put(sobjectType, objectSetting);
        }
    }

    // ============================================================================
    // INNER CLASS FACTORY METHODS
    // ============================================================================

    /**
     * Factory method to create PluginSetting from CMT record.
     */
    public static PluginSetting createPluginSettingFromMetadata(UoWPluginSetting__mdt mdt) {
        PluginSetting setting = new PluginSetting();
        setting.className = mdt.PluginClassName__c;
        setting.pluginName = mdt.Label;
        setting.executionOrder = mdt.ExecutionOrder__c != null ? Integer.valueOf(mdt.ExecutionOrder__c) : 0;
        setting.isActive = mdt.IsEnabled__c;

        if (String.isNotBlank(mdt.Settings__c)) {
            setting.settingsJson = mdt.Settings__c;
            setting.settings = (Map<String, Object>) JSON.deserializeUntyped(mdt.Settings__c);
        }

        return setting;
    }

    /**
     * Factory method to create PolicySetting from CMT record.
     */
    public static PolicySetting createPolicySettingFromMetadata(UoWPolicySetting__mdt mdt) {
        PolicySetting setting = new PolicySetting();
        setting.className = mdt.PolicyClassName__c;
        setting.policyName = mdt.Label;
        setting.executionOrder = 0;
        setting.isActive = mdt.IsEnabled__c;

        if (String.isNotBlank(mdt.Settings__c)) {
            setting.settingsJson = mdt.Settings__c;
            setting.settings = (Map<String, Object>) JSON.deserializeUntyped(mdt.Settings__c);
        }

        return setting;
    }

    /**
     * Factory method to create ObjectSetting from CMT record.
     */
    public static ObjectSetting createObjectSettingFromMetadata(UoWObjectSetting__mdt mdt) {
        ObjectSetting setting = new ObjectSetting();
        setting.sobjectType = mdt.SObjectType__c;
        setting.dmlStrategyClassName = mdt.DmlStrategyClassName__c;
        setting.baseRiskWeight = mdt.BaseRiskWeight__c;
        setting.insertRiskWeight = mdt.InsertRiskWeight__c;
        setting.updateRiskWeight = mdt.UpdateRiskWeight__c;
        setting.upsertRiskWeight = mdt.UpsertRiskWeight__c;
        setting.deleteRiskWeight = mdt.DeleteRiskWeight__c;
        setting.undeleteRiskWeight = mdt.UndeleteRiskWeight__c;
        setting.riskLevel = mdt.RiskLevel__c;
        setting.auditSampleStrategy = mdt.AuditSampleStrategy__c;
        setting.auditSampleSize = mdt.AuditSampleSize__c;

        return setting;
    }

    // ============================================================================
    // INNER CLASSES
    // ============================================================================

    /**
     * Plugin configuration setting (mirrors UoWPluginSetting__mdt).
     */
    public class PluginSetting {
        @AuraEnabled public String className;
        @AuraEnabled public String pluginName;
        @AuraEnabled public Integer executionOrder;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean isCritical;
        @AuraEnabled public String category;
        @AuraEnabled public String settingsJson;
        public transient Map<String, Object> settings;

        public PluginSetting() {
            this.isActive = true;
            this.isCritical = false;
            this.settings = new Map<String, Object>();
        }
    }

    /**
     * Policy configuration setting (mirrors UoWPolicySetting__mdt).
     */
    public class PolicySetting {
        @AuraEnabled public String className;
        @AuraEnabled public String policyName;
        @AuraEnabled public Integer executionOrder;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean isCritical;
        @AuraEnabled public String settingsJson;
        public transient Map<String, Object> settings;

        public PolicySetting() {
            this.isActive = true;
            this.isCritical = true;
            this.settings = new Map<String, Object>();
        }
    }

    /**
     * Object-specific configuration setting (mirrors UoWObjectSetting__mdt).
     */
    public class ObjectSetting {
        @AuraEnabled public String sobjectType;
        @AuraEnabled public String dmlStrategyClassName;
        @AuraEnabled public Decimal baseRiskWeight;
        @AuraEnabled public Decimal insertRiskWeight;
        @AuraEnabled public Decimal updateRiskWeight;
        @AuraEnabled public Decimal upsertRiskWeight;
        @AuraEnabled public Decimal deleteRiskWeight;
        @AuraEnabled public Decimal undeleteRiskWeight;
        @AuraEnabled public String riskLevel;
        @AuraEnabled public String auditSampleStrategy;
        @AuraEnabled public Decimal auditSampleSize;

        public ObjectSetting() {
            this.baseRiskWeight = 1.0;
        }
    }

}