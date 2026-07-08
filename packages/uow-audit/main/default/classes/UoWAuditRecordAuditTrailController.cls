//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Apex controller for the record-page Audit Activity LWC (uowRecordAuditActivity).
 * Given any business record Id, returns the UoW audit transactions - and the work items within
 * them - that touched that record, resolved through the UoWAuditRecordIndex__c reverse-lookup
 * index. Results are grouped by transaction, most-recent-first.
 *
 * Only sampled records are indexed, so the result is a subset of all activity (see the component's
 * footer note). Only CUSTOM_OBJECT storage mode is queryable here.
 *
 * @author Vipul Taylor
 * @group UoW Audit
 * @see UoWAuditDataSelector
 * @see UoWAuditRecordIndex__c
 */
public with sharing class UoWAuditRecordAuditTrailController {

    // ============================================================================
    // PUBLIC API
    // ============================================================================

    /**
     * Get the UoW audit activity for a business record, grouped by transaction.
     *
     * @param recordId The business record Id (e.g. an Account or Contact Id)
     * @return Transactions that touched the record (most-recent-first), each with the work items
     *         that touched it; empty list when there is no indexed activity
     */
    @AuraEnabled(cacheable=true)
    public static List<TransactionActivity> getAuditActivityForRecord(Id recordId) {
        try {
            List<UoWAuditRecordIndex__c> rows =
                UoWAuditDataSelector.getInstance().getAuditActivityByRecordId(recordId, 50);
            return groupByTransaction(rows);
        } catch (Exception e) {
            throw UoWExceptionService.buildAuraException(
                'Failed to load audit activity: ' + e.getMessage()
            );
        }
    }

    // ============================================================================
    // PRIVATE HELPERS
    // ============================================================================

    /**
     * Group flat index rows (already ordered most-recent-first) into a transaction -> work items
     * structure, preserving the incoming order.
     */
    private static List<TransactionActivity> groupByTransaction(List<UoWAuditRecordIndex__c> rows) {
        List<TransactionActivity> ordered = new List<TransactionActivity>();
        Map<Id, TransactionActivity> byTransaction = new Map<Id, TransactionActivity>();

        for (UoWAuditRecordIndex__c row : rows) {
            UoWAuditWorkItem__c wi = row.AuditWorkItem__r;
            if (wi == null || wi.AuditTransaction__r == null) {
                continue;
            }

            UoWAuditTransaction__c txn = wi.AuditTransaction__r;
            TransactionActivity activity = byTransaction.get(txn.Id);
            if (activity == null) {
                activity = new TransactionActivity();
                activity.transactionId = txn.Id;
                activity.name = txn.Name;
                activity.status = txn.TransactionStatus__c;
                activity.commitMode = txn.CommitMode__c;
                activity.startTime = txn.StartTime__c;
                activity.executionTimeMs = txn.ExecutionTimeMs__c;
                activity.workItems = new List<WorkItemActivity>();
                byTransaction.put(txn.Id, activity);
                ordered.add(activity);
            }

            WorkItemActivity item = new WorkItemActivity();
            item.workItemId = wi.Id;
            item.name = wi.Name;
            item.workType = wi.WorkType__c;
            item.status = wi.WorkItemStatus__c;
            item.operation = row.Operation__c;
            item.sobjectType = row.SObjectType__c;
            item.recordCount = wi.ProcessedCount__c == null ? null : wi.ProcessedCount__c.intValue();
            activity.workItems.add(item);
        }

        return ordered;
    }

    // ============================================================================
    // DTOs
    // ============================================================================

    /**
     * A transaction that touched the record, with the work items that touched it.
     */
    public class TransactionActivity {
        @AuraEnabled public Id transactionId;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String commitMode;
        @AuraEnabled public Datetime startTime;
        @AuraEnabled public Decimal executionTimeMs;
        @AuraEnabled public List<WorkItemActivity> workItems;
    }

    /**
     * A single work item within a transaction that touched the record.
     */
    public class WorkItemActivity {
        @AuraEnabled public Id workItemId;
        @AuraEnabled public String name;
        @AuraEnabled public String workType;
        @AuraEnabled public String status;
        @AuraEnabled public String operation;
        @AuraEnabled public String sobjectType;
        @AuraEnabled public Integer recordCount;
    }
}
