//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Risk assessment type definitions for the UnitOfWork framework.
 * Contains RiskFactor, RiskAssessment, and related risk enums.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Core
 * @see UoWInterfaces.IRiskAssessor
 * @see UoWDefaultRiskAssessor
 */
public inherited sharing class UoWRiskTypes {

    // ============================================================================
    // PUBLIC CONSTANTS
    // ============================================================================

    public static final Decimal MAX_RISK_FACTOR_SCORE = 15.0;

    // ============================================================================
    // ENUMERATIONS - RISK LEVEL
    // ============================================================================

    // Risk levels for operations
    public enum RiskLevel {
        NONE,
        LOW,
        MEDIUM,
        HIGH,
        CRITICAL
    }

    // ============================================================================
    // ENUMERATIONS - RISK FACTOR CATEGORY
    // ============================================================================

    // Risk factor category enum
    public enum RiskFactorCategory {
        POLICY,
        CUSTOM_OBJECT,
        OPERATION,
        VOLUME,
        FIELD,
        USER,
        TEMPORAL,
        AGENT,
        CUSTOM
    }

    // ============================================================================
    // INNER CLASSES - RISK FACTOR
    // ============================================================================

    /**
     * Individual risk factor with score and metadata.
     */
    public class RiskFactor {

        // ============================================================================
        // PUBLIC PROPERTIES
        // ============================================================================

        public String reason { get; set; }                      // Reason for this risk factor
        public Decimal score { get; set; }                      // Risk score (0-15)
        public String origin { get; set; }                      // Origin identifier
        public RiskFactorCategory category { get; set; }        // Category classification
        public Map<String, Object> metadata { get; set; }       // Additional metadata
        public DateTime addedAt { get; set; }                   // Timestamp when added

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public RiskFactor() {
            this.metadata = new Map<String, Object>();
            this.addedAt = DateTime.now();
        }

        public RiskFactor(String reason, Decimal score, String origin) {
            this();
            this.reason = reason;
            this.score = Math.min(score, MAX_RISK_FACTOR_SCORE);
            this.origin = origin;
            this.category = UoWRiskTypes.RiskFactorCategory.CUSTOM;
        }

        // ============================================================================
        // PUBLIC API - FLUENT CONFIGURATION
        // ============================================================================

        /**
         * Add category to risk factor.
         *
         * @param category The risk factor category
         * @return This risk factor for chaining
         */
        public RiskFactor withCategory(UoWRiskTypes.RiskFactorCategory category) {
            this.category = category;
            return this;
        }

        /**
         * Add metadata to risk factor.
         *
         * @param key Metadata key
         * @param value Metadata value
         * @return This risk factor for chaining
         */
        public RiskFactor withMetadata(String key, Object value) {
            this.metadata.put(key, value);
            return this;
        }
    }

    // ============================================================================
    // INNER CLASSES - RISK ASSESSMENT
    // ============================================================================

    /**
     * Risk assessment data.
     */
    public class RiskAssessment {

        // ============================================================================
        // PUBLIC PROPERTIES - RISK LEVEL
        // ============================================================================

        public RiskLevel riskLevel { get; set; }                // Overall risk level
        public Decimal riskScore { get; set; }                  // Total risk score

        // ============================================================================
        // PUBLIC PROPERTIES - RISK FACTORS
        // ============================================================================

        public List<RiskFactor> riskFactors { get; set; }       // Individual risk factors

        // ============================================================================
        // PUBLIC PROPERTIES - APPROVAL
        // ============================================================================

        public Boolean requiresApproval { get; set; }           // Whether approval is required
        public String approvalReason { get; set; }              // Reason for approval requirement

        // ============================================================================
        // PUBLIC PROPERTIES - METADATA
        // ============================================================================

        public DateTime assessedAt { get; set; }                // Assessment timestamp

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public RiskAssessment() {
            this.riskFactors = new List<RiskFactor>();
            this.riskScore = 0;
            this.riskLevel = UoWRiskTypes.RiskLevel.NONE;
            this.requiresApproval = false;
            this.assessedAt = DateTime.now();
        }

        // ============================================================================
        // PUBLIC API - FACTOR MANAGEMENT
        // ============================================================================

        /**
         * Helper to add a risk factor.
         *
         * @param factor The risk factor to add
         */
        public void addRiskFactor(RiskFactor factor) {
            if (factor != null) {
                this.riskFactors.add(factor);
            }
        }

        // ============================================================================
        // PUBLIC API - SCORE CALCULATION
        // ============================================================================

        /**
         * Get total score from all risk factors.
         *
         * @return Total risk score
         */
        public Decimal getTotalFactorScore() {
            Decimal total = 0;
            for (RiskFactor factor : riskFactors) {
                if (factor.score != null) {
                    total += factor.score;
                }
            }
            return total;
        }

        // ============================================================================
        // PUBLIC API - FACTOR QUERIES
        // ============================================================================

        /**
         * Get factors by category.
         *
         * @param category The category to filter by
         * @return List of risk factors matching the category
         */
        public List<RiskFactor> getFactorsByCategory(RiskFactorCategory category) {
            List<RiskFactor> filtered = new List<RiskFactor>();
            for (RiskFactor factor : riskFactors) {
                if (factor.category == category) {
                    filtered.add(factor);
                }
            }
            return filtered;
        }
    }
}