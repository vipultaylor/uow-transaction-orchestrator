//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Cache service for UnitOfWork framework.
 * Provides cached describe operations to reduce governor limit consumption.
 * This is a core framework service, not an optional plugin.
 * Cache is transaction-scoped and automatically cleared after each transaction.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Services
 */
public inherited sharing class UoWCacheService {

    // ============================================================================
    // PRIVATE FIELDS
    // ============================================================================

    private static Map<String, Schema.SObjectType> globalDescribeCache =
        new Map<String, Schema.SObjectType>();

    private static Map<String, Schema.DescribeSObjectResult> describeCache =
        new Map<String, Schema.DescribeSObjectResult>();

    private static Map<String, Schema.DescribeFieldResult> fieldDescribeCache =
        new Map<String, Schema.DescribeFieldResult>();

    // Cache configuration (can be enhanced with Custom Metadata in future)
    private static final Integer MAX_CACHE_SIZE = 1000;
    private static Boolean cacheEnabled = true;

    // ============================================================================
    // PUBLIC API - DESCRIBE OPERATIONS
    // ============================================================================

    /**
     * Get SObject describe (cached)
     *
     * @return Global describe map
     */
    public static Map<String, Schema.SObjectType> getGlobalDescribe() {
        if (!cacheEnabled) {
            return Schema.getGlobalDescribe();
        }

        if (globalDescribeCache.isEmpty()) {
            globalDescribeCache = Schema.getGlobalDescribe();
        }

        return globalDescribeCache;
    }

    /**
     * Get SObject type from global describe by name (cached)
     *
     * @param sObjectName SObject API name
     * @return SObject type
     */
    public static Schema.SObjectType getSobjectTypeFromGlobalDescribe(String sObjectName) {
        UoWExceptionService.requireNonNull(sObjectName, 'SObjectName for Global Describe');

        Map<String, Schema.SObjectType> mapGlobalDescribe = getGlobalDescribe();
        UoWExceptionService.require(mapGlobalDescribe.containsKey(sObjectName), 'SObjectName ' + sObjectName + ' invalid for this org');

        return mapGlobalDescribe.get(sObjectName);
    }

    /**
     * Get SObject describe (cached)
     *
     * @param sType SObject type
     * @return Describe result
     */
    public static Schema.DescribeSObjectResult getDescribe(Schema.SObjectType sType) {
        UoWExceptionService.requireNonNull(sType, 'SObjectType for describe');

        // PERFORMANCE: Use String.valueOf(sType) as cache key to avoid calling getDescribe() before cache check
        String cacheKey = String.valueOf(sType);

        if (!cacheEnabled) {
            return sType.getDescribe(SObjectDescribeOptions.DEFERRED);
        }

        if (!describeCache.containsKey(cacheKey)) {
            // Check cache size limit
            if (describeCache.size() >= MAX_CACHE_SIZE) {
                // Simple eviction: clear entire cache
                describeCache.clear();
            }
            describeCache.put(cacheKey, sType.getDescribe(SObjectDescribeOptions.DEFERRED));
        }

        return describeCache.get(cacheKey);
    }

    /**
     * Get field describe (cached)
     *
     * @param field SObject field
     * @return Field describe result
     */
    public static Schema.DescribeFieldResult getFieldDescribe(Schema.SObjectField field) {
        UoWExceptionService.requireNonNull(field, 'SObjectField for describe');

        if (!cacheEnabled) {
            return field.getDescribe(FieldDescribeOptions.DEFAULT);
        }

        String cacheKey = String.valueOf(field);

        if (!fieldDescribeCache.containsKey(cacheKey)) {
            // Check cache size limit
            if (fieldDescribeCache.size() >= MAX_CACHE_SIZE) {
                // Simple eviction: clear entire cache
                fieldDescribeCache.clear();
            }
            fieldDescribeCache.put(cacheKey, field.getDescribe(FieldDescribeOptions.DEFAULT));
        }

        return fieldDescribeCache.get(cacheKey);
    }

    /**
     * Warmup cache with describes for given SObject types.
     * Typically called before transaction to pre-populate cache.
     *
     * @param sObjectTypes Set of SObject types to cache
     */
    public static void warmupCache(Set<Schema.SObjectType> sObjectTypes) {
        if (!cacheEnabled || sObjectTypes == null || sObjectTypes.isEmpty()) {
            return;
        }

        for (Schema.SObjectType sType : sObjectTypes) {
            getDescribe(sType);
        }
    }

    /**
     * Clear transaction cache.
     * Should be called after each transaction completes.
     */
    public static void clearCache() {
        globalDescribeCache.clear();
        describeCache.clear();
        fieldDescribeCache.clear();
    }

    /**
     * Enable or disable caching.
     * Useful for testing or debugging.
     *
     * @param enabled True to enable caching, false to disable
     */
    public static void setCacheEnabled(Boolean enabled) {
        cacheEnabled = enabled;
    }

    /**
     * Check if cache is enabled
     *
     * @return True if caching is enabled
     */
    public static Boolean isCacheEnabled() {
        return cacheEnabled;
    }
}