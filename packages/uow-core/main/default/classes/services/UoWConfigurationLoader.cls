//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Loads UnitOfWork configuration from Custom Metadata Types.
 * Provides metadata-driven configuration for plugins and policies.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Services
 */
public inherited sharing class UoWConfigurationLoader {

    // ============================================================================
    // SINGLETON
    // ============================================================================

    private static UoWConfigurationLoader instance;

    public static UoWConfigurationLoader getInstance() {
        if (instance == null) {
            instance = new UoWConfigurationLoader();
        }
        return instance;
    }

    /**
     * Reset the singleton instance (for testing purposes).
     * This forces a fresh load of configuration data on next getInstance() call.
     */
    @TestVisible
    private static void resetInstance() {
        instance = null;
    }

    // ============================================================================
    // CACHE
    // ============================================================================

    private Map<String, UoWConfiguration__mdt> configCache;
    private Map<String, List<UoWPluginSetting__mdt>> pluginSettingsCache;
    private Map<String, List<UoWPolicySetting__mdt>> policySettingsCache;
    private Map<String, Map<String, UoWObjectSetting__mdt>> objectSettingsCache; // configName -> (sobjectType -> setting)

    // ============================================================================
    // CONSTRUCTOR
    // ============================================================================

    private UoWConfigurationLoader() {
        loadAllConfigurations();
    }

    // ============================================================================
    // CONFIGURATION LOADING
    // ============================================================================

    // Load all configuration from custom metadata using separate queries
    // Note: Separate queries are used instead of subqueries for reliability with Test.loadData()
    // Uses Configuration__c (Id) for relationship resolution instead of traversing relationship
    private void loadAllConfigurations() {
        configCache = new Map<String, UoWConfiguration__mdt>();
        pluginSettingsCache = new Map<String, List<UoWPluginSetting__mdt>>();
        policySettingsCache = new Map<String, List<UoWPolicySetting__mdt>>();
        objectSettingsCache = new Map<String, Map<String, UoWObjectSetting__mdt>>();

        // Map of Configuration Id to DeveloperName for relationship resolution
        Map<String, String> configIdToName = new Map<String, String>();

        // Load all configurations
        for (UoWConfiguration__mdt config : [
            SELECT Id, DeveloperName, Label,
                        // Custom fields (alphabetical order)
                        ApprovalChannelClassName__c,
                        ApprovalMetadataJson__c,
                        ApprovalNamedCredential__c,
                        ApprovalTimeoutMinutes__c,
                        CalloutStrategyClassName__c,
                        ConfidenceThreshold__c,
                        Description__c,
                        DmlBatchSize__c,
                        DmlSecurityMode__c,
                        DmlStrategyClassName__c,
                        EmailChannelClassName__c,
                        EnableMasking__c,
                        EnableOriginSourceMetadata__c,
                        EnableScenarioRecordTracking__c,
                        EnableTracing__c,
                        EventBatchSize__c,
                        EventChannelClassName__c,
                        FlowChannelClassName__c,
                        MaxAsyncDepth__c,
                        MaxDmlBatchSize__c,
                        MinimumLoggingLevel__c,
                        NotificationChannelClassName__c,
                        RethrowTransactionExceptions__c,
                        RiskApprovalThreshold__c,
                        RiskAssessorClassName__c,
                        RiskBlockThreshold__c,
                        RiskCriticalThreshold__c,
                        RiskHighThreshold__c,
                        RiskLowThreshold__c,
                        RiskMediumThreshold__c,
                        TransactionFinalizerClassName__c,
                        EventPublishFailureHandlerClassName__c
                FROM UoWConfiguration__mdt
        ]) {
            // Cache configuration
            configCache.put(config.DeveloperName, config);
            configIdToName.put(config.Id, config.DeveloperName);

            // Initialize empty caches for child records
            pluginSettingsCache.put(config.DeveloperName, new List<UoWPluginSetting__mdt>());
            policySettingsCache.put(config.DeveloperName, new List<UoWPolicySetting__mdt>());
            objectSettingsCache.put(config.DeveloperName, new Map<String, UoWObjectSetting__mdt>());
        }

        // Load plugin settings separately (more reliable with Test.loadData())
        // Use Configuration__c (Id) for relationship resolution
        for (UoWPluginSetting__mdt plugin : [
            SELECT Id, DeveloperName, Label,
                   ExecutionOrder__c, IsEnabled__c, PluginClassName__c, Settings__c,
                   Configuration__c
            FROM UoWPluginSetting__mdt
            WHERE IsEnabled__c = true
            ORDER BY ExecutionOrder__c ASC
        ]) {
            String configName = configIdToName.get(plugin.Configuration__c);
            if (configName != null && pluginSettingsCache.containsKey(configName)) {
                pluginSettingsCache.get(configName).add(plugin);
            }
        }

        // Load policy settings separately
        for (UoWPolicySetting__mdt policy : [
            SELECT Id, DeveloperName, Label,
                   IsEnabled__c, PolicyClassName__c, Settings__c,
                   Configuration__c
            FROM UoWPolicySetting__mdt
            WHERE IsEnabled__c = true
        ]) {
            String configName = configIdToName.get(policy.Configuration__c);
            if (configName != null && policySettingsCache.containsKey(configName)) {
                policySettingsCache.get(configName).add(policy);
            }
        }

        // Load object settings separately
        for (UoWObjectSetting__mdt objectSetting : [
            SELECT Id, DeveloperName, Label,
                   AuditSampleSize__c, AuditSampleStrategy__c, BaseRiskWeight__c,
                   DeleteRiskWeight__c, DmlStrategyClassName__c,
                   InsertRiskWeight__c, RiskLevel__c, SObjectType__c,
                   UndeleteRiskWeight__c, UpdateRiskWeight__c, UpsertRiskWeight__c,
                   Configuration__c
            FROM UoWObjectSetting__mdt
        ]) {
            String configName = configIdToName.get(objectSetting.Configuration__c);
            if (configName != null && objectSettingsCache.containsKey(configName)) {
                objectSettingsCache.get(configName).put(objectSetting.SObjectType__c, objectSetting);
            }
        }
    }

    // ============================================================================
    // CONFIGURATION RETRIEVAL
    // ============================================================================

    /**
     * Get configuration by name.
     *
     * @param configName Configuration name
     * @return Configuration record
     * @throws UoWException if configuration not found
     */
    public UoWConfiguration__mdt getConfiguration(String configName) {
        UoWExceptionService.requireNonBlank(configName, 'Config name');
        UoWExceptionService.require(configCache.containsKey(configName), 'Configuration not found: ' + configName + '. Please ensure UoWConfiguration__mdt record exists with DeveloperName: ' + configName);

        return configCache.get(configName);
    }

    // ============================================================================
    // PLUGIN SETTINGS
    // ============================================================================

    /**
     * Get enabled plugin settings for a configuration.
     *
     * @param configName Configuration name
     * @return List of plugin settings
     * @throws UoWException if configuration not found
     */
    public List<UoWPluginSetting__mdt> getPluginSettings(String configName) {
        // Validate configuration exists
        getConfiguration(configName);

        return pluginSettingsCache.get(configName) ?? new List<UoWPluginSetting__mdt>();
    }

    // ============================================================================
    // POLICY SETTINGS
    // ============================================================================

    /**
     * Get enabled policy settings for a configuration.
     *
     * @param configName Configuration name
     * @return List of policy settings
     * @throws UoWException if configuration not found
     */
    public List<UoWPolicySetting__mdt> getPolicySettings(String configName) {
        // Validate configuration exists
        getConfiguration(configName);

        return policySettingsCache.get(configName) ?? new List<UoWPolicySetting__mdt>();
    }

    // ============================================================================
    // OBJECT SETTINGS
    // ============================================================================

    /**
     * Get object setting for a specific SObject type.
     *
     * @param configName Configuration name
     * @param sobjectType SObject API name (e.g., 'Account', 'CustomObject__c')
     * @return Object setting or null if not found
     * @throws UoWException if configuration not found
     */
    public UoWObjectSetting__mdt getObjectSetting(String configName, String sobjectType) {
        UoWExceptionService.requireNonBlank(sobjectType, 'SObject Type');

        // Validate configuration exists
        getConfiguration(configName);

        Map<String, UoWObjectSetting__mdt> objectMap = objectSettingsCache.get(configName);
        if (objectMap != null && objectMap.containsKey(sobjectType)) {
            return objectMap.get(sobjectType);
        }

        return null;
    }

    /**
     * Get all object settings for a configuration.
     *
     * @param configName Configuration name
     * @return Map of sobjectType to object setting
     * @throws UoWException if configuration not found
     */
    public Map<String, UoWObjectSetting__mdt> getAllObjectSettings(String configName) {
        // Validate configuration exists
        getConfiguration(configName);

        return objectSettingsCache.get(configName) ?? new Map<String, UoWObjectSetting__mdt>();
    }
}