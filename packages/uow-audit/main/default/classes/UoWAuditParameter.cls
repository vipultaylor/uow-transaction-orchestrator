//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Audit package parameter accessor for UoWParameters__mdt custom metadata.
 * Provides type-safe access to audit-specific global constants with caching.
 *
 * For core framework parameters, see UoWCoreParameter in the uow-core package.
 *
 * Usage:
 * - Access static properties for compile-time safety: UoWAuditParameter.MAX_FIELD_SIZE
 *
 * @group UoW Audit
 * @author Vipul Taylor
 */
public class UoWAuditParameter {

    // ============================================================================
    // SAMPLING PARAMETERS
    // ============================================================================

    /**
     * Default number of records to sample for audit snapshots.
     */
    public static Integer DEFAULT_SAMPLING_COUNT {
        get {
            if (DEFAULT_SAMPLING_COUNT == null) {
                DEFAULT_SAMPLING_COUNT = UoWParameterUtil.getInteger('DefaultSamplingCount', 5);
            }
            return DEFAULT_SAMPLING_COUNT;
        }
        private set;
    }

    /**
     * Default sampling strategy for audit snapshots.
     * Valid values: FIRST_N, LAST_N, RANDOM, SPREAD
     */
    public static String DEFAULT_SAMPLING_STRATEGY {
        get {
            if (DEFAULT_SAMPLING_STRATEGY == null) {
                DEFAULT_SAMPLING_STRATEGY = UoWParameterUtil.getString('DefaultSamplingStrategy', 'FIRST_N');
            }
            return DEFAULT_SAMPLING_STRATEGY;
        }
        private set;
    }

    // ============================================================================
    // STORAGE PARAMETERS
    // ============================================================================

    /**
     * Maximum field size for audit storage (in characters).
     * Default is 131072 (128KB) which is the Salesforce long text area limit.
     */
    public static Integer MAX_FIELD_SIZE {
        get {
            if (MAX_FIELD_SIZE == null) {
                MAX_FIELD_SIZE = UoWParameterUtil.getInteger('MaxAuditFieldSize', 131072);
            }
            return MAX_FIELD_SIZE;
        }
        private set;
    }

    /**
     * Default batch size for audit record processing.
     */
    public static Integer DEFAULT_BATCH_SIZE {
        get {
            if (DEFAULT_BATCH_SIZE == null) {
                DEFAULT_BATCH_SIZE = UoWParameterUtil.getInteger('DefaultAuditBatchSize', 200);
            }
            return DEFAULT_BATCH_SIZE;
        }
        private set;
    }

    // ============================================================================
    // RETENTION PARAMETERS
    // ============================================================================

    /**
     * Default number of days to retain audit records before archiving.
     */
    public static Integer DEFAULT_RETENTION_DAYS {
        get {
            if (DEFAULT_RETENTION_DAYS == null) {
                DEFAULT_RETENTION_DAYS = UoWParameterUtil.getInteger('DefaultRetentionDays', 14);
            }
            return DEFAULT_RETENTION_DAYS;
        }
        private set;
    }

    /**
     * Number of years to retain archived audit records before purging.
     */
    public static Integer ARCHIVE_RETENTION_YEARS {
        get {
            if (ARCHIVE_RETENTION_YEARS == null) {
                ARCHIVE_RETENTION_YEARS = UoWParameterUtil.getInteger('AuditArchiveRetentionYears', 7);
            }
            return ARCHIVE_RETENTION_YEARS;
        }
        private set;
    }

    // ============================================================================
    // FEATURE TOGGLES
    // ============================================================================

    /**
     * Whether the UoWScenarioTrigger on UoWScenario__c is active.
     * Disabled by default to avoid unnecessary execution overhead.
     */
    public static Boolean ENABLE_SCENARIO_TRIGGER {
        get {
            if (ENABLE_SCENARIO_TRIGGER == null) {
                ENABLE_SCENARIO_TRIGGER = UoWParameterUtil.getBoolean('EnableScenarioTrigger', false);
            }
            return ENABLE_SCENARIO_TRIGGER;
        }
        private set;
    }

    // ============================================================================
    // CONSTANTS (Non-configurable)
    // ============================================================================

    /** Event type identifier for transaction-level audit records */
    public static final String EVENT_TYPE_TRANSACTION = 'TRANSACTION';

    /** Event type identifier for work item-level audit records */
    public static final String EVENT_TYPE_WORK_ITEM = 'WORK_ITEM';

    /** Mapping plan name for Transaction to BigObject archival */
    public static final String PLAN_TRANSACTION_TO_BIGOBJECT = 'Transaction_To_BigObject';

    /** Mapping plan name for WorkItem to BigObject archival */
    public static final String PLAN_WORKITEM_TO_BIGOBJECT = 'WorkItem_To_BigObject';

    // ============================================================================
    // TESTING SUPPORT
    // ============================================================================

    /**
     * Clear the parameter cache. Useful for testing.
     */
    @TestVisible
    private static void clearCache() {
        UoWParameterUtil.clearCache();
        DEFAULT_SAMPLING_COUNT = null;
        DEFAULT_SAMPLING_STRATEGY = null;
        MAX_FIELD_SIZE = null;
        DEFAULT_BATCH_SIZE = null;
        DEFAULT_RETENTION_DAYS = null;
        ARCHIVE_RETENTION_YEARS = null;
        ENABLE_SCENARIO_TRIGGER = null;
    }
}
