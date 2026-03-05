//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Registry for DML execution strategies (Pattern C: Per-Key Extensibility).
 *
 * 4-Tier Priority Resolution:
 * 1. Already resolved instance (ctx.getFeatureSettings().resolvedDmlStrategies per SObjectType)
 * 2. Object-specific override (ctx.getFeatureSettings().dmlStrategyOverrides or objectSettings)
 * 3. Global configuration (ctx.getFeatureSettings().dmlStrategyClassName)
 * 4. Default fallback (UoWBaseDmlStrategy)
 *
 * Registry owns resolution logic for Pattern C (per-key extensibility).
 * Resolution updates dmlStrategyOverrides so audit sees the actual class used.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWInterfaces.IDmlStrategy
 * @see UoWBaseDmlStrategy
 */
public inherited sharing class UoWDmlStrategyRegistry {

    // ============================================================================
    // SINGLETON
    // ============================================================================

    private static UoWDmlStrategyRegistry instance;

    public static UoWDmlStrategyRegistry getInstance() {
        if (instance == null) {
            instance = new UoWDmlStrategyRegistry();
        }
        return instance;
    }

    // ============================================================================
    // PUBLIC API - EXECUTION
    // ============================================================================

    /**
     * Execute DML work item using resolved strategy - static entry point.
     *
     * @param workItem The DML work item
     * @param ctx The execution context
     * @param result The execution result for logging
     */
    public static void executeDml(UoWDmlWorkItem workItem, UoWContext ctx, UoWResult result) {
        getInstance().executeWithResolvedStrategy(workItem, ctx, result);
    }

    // ============================================================================
    // PRIVATE METHODS
    // ============================================================================

    // Execute DML work item using dynamically resolved strategy
    private void executeWithResolvedStrategy(UoWDmlWorkItem workItem, UoWContext ctx, UoWResult result) {
        List<SObject> records = workItem?.getOriginalRecords();
        if (workItem == null || records == null || records.isEmpty()) {
            return;
        }

        UoWInterfaces.IDmlStrategy strategy = resolveForSObjectType(workItem.sobjectType, ctx, result);

        switch on workItem.operation {
            when INSERT_OP {
                strategy.executeInsert(workItem, ctx);
            }
            when UPDATE_OP {
                strategy.executeUpdate(workItem, ctx);
            }
            when UPSERT_OP {
                strategy.executeUpsert(workItem, ctx);
            }
            when DELETE_OP {
                strategy.executeDelete(workItem, ctx);
            }
            when UNDELETE_OP {
                strategy.executeUndelete(workItem, ctx);
            }
        }
    }

    // ============================================================================
    // PUBLIC API - RESOLUTION
    // ============================================================================

    /**
     * Resolve DML strategy for SObjectType using 4-tier priority (public for testing).
     * Updates featureSettings with resolved instance and class name override.
     *
     * @param sObjectType The SObjectType to resolve strategy for
     * @param ctx Execution context
     * @param result Execution result for logging
     * @return DML strategy instance (never null)
     */
    @TestVisible
    public UoWInterfaces.IDmlStrategy resolveForSObjectType(Schema.SObjectType sObjectType, UoWContext ctx, UoWResult result) {
        UoWExceptionService.requireNonNull(sObjectType, 'sObjectType');
        UoWFeatureSettings settings = ctx.getFeatureSettings();

        // Priority 1: Already resolved instance (per SObjectType)
        UoWInterfaces.IDmlStrategy resolvedStrategy = settings.resolvedDmlStrategies?.get(sObjectType);
        if (resolvedStrategy != null) {
            return resolvedStrategy;
        }

        String objectName = UoWCacheService.getDescribe(sObjectType).getName();
        UoWInterfaces.IDmlStrategy strategy = null;

        // Priority 2a: Check dmlStrategyOverrides map first (runtime or from objectSettings)
        String overrideClassName = settings.dmlStrategyOverrides?.get(objectName);
        if (String.isNotBlank(overrideClassName)) {
            strategy = UoWExtensibilityInstantiator.instantiateDmlStrategy(
                overrideClassName, result, 'UoWDmlStrategyRegistry'
            );
        }

        // Priority 2b: Fall back to objectSettings for DML strategy (loaded from CMT)
        if (strategy == null && settings.objectSettings != null) {
            UoWFeatureSettings.ObjectSetting objSetting = settings.objectSettings.get(objectName);
            if (objSetting != null && objSetting.dmlStrategyClassName != null) {
                strategy = UoWExtensibilityInstantiator.instantiateDmlStrategy(
                    objSetting.dmlStrategyClassName, result, 'UoWDmlStrategyRegistry'
                );
            }
        }

        // Priority 3: Global configuration
        if (strategy == null && String.isNotBlank(settings.dmlStrategyClassName)) {
            strategy = UoWExtensibilityInstantiator.instantiateDmlStrategy(
                settings.dmlStrategyClassName, result, 'UoWDmlStrategyRegistry'
            );
        }

        // Priority 4: Default fallback
        if (strategy == null) {
            strategy = new UoWBaseDmlStrategy();

            // Set global class name if not already configured (so audit shows actual default used)
            if (String.isBlank(settings.dmlStrategyClassName)) {
                settings.dmlStrategyClassName = 'UoWBaseDmlStrategy';
            }
        }

        // Store resolved instance ONLY (transient, for reuse within this transaction)
        // Do NOT update dmlStrategyOverrides - that's only for configured overrides
        settings.resolvedDmlStrategies.put(sObjectType, strategy);

        return strategy;
    }
}