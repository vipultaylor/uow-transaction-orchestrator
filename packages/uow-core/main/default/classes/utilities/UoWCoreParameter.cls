//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Core framework parameter accessor for UoWParameters__mdt custom metadata.
 * Provides type-safe access to core-specific global constants with caching.
 *
 * For audit-specific parameters, see UoWAuditParameter in the uow-audit package.
 *
 * Usage:
 * - Access static properties for compile-time safety: UoWCoreParameter.DEFAULT_RISK_LOW_THRESHOLD
 *
 * @group UoW Core
 * @author Vipul Taylor
 */
public class UoWCoreParameter {

    // ============================================================================
    // DEFAULT RISK THRESHOLDS
    // ============================================================================

    /**
     * Default low risk threshold (risk score below this is NONE).
     */
    public static Decimal DEFAULT_RISK_LOW_THRESHOLD {
        get {
            if (DEFAULT_RISK_LOW_THRESHOLD == null) {
                DEFAULT_RISK_LOW_THRESHOLD = UoWParameterUtil.getDecimal('DefaultRiskLowThreshold', 25.0);
            }
            return DEFAULT_RISK_LOW_THRESHOLD;
        }
        private set;
    }

    /**
     * Default medium risk threshold (risk score at or above this is MEDIUM).
     */
    public static Decimal DEFAULT_RISK_MEDIUM_THRESHOLD {
        get {
            if (DEFAULT_RISK_MEDIUM_THRESHOLD == null) {
                DEFAULT_RISK_MEDIUM_THRESHOLD = UoWParameterUtil.getDecimal('DefaultRiskMediumThreshold', 50.0);
            }
            return DEFAULT_RISK_MEDIUM_THRESHOLD;
        }
        private set;
    }

    /**
     * Default high risk threshold (risk score at or above this is HIGH).
     */
    public static Decimal DEFAULT_RISK_HIGH_THRESHOLD {
        get {
            if (DEFAULT_RISK_HIGH_THRESHOLD == null) {
                DEFAULT_RISK_HIGH_THRESHOLD = UoWParameterUtil.getDecimal('DefaultRiskHighThreshold', 75.0);
            }
            return DEFAULT_RISK_HIGH_THRESHOLD;
        }
        private set;
    }

    /**
     * Default critical risk threshold (risk score at or above this is CRITICAL).
     */
    public static Decimal DEFAULT_RISK_CRITICAL_THRESHOLD {
        get {
            if (DEFAULT_RISK_CRITICAL_THRESHOLD == null) {
                DEFAULT_RISK_CRITICAL_THRESHOLD = UoWParameterUtil.getDecimal('DefaultRiskCriticalThreshold', 90.0);
            }
            return DEFAULT_RISK_CRITICAL_THRESHOLD;
        }
        private set;
    }

    /**
     * Default approval risk threshold (risk score at or above this requires approval).
     */
    public static Decimal DEFAULT_RISK_APPROVAL_THRESHOLD {
        get {
            if (DEFAULT_RISK_APPROVAL_THRESHOLD == null) {
                DEFAULT_RISK_APPROVAL_THRESHOLD = UoWParameterUtil.getDecimal('DefaultRiskApprovalThreshold', 75.0);
            }
            return DEFAULT_RISK_APPROVAL_THRESHOLD;
        }
        private set;
    }

    /**
     * Default block risk threshold (risk score at or above this blocks execution).
     */
    public static Decimal DEFAULT_RISK_BLOCK_THRESHOLD {
        get {
            if (DEFAULT_RISK_BLOCK_THRESHOLD == null) {
                DEFAULT_RISK_BLOCK_THRESHOLD = UoWParameterUtil.getDecimal('DefaultRiskBlockThreshold', 95.0);
            }
            return DEFAULT_RISK_BLOCK_THRESHOLD;
        }
        private set;
    }

    // ============================================================================
    // DEFAULT BATCH SIZES
    // ============================================================================

    /**
     * Default DML batch size for chunking large DML operations.
     */
    public static Integer DEFAULT_DML_BATCH_SIZE {
        get {
            if (DEFAULT_DML_BATCH_SIZE == null) {
                DEFAULT_DML_BATCH_SIZE = UoWParameterUtil.getInteger('DefaultDmlBatchSize', 200);
            }
            return DEFAULT_DML_BATCH_SIZE;
        }
        private set;
    }

