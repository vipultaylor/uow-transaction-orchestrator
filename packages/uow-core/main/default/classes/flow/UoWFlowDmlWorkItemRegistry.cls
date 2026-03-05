//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * DML work item registry for tracking registered records across Flow actions.
 *
 * Enables Flow to establish parent-child relationships by referencing records via IDs.
 * Since Flow doesn't have object references, this registry maintains a map of work item IDs
 * to their registered records.
 *
 * Pattern:
 * 1. Register Insert (Account) → workId: "FLOW-WORK-123" → returns to Flow
 * 2. Register Insert (Contact) with parentWorkItemId: "FLOW-WORK-123", relationshipField: "AccountId"
 * 3. Framework retrieves parent record for FLOW-WORK-123 and calls uow.relate(records, Contact.AccountId, parentRecord)
 *
 * NOTE: This registry is ONLY for Flow actions. Apex code should use direct record references.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Flow Actions
 * @see UoWFlowRegisterInsertAction
 * @see UoWFlowRegisterUpsertAction
 */
public inherited sharing class UoWFlowDmlWorkItemRegistry {
    // ============================================================================
    // PRIVATE FIELDS
    // ============================================================================

    // Maps Flow work ID to the first record in that registration (for relationship parent)
    private static Map<String, SObject> parentRecords = new Map<String, SObject>();

    // ============================================================================
    // PUBLIC API - REGISTRATION
    // ============================================================================

    /**
     * Register records and assign a Flow-friendly work ID.
     * Generates a unique ID with FLOW-WORK prefix.
     * Stores the first record for use as relationship parent.
     *
     * @param records The records being registered
     * @return Work item ID (with FLOW-WORK prefix)
     */
    public static String register(List<SObject> records) {
        UoWExceptionService.requireNonEmpty(records, 'Records');

        // Generate unique Flow work ID
        String workId = UoWUtils.generateId('FLOW-WORK');

        // Store first record as parent for relationships
        parentRecords.put(workId, records[0]);

        return workId;
    }

    /**
     * Retrieve the parent record by work item ID
     *
     * @param workItemId The work item ID returned from register()
     * @return Parent record instance (first record in the registration)
     * @throws UoWException if work item not found
     */
    public static SObject getParentRecord(String workItemId) {
        UoWExceptionService.requireNonBlank(workItemId, 'Work item ID');

        SObject parentRecord = parentRecords.get(workItemId);
        if (parentRecord == null) {
            throw new UoWExceptionService.UoWException('Work item not found: ' + workItemId + '. Work item may not exist in this transaction.');
        }

        return parentRecord;
    }

    // Clear all work items (called after transaction commit/cleanup)
    public static void clearAll() {
        parentRecords.clear();
    }
}