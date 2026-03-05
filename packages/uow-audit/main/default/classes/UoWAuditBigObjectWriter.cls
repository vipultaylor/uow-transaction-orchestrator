//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * @description Service class for writing audit data to Big Object storage.
 *              Used when AuditStorageMode is set to BIG_OBJECT.
 *
 *              Design:
 *              - Single denormalized Big Object (UoWAuditHistory__b)
 *              - Each work item event contains full transaction context (populated by publisher)
 *              - Uses Database.insertAsync() for high-volume performance
 *              - No triggers/formulas on Big Objects - all computed values calculated before insert
 *              - Uses direct field mapping for simplicity and performance
 *
 *              Note: For BIG_OBJECT storage mode, UoWAuditEventPublisher creates denormalized
 *              work item events that include all transaction context fields. This eliminates
 *              the need to correlate TRANSACTION and WORK_ITEM events, which was unreliable
 *              due to platform events potentially arriving in different batches.
 *
 *              Compound Index: CorrelationId__c (ASC) + Sequence__c (ASC) + CreatedTimestamp__c (DESC)
 *              - Enables efficient queries by transaction and work item order
 *              - Note: DateTime fields (like ArchiveDate__c) cannot be filtered in Big Object SOQL
 *
 * @author Vipul Taylor
 */
public class UoWAuditBigObjectWriter {

    // ============================================================================
    // PUBLIC API
    // ============================================================================

    /**
     * @description Write audit events to Big Object storage
     *              Creates one UoWAuditHistory__b record per work item event.
     *              Work item events are fully denormalized - they contain all transaction context.
     * @param transactionEvents List of TRANSACTION type events (ignored for BIG_OBJECT mode)
     * @param workItemEvents List of WORK_ITEM type events (contains all data including transaction context)
     */
    public static void writeAuditData(
        List<UoWAuditEvent__e> transactionEvents,
        List<UoWAuditEvent__e> workItemEvents
    ) {
        if (workItemEvents == null || workItemEvents.isEmpty()) {
            return;
        }

        // Note: transactionEvents parameter is kept for interface compatibility but ignored.
        // For BIG_OBJECT mode, the publisher doesn't create TRANSACTION events - all context
        // is embedded in each WORK_ITEM event.

        // Create Big Object records directly from work item events
        List<UoWAuditHistory__b> historyRecords = new List<UoWAuditHistory__b>();

        for (UoWAuditEvent__e event : workItemEvents) {
            try {
                UoWAuditHistory__b record = createHistoryRecord(event);
                historyRecords.add(record);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'Failed to create Big Object record from event: ' + e.getMessage() +
                    '\nCorrelationId: ' + event.CorrelationId__c +
                    '\nWorkId: ' + event.WorkId__c);
            }
        }