    /**
     * Maximum DML batch size limit.
     */
    public static Integer DEFAULT_MAX_DML_BATCH_SIZE {
        get {
            if (DEFAULT_MAX_DML_BATCH_SIZE == null) {
                DEFAULT_MAX_DML_BATCH_SIZE = UoWParameterUtil.getInteger('DefaultMaxDmlBatchSize', 10000);
            }
            return DEFAULT_MAX_DML_BATCH_SIZE;
        }
        private set;
    }

    /**
     * Default event batch size for platform events.
     */
    public static Integer DEFAULT_EVENT_BATCH_SIZE {
        get {
            if (DEFAULT_EVENT_BATCH_SIZE == null) {
                DEFAULT_EVENT_BATCH_SIZE = UoWParameterUtil.getInteger('DefaultEventBatchSize', 100);
            }
            return DEFAULT_EVENT_BATCH_SIZE;
        }
        private set;
    }

    /**
     * Maximum async depth for queueable chaining.
     */
    public static Integer DEFAULT_MAX_ASYNC_DEPTH {
        get {
            if (DEFAULT_MAX_ASYNC_DEPTH == null) {
                DEFAULT_MAX_ASYNC_DEPTH = UoWParameterUtil.getInteger('DefaultMaxAsyncDepth', 1);
            }
            return DEFAULT_MAX_ASYNC_DEPTH;
        }
        private set;
    }

    // ============================================================================
    // DEFAULT APPROVAL SETTINGS
    // ============================================================================

    /**
     * Default confidence threshold for agent approval.
     */
    public static Decimal DEFAULT_CONFIDENCE_THRESHOLD {
        get {
            if (DEFAULT_CONFIDENCE_THRESHOLD == null) {
                DEFAULT_CONFIDENCE_THRESHOLD = UoWParameterUtil.getDecimal('DefaultConfidenceThreshold', 0.70);
            }
            return DEFAULT_CONFIDENCE_THRESHOLD;
        }
        private set;
    }

    /**
     * Default approval timeout in minutes.
     */
    public static Integer DEFAULT_APPROVAL_TIMEOUT_MINUTES {
        get {
            if (DEFAULT_APPROVAL_TIMEOUT_MINUTES == null) {
                DEFAULT_APPROVAL_TIMEOUT_MINUTES = UoWParameterUtil.getInteger('DefaultApprovalTimeoutMinutes', 30);
            }
            return DEFAULT_APPROVAL_TIMEOUT_MINUTES;
        }
        private set;
    }

    // ============================================================================
    // RETRY PARAMETERS
    // ============================================================================

    /**
     * HTTP status codes that should trigger automatic retry.
     */
    public static List<Integer> RETRYABLE_STATUS_CODES {
        get {
            if (RETRYABLE_STATUS_CODES == null) {
                RETRYABLE_STATUS_CODES = UoWParameterUtil.getIntegerList('RetryableStatusCodes', new List<Integer>{ 429, 500, 502, 503, 504 });
            }
            return RETRYABLE_STATUS_CODES;
        }
        private set;
    }

    // ============================================================================
    // TESTING SUPPORT
    // ============================================================================

    /**
     * Clear the parameter cache. Useful for testing.
     */
    @TestVisible
    private static void clearCache() {
        UoWParameterUtil.clearCache();
        DEFAULT_RISK_LOW_THRESHOLD = null;
        DEFAULT_RISK_MEDIUM_THRESHOLD = null;
        DEFAULT_RISK_HIGH_THRESHOLD = null;
        DEFAULT_RISK_CRITICAL_THRESHOLD = null;
        DEFAULT_RISK_APPROVAL_THRESHOLD = null;
        DEFAULT_RISK_BLOCK_THRESHOLD = null;
        DEFAULT_DML_BATCH_SIZE = null;
        DEFAULT_MAX_DML_BATCH_SIZE = null;
        DEFAULT_EVENT_BATCH_SIZE = null;
        DEFAULT_MAX_ASYNC_DEPTH = null;
        DEFAULT_CONFIDENCE_THRESHOLD = null;
        DEFAULT_APPROVAL_TIMEOUT_MINUTES = null;
        RETRYABLE_STATUS_CODES = null;
    }
}