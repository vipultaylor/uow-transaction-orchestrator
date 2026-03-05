//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Audit package implementation of IEventPublishFailureHandler.
 * Creates UoWEventPublishFailure__c records when business platform events
 * fail to deliver asynchronously after commit.
 *
 * Attempts to relate the failure record to the corresponding
 * UoWAuditTransaction__c via TransactionId lookup.
 *
 * Configured via UoWConfiguration__mdt.EventPublishFailureHandlerClassName__c
 * pointing to this class name.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Audit
 * @see UoWInterfaces.IEventPublishFailureHandler
 * @see UoWDefaultPublishFailureCallback
 */
public inherited sharing class UoWEventPublishFailureHandler implements UoWInterfaces.IEventPublishFailureHandler {

    // ============================================================================
    // PUBLIC API - INTERFACE IMPLEMENTATION
    // ============================================================================

    /**
     * Get handler name.
     *
     * @return Handler name
     */
    public String getName() {
        return 'Event Publish Failure Handler';
    }

    /**
     * Handle async platform event delivery failure for business events.
     * Creates a UoWEventPublishFailure__c record and attempts to link it
     * to the corresponding UoWAuditTransaction__c via TransactionId.
     *
     * Runs in a SEPARATE transaction from the original publish call.
     *
     * @param failureCtx The failure context with transaction identity and failure details
     */
    public void handleFailure(UoWEventPublishFailureContext failureCtx) {
        try {
            // Try to resolve the audit transaction record
            Id auditTransactionId = resolveAuditTransactionId(failureCtx.transactionId);

            // If no audit transaction exists yet (timing issue), create an orphan transaction
            // to satisfy the MasterDetail relationship on UoWEventPublishFailure__c
            if (auditTransactionId == null) {
                auditTransactionId = createOrphanTransaction(failureCtx);
            }

            UoWEventPublishFailure__c failure = new UoWEventPublishFailure__c(
                AuditTransaction__c = auditTransactionId,
                CorrelationId__c = failureCtx.correlationId,
                TransactionId__c = failureCtx.transactionId,
                WorkId__c = failureCtx.workId,
                FailureSource__c = 'BUSINESS_EVENT',
                FailedEventCount__c = failureCtx.failedEventCount,
                PublishedEventCount__c = failureCtx.publishedEventCount,
                FailedAt__c = failureCtx.failedAt,
                HasRelatedTransaction__c = (auditTransactionId != null),
                ErrorMessage__c = 'Async delivery failure: ' + failureCtx.failedEventCount +
                    ' of ' + failureCtx.publishedEventCount + ' events failed to deliver.'
            );

            Database.insert(failure, false);

        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'UoWEventPublishFailureHandler.handleFailure failed: ' + ex.getMessage()
                + '\n' + ex.getStackTraceString()
                + ' | CorrelationId: ' + failureCtx.correlationId);
        }
    }

    // ============================================================================
    // PRIVATE HELPERS
    // ============================================================================

    /**
     * Create an orphan UoWAuditTransaction__c to serve as the MasterDetail parent
     * when no audit transaction exists yet (timing issue between async callbacks).
     * Uses upsert on TransactionId__c so that if the real audit record arrives later,
     * it seamlessly overwrites the orphan.
     *
     * @param failureCtx The failure context
     * @return The Salesforce Id of the orphan transaction, or null if upsert failed
     */
    private Id createOrphanTransaction(UoWEventPublishFailureContext failureCtx) {
        UoWAuditTransaction__c orphan = new UoWAuditTransaction__c(
            Name = failureCtx.transactionId,
            TransactionId__c = failureCtx.transactionId,
            CorrelationId__c = failureCtx.correlationId,
            TransactionType__c = 'TOMBSTONE',
            TransactionStatus__c = UoWEnums.TransactionStatus.FAILED.name()
        );

        List<Database.UpsertResult> results = Database.upsert(
            new List<UoWAuditTransaction__c>{ orphan },
            UoWAuditTransaction__c.TransactionId__c,
            false
        );

        return results[0].isSuccess() ? orphan.Id : null;
    }

    /**
     * Query for audit transaction by TransactionId external ID.
     * May not exist yet due to timing (callback fires in separate transaction).
     *
     * @param transactionId The transaction ID to look up
     * @return The audit transaction record Id, or null if not found
     */
    private Id resolveAuditTransactionId(String transactionId) {
        if (String.isBlank(transactionId)) {
            return null;
        }

        List<UoWAuditTransaction__c> txns = [
            SELECT Id FROM UoWAuditTransaction__c
            WHERE TransactionId__c = :transactionId
            LIMIT 1
        ];

        return txns.isEmpty() ? null : txns[0].Id;
    }
}
