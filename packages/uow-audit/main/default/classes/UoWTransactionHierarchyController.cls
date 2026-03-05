//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Controller for UoW Transaction Hierarchy LWC.
 * Provides methods to query and display transaction hierarchies.
 *
 * @author UoW Audit
 * @since 1.0.0
 * @group UoW Audit
 */
public with sharing class UoWTransactionHierarchyController {

    // ============================================================================
    // PRIVATE FIELDS
    // ============================================================================

    private static UoWAuditDataSelector selector {
        get {
            if (selector == null) {
                selector = UoWAuditDataSelector.getInstance();
            }
            return selector;
        }
        set;
    }

    // ============================================================================
    // PUBLIC API
    // ============================================================================

    /**
     * Get the full transaction hierarchy for a given correlation ID.
     * Returns all transactions in the chain with their parent-child relationships.
     *
     * @param correlationId The correlation ID to get hierarchy for
     * @return TransactionHierarchy with root and all descendant transactions
     */
    @AuraEnabled
    public static TransactionHierarchy getHierarchyByCorrelationId(String correlationId) {
        if (String.isBlank(correlationId)) {
            throw UoWExceptionService.buildAuraException('Correlation ID is required');
        }

        List<UoWAuditTransaction__c> allTransactions = selector.getTransactionsByCorrelationId(correlationId);
        return buildHierarchy(allTransactions);
    }

    /**
     * Get the transaction hierarchy starting from a specific transaction.
     * Finds the correlation ID and returns the full chain.
     *
     * @param transactionRecordId The record ID of the transaction to start from
     * @return TransactionHierarchy with root and all descendant transactions
     */
    @AuraEnabled
    public static TransactionHierarchy getHierarchyByTransactionId(Id transactionRecordId) {
        if (transactionRecordId == null) {
            throw UoWExceptionService.buildAuraException('Transaction ID is required');
        }

        String corrId = selector.getCorrelationIdByTransactionId(transactionRecordId);
        if (corrId == null) {
            throw UoWExceptionService.buildAuraException('Transaction not found');
        }

        return getHierarchyByCorrelationId(corrId);
    }

    /**
     * Get recent transaction hierarchies (root transactions only).
     *
     * @param limitCount Maximum number of hierarchies to return
     * @return List of root transactions with child counts
     */
    @AuraEnabled
    public static List<RootTransactionInfo> getRecentHierarchies(Integer limitCount) {
        List<UoWAuditTransaction__c> rootTransactions = selector.getRecentRootTransactions(limitCount);

        List<RootTransactionInfo> results = new List<RootTransactionInfo>();
        for (UoWAuditTransaction__c txn : rootTransactions) {
            RootTransactionInfo info = new RootTransactionInfo();
            info.id = txn.Id;
            info.name = txn.Name;
            info.transactionId = txn.TransactionId__c;
            info.correlationId = txn.CorrelationId__c;
            info.status = txn.TransactionStatus__c;
            info.commitMode = txn.CommitMode__c;
            info.startTime = txn.StartTime__c;
            info.executionTimeMs = txn.ExecutionTimeMs__c;
            info.workItemCount = txn.TotalWorkItems__c != null ? txn.TotalWorkItems__c.intValue() : 0;
            info.childCount = txn.UoWAuditTransactions__r != null ? txn.UoWAuditTransactions__r.size() : 0;
            results.add(info);
        }

        return results;
    }

    // ============================================================================
    // PRIVATE METHODS
    // ============================================================================

    private static TransactionHierarchy buildHierarchy(List<UoWAuditTransaction__c> transactions) {
        TransactionHierarchy hierarchy = new TransactionHierarchy();
        if (transactions.isEmpty()) {
            return hierarchy;
        }

        // Build a map of ID to node
        Map<Id, TransactionNode> nodeMap = new Map<Id, TransactionNode>();
        TransactionNode rootNode = null;

        // First pass: create all nodes
        for (UoWAuditTransaction__c txn : transactions) {
            TransactionNode node = createNode(txn);
            nodeMap.put(txn.Id, node);

            if (txn.ParentTransaction__c == null) {
                rootNode = node;
            }
        }

        // Second pass: link children to parents
        for (UoWAuditTransaction__c txn : transactions) {
            if (txn.ParentTransaction__c != null && nodeMap.containsKey(txn.ParentTransaction__c)) {
                TransactionNode parentNode = nodeMap.get(txn.ParentTransaction__c);
                TransactionNode childNode = nodeMap.get(txn.Id);
                if (parentNode.children == null) {
                    parentNode.children = new List<TransactionNode>();
                }
                parentNode.children.add(childNode);
                parentNode.hasChildren = true;
            }
        }

        hierarchy.root = rootNode;
        return hierarchy;
    }

    private static TransactionNode createNode(UoWAuditTransaction__c txn) {
        TransactionNode node = new TransactionNode();
        node.id = txn.Id;
        node.transactionId = txn.TransactionId__c;
        node.description = txn.Description__c;
        node.status = txn.TransactionStatus__c;
        node.hasChildren = txn.HasChildTransactions__c;
        node.totalWorkCount = txn.TotalWorkItems__c != null ? txn.TotalWorkItems__c.intValue() : 0;
        return node;
    }

    // ============================================================================
    // INNER CLASSES
    // ============================================================================

    /**
     * Full hierarchy response.
     */
    public class TransactionHierarchy {
        @AuraEnabled public TransactionNode root { get; set; }
    }

    /**
     * Single transaction node in the hierarchy tree.
     */
    public class TransactionNode {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String transactionId { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Boolean hasChildren { get; set; }
        @AuraEnabled public Integer totalWorkCount { get; set; }
        @AuraEnabled public List<TransactionNode> children { get; set; }
    }

    /**
     * Summary info for root transactions list.
     */
    public class RootTransactionInfo {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String transactionId { get; set; }
        @AuraEnabled public String correlationId { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String commitMode { get; set; }
        @AuraEnabled public Datetime startTime { get; set; }
        @AuraEnabled public Decimal executionTimeMs { get; set; }
        @AuraEnabled public Integer workItemCount { get; set; }
        @AuraEnabled public Integer childCount { get; set; }
    }
}