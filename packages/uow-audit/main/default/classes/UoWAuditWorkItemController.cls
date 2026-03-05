//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Apex controller for UoW Audit Work Item LWC components.
 * Provides data access for work item detail display.
 *
 * @author Vipul Taylor
 * @see UoWAuditTimelineController
 * @see UowSnapshotViewer
 */
public with sharing class UoWAuditWorkItemController {

    // ============================================================================
    // PUBLIC API
    // ============================================================================

    /**
     * Get work item record by Salesforce record ID.
     * Used by quick action viewer and record page components.
     *
     * @param recordId The Salesforce record ID
     * @return Work item record with all fields for viewer display
     */
    @AuraEnabled(cacheable=true)
    public static UoWAuditWorkItem__c getWorkItemForViewer(Id recordId) {
        try {
            return UoWAuditDataSelector.getInstance().getWorkItemById(recordId);
        } catch (Exception e) {
            throw UoWExceptionService.buildAuraException('Failed to load work item: ' + e.getMessage());
        }
    }
}