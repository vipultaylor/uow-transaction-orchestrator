//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Configuration for work item serialization behavior.
 * Controls whether masking and sampling are applied during serialization.
 *
 * Usage scenarios:
 * - Async execution: applyMasking=false, applySampling=false (preserve original data for DML)
 * - Audit snapshots: applyMasking=true, applySampling=true (data reduction + security)
 *
 * Factory methods:
 * - forAsync() - for async Queueable serialization
 * - forAudit() - for audit snapshots without sampling
 * - forAudit(strategy, count) - for audit snapshots with sampling
 * - fromObjectSetting(objSetting) - from CMT object settings
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Services
 */
public inherited sharing class UoWSerializationConfig {

    // ============================================================================
    // PUBLIC PROPERTIES
    // ============================================================================

    /** Whether to use masked records/events instead of originals */
    public Boolean applyMasking = false;

    /** Whether to apply sampling to reduce data volume */
    public Boolean applySampling = false;

    /** Sampling strategy (FIRST_N, LAST_N, RANDOM) */
    public UoWEnums.SamplingStrategy samplingStrategy = UoWEnums.SamplingStrategy.FIRST_N;

    /** Maximum number of records/events to include when sampling */
    public Integer samplingCount = 5;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Default constructor - no masking, no sampling (async-safe).
     */
    public UoWSerializationConfig() {}

    // ============================================================================
    // FACTORY METHODS
    // ============================================================================

    /**
     * Factory method for async execution serialization.
     * No masking, no sampling - preserves original data for DML execution.
     *
     * @return UoWSerializationConfig for async use
     */
    public static UoWSerializationConfig forAsync() {
        UoWSerializationConfig config = new UoWSerializationConfig();
        config.applyMasking = false;
        config.applySampling = false;
        return config;
    }

    /**
     * Factory method for audit snapshot with defaults.
     * Applies masking, no sampling (full audit).
     *
     * @return UoWSerializationConfig for full audit
     */
    public static UoWSerializationConfig forAudit() {
        UoWSerializationConfig config = new UoWSerializationConfig();
        config.applyMasking = true;
        config.applySampling = false;
        return config;
    }

    /**
     * Factory method for audit snapshot serialization.
     * Applies masking (if masked data available) and sampling.
     *
     * @param strategy Sampling strategy
     * @param count Maximum records to sample
     * @return UoWSerializationConfig for audit use
     */
    public static UoWSerializationConfig forAudit(UoWEnums.SamplingStrategy strategy, Integer count) {
        UoWSerializationConfig config = new UoWSerializationConfig();
        config.applyMasking = true;
        config.applySampling = true;
        config.samplingStrategy = strategy ?? UoWEnums.SamplingStrategy.FIRST_N;
        config.samplingCount = count ?? 5;
        return config;
    }

    /**
     * Build from object settings.
     * Creates audit-appropriate config from UoWFeatureSettings.ObjectSetting.
     *
     * @param objSetting The object setting containing sampling configuration
     * @return UoWSerializationConfig with masking enabled and sampling from settings
     */
    public static UoWSerializationConfig fromObjectSetting(UoWFeatureSettings.ObjectSetting objSetting) {
        UoWSerializationConfig config = new UoWSerializationConfig();
        config.applyMasking = true;

        // Resolve the strategy first so that NONE is authoritative regardless of sample size.
        // (NONE means "capture no records for this object"; it must win even when the size is unset.)
        if (objSetting != null && String.isNotBlank(objSetting.auditSampleStrategy)) {
            try {
                config.samplingStrategy = UoWEnums.SamplingStrategy.valueOf(objSetting.auditSampleStrategy);
            } catch (Exception ex) {
                config.samplingStrategy = UoWEnums.SamplingStrategy.FIRST_N;
            }
        }

        // NONE = no record capture: sampling logic short-circuits to an empty selection.
        if (config.samplingStrategy == UoWEnums.SamplingStrategy.NONE) {
            config.applySampling = true;
            config.samplingCount = 0;
            return config;
        }

        if (objSetting == null || objSetting.auditSampleSize == null || objSetting.auditSampleSize <= 0) {
            config.applySampling = false;
            return config;
        }

        config.applySampling = true;
        config.samplingCount = Integer.valueOf(objSetting.auditSampleSize);

        return config;
    }
}