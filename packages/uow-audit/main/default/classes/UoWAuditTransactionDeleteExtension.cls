//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Visualforce controller extension for deleting UoW Audit Transaction records.
 * Extracts selected record IDs from StandardSetController (mass delete)
 * or StandardController (single delete) and passes them to the Screen Flow.
 *
 * @group UoW Audit UI
 * @see UoWAuditTransactionDelete (VF Page)
 * @see UoW_AuditTransaction_DeleteConfirmation (Screen Flow)
 */
public with sharing class UoWAuditTransactionDeleteExtension {
    // ============================================================================
    // PUBLIC PROPERTIES
    // ============================================================================

    /**
     * Comma-separated list of selected record IDs
     */
    public String selectedIds { get; private set; }

    /**
     * List of selected record IDs (for Flow collection input)
     */
    public List<String> selectedIdList { get; private set; }

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Constructor for StandardSetController (mass delete from list view)
     * @param controller StandardSetController with selected records
     */
    public UoWAuditTransactionDeleteExtension(ApexPages.StandardSetController controller) {
        this.selectedIdList = new List<String>();
        for (SObject obj : controller.getSelected()) {
            this.selectedIdList.add(obj.Id);
        }
        this.selectedIds = String.join(this.selectedIdList, ',');
    }

    /**
     * Constructor for StandardController (single record delete)
     * @param controller StandardController with single record
     */
    public UoWAuditTransactionDeleteExtension(ApexPages.StandardController controller) {
        String recordId = String.valueOf((Id) controller.getId());
        this.selectedIdList = new List<String>();
        if (String.isNotBlank(recordId)) {
            this.selectedIdList.add(recordId);
            this.selectedIds = recordId;
        } else {
            this.selectedIds = '';
        }
    }
}
