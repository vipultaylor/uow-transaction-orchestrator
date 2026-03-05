//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Standard risk assessor implementation for UnitOfWork framework.
 * Evaluates risk based on object type, operation type, record volume, and policy factors.
 * Can be extended or replaced with custom risk assessor implementations.
 *
 * This is an OPTIONAL component. Risk assessment is only performed if a risk assessor
 * is explicitly configured. A score of 0 from this assessor means "no risk factors detected",
 * which is different from "no risk assessment performed".
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWInterfaces.IRiskAssessor
 * @see UoWRiskTypes
 */
public inherited sharing class UoWStandardRiskAssessor implements UoWInterfaces.IRiskAssessor {

    // ============================================================================
    // PRIVATE STATIC CONSTANTS
    // ============================================================================

    // Object type risk weights (can be overridden by custom metadata in future)
    private static final Map<String, Decimal> OBJECT_RISK_WEIGHTS = new Map<String, Decimal>{
        // Security objects - highest risk
        'User' => 50.0,
        'Profile' => 50.0,
        'PermissionSet' => 50.0,
        'PermissionSetAssignment' => 45.0,
        'PermissionSetGroup' => 45.0,
        'Group' => 40.0,
        'UserRole' => 40.0,

        // Core business objects - high risk
        'Account' => 30.0,
        'Opportunity' => 35.0,
        'Contact' => 25.0,
        'Contract' => 30.0,
        'Order' => 25.0,
        'Quote' => 25.0,

        // Transactional objects - moderate risk
        'Lead' => 20.0,
        'Case' => 20.0,
        'Task' => 10.0,
        'Event' => 10.0,

        // Configuration objects - moderate to high risk
        'CustomPermission' => 40.0,
        'CustomMetadata' => 35.0,
        'CustomSetting' => 30.0
    };

    // Operation type multipliers
    private static final Map<UoWEnums.DmlOperation, Decimal> OPERATION_MULTIPLIERS = new Map<UoWEnums.DmlOperation, Decimal>{
        UoWEnums.DmlOperation.INSERT_OP => 1.0,      // Lowest risk - new data
        UoWEnums.DmlOperation.UNDELETE_OP => 1.1,    // Low risk - recovery
        UoWEnums.DmlOperation.UPDATE_OP => 1.2,      // Moderate risk - modifying existing
        UoWEnums.DmlOperation.UPSERT_OP => 1.3,      // Higher risk - uncertain insert vs update
        UoWEnums.DmlOperation.DELETE_OP => 1.5       // Highest risk - data loss
    };

    // Cache for metadata-based risk weights (loaded from UoWObjectSetting__mdt)
    private static Map<String, UoWObjectSetting__mdt> objectSettingsCache;
    private static Boolean cacheLoaded = false;

    // ============================================================================
    // PUBLIC API - INTERFACE IMPLEMENTATION
    // ============================================================================

    /**
     * Get assessor name.
     *
     * @return Assessor name
     */
    public String getName() {
        return 'StandardRiskAssessor';
    }

    /**
     * Assess risk for the given context and plan.
     *
     * @param ctx Execution context
     * @param plan Execution plan
     * @return Risk assessment result
     */
    public UoWRiskTypes.RiskAssessment assessRisk(UoWContext ctx, UoWPlan plan) {
        // Create fresh assessment
        UoWRiskTypes.RiskAssessment assessment = new UoWRiskTypes.RiskAssessment();

        // Calculate risk from multiple dimensions
        calculateObjectRisk(assessment, ctx, plan);
        calculateVolumeRisk(assessment, plan);
        calculateOperationRisk(assessment, plan);

        // Calculate TOTAL score from all risk factors added from here and various other sources
        assessment.riskScore = assessment.getTotalFactorScore();

        // Cap at 100
        assessment.riskScore = Math.min(assessment.riskScore, 100);

        // Calculate risk level based on thresholds from configuration
        assessment.riskLevel = calculateRiskLevel(assessment.riskScore, ctx);

        // Set approval requirement based on threshold
        assessment.requiresApproval = assessment.riskScore >= ctx.getFeatureSettings().getRiskApprovalThreshold();
        if (assessment.requiresApproval) {
            assessment.approvalReason = 'Risk score ' + assessment.riskScore +
                ' exceeds approval threshold of ' + ctx.getFeatureSettings().getRiskApprovalThreshold();
        }

        assessment.assessedAt = DateTime.now();

        return assessment;
    }

    // ============================================================================
    // PRIVATE METHODS - RISK CALCULATION
    // ============================================================================

    // Calculate risk based on object types being modified
    private void calculateObjectRisk(UoWRiskTypes.RiskAssessment assessment, UoWContext ctx, UoWPlan plan) {
        Map<String, Decimal> objectRisks = new Map<String, Decimal>();

        for (UoWDmlWorkItem work : plan.getPlannedDmlWork()) {
            String objType = String.valueOf(work.sobjectType);

            // Get risk weight (metadata-driven or fallback to hardcoded)
            Decimal operationRisk = getRiskWeight(ctx.configurationName, objType, work.operation);

            // Track highest risk per object type
            if (!objectRisks.containsKey(objType) || objectRisks.get(objType) < operationRisk) {
                objectRisks.put(objType, operationRisk);
            }
        }

        // Add risk factors for each high-risk object
        for (String objType : objectRisks.keySet()) {
            Decimal risk = objectRisks.get(objType);

            // Only add factor if significant (threshold of 30)
            if (risk >= 30.0) {
                // Normalize to MAX_RISK_FACTOR_SCORE (15)
                // Formula: (risk / 100) * MAX_RISK_FACTOR_SCORE
                Decimal normalizedScore = (risk / 100.0) * UoWRiskTypes.MAX_RISK_FACTOR_SCORE;

                String reason = String.format('High-risk object operation: {0}', new List<String>{ objType });
                UoWRiskTypes.RiskFactor factor = new UoWRiskTypes.RiskFactor(reason, normalizedScore, this.getName())
                                                        .withCategory(UoWRiskTypes.RiskFactorCategory.CUSTOM_OBJECT);
                factor.withMetadata('objectType', objType)
                      .withMetadata('baseWeight', OBJECT_RISK_WEIGHTS.get(objType))
                      .withMetadata('calculatedRisk', risk);

                assessment.addRiskFactor(factor);
            }
        }
    }

    // Calculate risk based on record volume
    private void calculateVolumeRisk(UoWRiskTypes.RiskAssessment assessment, UoWPlan plan) {
        Integer totalRecords = plan.getTotalPlannedRecordCount();

        Decimal volumeScore = 0;
        String volumeLevel = '';

        // Progressive risk based on volume
        if (totalRecords > 5000) {
            volumeScore = UoWRiskTypes.MAX_RISK_FACTOR_SCORE;
            volumeLevel = 'Very High';
        } else if (totalRecords > 1000) {
            volumeScore = 12.0;
            volumeLevel = 'High';
        } else if (totalRecords > 500) {
            volumeScore = 10.0;
            volumeLevel = 'Moderate';
        } else if (totalRecords > 100) {
            volumeScore = 5.0;
            volumeLevel = 'Low';
        }

        if (volumeScore > 0) {
            String reason = String.format('{0} volume operation: {1} records', new List<String>{ volumeLevel, String.valueOf(totalRecords) });
            UoWRiskTypes.RiskFactor factor = new UoWRiskTypes.RiskFactor(reason, volumeScore, this.getName())
                                                    .withCategory(UoWRiskTypes.RiskFactorCategory.VOLUME)
                                                    .withMetadata('recordCount', totalRecords)
                                                    .withMetadata('volumeLevel', volumeLevel);

            assessment.addRiskFactor(factor);
        }
    }

    // Calculate risk based on operation types (focus on destructive operations)
    private void calculateOperationRisk(UoWRiskTypes.RiskAssessment assessment, UoWPlan plan) {
        // Check for destructive operations
        Boolean hasDelete = false;
        Integer deleteCount = 0;

        for (UoWDmlWorkItem work : plan.getPlannedDmlWork()) {
            if (work.operation == UoWEnums.DmlOperation.DELETE_OP) {
                hasDelete = true;
                deleteCount += work.getOriginalRecords()?.size() ?? 0;
            }
        }

        if (hasDelete) {
            // Base risk for delete + additional risk for volume
            // Formula: 10 base + (deleteCount / 100)
            Decimal deleteRisk = 10.0 + (deleteCount / 100.0);

            String reason = String.format('Destructive DELETE operation on {0} records', new List<String>{ String.valueOf(deleteCount) });
            UoWRiskTypes.RiskFactor factor = new UoWRiskTypes.RiskFactor(reason, deleteRisk, this.getName())
                                                    .withCategory(UoWRiskTypes.RiskFactorCategory.OPERATION)
                                                    .withMetadata('operation', 'DELETE')
                                                    .withMetadata('recordCount', deleteCount);

            assessment.addRiskFactor(factor);
        }
    }

    // Calculate risk level based on score and configuration thresholds
    private UoWRiskTypes.RiskLevel calculateRiskLevel(Decimal score, UoWContext ctx) {
        if (score >= ctx.getFeatureSettings().getRiskCriticalThreshold()) {
            return UoWRiskTypes.RiskLevel.CRITICAL;
        } else if (score >= ctx.getFeatureSettings().getRiskHighThreshold()) {
            return UoWRiskTypes.RiskLevel.HIGH;
        } else if (score >= ctx.getFeatureSettings().getRiskMediumThreshold()) {
            return UoWRiskTypes.RiskLevel.MEDIUM;
        } else if (score >= ctx.getFeatureSettings().getRiskLowThreshold()) {
            return UoWRiskTypes.RiskLevel.LOW;
        } else {
            return UoWRiskTypes.RiskLevel.NONE;
        }
    }

    // ============================================================================
    // PRIVATE METHODS - METADATA LOADING
    // ============================================================================

    // Get risk weight for object and operation from metadata or hardcoded defaults
    private static Decimal getRiskWeight(String configurationName, String objectType, UoWEnums.DmlOperation operation) {

        UoWObjectSetting__mdt setting = UoWConfigurationLoader.getInstance().getObjectSetting(configurationName, objectType);
        if (setting != null) {
            // Check for operation-specific risk weight first, then fall back to base weight
            Decimal riskWeight = getOperationSpecificWeight(setting, operation);

            // Risk weights are on a 0-1 scale, multiply by 100 to match our scoring system
            return riskWeight * 100;
        }

        // Fall back to hardcoded values
        Decimal baseWeight = OBJECT_RISK_WEIGHTS.containsKey(objectType)
            ? OBJECT_RISK_WEIGHTS.get(objectType)
            : 10.0; // default for unknown objects

        Decimal multiplier = OPERATION_MULTIPLIERS.containsKey(operation)
            ? OPERATION_MULTIPLIERS.get(operation)
            : 1.0;

        return baseWeight * multiplier;
    }

    // Get operation-specific risk weight or fall back to base weight
    private static Decimal getOperationSpecificWeight(UoWObjectSetting__mdt setting, UoWEnums.DmlOperation operation) {
        Decimal operationWeight = null;

        // Check for operation-specific weight
        switch on operation {
            when INSERT_OP {
                operationWeight = setting.InsertRiskWeight__c;
            }
            when UPDATE_OP {
                operationWeight = setting.UpdateRiskWeight__c;
            }
            when UPSERT_OP {
                operationWeight = setting.UpsertRiskWeight__c;
            }
            when DELETE_OP {
                operationWeight = setting.DeleteRiskWeight__c;
            }
            when UNDELETE_OP {
                operationWeight = setting.UndeleteRiskWeight__c;
            }
        }

        // If operation-specific weight is set, use it; otherwise fall back to base weight
        if (operationWeight != null) {
            return operationWeight;
        }

        // Fall back to base weight, defaulting to 0.5 if not set
        return setting.BaseRiskWeight__c ?? 0.5;
    }

}