//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * @description Service for publishing audit events to platform events.
 *              Handles transaction and work item event publishing with individual fields.
 *
 *              Design Principles:
 *              1. Individual fields for all queryable/filterable properties
 *              2. Separate JSON fields for each complex data type (no combined payload)
 *              3. Uses JSON.serialize() directly on domain objects
 *              4. Platform events survive transaction rollbacks
 *              5. Storage mode determines event structure:
 *                 - CUSTOM_OBJECT: 1 TRANSACTION + N WORK_ITEM events
 *                 - BIG_OBJECT: N denormalized WORK_ITEM events (no TRANSACTION event)
 *              6. Uses Result (outcome) not Plan (intent) for work items
 *
 * @author Vipul Taylor
 */
public inherited sharing class UoWAuditEventPublisher {

    // ============================================================================
    // PUBLIC API
    // ============================================================================

    /**
     * @description Publish all audit events for a transaction.
     *              Uses result.getAllWorkItems() to get outcomes (both executed
     *              and non-executed work items are in Result after finalization).
     *
     *              Storage mode determines event structure:
     *              - CUSTOM_OBJECT: Publishes 1 TRANSACTION + N WORK_ITEM events
     *              - BIG_OBJECT: Publishes N denormalized WORK_ITEM events with transaction context
     *              - PLATFORM_EVENT/EXTERNAL: Same as CUSTOM_OBJECT (for downstream consumption)
     *
     * @param ctx The UoW context
     * @param result The UoW result containing all work items (outcome)
     * @param auditPlugin The audit plugin instance containing settings
     * @return PublishResult with success status and any errors
     */
    public static PublishResult publishAuditEvents(UoWContext ctx, UoWResult result, UoWAuditPlugin auditPlugin) {
        try {
            // Get all work items from Result (outcome, not Plan/intent)
            List<UoWWorkItem> workItems = result.getAllWorkItems();

            // Collect all events to publish - structure depends on storage mode
            List<UoWAuditEvent__e> eventsToPublish;
            Boolean hasTransactionEvent;

            if (auditPlugin.getStorageMode() == UoWAuditEnums.AuditStorageMode.BIG_OBJECT) {
                // BIG_OBJECT mode: Publish denormalized work item events (no transaction event)
                // Each work item event contains full transaction context
                eventsToPublish = buildDenormalizedWorkItemEvents(ctx, result, workItems, auditPlugin);
                hasTransactionEvent = false;
            } else {
                // CUSTOM_OBJECT, PLATFORM_EVENT, EXTERNAL: Standard structure
                // 1 TRANSACTION event + N WORK_ITEM events
                eventsToPublish = buildStandardEvents(ctx, result, workItems, auditPlugin);
                hasTransactionEvent = true;
            }

            // Create failure callback for async delivery failure detection
            UoWAuditPublishFailureCallback failureCallback = new UoWAuditPublishFailureCallback(ctx.correlationId, ctx.transactionId);
            failureCallback.parentTransactionId = ctx.parentTransactionId;
            failureCallback.eventCount = eventsToPublish.size();
            failureCallback.storageMode = auditPlugin.getStorageMode().name();
            failureCallback.transactionStatus = result.transactionStatus?.name();
            failureCallback.serializedEventsJson = JSON.serialize(eventsToPublish);

            // Publish all events in a single call with failure callback
            List<Database.SaveResult> saveResults = EventBus.publish(eventsToPublish, failureCallback);

            // Process synchronous results into a fully populated PublishResult
            return processPublishResults(saveResults, workItems.size(), hasTransactionEvent);

        } catch (Exception ex) {
            PublishResult publishResult = new PublishResult();
            publishResult.isSuccess = false;
            PublishError pubError = new PublishError('PUBLISHER', 'EXCEPTION', ex.getMessage() + '\n' + ex.getStackTraceString());
            publishResult.errors.add(pubError);
            return publishResult;
        }
    }

    /**
     * @description Process synchronous publish SaveResults into a fully populated PublishResult.
     *              Creates the PublishResult, sets all properties (event counts, success/failure
     *              counts, error details, isSuccess flag), and returns it.
     *
     * @param saveResults The SaveResult list from EventBus.publish()
     * @param workItemCount Number of work item events built
     * @param hasTransactionEvent Whether a TRANSACTION event was included (first in list)
     * @return Fully populated PublishResult
     */
    @TestVisible
    private static PublishResult processPublishResults(List<Database.SaveResult> saveResults, Integer workItemCount, Boolean hasTransactionEvent) {
        PublishResult publishResult = new PublishResult();
        publishResult.transactionEventBuilt = hasTransactionEvent;
        publishResult.workItemEventsBuilt = workItemCount;

        for (Integer i = 0; i < saveResults.size(); i++) {
            Database.SaveResult sr = saveResults[i];
            if (sr.isSuccess()) {
                publishResult.successCount++;
            } else {
                publishResult.failureCount++;
                for (Database.Error err : sr.getErrors()) {
                    String eventId = (hasTransactionEvent && i == 0) ? 'TRANSACTION' : 'WORK_ITEM_' + (hasTransactionEvent ? i : i + 1);
                    PublishError pubError = new PublishError(eventId, err.getStatusCode().name(), err.getMessage());
                    publishResult.errors.add(pubError);
                }
            }
        }

        publishResult.isSuccess = (publishResult.failureCount == 0);
        return publishResult;
    }

    // ============================================================================
    // PRIVATE METHODS - EVENT BUILDING BY STORAGE MODE
    // ============================================================================

    /**
     * @description Build standard events for CUSTOM_OBJECT, PLATFORM_EVENT, EXTERNAL modes.
     *              Creates 1 TRANSACTION event + N WORK_ITEM events.
     */
    private static List<UoWAuditEvent__e> buildStandardEvents(
        UoWContext ctx,
        UoWResult result,
        List<UoWWorkItem> workItems,
        UoWAuditPlugin auditPlugin
    ) {
        List<UoWAuditEvent__e> events = new List<UoWAuditEvent__e>();

        // Build and add transaction event
        events.add(buildTransactionEvent(ctx, result, workItems.size(), auditPlugin));

        // Build and add work item events
        for (UoWWorkItem workItem : workItems) {
            events.add(buildWorkItemEvent(ctx, workItem, result.maskingResult, auditPlugin));
        }

        return events;
    }

    /**
     * @description Build denormalized work item events for BIG_OBJECT mode.
     *              Each event contains full transaction context - no separate TRANSACTION event needed.
     *              This ensures Big Object records have all data even if events arrive in different batches.
     */
    private static List<UoWAuditEvent__e> buildDenormalizedWorkItemEvents(
        UoWContext ctx,
        UoWResult result,
        List<UoWWorkItem> workItems,
        UoWAuditPlugin auditPlugin
    ) {
        List<UoWAuditEvent__e> events = new List<UoWAuditEvent__e>();

        for (UoWWorkItem workItem : workItems) {
            UoWAuditEvent__e evt = new UoWAuditEvent__e();

            // Core identifiers
            evt.EventType__c = UoWAuditParameter.EVENT_TYPE_WORK_ITEM;
            evt.CorrelationId__c = ctx.correlationId;
            evt.TransactionId__c = ctx.transactionId;
            evt.StorageMode__c = auditPlugin.getStorageMode().name();

            // Populate BOTH transaction context AND work item fields
            populateTransactionContextFields(evt, ctx, result, workItems.size(), auditPlugin);
            populateWorkItemFields(evt, ctx, workItem, result.maskingResult, auditPlugin);

            events.add(evt);
        }

        return events;
    }

    // ============================================================================
    // PRIVATE METHODS - FIELD POPULATION (REUSABLE)
    // ============================================================================

    /**
     * @description Populate transaction-level context fields on an event.
     *              Used by both TRANSACTION events and denormalized WORK_ITEM events (BIG_OBJECT mode).
     *              Includes: session context, execution context, timing, risk, policy, agent, retention.
     */
    private static void populateTransactionContextFields(
        UoWAuditEvent__e evt,
        UoWContext ctx,
        UoWResult result,
        Integer workItemCount,
        UoWAuditPlugin auditPlugin
    ) {
        // Transaction status
        evt.TransactionStatus__c = result.transactionStatus?.name();

        // Session context (user, organization, auth) - uses snapshot for async persistence
        populateSessionContext(evt, ctx.sessionSnapshot);

        // Execution context
        evt.ExecutionContext__c = ctx.sessionSnapshot?.quiddity;
        evt.IsDryRun__c = ctx.isDryRun == true;
        evt.CommitMode__c = result.commitMode?.name();

        // Configuration
        evt.ConfigurationName__c = ctx.configurationName;

        // Async tracking
        evt.ParentTransactionId__c = ctx.parentTransactionId;
        evt.AsyncDepth__c = ctx.asyncDepth;

        // Transaction timing
        evt.StartTime__c = result.startedAt;
        evt.EndTime__c = result.completedAt;
        evt.ExecutionTimeMs__c = result.executionTimeMs;

        // Execution summary
        evt.WorkItemCount__c = workItemCount;
        evt.HasErrors__c = result.hasErrors();
        evt.ErrorCount__c = result.hasErrors() ? result.getErrors().size() : 0;

        // Retention and Archival (from audit plugin settings)
        evt.RetentionDays__c = auditPlugin.getRetentionDays();
        evt.ArchivalMode__c = auditPlugin.getArchivalMode()?.name();
        if (auditPlugin.getRetentionDays() != null) {
            evt.ArchiveDate__c = Date.today().addDays(auditPlugin.getRetentionDays());
        }

        evt.RequiresApproval__c = result.requiresApproval;

        // Agent context
        populateAgentContext(evt, ctx);

        // Scenario and description
        evt.TransactionScenarioName__c = ctx.scenarioName;
        evt.Description__c = evt.CommitMode__c == 'ASYNC' ? '[ASYNC] ' + ctx.description : ctx.description;
        evt.EnableScenarioRecordTracking__c = ctx.getFeatureSettings()?.configuration?.EnableScenarioRecordTracking__c == true;

        // Risk assessment
        populateRiskAssessment(evt, result.riskAssessment);

        // Policy evaluation
        populatePolicyEvaluation(evt, result.policyEvalSummary);
    }

    /**
     * @description Populate work-item-specific fields on an event.
     *              Used by WORK_ITEM events in all modes.
     *              Includes: work item identity, timing, origin, masking, type-specific fields.
     */
    private static void populateWorkItemFields(
        UoWAuditEvent__e evt,
        UoWContext ctx,
        UoWWorkItem workItem,
        UoWMaskingService.MaskingResult maskingResult,
        UoWAuditPlugin auditPlugin
    ) {
        // Work item identifiers
        evt.WorkId__c = workItem.workId;
        evt.Sequence__c = workItem.transactionSequence;
        evt.WorkType__c = workItem.workType?.name();
        evt.WorkItemStatus__c = workItem.status?.name();

        // Timing
        evt.Timestamp__c = DateTime.now();
        evt.RequestedAt__c = workItem.requestedAt;
        evt.StartTime__c = workItem.startTime;
        evt.EndTime__c = workItem.endTime;
        evt.IsExecuted__c = workItem.isExecuted;
        evt.ExecutionTimeMs__c = workItem.executionTimeMs;

        // Request origin
        evt.RequestStackTrace__c = workItem.requestStackTrace;
        evt.RequestOrigin__c = workItem.requestOriginLocation;

        // Capture origin source metadata if enabled
        if (ctx.getFeatureSettings()?.configuration?.EnableOriginSourceMetadata__c == true) {
            UoWOriginSourceService.CaptureResult captureResult = UoWOriginSourceService.captureOriginMetadata(
                workItem.requestClassName,
                workItem.requestOriginLocation,
                workItem.requestOriginType
            );
            if (captureResult != null) {
                evt.OriginMetadataType__c = captureResult.metadataType;
                evt.OriginApiVersion__c = captureResult.apiVersion;
                evt.OriginClassName__c = captureResult.className;
                evt.OriginMethodName__c = captureResult.methodName;
                evt.OriginLineNumber__c = captureResult.lineNumber;
                evt.OriginSnippetStartLine__c = captureResult.snippetStartLine;
                evt.OriginLastModifiedDate__c = captureResult.lastModifiedDate;
                evt.OriginSourceMetadata__c = captureResult.sourceSnippet;
            }
        }

        // Masking information
        if (maskingResult != null) {
            evt.MaskingApplied__c = maskingResult.hasMasking(workItem.workId);
            evt.MaskedFields__c = maskingResult.getMaskedFieldsAsString(workItem.workId);
        }

        // Type-specific fields
        populateTypeSpecificFields(evt, workItem);

        // Governor limits - work item level (before/after)
        populateGovernorLimits(evt, workItem.governorLimits);

        // Error handling
        populateErrorDetails(evt, workItem.errors);
        evt.ContinueOnError__c = workItem.continueOnError;
        if (String.isNotBlank(workItem.errorMessage)) {
            evt.ErrorMessage__c = workItem.errorMessage.left(1000);
        }

        // Snapshot - prepare work item for audit serialization with masking and sampling
        UoWSerializationConfig serializationConfig = getSerializationConfigForWorkItem(ctx, workItem);
        UoWSerializationService.prepareWorkItemForAuditSnapshot(workItem, serializationConfig);
        evt.Snapshot__c = JSON.serialize(workItem);
    }

    // ============================================================================
    // PRIVATE METHODS - TRANSACTION EVENT BUILDING
    // ============================================================================

    private static UoWAuditEvent__e buildTransactionEvent(
        UoWContext ctx,
        UoWResult result,
        Integer operationCount,
        UoWAuditPlugin auditPlugin
    ) {
        UoWAuditEvent__e evt = new UoWAuditEvent__e();

        // Core identifiers
        evt.EventType__c = UoWAuditParameter.EVENT_TYPE_TRANSACTION;
        evt.CorrelationId__c = result.correlationId;
        evt.TransactionId__c = result.transactionId;
        evt.StorageMode__c = auditPlugin.getStorageMode().name();

        // Populate shared transaction context fields
        populateTransactionContextFields(evt, ctx, result, operationCount, auditPlugin);

        // Transaction-event-only fields below (not included in denormalized work items)

        // Timestamp for event itself
        evt.Timestamp__c = DateTime.now();

        // Configuration snapshot (only on transaction event - large JSON)
        UoWFeatureSettings settings = ctx.getFeatureSettings();
        if (settings != null) {
            settings.prepareForSerialization();
        }
        evt.ConfigurationSnapshot__c = JSON.serialize(settings);

        // Custom metadata from result
        Map<String, Object> resultMetadata = result.getMetadata();
        if (resultMetadata != null && !resultMetadata.isEmpty()) {
            evt.CustomMetadata__c = JSON.serialize(resultMetadata);
        }

        // Statistics - scalar fields (only on transaction event)
        populateStatistics(evt, result.statistics);

        // Timeline/tracing (only on transaction event)
        populateTracer(evt, result.tracer);

        // Messages - JSON serialization with warning count (only on transaction event)
        populateMessages(evt, result);

        // Governor limits - JSON for all 3 snapshots (transaction-level)
        populateGovernorLimits(evt, result.governorLimits);

        // Error details - full JSON serialization (transaction-level errors)
        populateErrorDetails(evt, result.getErrors());

        return evt;
    }

    // ============================================================================
    // PRIVATE METHODS - WORK ITEM EVENT BUILDING
    // ============================================================================

    private static UoWAuditEvent__e buildWorkItemEvent(
        UoWContext ctx,
        UoWWorkItem workItem,
        UoWMaskingService.MaskingResult maskingResult,
        UoWAuditPlugin auditPlugin
    ) {
        UoWAuditEvent__e evt = new UoWAuditEvent__e();

        // Core identifiers
        evt.EventType__c = UoWAuditParameter.EVENT_TYPE_WORK_ITEM;
        evt.CorrelationId__c = ctx.correlationId;
        evt.TransactionId__c = ctx.transactionId;
        evt.StorageMode__c = auditPlugin.getStorageMode().name();

        // Populate work item fields using shared method
        populateWorkItemFields(evt, ctx, workItem, maskingResult, auditPlugin);

        return evt;
    }

    /**
     * @description Get serialization configuration for a work item based on its SObject type.
     *              Looks up object settings from context's feature settings.
     * @param ctx The UoW context
     * @param workItem The work item to get config for
     * @return SerializationConfig with masking enabled and sampling from object settings
     */
    private static UoWSerializationConfig getSerializationConfigForWorkItem(
        UoWContext ctx,
        UoWWorkItem workItem
    ) {
        // Get the SObject type name from the work item
        String sobjectTypeName = getSobjectTypeNameFromWorkItem(workItem);

        // If no SObject type (Email, Notification, Flow, Callout), use default audit config
        if (String.isBlank(sobjectTypeName) || ctx == null || ctx.getFeatureSettings() == null) {
            return UoWSerializationConfig.forAudit();
        }

        // Look up object settings
        Map<String, UoWFeatureSettings.ObjectSetting> objectSettings = ctx.getFeatureSettings().objectSettings;
        if (objectSettings == null || !objectSettings.containsKey(sobjectTypeName)) {
            return UoWSerializationConfig.forAudit();
        }

        // Build config from object settings (includes masking + sampling)
        return UoWSerializationConfig.fromObjectSetting(objectSettings.get(sobjectTypeName));
    }

    /**
     * @description Extract SObject type name from work item based on its type.
     * @param workItem The work item
     * @return SObject type API name or null
     */
    private static String getSobjectTypeNameFromWorkItem(UoWWorkItem workItem) {
        if (workItem == null || workItem.workType == null) {
            return null;
        }

        switch on workItem.workType {
            when DML {
                return ((UoWDmlWorkItem) workItem).sobjectTypeName;
            }
            when EVENT {
                return ((UoWEventWorkItem) workItem).sobjectTypeName;
            }
            when else {
                // Email, Notification, Flow, Callout don't have SObject types
                return null;
            }
        }
    }

    // ============================================================================
    // PRIVATE HELPER METHODS - POPULATING EVENT DETAILS
    // ============================================================================

    /**
     * @description Populate session context fields on transaction event.
     *              Uses SessionSnapshot for async persistence - ensures original session
     *              context is preserved through async serialization/deserialization.
     * @param evt The event to populate
     * @param snapshot The session snapshot captured at transaction creation
     */
    private static void populateSessionContext(UoWAuditEvent__e evt, UoWContext.SessionSnapshot snapshot) {
        if (snapshot == null) {
            return;
        }

        // User identity
        evt.UserId__c = snapshot.userId;
        evt.Username__c = snapshot.username;
        evt.UserType__c = snapshot.userType;
        evt.UserProfileId__c = snapshot.profileId;
        evt.UserProfileName__c = snapshot.profileName;
        evt.UserRoleId__c = snapshot.userRoleId;
        evt.UserRoleName__c = snapshot.userRoleName;
        evt.UserLicenseName__c = snapshot.userLicenseName;

        // User preferences
        evt.UserLocale__c = snapshot.locale;
        evt.UserTimeZone__c = snapshot.timeZoneSidKey;

        // Organization
        evt.OrganizationId__c = snapshot.organizationId;
        evt.OrganizationName__c = snapshot.organizationName;
        evt.OrganizationInstanceName__c = snapshot.organizationInstanceName;
        evt.OrganizationIsSandbox__c = snapshot.isSandbox == true;

        // Request context
        evt.RequestId__c = snapshot.requestId;

        // Auth session (stored directly in snapshot, not as nested object)
        evt.LoginType__c = snapshot.loginType;
        evt.SessionType__c = snapshot.sessionType;
        evt.SourceIp__c = snapshot.sourceIp;
        evt.UserIsImpersonated__c = snapshot.isImpersonated == true;
    }

    /**
     * @description Populate agent context fields on transaction event
     * @param evt The event to populate
     * @param ctx The UoW context
     */
    private static void populateAgentContext(UoWAuditEvent__e evt, UoWContext ctx) {
        UoWContext.AgentContext agent = ctx.agentContext;
        if (agent == null) {
            evt.IsAgentTransaction__c = false;
            return;
        }

        evt.IsAgentTransaction__c = agent.isAgentTransaction();
        evt.AgentId__c = agent.agentId;
        evt.AgentName__c = agent.agentName;
        evt.AgentModelId__c = agent.modelId;
        evt.AgentPromptHash__c = agent.promptHash;
        evt.AgentConfidenceScore__c = agent.confidenceScore;
        evt.AgentIntent__c = agent.intent;
        evt.AgentInvokedAt__c = agent.invokedAt;
    }

    /**
     * @description Populate risk assessment fields on event
     * @param evt The event to populate
     * @param riskAssessment The risk assessment from result
     */
    private static void populateRiskAssessment(UoWAuditEvent__e evt, UoWRiskTypes.RiskAssessment riskAssessment) {
        // Set RiskEvaluated__c based on whether risk assessment was performed
        evt.RiskEvaluated__c = (riskAssessment != null);

        if (riskAssessment == null) {
            return;
        }

        evt.RiskScore__c = riskAssessment.riskScore;
        evt.RiskFactors__c = JSON.serialize(riskAssessment.riskFactors);
    }

    /**
     * @description Populate policy evaluation fields on event
     * @param evt The event to populate
     * @param policyEvalSummary The policy evaluation summary from result
     */
    private static void populatePolicyEvaluation(UoWAuditEvent__e evt, UoWPolicyEvaluation.Summary policyEvalSummary) {
        // Set PolicyEvaluated__c based on whether policies were actually evaluated
        // Summary is always created but totalPolicies > 0 indicates actual evaluation occurred
        evt.PolicyEvaluated__c = policyEvalSummary?.totalPolicies > 0;

        if (policyEvalSummary == null) {
            return;
        }

        evt.PolicyCount__c = policyEvalSummary.totalPolicies;
        evt.StrictestAction__c = policyEvalSummary.strictestPolicyAction?.name();
        evt.PolicyEvaluations__c = JSON.serialize(policyEvalSummary.evaluations);
    }

    /**
     * @description Populate statistics fields on event
     * @param evt The event to populate
     * @param statistics The statistics object from result
     */
    private static void populateStatistics(UoWAuditEvent__e evt, UoWStatisticsTracker.TransactionStats statistics) {
        if (statistics == null) {
            return;
        }

        evt.TotalProcessed__c = statistics.getTotalProcessed();
        evt.TotalSucceeded__c = statistics.getTotalSucceeded();
        evt.TotalFailed__c = statistics.getTotalFailed();
        evt.Statistics__c = JSON.serialize(statistics);
    }

    /**
     * @description Populate tracer/timeline fields on event using compact format.
     *              Uses UoWCompactTimeline for size-optimized JSON storage within
     *              Salesforce's 131KB LongTextArea field limit.
     * @param evt The event to populate
     * @param tracer The tracer from result
     */
    private static void populateTracer(UoWAuditEvent__e evt, UoWTracer tracer) {
        if (tracer == null) {
            return;
        }

        UoWTracer.TraceSummary summary = tracer.getSummary();
        if (summary != null) {
            // Use compact format for size optimization (50-60% smaller than full OTel format)
            evt.TraceTimeline__c = UoWCompactTimeline.toCompactJson(summary);
        }
    }

    /**
     * @description Populate messages JSON and warning count on event
     * @param evt The event to populate
     * @param result The UoW result
     */
    private static void populateMessages(UoWAuditEvent__e evt, UoWResult result) {
        List<UoWMessage> messages = result.getMessages();
        if (messages == null || messages.isEmpty()) {
            evt.WarningCount__c = 0;
            return;
        }

        // Count warnings
        Integer warningCount = 0;
        for (UoWMessage msg : messages) {
            if (msg.loggingLevel == System.LoggingLevel.WARN) {
                warningCount++;
            }
        }
        evt.WarningCount__c = warningCount;

        // Serialize messages
        evt.Messages__c = JSON.serialize(messages);
    }

    /**
     * @description Populate governor limits fields on event for transaction-level.
     *              Includes max limits (only captured at result level).
     * @param evt The event to populate
     * @param limits Result governor limits container with start, finish, and max
     */
    private static void populateGovernorLimits(UoWAuditEvent__e evt, UoWResult.GovernorLimits limits) {
        if (limits == null) {
            return;
        }

        if (limits.start != null) {
            evt.LimitsAtStart__c = JSON.serialize(limits.start);
        }

        if (limits.finish != null) {
            evt.LimitsAtEnd__c = JSON.serialize(limits.finish);
        }

        if (limits.max != null) {
            evt.LimitsMax__c = JSON.serialize(limits.max);
        }

        // Calculate consumed if both snapshots available
        UoWGovernorLimits consumed = limits.getConsumed();
        if (consumed != null) {
            evt.LimitsTotalConsumed__c = JSON.serialize(consumed);
        }
    }

    /**
     * @description Populate governor limits fields on event for work item-level.
     *              Used for work items which have before/after snapshots.
     * @param evt The event to populate
     * @param limits Work item governor limits container with before and after
     */
    private static void populateGovernorLimits(UoWAuditEvent__e evt, UoWWorkItem.GovernorLimits limits) {
        if (limits == null) {
            return;
        }

        if (limits.before != null) {
            evt.LimitsAtStart__c = JSON.serialize(limits.before);
        }

        if (limits.after != null) {
            evt.LimitsAtEnd__c = JSON.serialize(limits.after);
        }

        // Calculate consumed if both snapshots available
        if (limits.before != null && limits.after != null) {
            UoWGovernorLimits consumed = UoWGovernorLimits.getConsumed(limits.before, limits.after);
            if (consumed != null) {
                evt.LimitsConsumed__c = JSON.serialize(consumed);
            }
        }
    }

    // ============================================================================
    // PRIVATE HELPER METHODS - TYPE SPECIFIC
    // ============================================================================

    /**
     * @description Populate type-specific fields based on work item type
     * @param evt The event to populate
     * @param workItem The work item
     */
    private static void populateTypeSpecificFields(UoWAuditEvent__e evt, UoWWorkItem workItem) {
        if (workItem.workType == null) {
            return;
        }

        // Use pre-calculated statistics from workItem.processResults()
        // These are set by processResults() after execution (single-pass through results)
        evt.PlannedCount__c = workItem.statistics.planned;
        evt.ProcessedCount__c = workItem.statistics.processed;
        evt.SuccessCount__c = workItem.statistics.successes;
        evt.FailureCount__c = workItem.statistics.failures;

        // Type-specific fields
        switch on workItem.workType {
            when DML {
                populateDmlFields(evt, (UoWDmlWorkItem) workItem);
            }
            when EVENT {
                populateEventFields(evt, (UoWEventWorkItem) workItem);
            }
            when EMAIL {
                populateEmailFields(evt, (UoWEmailWorkItem) workItem);
            }
            when NOTIFICATION {
                populateNotificationFields(evt, (UoWNotificationWorkItem) workItem);
            }
            when FLOW {
                populateFlowFields(evt, (UoWFlowWorkItem) workItem);
            }
            when CALLOUT {
                populateCalloutFields(evt, (UoWCalloutWorkItem) workItem);
            }
        }
    }

    /**
     * @description Populate DML-specific fields
     */
    private static void populateDmlFields(UoWAuditEvent__e evt, UoWDmlWorkItem dml) {
        evt.SObjectType__c = dml.sobjectTypeName;
        evt.DmlOperation__c = dml.operation?.name();

        // Upsert-specific statistics
        if (dml.operation == UoWEnums.DmlOperation.UPSERT_OP &&
            dml.statistics instanceof UoWDmlWorkItem.UpsertStatistics) {
            UoWDmlWorkItem.UpsertStatistics upsertStats = (UoWDmlWorkItem.UpsertStatistics) dml.statistics;
            evt.UpsertCreatedCount__c = upsertStats.inserts;
            evt.UpsertUpdatedCount__c = upsertStats.updates;
        }
    }

    /**
     * @description Populate Event-specific fields
     */
    private static void populateEventFields(UoWAuditEvent__e evt, UoWEventWorkItem eventItem) {
        evt.SObjectType__c = eventItem.sobjectTypeName;
        evt.ExecutionPhase__c = eventItem.executionPhase?.name();
    }

    /**
     * @description Populate Email-specific fields
     */
    private static void populateEmailFields(UoWAuditEvent__e evt, UoWEmailWorkItem email) {
        evt.ExecutionPhase__c = email.executionPhase?.name();

        // Email recipients - aggregate from all emails
        List<Map<String, Object>> recipientsList = new List<Map<String, Object>>();
        List<Messaging.Email> emails = email.getEmails();
        if (emails != null) {
            for (Messaging.Email mailMsg : emails) {
                if (mailMsg instanceof Messaging.SingleEmailMessage) {
                    Messaging.SingleEmailMessage sem = (Messaging.SingleEmailMessage) mailMsg;
                    Map<String, Object> recipients = new Map<String, Object>();
                    recipients.put('to', sem.getToAddresses());
                    recipients.put('cc', sem.getCcAddresses());
                    recipients.put('bcc', sem.getBccAddresses());
                    recipientsList.add(recipients);
                }
            }
        }
        if (!recipientsList.isEmpty()) {
            evt.EmailRecipients__c = JSON.serialize(recipientsList);
        }
    }

    /**
     * @description Populate Notification-specific fields
     */
    private static void populateNotificationFields(UoWAuditEvent__e evt, UoWNotificationWorkItem notif) {
        evt.ExecutionPhase__c = notif.executionPhase?.name();
        evt.NotificationType__c = notif.customNotifTypeName;

        // Notification recipients
        if (notif.recipientIds != null && !notif.recipientIds.isEmpty()) {
            evt.NotificationRecipients__c = JSON.serialize(notif.recipientIds);
        }
    }

    /**
     * @description Populate Flow-specific fields
     */
    private static void populateFlowFields(UoWAuditEvent__e evt, UoWFlowWorkItem flow) {
        evt.ExecutionPhase__c = flow.executionPhase?.name();
        evt.FlowApiName__c = flow.flowApiName;

        // Flow inputs
        if (flow.flowInputs != null && !flow.flowInputs.isEmpty()) {
            evt.FlowInputs__c = JSON.serialize(flow.flowInputs);
        }

        // Flow outputs
        if (flow.flowOutputs != null && !flow.flowOutputs.isEmpty()) {
            evt.FlowOutputs__c = JSON.serialize(flow.flowOutputs);
        }
    }

    /**
     * @description Populate Callout-specific fields
     */
    private static void populateCalloutFields(UoWAuditEvent__e evt, UoWCalloutWorkItem callout) {
        evt.ExecutionPhase__c = callout.executionPhase?.name();
        evt.Endpoint__c = callout.endpoint?.left(500);
        evt.HttpMethod__c = callout.httpMethod;

        if (callout.response != null) {
            evt.ResponseStatusCode__c = callout.response.getStatusCode();
            // Response body
            evt.CalloutResponseBody__c = callout.response.getBody();
        }

        // Request body
        evt.CalloutRequestBody__c = callout.requestBody;

        // Retry configuration
        if (callout.retryConfig != null) {
            evt.CalloutRetryConfig__c = JSON.serialize(callout.retryConfig);
        }
    }

    // ============================================================================
    // PRIVATE HELPER METHODS - ERROR DETAILS
    // ============================================================================

    /**
     * @description Populate error details JSON on event
     * @param evt The event to populate
     * @param errors The list of errors
     */
    private static void populateErrorDetails(UoWAuditEvent__e evt, List<UoWExceptionService.ErrorInfo> errors) {
        if (errors == null || errors.isEmpty()) {
            return;
        }

        // Serialize full error details
        evt.ErrorDetails__c = JSON.serialize(errors);
        evt.HasErrors__c = errors.size() > 0;
        evt.ErrorCount__c = errors.size();

        // Extract first stack trace if available
        for (UoWExceptionService.ErrorInfo error : errors) {
            if (String.isNotBlank(error.stackTrace)) {
                evt.ErrorStackTrace__c = error.stackTrace;
                break;
            }
        }
    }

    // ============================================================================
    // INNER CLASSES - RESULT TYPES
    // ============================================================================

    /**
     * @description Result of publish operation
     */
    public class PublishResult {
        public Boolean isSuccess = false;
        public Boolean transactionEventBuilt = false;
        public Integer workItemEventsBuilt = 0;
        public Integer successCount = 0;
        public Integer failureCount = 0;
        public List<PublishError> errors = new List<PublishError>();

        /**
         * @description Get total events attempted
         * @return Total count
         */
        public Integer getTotalEventsAttempted() {
            return (transactionEventBuilt ? 1 : 0) + workItemEventsBuilt;
        }
    }

    /**
     * @description Error during publish operation
     */
    public class PublishError {
        public String eventIdentifier;
        public String errorCode;
        public String errorMessage;

        public PublishError(String eventIdentifier, String errorCode, String errorMessage) {
            this.eventIdentifier = eventIdentifier;
            this.errorCode = errorCode;
            this.errorMessage = errorMessage;
        }
    }

}