        // Insert asynchronously for performance
        if (!historyRecords.isEmpty()) {
            insertHistoryRecords(historyRecords);
        }
    }

    /**
     * @description Write a single work item to Big Object storage
     *              Used for real-time single record writes.
     *              Work item event should be fully denormalized (contain transaction context).
     * @param workItemEvent Single WORK_ITEM event (contains all data including transaction context)
     */
    public static void writeSingleWorkItem(UoWAuditEvent__e workItemEvent) {
        if (workItemEvent == null) {
            return;
        }

        UoWAuditHistory__b record = createHistoryRecord(workItemEvent);
        insertHistoryRecords(new List<UoWAuditHistory__b>{ record });
    }

    /**
     * @description Write tombstone records from a publish failure context.
     *              For Big Objects, creates denormalized history records from serialized events.
     *              Each work item event becomes a record with overridden status.
     *              Called by UoWAuditPublishFailureCallback when BIG_OBJECT storage mode.
     *
     * @param ctx The failure context from the callback
     */
    public static void writeFromFailure(UoWAuditPublishFailureCallback.FailureContext ctx) {
        if (ctx == null) {
            return;
        }

        List<UoWAuditHistory__b> historyRecords = new List<UoWAuditHistory__b>();

        // Step 1: Always create a tombstone record (no deserialization needed)
        historyRecords.add(createTombstoneRecord(ctx));

        // Step 2: Try to deserialize events and create work item records
        if (String.isNotBlank(ctx.serializedEventsJson)) {
            try {
                List<UoWAuditEvent__e> events = (List<UoWAuditEvent__e>) JSON.deserialize(
                    ctx.serializedEventsJson,
                    List<UoWAuditEvent__e>.class
                );

                for (UoWAuditEvent__e event : events) {
                    // For BIG_OBJECT mode, we only have WORK_ITEM events (denormalized with transaction context)
                    if (event.EventType__c == UoWAuditParameter.EVENT_TYPE_WORK_ITEM) {
                        // Override transaction status - use effective status from failure context
                        // (ROLLED_BACK_BY_PARENT for child transactions, FAILED otherwise)
                        event.TransactionStatus__c = ctx.transactionStatus;
                        // Override work item status to FAILED since operation was rolled back
                        event.WorkItemStatus__c = UoWEnums.WorkStatus.FAILED.name();

                        try {
                            UoWAuditHistory__b record = createHistoryRecord(event);
                            historyRecords.add(record);
                        } catch (Exception e) {
                            System.debug(LoggingLevel.ERROR,
                                'Failed to create Big Object record from failure event: ' + e.getMessage() +
                                '\nCorrelationId: ' + event.CorrelationId__c +
                                '\nWorkId: ' + event.WorkId__c);
                        }
                    }
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'UoWAuditBigObjectWriter.writeFromFailure deserialization failed: ' + e.getMessage() +
                    '\n' + e.getStackTraceString() +
                    ' | CorrelationId: ' + ctx.correlationId
                );
            }
        }

        // Insert all records (tombstone + any work items)
        if (!historyRecords.isEmpty()) {
            insertHistoryRecords(historyRecords);
        }
    }

    /**
     * @description Create a tombstone UoWAuditHistory__b record from failure context.
     *              Uses Sequence__c = 0 as sentinel value (real work items start at 1).
     *              Captures core identifiers and failure details without requiring event deserialization.
     * @param ctx The failure context from the callback
     * @return Tombstone Big Object record
     */
    private static UoWAuditHistory__b createTombstoneRecord(UoWAuditPublishFailureCallback.FailureContext ctx) {
        UoWAuditHistory__b tombstone = new UoWAuditHistory__b();

        // Compound index fields
        tombstone.CorrelationId__c = UoWUtils.safeTrim(ctx.correlationId);
        tombstone.Sequence__c = 0; // Sentinel value for tombstone records
        tombstone.CreatedTimestamp__c = ctx.failedAt ?? DateTime.now();

        // Transaction context
        tombstone.TransactionId__c = ctx.transactionId;
        tombstone.ParentTransactionId__c = ctx.parentTransactionId;
        tombstone.TransactionStatus__c = UoWEnums.TransactionStatus.FAILED.name();

        // Failure marker
        tombstone.FailureSource__c = 'AUDIT_EVENT';
        tombstone.ErrorMessage__c = ctx.errorMessage;

        // Archive date
        tombstone.ArchiveDate__c = DateTime.now().addDays(365 * UoWAuditParameter.ARCHIVE_RETENTION_YEARS);

        return tombstone;
    }

    // ============================================================================
    // PRIVATE HELPER METHODS - RECORD CREATION
    // ============================================================================

    /**
     * @description Create UoWAuditHistory__b record from a denormalized work item event.
     *              All fields (work item + transaction context) are read directly from the event.
     *              The publisher embeds transaction context in each work item event for BIG_OBJECT mode.
     * @param event The denormalized work item event containing all data
     * @return UoWAuditHistory__b record ready for insertion
     */
    private static UoWAuditHistory__b createHistoryRecord(UoWAuditEvent__e event) {
        UoWAuditHistory__b record = new UoWAuditHistory__b();
        DateTime now = DateTime.now();

        // ========================================================================
        // COMPOUND INDEX FIELDS (REQUIRED)
        // Per Salesforce Big Object best practices, trim index fields for reliable querying
        // ========================================================================
        record.CorrelationId__c = UoWUtils.safeTrim(event.CorrelationId__c);
        record.Sequence__c = safeIntegerFromDecimal(event.Sequence__c);
        record.CreatedTimestamp__c = now;

        // ========================================================================
        // TRANSACTION CONTEXT (from denormalized event)
        // ========================================================================
        record.TransactionId__c = event.TransactionId__c;
        record.TransactionStatus__c = event.TransactionStatus__c;
        record.ParentTransactionId__c = event.ParentTransactionId__c;

        // Transaction timing (from result.startedAt/completedAt via populateTransactionContextFields)
        record.TransactionStartTime__c = event.StartTime__c;
        record.TransactionEndTime__c = event.EndTime__c;
        record.TransactionDurationMs__c = safeIntegerFromDecimal(event.ExecutionTimeMs__c);
        record.TotalWorkItems__c = safeIntegerFromDecimal(event.WorkItemCount__c);
        record.TotalErrors__c = safeIntegerFromDecimal(event.ErrorCount__c);

        // Configuration
        record.ConfigurationName__c = event.ConfigurationName__c;
        record.ExecutionContext__c = event.ExecutionContext__c;
        record.IsDryRun__c = event.IsDryRun__c == true ? 'true' : 'false';
        record.RetentionDays__c = safeIntegerFromDecimal(event.RetentionDays__c);

        // Risk assessment
        record.RiskEvaluated__c = event.RiskEvaluated__c == true ? 'true' : 'false';
        record.RiskLevel__c = event.RiskLevel__c;
        record.RiskScore__c = event.RiskScore__c;

        // Policy evaluation
        record.PolicyEvaluated__c = event.PolicyEvaluated__c == true ? 'true' : 'false';

        // Scenario and description
        record.TransactionScenarioName__c = event.TransactionScenarioName__c;
        record.Description__c = event.Description__c;
        record.RequiresApproval__c = event.RequiresApproval__c == true ? 'true' : 'false';

        // Agent context
        record.IsAgentTransaction__c = event.IsAgentTransaction__c == true ? 'true' : 'false';
        record.AgentId__c = event.AgentId__c;
        record.AgentName__c = event.AgentName__c;
        record.AgentModelId__c = event.AgentModelId__c;
        record.AgentIntent__c = event.AgentIntent__c;
        record.AgentConfidenceScore__c = event.AgentConfidenceScore__c;
        record.AgentPromptHash__c = event.AgentPromptHash__c;

        // ========================================================================
        // USER CONTEXT (from session snapshot via populateSessionContext)
        // ========================================================================
        record.UserId__c = event.UserId__c;
        record.Username__c = event.Username__c;
        record.UserType__c = event.UserType__c;
        record.UserProfileId__c = event.UserProfileId__c;
        record.UserProfileName__c = event.UserProfileName__c;
        record.UserRoleId__c = event.UserRoleId__c;
        record.UserRoleName__c = event.UserRoleName__c;
        record.UserLicenseName__c = event.UserLicenseName__c;
        record.UserLocale__c = event.UserLocale__c;
        record.UserTimeZone__c = event.UserTimeZone__c;
        record.UserIsImpersonated__c = event.UserIsImpersonated__c == true ? 'true' : 'false';

        // ========================================================================
        // ORGANIZATION CONTEXT
        // ========================================================================
        record.OrganizationId__c = event.OrganizationId__c;
        record.OrganizationName__c = event.OrganizationName__c;
        record.OrganizationInstanceName__c = event.OrganizationInstanceName__c;
        record.OrganizationIsSandbox__c = event.OrganizationIsSandbox__c == true ? 'true' : 'false';

        // ========================================================================
        // REQUEST/AUTH CONTEXT
        // ========================================================================
        record.RequestId__c = event.RequestId__c;
        record.LoginType__c = event.LoginType__c;
        record.SessionType__c = event.SessionType__c;
        record.SourceIp__c = event.SourceIp__c;

        // ========================================================================
        // WORK ITEM FIELDS
        // ========================================================================
        record.WorkId__c = event.WorkId__c;
        record.WorkType__c = event.WorkType__c;
        record.WorkItemStatus__c = event.WorkItemStatus__c;
        record.SObjectType__c = event.SObjectType__c;
        record.DmlOperation__c = event.DmlOperation__c;
        record.ExecutionPhase__c = event.ExecutionPhase__c;

        // Counts
        record.PlannedCount__c = safeIntegerFromDecimal(event.PlannedCount__c);
        record.ProcessedCount__c = safeIntegerFromDecimal(event.ProcessedCount__c);
        record.SuccessCount__c = safeIntegerFromDecimal(event.SuccessCount__c);
        record.FailureCount__c = safeIntegerFromDecimal(event.FailureCount__c);

        // Work item timing
        record.StartTime__c = event.StartTime__c;
        record.EndTime__c = event.EndTime__c;
        record.ExecutionTimeMs__c = safeIntegerFromDecimal(event.ExecutionTimeMs__c);

        // Error and request info
        record.ErrorMessage__c = event.ErrorMessage__c;
        record.ErrorDetails__c = event.ErrorDetails__c;
        record.RequestOrigin__c = event.RequestOrigin__c;
        record.ContinueOnError__c = event.ContinueOnError__c == true ? 'true' : 'false';

        // Masking information
        record.MaskingApplied__c = event.MaskingApplied__c == true ? 'true' : 'false';
        record.MaskedFields__c = event.MaskedFields__c;

        // ========================================================================
        // WORK TYPE SPECIFIC FIELDS
        // ========================================================================
        // Flow
        record.FlowApiName__c = event.FlowApiName__c;

        // Callout
        record.Endpoint__c = event.Endpoint__c;
        record.HttpMethod__c = event.HttpMethod__c;

        // Notification
        record.NotificationType__c = event.NotificationType__c;

        // ========================================================================
        // ORIGIN SOURCE METADATA
        // ========================================================================
        record.OriginClassName__c = event.OriginClassName__c;
        record.OriginMethodName__c = event.OriginMethodName__c;
        record.OriginLineNumber__c = safeIntegerFromDecimal(event.OriginLineNumber__c);
        record.OriginMetadataType__c = event.OriginMetadataType__c;
        record.OriginApiVersion__c = event.OriginApiVersion__c;
        record.OriginSourceMetadata__c = event.OriginSourceMetadata__c;
        record.OriginSnippetStartLine__c = safeIntegerFromDecimal(event.OriginSnippetStartLine__c);
        record.OriginLastModifiedDate__c = event.OriginLastModifiedDate__c;

        // ========================================================================
        // ARCHIVE DATE
        // ========================================================================
        record.ArchiveDate__c = now.addDays(365 * UoWAuditParameter.ARCHIVE_RETENTION_YEARS);

        return record;
    }

    // ============================================================================
    // PRIVATE HELPER METHODS - DML
    // ============================================================================

    /**
     * @description Insert Big Object records via injectable DML service.
     *              Delegates to UoWAuditBigObjectDmlService which can be
     *              stubbed via System.StubProvider in tests.
     */
    private static void insertHistoryRecords(List<UoWAuditHistory__b> records) {
        UoWAuditBigObjectDmlService.getInstance().insertRecords(records);
    }

    // ============================================================================
    // PRIVATE HELPER METHODS - UTILITIES
    // ============================================================================

    /**
     * @description Safely convert Decimal to Integer
     */
    private static Integer safeIntegerFromDecimal(Decimal value) {
        if (value == null) {
            return null;
        }
        return value.intValue();
    }
}