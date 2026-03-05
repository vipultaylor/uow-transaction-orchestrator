//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Registry for managing UnitOfWork policies.
 *
 * Responsibilities:
 * 1. Singleton management
 * 2. Policy registration (metadata + runtime)
 * 3. Policy initialization from Custom Metadata
 * 4. Policy retrieval (getEnabledPolicies)
 *
 * Policy EVALUATION is handled by UoWPolicyEvaluation.evaluateAll().
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWInterfaces.IPolicy
 * @see UoWBasePolicy
 * @see UoWPolicyEvaluation
 */
public inherited sharing class UoWPolicyRegistry {

    // ============================================================================
    // SINGLETON
    // ============================================================================

    private static UoWPolicyRegistry instance;

    public static UoWPolicyRegistry getInstance() {
        if (instance == null) {
            instance = new UoWPolicyRegistry();
        }
        return instance;
    }

    // ============================================================================
    // PRIVATE PROPERTIES
    // ============================================================================

    private Boolean isInitialized;

    @TestVisible
    private Map<String, UoWInterfaces.IPolicy> registeredPolicies;

    @TestVisible
    private static Boolean disableAutoInit = false;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    private UoWPolicyRegistry() {
        this.registeredPolicies = new Map<String, UoWInterfaces.IPolicy>();
        this.isInitialized = false;
    }

    // ============================================================================
    // PUBLIC API - RETRIEVAL
    // ============================================================================

    /**
     * Get all enabled policies (metadata + runtime) - Single source of truth.
     * This is the authoritative method for retrieving the complete policy list.
     *
     * @param ctx Execution context (provides runtime policies from FeatureSettings)
     * @param result Result object for logging warnings during initialization
     * @return List of all enabled policies (metadata + runtime, deduplicated by name)
     */
    public List<UoWInterfaces.IPolicy> getEnabledPolicies(UoWContext ctx, UoWResult result) {
        // Initialize registry with context's configuration if not yet initialized
        if (!isInitialized && !disableAutoInit) {
            initialize(ctx, result);
        }

        // Use map for deduplication by policy name (runtime overrides metadata)
        Map<String, UoWInterfaces.IPolicy> policiesByName = new Map<String, UoWInterfaces.IPolicy>();

        // Add registry's metadata-loaded policies first
        for (UoWInterfaces.IPolicy policy : registeredPolicies.values()) {
            policiesByName.put(policy.getName(), policy);
        }

        // Add resolved policies (will override metadata policies with same name)
        if (ctx != null) {
            UoWFeatureSettings settings = ctx.getFeatureSettings();
            if (settings.resolvedPolicies != null) {
                for (UoWInterfaces.IPolicy policy : settings.resolvedPolicies) {
                    policiesByName.put(policy.getName(), policy);
                }
            }
        }

        return policiesByName.values();
    }

    // ============================================================================
    // PRIVATE METHODS - INITIALIZATION
    // ============================================================================

    // Initialize policies from Custom Metadata configuration
    private void initialize(UoWContext ctx, UoWResult result) {
        if (isInitialized) {
            return;
        }

        // Load policy settings from metadata
        UoWConfigurationLoader loader = UoWConfigurationLoader.getInstance();
        List<UoWPolicySetting__mdt> policySettings = loader.getPolicySettings(ctx?.configurationName);

        // Dynamically instantiate and register policies from metadata
        for (UoWPolicySetting__mdt setting : policySettings) {
            if (setting.IsEnabled__c && String.isNotBlank(setting.PolicyClassName__c)) {
                // Use shared instantiation method with result for warning logging
                UoWInterfaces.IPolicy policy = UoWExtensibilityInstantiator.instantiatePolicy(
                    setting.PolicyClassName__c, result, 'UoWPolicyRegistry'
                );
                if (policy != null) {
                    // Register the policy
                    registeredPolicies.put(policy.getName(), policy);
                }
            }
        }

        isInitialized = true;
    }

    // ============================================================================
    // TEST-VISIBLE API
    // ============================================================================

    // Clear all registered policies (test use only - resets singleton state)
    @TestVisible
    private void clearAll() {
        registeredPolicies.clear();
        isInitialized = false;
    }

}