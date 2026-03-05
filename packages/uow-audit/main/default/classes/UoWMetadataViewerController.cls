//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Controller for uowMetadataViewer LWC component.
 * Provides permission checks and modification detection for origin source metadata.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Audit
 */
public with sharing class UoWMetadataViewerController {

    // ============================================================================
    // PUBLIC API
    // ============================================================================

    /**
     * Check if the current user can view origin source metadata.
     * Access is granted if user has:
     * - Read access to ApexClass object, OR
     * - CanViewOriginSourceMetadata custom permission
     *
     * @return True if user can view origin metadata
     */
    @AuraEnabled(cacheable=true)
    public static Boolean canViewOriginMetadata() {
        return Schema.ApexClass.SObjectType.getDescribe().isAccessible()
            || System.FeatureManagement.checkPermission('CanViewOriginSourceMetadata');
    }

    /**
     * Check if the source code has been modified since the audit record was created.
     * Compares LastModifiedDate from current metadata against the captured date.
     *
     * @param metadataType 'ApexClass' or 'ApexTrigger'
     * @param className Name of the class or trigger
     * @param capturedLastModifiedDate The LastModifiedDate captured at audit time (DateTime field value)
     * @return MetadataCheckResult with modification status
     */
    @AuraEnabled(cacheable=true)
    public static MetadataCheckResult checkForModifications(
        String metadataType,
        String className,
        DateTime capturedLastModifiedDate
    ) {
        // Permission check first
        if (!canViewOriginMetadata()) {
            throw UoWExceptionService.buildAuraException('Insufficient permissions to view origin metadata');
        }

        MetadataCheckResult result = new MetadataCheckResult();

        if (String.isBlank(metadataType) || String.isBlank(className)) {
            result.hasBeenModified = false;
            return result;
        }

        try {
            if (metadataType == 'ApexClass') {
                return checkApexClassModification(className, capturedLastModifiedDate);
            } else if (metadataType == 'ApexTrigger') {
                return checkApexTriggerModification(className, capturedLastModifiedDate);
            }
        } catch (Exception ex) {
            // Log the error but don't fail - just indicate unknown status
            System.debug(LoggingLevel.WARN, 'Error checking for modifications: ' + ex.getMessage());
            result.hasBeenModified = null; // Unknown
            result.errorMessage = 'Unable to determine modification status';
        }

        return result;
    }

    // ============================================================================
    // PRIVATE METHODS
    // ============================================================================

    private static MetadataCheckResult checkApexClassModification(
        String className,
        DateTime capturedLastModifiedDate
    ) {
        MetadataCheckResult result = new MetadataCheckResult();

        List<ApexClass> classes = [
            SELECT Id, ApiVersion, LastModifiedDate
            FROM ApexClass
            WHERE Name = :className
            LIMIT 1
        ];

        if (classes.isEmpty()) {
            result.classNotFound = true;
            result.hasBeenModified = null;
            return result;
        }

        ApexClass cls = classes[0];
        result.currentApiVersion = String.valueOf(cls.ApiVersion);
        result.currentLastModifiedDate = cls.LastModifiedDate?.format('yyyy-MM-dd\'T\'HH:mm:ss.SSSZ');

        // Compare dates
        result.hasBeenModified = compareDates(capturedLastModifiedDate, cls.LastModifiedDate);

        return result;
    }

    private static MetadataCheckResult checkApexTriggerModification(
        String triggerName,
        DateTime capturedLastModifiedDate
    ) {
        MetadataCheckResult result = new MetadataCheckResult();

        List<ApexTrigger> triggers = [
            SELECT Id, ApiVersion, LastModifiedDate
            FROM ApexTrigger
            WHERE Name = :triggerName
            LIMIT 1
        ];

        if (triggers.isEmpty()) {
            result.classNotFound = true;
            result.hasBeenModified = null;
            return result;
        }

        ApexTrigger trg = triggers[0];
        result.currentApiVersion = String.valueOf(trg.ApiVersion);
        result.currentLastModifiedDate = trg.LastModifiedDate?.format('yyyy-MM-dd\'T\'HH:mm:ss.SSSZ');

        // Compare dates
        result.hasBeenModified = compareDates(capturedLastModifiedDate, trg.LastModifiedDate);

        return result;
    }

    /**
     * Compare captured DateTime with current LastModifiedDate.
     * Returns true if the dates differ (code has been modified).
     */
    private static Boolean compareDates(DateTime capturedDate, DateTime currentDate) {
        if (capturedDate == null || currentDate == null) {
            return null; // Unknown - can't compare
        }

        // Compare - if current is later than captured, code has been modified
        // Use a small tolerance (1 second) to account for serialization precision
        Long diffMs = Math.abs(currentDate.getTime() - capturedDate.getTime());
        return diffMs > 1000;
    }

    // ============================================================================
    // INNER CLASSES
    // ============================================================================

    /**
     * Result of modification check.
     */
    public class MetadataCheckResult {
        @AuraEnabled public Boolean hasBeenModified;
        @AuraEnabled public String currentLastModifiedDate;
        @AuraEnabled public String currentApiVersion;
        @AuraEnabled public Boolean classNotFound;
        @AuraEnabled public String errorMessage;
    }
}
