//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Flow invocable action to commit a Unit of Work transaction.
 *
 * This is the final action in the Flow UoW pattern. It retrieves the UnitOfWork instance
 * by transaction ID, executes all registered work items, and returns detailed statistics
 * and error information.
 *
 * Flow Pattern:
 * 1. Initialize Transaction → transactionId
 * 2. Register work items (using transactionId)
 * 3. Commit Transaction (using transactionId) → statistics, errors, correlation ID
 *
 * Example Basic Flow usage:
 * [Commit Transaction]
 *   Transaction ID: {!transactionId}
 *   Commit Mode: SYNC
 *   ↓ outputs: success, correlationId, dmlInserts, dmlUpdates, etc.
 * [Decision: {!success} = true?]
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Flow Actions
 * @see UoWFlowInitializeAction
 * @see UoWFlowTransactionRegistry
 */
public inherited sharing class UoWFlowCommitAction {
    // ============================================================================
    // INVOCABLE METHOD
    // ============================================================================

    /**
     * Commit a Unit of Work transaction
     *
     * @param requests List of commit requests (Flow passes single-item list)
     * @return List of commit results with statistics and errors
     */
    @InvocableMethod(
        label='UoW: Commit Transaction'
        description='Execute all registered work items in the Unit of Work transaction'
        category='Unit of Work'
    )
    public static List<CommitResult> commitTransaction(List<CommitRequest> requests) {
        List<CommitResult> results = new List<CommitResult>();

        for (CommitRequest request : requests) {
            CommitResult result = new CommitResult();

            try {
                // Validate transaction ID
                UoWExceptionService.requireNonBlank(request.transactionId, 'Transaction ID');

                // Retrieve UnitOfWork instance
                UnitOfWork uow = UoWFlowTransactionRegistry.get(request.transactionId);

                // Parse commit mode
                UoWEnums.CommitMode mode = UoWFlowActionHelpers.parseCommitMode(request.commitMode);

                // Execute transaction
                UoWResult uowResult = (mode != null) ? uow.commitWork(mode) : uow.commitWork();

                // Map result to Flow output
                result.success = uowResult.isSuccess();
                result.correlationId = uowResult.correlationId;
                result.transactionStatus = uowResult.transactionStatus.name();
                result.executionTimeMs = uowResult.statistics.executionTimeMs;

                // Statistics
                result.totalRecordsProcessed = uowResult.statistics.dmlStats.records.processed;
                result.dmlInserts = uowResult.statistics.dmlStats.inserts.records.successes;
                result.dmlUpdates = uowResult.statistics.dmlStats.updates.records.successes;
                result.dmlDeletes = uowResult.statistics.dmlStats.deletes.records.successes;
                result.dmlErrors = uowResult.statistics.dmlStats.records.errors;
                result.eventsPublished = uowResult.statistics.eventStats.events.published;
                result.emailsSent = uowResult.statistics.emailStats.emails.sent;
                result.notificationsSent = uowResult.statistics.notificationStats.notifications.sent;
                result.flowsExecuted = uowResult.statistics.flowStats.flows.executed;
                result.calloutsMade = uowResult.statistics.calloutStats.callouts.executed;

                // Errors
                result.hasErrors = uowResult.hasErrors();
                if (uowResult.hasErrors()) {
                    result.errorDetailsJson = JSON.serialize(uowResult.getErrors());
                    result.errorSummary = UoWFlowActionHelpers.generateErrorSummary(uowResult);
                }

                // Messages - Filter to only ERROR and WARN (INFO/DEBUG would bloat Flow variables)
                List<UoWMessage> errorMessages = new List<UoWMessage>();
                List<UoWMessage> warningMessages = new List<UoWMessage>();
                for (UoWMessage msg : uowResult.getMessages()) {
                    if (msg.loggingLevel == System.LoggingLevel.ERROR) {
                        errorMessages.add(msg);
                    } else if (msg.loggingLevel == System.LoggingLevel.WARN) {
                        warningMessages.add(msg);
                    }
                }
                result.errorMessagesJson = errorMessages.isEmpty() ? null : JSON.serialize(errorMessages);
                result.warningMessagesJson = warningMessages.isEmpty() ? null : JSON.serialize(warningMessages);

                // Policy Evaluation Summary
                if (uowResult.policyEvalSummary != null) {
                    result.policyEvaluationJson = JSON.serialize(uowResult.policyEvalSummary);
                    result.policyAction = uowResult.policyEvalSummary.strictestPolicyAction?.name();
                }

                // Risk Assessment
                if (uowResult.riskAssessment != null) {
                    result.riskAssessmentJson = JSON.serialize(uowResult.riskAssessment);
                    result.riskLevel = uowResult.riskAssessment.riskLevel?.name();
                    result.riskScore = uowResult.riskAssessment.riskScore;
                }

                // Cleanup registry
                UoWFlowTransactionRegistry.remove(request.transactionId);
                UoWFlowDmlWorkItemRegistry.clearAll();

            } catch (Exception ex) {
                result.success = false;
                result.errorSummary = UoWFlowActionHelpers.formatException(ex);
            }

            results.add(result);
        }

        return results;
    }

    // ============================================================================
    // INNER CLASSES - REQUEST/RESPONSE
    // ============================================================================

    /**
     * Input parameters for transaction commit
     */
    public class CommitRequest {
        @InvocableVariable(
            label='Transaction ID'
            description='Transaction ID from Initialize Transaction action'
            required=true
        )
        public String transactionId;

        @InvocableVariable(
            label='Commit Mode'
            description='Execution mode: SYNC (default), ASYNC'
        )
        public String commitMode;
    }

    /**
     * Output results from transaction commit
     */
    public class CommitResult {
        @InvocableVariable(
            label='Success'
            description='True if transaction completed successfully (check Transaction Status for details)'
        )
        public Boolean success;

        @InvocableVariable(
            label='Correlation ID'
            description='Unique correlation ID for this transaction execution'
        )
        public String correlationId;

        @InvocableVariable(
            label='Transaction Status'
            description='Final status: SUCCESS, PARTIAL_SUCCESS, FAILED, ROLLED_BACK, DENIED_BY_POLICY, etc.'
        )
        public String transactionStatus;

        @InvocableVariable(
            label='Execution Time (ms)'
            description='Total execution time in milliseconds'
        )
        public Long executionTimeMs;

        // ========================================================================
        // STATISTICS
        // ========================================================================

        @InvocableVariable(
            label='Total Records Processed'
            description='Total DML records attempted (inserts + updates + deletes + upserts + undeletes)'
        )
        public Integer totalRecordsProcessed;

        @InvocableVariable(
            label='DML Inserts'
            description='Number of successful insert operations'
        )
        public Integer dmlInserts;

        @InvocableVariable(
            label='DML Updates'
            description='Number of successful update operations'
        )
        public Integer dmlUpdates;

        @InvocableVariable(
            label='DML Deletes'
            description='Number of successful delete operations'
        )
        public Integer dmlDeletes;

        @InvocableVariable(
            label='DML Errors'
            description='Number of failed DML operations'
        )
        public Integer dmlErrors;

        @InvocableVariable(
            label='Events Published'
            description='Number of platform events published'
        )
        public Integer eventsPublished;

        @InvocableVariable(
            label='Emails Sent'
            description='Number of emails sent'
        )
        public Integer emailsSent;

        @InvocableVariable(
            label='Notifications Sent'
            description='Number of custom notifications sent'
        )
        public Integer notificationsSent;

        @InvocableVariable(
            label='Flows Executed'
            description='Number of flows executed'
        )
        public Integer flowsExecuted;

        @InvocableVariable(
            label='Callouts Made'
            description='Number of HTTP callouts made'
        )
        public Integer calloutsMade;

        // ========================================================================
        // ERRORS & MESSAGES
        // ========================================================================

        @InvocableVariable(
            label='Has Errors'
            description='True if any errors occurred during execution'
        )
        public Boolean hasErrors;

        @InvocableVariable(
            label='Error Details (JSON)'
            description='JSON array of detailed error objects (for parsing in Flow)'
        )
        public String errorDetailsJson;

        @InvocableVariable(
            label='Error Messages (JSON)'
            description='JSON array of ERROR-level messages only (filtered to prevent bloat)'
        )
        public String errorMessagesJson;

        @InvocableVariable(
            label='Warning Messages (JSON)'
            description='JSON array of WARN-level messages only (filtered to prevent bloat)'
        )
        public String warningMessagesJson;

        @InvocableVariable(
            label='Error Summary'
            description='User-friendly summary of errors for display/logging'
        )
        public String errorSummary;

        // ========================================================================
        // POLICY & RISK ASSESSMENT
        // ========================================================================

        @InvocableVariable(
            label='Policy Evaluation (JSON)'
            description='JSON object with policy evaluation summary (action, policies evaluated, etc.)'
        )
        public String policyEvaluationJson;

        @InvocableVariable(
            label='Policy Action'
            description='Strictest policy action: ALLOW, REQUIRE_APPROVAL, REQUIRE_TRACING, REQUIRE_MASKING, DENY'
        )
        public String policyAction;

        @InvocableVariable(
            label='Risk Assessment (JSON)'
            description='JSON object with risk assessment details'
        )
        public String riskAssessmentJson;

        @InvocableVariable(
            label='Risk Level'
            description='Transaction risk level: LOW, MEDIUM, HIGH, CRITICAL'
        )
        public String riskLevel;

        @InvocableVariable(
            label='Risk Score'
            description='Numeric risk score (0.0 to 1.0)'
        )
        public Decimal riskScore;
    }
}