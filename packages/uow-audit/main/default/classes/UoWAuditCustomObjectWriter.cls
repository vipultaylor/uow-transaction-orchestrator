//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * @description Service class for writing audit data to Custom Object storage.
 *              Used when AuditStorageMode is set to CUSTOM_OBJECT (default).
 *
 *              Design:
 *              - Creates UoWAuditTransaction__c parent records from TRANSACTION events
 *              - Creates UoWAuditWorkItem__c child records from WORK_ITEM events
 *              - Uses insert (not upsert) since each transaction is unique
 *              - Direct field mapping for fields with matching names
 *
 * @author Vipul Taylor
 */
public without sharing class UoWAuditCustomObjectWriter {

    // ============================================================================
    // PUBLIC API
    // ============================================================================

    /**
     * @description Write audit events to Custom Object storage
     *              Creates UoWAuditTransaction__c and UoWAuditWorkItem__c records
     * @param transactionEvents List of TRANSACTION type events
     * @param workItemEvents List of WORK_ITEM type events
     */
    public static void writeAuditData(
        List<UoWAuditEvent__e> transactionEvents,
        List<UoWAuditEvent__e> workItemEvents
    ) {
        // Process TRANSACTION events first (create parent records)
        if (transactionEvents != null && !transactionEvents.isEmpty()) {
            processTransactionEvents(transactionEvents);
        }

        // Process WORK_ITEM events (create child records)
        if (workItemEvents != null && !workItemEvents.isEmpty()) {
            processWorkItemEvents(workItemEvents);
        }
    }

    /**
     * @description Write tombstone transaction and work items from a publish failure context.
     *              Deserializes the original events, overrides status fields, and uses
     *              createTransactionFromEvent/createWorkItemFromEvent for field mapping (DRY).
     *              Called by UoWAuditPublishFailureCallback when CUSTOM_OBJECT storage mode.
     *
     * @param ctx The failure context from the callback
     */
    public static void writeFromFailure(UoWAuditPublishFailureCallback.FailureContext ctx) {
        if (ctx == null || String.isBlank(ctx.serializedEventsJson)) {
            return;
        }

        try {
            // Deserialize the original events
            List<UoWAuditEvent__e> events = (List<UoWAuditEvent__e>) JSON.deserialize(
                ctx.serializedEventsJson,
                List<UoWAuditEvent__e>.class
            );

            // Process events and build records with overrides
            List<UoWAuditTransaction__c> transactions = new List<UoWAuditTransaction__c>();
            List<UoWAuditEvent__e> workItemEvents = new List<UoWAuditEvent__e>();

            for (UoWAuditEvent__e event : events) {
                if (event.EventType__c == UoWAuditParameter.EVENT_TYPE_TRANSACTION) {
                    // Override transaction status (ROLLED_BACK_BY_PARENT for child, FAILED otherwise)
                    event.TransactionStatus__c = ctx.transactionStatus;

                    // Create transaction record using standard field mapping
                    UoWAuditTransaction__c txn = createTransactionFromEvent(event);
                    // Override to TOMBSTONE with FAILED status (audit persistence failed)
                    txn.TransactionType__c = 'TOMBSTONE';
                    txn.TransactionStatus__c = UoWEnums.TransactionStatus.FAILED.name();
                    transactions.add(txn);

                } else if (event.EventType__c == UoWAuditParameter.EVENT_TYPE_WORK_ITEM) {
                    // Override work item status to FAILED since operation was rolled back
                    event.WorkItemStatus__c = UoWEnums.WorkStatus.FAILED.name();
                    workItemEvents.add(event);
                }
            }

            // Upsert scenario records before transactions (mirrors processTransactionEvents flow)
            upsertScenarioRecords(events);

            // Upsert tombstone transaction
            Id transactionId = null;
            if (!transactions.isEmpty()) {
                List<Database.UpsertResult> upsertResults = Database.upsert(
                    transactions, UoWAuditTransaction__c.TransactionId__c, false
                );
                if (upsertResults[0].isSuccess()) {
                    transactionId = transactions[0].Id;
                } else {
                    for (Database.Error err : upsertResults[0].getErrors()) {
                        System.debug(LoggingLevel.ERROR,
                            'UoWAuditCustomObjectWriter.writeFromFailure tombstone upsert failed: ' +
                            err.getStatusCode() + ' - ' + err.getMessage() +
                            ' | CorrelationId: ' + ctx.correlationId
                        );
                    }
                }
            }

            // Process work items using existing method
            if (!workItemEvents.isEmpty()) {
                processWorkItemEvents(workItemEvents);
            }

            // Create failure record linked to transaction
            if (transactionId != null) {
                createFailureRecord(ctx, transactionId);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'UoWAuditCustomObjectWriter.writeFromFailure failed: ' + e.getMessage() +
                '\n' + e.getStackTraceString() +
                ' | CorrelationId: ' + ctx.correlationId
            );
        }
    }

    /**
     * @description Create failure record linked to the transaction.
     * @param ctx The failure context
     * @param transactionId The Salesforce Id of the tombstone transaction
     */
    private static void createFailureRecord(UoWAuditPublishFailureCallback.FailureContext ctx, Id transactionId) {
        UoWEventPublishFailure__c failure = new UoWEventPublishFailure__c(
            AuditTransaction__c = transactionId,
            CorrelationId__c = ctx.correlationId,
            TransactionId__c = ctx.transactionId,
            FailureSource__c = 'AUDIT_EVENT',
            StorageMode__c = ctx.storageMode,
            FailedEventCount__c = ctx.eventCount,
            PublishedEventCount__c = ctx.eventCount,
            FailedAt__c = ctx.failedAt,
            HasRelatedTransaction__c = true,
            ErrorMessage__c = ctx.errorMessage?.left(5000)
        );
        Database.insert(failure, false);
    }

    // ============================================================================
    // PRIVATE HELPER METHODS - TRANSACTION EVENTS
    // ============================================================================

    /**
     * @description Process TRANSACTION type events and create parent records.
     *              Uses multi-pass approach:
     *              Pass 0: Upsert scenario records (if EnableScenarioRecordTracking is true)
     *              Pass 1: Insert all transactions without parent relationships
     *              Pass 2: Update transactions to set parent lookup (now that parents exist)
     */
    private static void processTransactionEvents(List<UoWAuditEvent__e> events) {
        // Pass 0: Upsert scenario records if any event has EnableScenarioRecordTracking enabled
        upsertScenarioRecords(events);

        List<UoWAuditTransaction__c> transactions = new List<UoWAuditTransaction__c>();

        // Track which transactions have parent relationships to resolve
        // Key: TransactionId__c of child, Value: ParentTransactionId__c
        Map<String, String> childToParentMap = new Map<String, String>();

        for (UoWAuditEvent__e event : events) {
            UoWAuditTransaction__c txn = createTransactionFromEvent(event);
            transactions.add(txn);
        }

        if (!transactions.isEmpty()) {
            upsertTransactions(transactions);
        }
    }

    /**
     * @description Upsert scenario records when EnableScenarioRecordTracking is enabled.
     *              Must be called BEFORE inserting transactions to ensure scenarios exist
     *              for external ID lookup.
     * @param events The transaction events to process
     */
    private static void upsertScenarioRecords(List<UoWAuditEvent__e> events) {
        // Collect unique scenario names from events that have tracking enabled
        Set<String> scenarioNames = new Set<String>();
        for (UoWAuditEvent__e event : events) {
            if (event.EnableScenarioRecordTracking__c == true && String.isNotBlank(event.TransactionScenarioName__c)) {
                scenarioNames.add(event.TransactionScenarioName__c);
            }
        }

        if (scenarioNames.isEmpty()) {
            return;
        }

        // Build scenario records for upsert
        List<UoWScenario__c> scenarios = new List<UoWScenario__c>();
        for (String name : scenarioNames) {
            scenarios.add(new UoWScenario__c(
                Name = name,
                UniqueId__c = name
            ));
        }

        // Upsert using UniqueId__c as external ID (allows partial success)
        Database.upsert(scenarios, UoWScenario__c.UniqueId__c, false);
    }

    /**
     * @description Create UoWAuditTransaction__c from TRANSACTION event
     *              Uses direct field mapping for matching field names
     */
    private static UoWAuditTransaction__c createTransactionFromEvent(UoWAuditEvent__e event) {
        UoWAuditTransaction__c txn = new UoWAuditTransaction__c();

        // Core identifiers - Name and TransactionId__c both store transactionId
        txn.Name = event.TransactionId__c;
        txn.TransactionId__c = event.TransactionId__c;
        txn.CorrelationId__c = event.CorrelationId__c;
        txn.TransactionType__c = 'AUDIT';
        txn.TransactionStatus__c = event.TransactionStatus__c;

        // User identity
        txn.User__c = event.UserId__c;
        txn.UserProfileId__c = event.UserProfileId__c;
        txn.UserProfileName__c = event.UserProfileName__c;
        txn.Username__c = event.Username__c;
        txn.UserType__c = event.UserType__c;
        txn.UserRoleId__c = event.UserRoleId__c;
        txn.UserRoleName__c = event.UserRoleName__c;
        txn.UserLicenseName__c = event.UserLicenseName__c;

        // User preferences
        txn.UserLocale__c = event.UserLocale__c;
        txn.UserTimeZone__c = event.UserTimeZone__c;

        // Organization context
        txn.OrganizationId__c = event.OrganizationId__c;
        txn.OrganizationName__c = event.OrganizationName__c;
        txn.OrganizationInstanceName__c = event.OrganizationInstanceName__c;
        txn.OrganizationIsSandbox__c = event.OrganizationIsSandbox__c;

        // Request context
        txn.RequestId__c = event.RequestId__c;

        // Auth session
        txn.LoginType__c = event.LoginType__c;
        txn.SessionType__c = event.SessionType__c;
        txn.SourceIp__c = event.SourceIp__c;
        txn.UserIsImpersonated__c = event.UserIsImpersonated__c;

        // Execution context
        txn.ExecutionContext__c = event.ExecutionContext__c;
        txn.IsDryRun__c = event.IsDryRun__c;
        txn.CommitMode__c = event.CommitMode__c;
        txn.ConfigurationName__c = event.ConfigurationName__c;

        // Async tracking - ParentTransaction__c lookup is resolved in second pass via resolveParentRelationships()
        // ParentTransactionId__c text field stored for deferred resolution via scheduled flow
        txn.ParentTransactionId__c = event.ParentTransactionId__c;
        txn.AsyncDepth__c = safeIntegerFromDecimal(event.AsyncDepth__c);

        // Timing (ExecutionTimeMs populated directly for millisecond precision)
        txn.StartTime__c = event.StartTime__c;
        txn.EndTime__c = event.EndTime__c;
        txn.ExecutionTimeMs__c = event.ExecutionTimeMs__c;

        // Error tracking
        txn.HasErrors__c = event.HasErrors__c;
        txn.ErrorCount__c = safeIntegerFromDecimal(event.ErrorCount__c);
        txn.WarningCount__c = safeIntegerFromDecimal(event.WarningCount__c);
        txn.ErrorDetails__c = event.ErrorDetails__c;

        // Risk assessment
        txn.RiskEvaluated__c = event.RiskEvaluated__c;
        txn.RiskScore__c = event.RiskScore__c;
        txn.RiskLevel__c = event.RiskLevel__c;
        txn.RequiresApproval__c = event.RequiresApproval__c;
        txn.RiskFactors__c = event.RiskFactors__c;

        // Policy evaluation
        txn.PolicyEvaluated__c = event.PolicyEvaluated__c;
        txn.PolicyCount__c = safeIntegerFromDecimal(event.PolicyCount__c);
        txn.StrictestAction__c = event.StrictestAction__c;
        txn.PolicyEvaluations__c = event.PolicyEvaluations__c;

        // Retention and Archival
        txn.RetentionDays__c = safeIntegerFromDecimal(event.RetentionDays__c);
        txn.ArchivalMode__c = event.ArchivalMode__c;
        txn.ArchiveDate__c = event.ArchiveDate__c;

        // Scenario and description
        txn.TransactionScenarioName__c = event.TransactionScenarioName__c;
        txn.Description__c = event.Description__c;

        // Scenario - lookup via external ID (scenario record already upserted if enabled)
        if (event.EnableScenarioRecordTracking__c == true && String.isNotBlank(event.TransactionScenarioName__c)) {
            txn.TransactionScenario__r = new UoWScenario__c(
                UniqueId__c = event.TransactionScenarioName__c
            );
        }

        // JSON fields
        txn.ConfigurationSnapshot__c = event.ConfigurationSnapshot__c;
        txn.CustomMetadata__c = event.CustomMetadata__c;
        txn.Statistics__c = event.Statistics__c;
        txn.Messages__c = event.Messages__c;
        txn.Timeline__c = event.TraceTimeline__c;

        // Tracing
        if (String.isNotBlank(event.TraceTimeline__c)) {
            txn.TracingEnabled__c = true;
        }

        // Governor limits - deserialize to UoWGovernorLimits and map to fields
        // For Transaction: store Consumed and Max separately
        populateTransactionLimits(txn, event.LimitsTotalConsumed__c, event.LimitsMax__c);

        return txn;
    }

    // ============================================================================
    // PRIVATE HELPER METHODS - WORK ITEM EVENTS
    // ============================================================================

    /**
     * @description Process WORK_ITEM type events and create child records
     */
    private static void processWorkItemEvents(List<UoWAuditEvent__e> events) {
        List<UoWAuditWorkItem__c> workItems = new List<UoWAuditWorkItem__c>();

        for (UoWAuditEvent__e event : events) {
            UoWAuditWorkItem__c wi = createWorkItemFromEvent(event);
            workItems.add(wi);
        }

        // Insert work items
        if (!workItems.isEmpty()) {
            insertWorkItems(workItems);
        }
    }

    /**
     * @description Create UoWAuditWorkItem__c from WORK_ITEM event
     *              Uses direct field mapping for matching field names
     */
    private static UoWAuditWorkItem__c createWorkItemFromEvent(UoWAuditEvent__e event) {
        UoWAuditWorkItem__c wi = new UoWAuditWorkItem__c();

        // Parent relationship via TransactionId__c (unique external ID)
        wi.AuditTransaction__r = new UoWAuditTransaction__c(
            TransactionId__c = event.TransactionId__c
        );

        // Core identifiers
        wi.Name = event.WorkId__c;
        wi.Sequence__c = safeIntegerFromDecimal(event.Sequence__c);
        wi.WorkType__c = event.WorkType__c;
        wi.WorkItemStatus__c = event.WorkItemStatus__c;

        // Type-specific fields
        wi.SObjectType__c = event.SObjectType__c;
        wi.DmlOperation__c = event.DmlOperation__c;
        wi.ExecutionPhase__c = event.ExecutionPhase__c;
        wi.FlowApiName__c = event.FlowApiName__c;
        wi.HttpMethod__c = event.HttpMethod__c;
        wi.Endpoint__c = event.Endpoint__c;
        wi.NotificationType__c = event.NotificationType__c;

        // Timing (DurationMs is formula field)
        wi.RequestedAt__c = event.RequestedAt__c;
        wi.StartTime__c = event.StartTime__c;
        wi.EndTime__c = event.EndTime__c;
        wi.ExecutionTimeMs__c = event.ExecutionTimeMs__c;
        wi.IsExecuted__c = event.IsExecuted__c;

        // Record counts
        wi.PlannedCount__c = safeIntegerFromDecimal(event.PlannedCount__c);
        wi.ProcessedCount__c = safeIntegerFromDecimal(event.ProcessedCount__c);
        wi.SuccessCount__c = safeIntegerFromDecimal(event.SuccessCount__c);
        wi.FailureCount__c = safeIntegerFromDecimal(event.FailureCount__c);

        // Error handling
        wi.ContinueOnError__c = event.ContinueOnError__c;
        wi.HasErrors__c = event.HasErrors__c;
        wi.ErrorCount__c = safeIntegerFromDecimal(event.ErrorCount__c);
        wi.ErrorMessage__c = event.ErrorMessage__c;
        wi.ErrorDetails__c = event.ErrorDetails__c;

        // Stack trace and origin
        wi.RequestStackTrace__c = event.RequestStackTrace__c;
        wi.RequestOrigin__c = event.RequestOrigin__c;

        // Origin source metadata
        wi.OriginMetadataType__c = event.OriginMetadataType__c;
        wi.OriginApiVersion__c = event.OriginApiVersion__c;
        wi.OriginClassName__c = event.OriginClassName__c;
        wi.OriginMethodName__c = event.OriginMethodName__c;
        wi.OriginLineNumber__c = safeIntegerFromDecimal(event.OriginLineNumber__c);
        wi.OriginSnippetStartLine__c = safeIntegerFromDecimal(event.OriginSnippetStartLine__c);
        wi.OriginLastModifiedDate__c = event.OriginLastModifiedDate__c;
        wi.OriginSourceMetadata__c = event.OriginSourceMetadata__c;

        // Snapshot
        wi.Snapshot__c = event.Snapshot__c;

        // Masking information
        wi.MaskingApplied__c = event.MaskingApplied__c;
        wi.MaskedFields__c = event.MaskedFields__c;

        // Governor limits - deserialize to UoWGovernorLimits and map to fields
        // For WorkItem: store AtStart and AtEnd (Consumed is calculated via formula fields)
        populateWorkItemLimits(wi, event.LimitsAtStart__c, event.LimitsAtEnd__c);

        return wi;
    }

    // ============================================================================
    // PRIVATE HELPER METHODS - GOVERNOR LIMITS
    // ============================================================================

    /**
     * @description Populate transaction limits from UoWGovernorLimits JSON
     *              Deserializes JSON to UoWGovernorLimits instances (avoids string literals)
     *              For Transaction: stores Consumed and Max values separately
     * @param txn The transaction record to populate
     * @param consumedJson JSON string with consumed UoWGovernorLimits data
     * @param maxJson JSON string with max UoWGovernorLimits data
     */
    private static void populateTransactionLimits(UoWAuditTransaction__c txn, String consumedJson, String maxJson) {
        // Consumed values (primary metric for transaction-level)
        if (String.isNotBlank(consumedJson)) {
            UoWGovernorLimits consumed = (UoWGovernorLimits) JSON.deserialize(consumedJson, UoWGovernorLimits.class);
            // DML limits
            txn.LimitsDmlStatementsConsumed__c = consumed.dmlStatements;
            txn.LimitsDmlRowsConsumed__c = consumed.dmlRows;
            // SOQL/SOSL limits
            txn.LimitsSoqlQueriesConsumed__c = consumed.soqlQueries;
            txn.LimitsSoqlRowsConsumed__c = consumed.soqlRows;
            txn.LimitsAggregateQueriesConsumed__c = consumed.aggregateQueries;
            txn.LimitsQueryLocatorRowsConsumed__c = consumed.queryLocatorRows;
            txn.LimitsSoslSearchesConsumed__c = consumed.soslSearches;
            // Apex cursor limits
            txn.LimitsApexCursorFetchCallsConsumed__c = consumed.apexCursorFetchCalls;
            txn.LimitsApexCursorRowsConsumed__c = consumed.apexCursorRows;
            // Resource limits
            txn.LimitsCpuTimeConsumed__c = consumed.cpuTime;
            txn.LimitsHeapSizeConsumed__c = consumed.heapSize;
            // Async limits
            txn.LimitsCalloutsConsumed__c = consumed.callouts;
            txn.LimitsFutureCallsConsumed__c = consumed.futureCalls;
            txn.LimitsQueueableJobsConsumed__c = consumed.queueableJobs;
            txn.LimitsEmailInvocationsConsumed__c = consumed.emailInvocations;
            txn.LimitsMobilePushApexCallsConsumed__c = consumed.mobilePushApexCalls;
            // Publish limits
            txn.LimitsPublishImmediateDmlConsumed__c = consumed.publishImmediateDml;
        }

        // Max values (limit values - constant within transaction)
        if (String.isNotBlank(maxJson)) {
            UoWGovernorLimits max = (UoWGovernorLimits) JSON.deserialize(maxJson, UoWGovernorLimits.class);
            // DML limits
            txn.LimitsDmlStatementsMax__c = max.dmlStatements;
            txn.LimitsDmlRowsMax__c = max.dmlRows;
            // SOQL/SOSL limits
            txn.LimitsSoqlQueriesMax__c = max.soqlQueries;
            txn.LimitsSoqlRowsMax__c = max.soqlRows;
            txn.LimitsAggregateQueriesMax__c = max.aggregateQueries;
            txn.LimitsQueryLocatorRowsMax__c = max.queryLocatorRows;
            txn.LimitsSoslSearchesMax__c = max.soslSearches;
            // Apex cursor limits
            txn.LimitsApexCursorFetchCallsMax__c = max.apexCursorFetchCalls;
            txn.LimitsApexCursorRowsMax__c = max.apexCursorRows;
            // Resource limits
            txn.LimitsCpuTimeMax__c = max.cpuTime;
            txn.LimitsHeapSizeMax__c = max.heapSize;
            // Async limits
            txn.LimitsCalloutsMax__c = max.callouts;
            txn.LimitsFutureCallsMax__c = max.futureCalls;
            txn.LimitsQueueableJobsMax__c = max.queueableJobs;
            txn.LimitsEmailInvocationsMax__c = max.emailInvocations;
            txn.LimitsMobilePushApexCallsMax__c = max.mobilePushApexCalls;
            // Publish limits
            txn.LimitsPublishImmediateDmlMax__c = max.publishImmediateDml;
        }
    }

    /**
     * @description Populate work item limits from UoWGovernorLimits JSON fields
     *              Deserializes JSON to UoWGovernorLimits instances (avoids string literals)
     *              For WorkItem: stores AtStart and AtEnd values only
     *              Note: Consumed values are calculated (AtEnd - AtStart) via formula fields
     * @param wi The work item record to populate
     * @param atStartJson JSON string with UoWGovernorLimits at start
     * @param atEndJson JSON string with UoWGovernorLimits at end
     */
    private static void populateWorkItemLimits(
        UoWAuditWorkItem__c wi,
        String atStartJson,
        String atEndJson
    ) {
        // Populate AtStart limits
        if (String.isNotBlank(atStartJson)) {
            UoWGovernorLimits atStart = (UoWGovernorLimits) JSON.deserialize(atStartJson, UoWGovernorLimits.class);
            // DML limits
            wi.LimitsDmlStatementsAtStart__c = atStart.dmlStatements;
            wi.LimitsDmlRowsAtStart__c = atStart.dmlRows;
            // SOQL/SOSL limits
            wi.LimitsSoqlQueriesAtStart__c = atStart.soqlQueries;
            wi.LimitsSoqlRowsAtStart__c = atStart.soqlRows;
            wi.LimitsAggregateQueriesAtStart__c = atStart.aggregateQueries;
            wi.LimitsQueryLocatorRowsAtStart__c = atStart.queryLocatorRows;
            wi.LimitsSoslSearchesAtStart__c = atStart.soslSearches;
            // Apex cursor limits
            wi.LimitsApexCursorFetchCallsAtStart__c = atStart.apexCursorFetchCalls;
            wi.LimitsApexCursorRowsAtStart__c = atStart.apexCursorRows;
            // Resource limits
            wi.LimitsCpuTimeAtStart__c = atStart.cpuTime;
            wi.LimitsHeapSizeAtStart__c = atStart.heapSize;
            // Async limits
            wi.LimitsCalloutsAtStart__c = atStart.callouts;
            wi.LimitsFutureCallsAtStart__c = atStart.futureCalls;
            wi.LimitsQueueableJobsAtStart__c = atStart.queueableJobs;
            wi.LimitsEmailInvocationsAtStart__c = atStart.emailInvocations;
            wi.LimitsMobilePushApexCallsAtStart__c = atStart.mobilePushApexCalls;
            // Publish limits
            wi.LimitsPublishImmediateDmlAtStart__c = atStart.publishImmediateDml;
        }

        // Populate AtEnd limits
        if (String.isNotBlank(atEndJson)) {
            UoWGovernorLimits atEnd = (UoWGovernorLimits) JSON.deserialize(atEndJson, UoWGovernorLimits.class);
            // DML limits
            wi.LimitsDmlStatementsAtEnd__c = atEnd.dmlStatements;
            wi.LimitsDmlRowsAtEnd__c = atEnd.dmlRows;
            // SOQL/SOSL limits
            wi.LimitsSoqlQueriesAtEnd__c = atEnd.soqlQueries;
            wi.LimitsSoqlRowsAtEnd__c = atEnd.soqlRows;
            wi.LimitsAggregateQueriesAtEnd__c = atEnd.aggregateQueries;
            wi.LimitsQueryLocatorRowsAtEnd__c = atEnd.queryLocatorRows;
            wi.LimitsSoslSearchesAtEnd__c = atEnd.soslSearches;
            // Apex cursor limits
            wi.LimitsApexCursorFetchCallsAtEnd__c = atEnd.apexCursorFetchCalls;
            wi.LimitsApexCursorRowsAtEnd__c = atEnd.apexCursorRows;
            // Resource limits
            wi.LimitsCpuTimeAtEnd__c = atEnd.cpuTime;
            wi.LimitsHeapSizeAtEnd__c = atEnd.heapSize;
            // Async limits
            wi.LimitsCalloutsAtEnd__c = atEnd.callouts;
            wi.LimitsFutureCallsAtEnd__c = atEnd.futureCalls;
            wi.LimitsQueueableJobsAtEnd__c = atEnd.queueableJobs;
            wi.LimitsEmailInvocationsAtEnd__c = atEnd.emailInvocations;
            wi.LimitsMobilePushApexCallsAtEnd__c = atEnd.mobilePushApexCalls;
            // Publish limits
            wi.LimitsPublishImmediateDmlAtEnd__c = atEnd.publishImmediateDml;
        }
    }

    // ============================================================================
    // PRIVATE HELPER METHODS - DML OPERATIONS
    // ============================================================================

    /**
     * @description Upsert transactions using TransactionId__c as external ID.
     *              Upsert (not insert) so that tombstone records created by
     *              AuditPublishFailureCallback are seamlessly overwritten with
     *              real transaction data - same record Id, failure records stay linked.
     */
    private static void upsertTransactions(List<UoWAuditTransaction__c> transactions) {
        List<Database.UpsertResult> results = Database.upsert(
            transactions, UoWAuditTransaction__c.TransactionId__c, false
        );

        List<String> errors = new List<String>();
        for (Integer i = 0; i < results.size(); i++) {
            Database.UpsertResult result = results[i];
            if (!result.isSuccess()) {
                for (Database.Error err : result.getErrors()) {
                    String txnId = transactions[i].TransactionId__c;
                    errors.add('Transaction[' + txnId + ']: ' + err.getStatusCode() + ' - ' + err.getMessage() +
                        ' (Fields: ' + String.join(err.getFields(), ', ') + ')');
                }
            }
        }

        if (!errors.isEmpty()) {
            throw new AuditWriterException(
                'Failed to upsert ' + errors.size() + ' transaction(s): ' + String.join(errors, '; ')
            );
        }
    }

    /**
     * @description Insert work items
     */
    private static void insertWorkItems(List<UoWAuditWorkItem__c> workItems) {
        List<Database.SaveResult> results = Database.insert(workItems, false);

        List<String> errors = new List<String>();
        for (Integer i = 0; i < results.size(); i++) {
            Database.SaveResult result = results[i];
            if (!result.isSuccess()) {
                for (Database.Error err : result.getErrors()) {
                    String workId = workItems[i].Name;
                    errors.add('WorkItem[' + workId + ']: ' + err.getStatusCode() + ' - ' + err.getMessage() +
                        ' (Fields: ' + String.join(err.getFields(), ', ') + ')');
                }
            }
        }

        if (!errors.isEmpty()) {
            throw new AuditWriterException(
                'Failed to insert ' + errors.size() + ' work item(s): ' + String.join(errors, '; ')
            );
        }
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

    // ============================================================================
    // INNER CLASSES
    // ============================================================================

    /**
     * @description Exception for audit writer errors - thrown to make failures visible in Flow interviews
     */
    public class AuditWriterException extends Exception {}
}