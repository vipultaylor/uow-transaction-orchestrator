//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Controller for deleting UoW Audit Transaction records with cascade delete support.
 * Used by both single record delete and mass delete VF pages.
 *
 * @group UoW Audit UI
 */
public with sharing class UoWAuditTransactionDeleteController {
    // ============================================================================
    // PUBLIC PROPERTIES
    // ============================================================================

    /** Selected record IDs passed from the VF page */
    private List<String> internalRecordIds;
    private Boolean isInitialized = false;

    public List<String> recordIds {
        get { return this.internalRecordIds; }
        set {
            this.internalRecordIds = value;
            // Don't auto-initialize here - wait for explicit initialize() call
        }
    }

    /** Selected records to delete */
    public List<UoWAuditTransaction__c> selectedRecords { get; private set; }

    /** Related records that will be cascade deleted */
    public List<UoWAuditTransaction__c> relatedRecords { get; private set; }

    /** Whether cascade delete is enabled */
    public Boolean cascadeDeleteEnabled { get; private set; }

    /** Total count of records to delete */
    public Integer totalCount { get; private set; }

    /** Error message if any */
    public String errorMessage { get; private set; }

    /** Whether deletion was successful */
    public Boolean deleteSuccess { get; private set; }

    /** Number of records deleted */
    public Integer deletedCount { get; private set; }

    // ============================================================================
    // CONSTRUCTOR
    // ============================================================================

    public UoWAuditTransactionDeleteController() {
        this.selectedRecords = new List<UoWAuditTransaction__c>();
        this.relatedRecords = new List<UoWAuditTransaction__c>();
        this.cascadeDeleteEnabled = false;
        this.totalCount = 0;
        this.deleteSuccess = false;
        this.deletedCount = 0;
    }

    // ============================================================================
    // PUBLIC METHODS
    // ============================================================================

    /**
     * Initialize the controller with record IDs and load data
     */
    public void initialize() {
        if (this.isInitialized) {
            return;
        }
        this.isInitialized = true;

        if (this.recordIds == null || this.recordIds.isEmpty()) {
            this.errorMessage = 'No records selected for deletion.';
            return;
        }

        try {
            // Load selected records
            this.selectedRecords = [
                SELECT Id, Name, TransactionStatus__c, StartTime__c, CorrelationId__c, TotalWorkItems__c
                FROM UoWAuditTransaction__c
                WHERE Id IN :this.recordIds
                WITH SECURITY_ENFORCED
            ];

            if (this.selectedRecords.isEmpty()) {
                this.errorMessage = 'Selected records not found. They may have already been deleted.';
                return;
            }

            // Check cascade delete setting
            this.cascadeDeleteEnabled = isCascadeDeleteEnabled();

            // If cascade enabled, find related records
            if (this.cascadeDeleteEnabled) {
                Set<String> correlationIds = new Set<String>();
                for (UoWAuditTransaction__c txn : this.selectedRecords) {
                    if (String.isNotBlank(txn.CorrelationId__c)) {
                        correlationIds.add(txn.CorrelationId__c);
                    }
                }

                if (!correlationIds.isEmpty()) {
                    Set<Id> selectedIdSet = new Set<Id>();
                    for (UoWAuditTransaction__c txn : this.selectedRecords) {
                        selectedIdSet.add(txn.Id);
                    }

                    this.relatedRecords = [
                        SELECT Id, Name, TransactionStatus__c, StartTime__c, CorrelationId__c, TotalWorkItems__c
                        FROM UoWAuditTransaction__c
                        WHERE CorrelationId__c IN :correlationIds
                        AND Id NOT IN :selectedIdSet
                        WITH SECURITY_ENFORCED
                    ];
                }
            }

            this.totalCount = this.selectedRecords.size() + this.relatedRecords.size();

        } catch (Exception e) {
            this.errorMessage = 'Error loading records: ' + e.getMessage();
        }
    }

    /**
     * Delete the selected and related records
     * Sets deleteSuccess flag and deletedCount on success
     */
    public void deleteRecords() {
        try {
            List<UoWAuditTransaction__c> allRecordsToDelete = new List<UoWAuditTransaction__c>();
            allRecordsToDelete.addAll(this.selectedRecords);
            allRecordsToDelete.addAll(this.relatedRecords);

            if (allRecordsToDelete.isEmpty()) {
                this.errorMessage = 'No records to delete.';
                return;
            }

            delete allRecordsToDelete;

            this.deleteSuccess = true;
            this.deletedCount = allRecordsToDelete.size();

        } catch (Exception e) {
            this.errorMessage = 'Error deleting records: ' + e.getMessage();
        }
    }

    /**
     * Cancel and return to previous page
     */
    public PageReference cancel() {
        return new PageReference('/lightning/o/UoWAuditTransaction__c/list');
    }

    // ============================================================================
    // COMPUTED PROPERTIES
    // ============================================================================

    public Boolean getHasSelectedRecords() {
        return !this.selectedRecords.isEmpty();
    }

    public Boolean getHasRelatedRecords() {
        return !this.relatedRecords.isEmpty();
    }

    public Boolean getHasError() {
        return String.isNotBlank(this.errorMessage);
    }

    public Integer getSelectedCount() {
        return this.selectedRecords.size();
    }

    public Integer getRelatedCount() {
        return this.relatedRecords.size();
    }

    // ============================================================================
    // PRIVATE METHODS
    // ============================================================================

    private Boolean isCascadeDeleteEnabled() {
        try {
            UoWParameters__mdt param = [
                SELECT Value__c
                FROM UoWParameters__mdt
                WHERE DeveloperName = 'CascadeDeleteRelatedTransactions'
                LIMIT 1
            ];
            return param.Value__c == 'true';
        } catch (Exception e) {
            return false;
        }
    }
}
