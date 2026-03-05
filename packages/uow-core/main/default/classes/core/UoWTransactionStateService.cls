//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Transaction State Service - Centralized state machine for UoW execution.
 *
 * Responsibilities:
 * 1. State Machine - TransactionPhase enum with valid transitions
 * 2. Phase Coordination - Orchestrate execution phases (policy, risk, execution, finalization)
 * 3. Decision Tracking - Record why masking/tracing/approval required
 * 4. Savepoint Lifecycle - Manage savepoint creation (respects Salesforce callout limitation)
 * 5. Audit Trail - Record all transitions with timestamps and rationale
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Core
 * @see UnitOfWork
 * @see UoWResult
 */
public inherited sharing class UoWTransactionStateService {

    // ============================================================================
    // PRIVATE FIELDS - STATE
    // ============================================================================

    private UoWEnums.OrchestratorPhase currentPhase;
    private List<PhaseTransition> transitionHistory;
    private DateTime transactionStartedAt;

    // References (injected at begin)
    private UoWContext context;
    private UoWPlan plan;
    private UoWResult result;

    // Decision tracking
    private Boolean maskingRequired;
    private Boolean tracingRequired;
    private Boolean approvalRequired;
    private Boolean savepointCreated;

    // Completion path tracking (for finally block finalization)
    private UoWEnums.TransactionCompletionPath completionPath;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    public UoWTransactionStateService() {
        this.transitionHistory = new List<PhaseTransition>();
        this.currentPhase = UoWEnums.OrchestratorPhase.NOT_STARTED;
        this.maskingRequired = false;
        this.tracingRequired = false;
        this.approvalRequired = false;
        this.savepointCreated = false;
        this.completionPath = UoWEnums.TransactionCompletionPath.FULL_EXECUTION;  // Default
    }

    // ============================================================================
    // PUBLIC API - LIFECYCLE
    // ============================================================================

    /**
     * Begin transaction - Initialize state machine.
     *
     * @param ctx The execution context
     * @param plan The work plan
     * @param result The result object
     */
    public void beginTransaction(UoWContext ctx, UoWPlan plan, UoWResult result) {
        this.context = ctx;
        this.plan = plan;
        this.result = result;
        this.result.setStartTime();

        // Start transaction span
        result.startSpan(UoWEnums.SpanPhase.TRANSACT, 'Transaction initiated');

        // Set ambient context for triggers/flows executing in this transaction
        UoWTransactionState.setCurrent(new UoWTransactionState(ctx));

        transitionTo(UoWEnums.OrchestratorPhase.STARTED, 'Transaction initialized');
    }

    /**
     * Prepare empty plan transaction - Sets completion path for finally block.
     * Called directly from UnitOfWork when plan.isEmpty() is detected
     */
    public void prepareEmptyPlanTransaction() {
        this.completionPath = UoWEnums.TransactionCompletionPath.EMPTY_PLAN;
        result.info('No work items in plan - transaction skipped', 'UoWTransactionStateService');
        result.addTraceEvent('No work items in plan - transaction skipped');
        result.setTransactionStatus(UoWEnums.TransactionStatus.SKIPPED);

        // DECISION: No policies evaluated for empty plan, fall back to config
        decideTraceCommitment();
    }

    /**
     * Enqueue transaction for asynchronous execution.
     * Sets completion path for finally block to handle finalization.
     * Uses Salesforce AsyncOptions to manage queueable stack depth.
     *
     * @return Partial result with async metadata
     */
    public void enqueueAsync() {
        this.completionPath = UoWEnums.TransactionCompletionPath.ASYNC_ENQUEUED;

        UoWTracer.Span enqueueExec = result.startSpan(UoWEnums.SpanPhase.ASYNC_QUEUED, 'Enqueuing transaction for asynchronous execution');

        // Set parent transaction tracking for async child
        context.parentTransactionId = result.correlationId;

        // Enqueue the queueable job with AsyncOptions for stack depth management
        UoWQueueable asyncJob = new UoWQueueable(context, plan);

        // Use AsyncOptions to let Salesforce manage queueable stack depth
        // This is the proper way to handle chained queueables - platform enforces the limit
        AsyncOptions asyncOptions = new AsyncOptions();
        asyncOptions.MaximumQueueableStackDepth = context.getFeatureSettings().getMaxAsyncDepth();

        Id jobId = System.enqueueJob(asyncJob, asyncOptions);

        // Set result metadata
        result.info('Transaction enqueued for asynchronous execution. Job ID: ' + jobId + ', Parent: ' + context.parentTransactionId);
        result.setMetadata('asyncJobId', jobId);
        result.setMetadata('maxQueueableStackDepth', String.valueOf(context.getFeatureSettings().getMaxAsyncDepth()));
        result.setTransactionStatus(UoWEnums.TransactionStatus.ENQUEUED);

        // End span and return
        result.endSpan(enqueueExec, UoWEnums.SpanPhaseResult.SUCCESS,
            'Transaction enqueued for asynchronous execution. Job ID: ' + jobId);

        // DECISION: No policies evaluated for async enqueue, fall back to config
        decideTraceCommitment();
    }

    /**
     * Evaluate policies - Execute policy evaluation and process results.
     * Replaces: Lines 631-640 + 853-871 in UnitOfWork.commitWork()
     */
    public void evaluatePolicies() {
        // Start tracing span for policy evaluation
        UoWTracer.Span policyEvaluationSpan = result.startSpan(UoWEnums.SpanPhase.POLICY_EVALUATION, 'Evaluating policies');

        transitionTo(UoWEnums.OrchestratorPhase.POLICY_EVALUATION, 'Evaluating policies');

        // Execute policy evaluation
        UoWPolicyEvaluation.Summary evalSummary = UoWPolicyEvaluation.evaluateAll(context, plan, result);
        result.setPolicyEvaluationSummary(evalSummary);

        // Policy denial check (Line 663-669)
        if (evalSummary.isDenied) {
            result.setTransactionStatus(UoWEnums.TransactionStatus.DENIED_BY_POLICY);
            String denyReason = !evalSummary.denialReasons.isEmpty() ?
                evalSummary.denialReasons[0] : 'Policy denied transaction';
            addDecision('Policy denial detected', denyReason);
            result.endSpan(policyEvaluationSpan, UoWEnums.SpanPhaseResult.FAILED,
                'DENIED: ' + denyReason);
            throw new UoWExceptionService.UoWException('Policy denied: ' + denyReason);
        }

        // Check if policies require justification (ALLOW_WITH_JUSTIFICATION)
        Integer justificationCount = evalSummary.policyActionCounts.get(UoWEnums.PolicyAction.ALLOW_WITH_JUSTIFICATION);
        if (justificationCount != null && justificationCount > 0) {
            // Log warning for justification requirement
            for (UoWPolicyEvaluation.Evaluation eval : evalSummary.evaluations) {
                if (eval.action == UoWEnums.PolicyAction.ALLOW_WITH_JUSTIFICATION) {
                    result.warn(
                        'Policy ' + eval.policyName + ' requires justification: ' + eval.reason,
                        'UnitOfWork'
                    );
                }
            }
        }

        // Control policy actions
        if (evalSummary.requiresMasking) {
            this.maskingRequired = true;
            context.getFeatureSettings().enableMasking();
            addDecision('Masking required by policy', 'Policy requires data masking');
        }

        if (evalSummary.requiresTracing) {
            this.tracingRequired = true;
            context.getFeatureSettings().enableTracing();
            addDecision('Tracing required by policy', 'Policy requires execution tracing');
        }

        if (evalSummary.requiresApproval) {
            this.approvalRequired = true;
            // Note: Approval is tracked in context, not result
            addDecision('Approval required by policy', 'Policy requires approval before execution');
        }

        // Determine phase result and end span
        UoWEnums.SpanPhaseResult phaseResult = evalSummary.totalPolicies == 0 ?
            UoWEnums.SpanPhaseResult.NOT_APPLICABLE : UoWEnums.SpanPhaseResult.SUCCESS;
        String resultLabel = evalSummary.isDenied ? 'DENIED' :
                              (evalSummary.totalPolicies == 0 ? 'NOT_APPLICABLE' : 'APPROVED');

        result.endSpan(policyEvaluationSpan, phaseResult, String.format('Evaluated {0} policies - Result: {1}',
            new String[]{ String.valueOf(evalSummary.totalPolicies), resultLabel }));
    }

    /**
     * Process control policy actions (REQUIRE_TRACING, REQUIRE_MASKING).
     * Called AFTER policy evaluation to enable features based on policy decisions
     */
    public void processControlPolicyActions() {
        //DO NOT check approval here - since approval can be requested by either policy evaluation
        //or risk assessment - we will check for approval flag AFTER we assess risk

        // Apply masking if enabled
        if (context.getFeatureSettings().getEnableMasking()) {
            UoWMaskingService.MaskingResult maskingResult = UoWMaskingService.applyMaskingToWorkItems(
                plan,
                result
            );

            if (!maskingResult.isEmpty()) {
                result.info(String.format('Applied masking to {0} work items', new String[]{ String.valueOf(maskingResult.getWorkItemCount()) }));
            }
        }

        // Decide trace commitment
        decideTraceCommitment();
    }

    /**
     * Assess risk - Execute risk assessment and check threshold.
     * Replaces: Lines 642-661 in UnitOfWork.commitWork()
     */
    public void assessRisk() {
        // Start tracing span for risk assessment
        UoWTracer.Span riskAssessmentSpan = result.startSpan(
            UoWEnums.SpanPhase.RISK_ASSESSMENT,
            'Assessing transaction risk'
        );

        transitionTo(UoWEnums.OrchestratorPhase.RISK_ASSESSMENT, 'Assessing risk');

        // Resolve risk assessor (2-tier priority: runtime > metadata, returns null if not configured)
        UoWInterfaces.IRiskAssessor riskAssessor = UoWRiskAssessorResolver.resolve(context, result);

        // Risk assessment is OPTIONAL - skip if no assessor configured
        if (riskAssessor == null) {
            result.endSpan(riskAssessmentSpan, UoWEnums.SpanPhaseResult.NOT_APPLICABLE,
                'Risk assessment - Result: NOT_APPLICABLE (no assessor configured)');
            return;
        }

        // Execute risk assessment
        UoWRiskTypes.RiskAssessment riskAssessment = riskAssessor.assessRisk(context, plan);
        result.setRiskAssessment(riskAssessment);

        // Add trace events for risk factors
        for (UoWRiskTypes.RiskFactor factor : riskAssessment.riskFactors) {
            result.addTraceEvent(String.format('[RISK FACTOR] {0} (+{1})',
                new String[]{ factor.reason, String.valueOf(factor.score) }));
        }

        // Risk threshold check
        if (riskAssessment.riskScore >= context.getFeatureSettings().getRiskBlockThreshold()) {
            String reason = String.format('Risk score ({0}) exceeds threshold ({1})',
                new String[]{ String.valueOf(riskAssessment.riskScore),
                             String.valueOf(context.getFeatureSettings().getRiskBlockThreshold()) });
            addDecision('Risk threshold exceeded', reason);
            result.endSpan(riskAssessmentSpan, UoWEnums.SpanPhaseResult.FAILED,
                'BLOCKED: ' + reason);
            throw new UoWExceptionService.UoWException(reason);
        }

        // End tracing span with result
        result.endSpan(riskAssessmentSpan, UoWEnums.SpanPhaseResult.SUCCESS,
            String.format('Risk score: {0} - Level: {1}',
                new String[]{ String.valueOf(riskAssessment.riskScore), String.valueOf(riskAssessment.riskLevel) }));
    }

    /**
     * Request approval and pause execution.
     * Sets completion path for finally block to handle finalization.
     * Resolves approval channel from resolver and delegates full lifecycle.
     * Approval is triggered by policies (PolicyAction.REQUIRE_APPROVAL) or risk assessment.
     *
     * @return Partial result indicating approval was requested
     */
    public UoWResult requestApproval() {
        this.completionPath = UoWEnums.TransactionCompletionPath.APPROVAL_DEFERRED;

        if(context.isDryRun){
            return result;
        }

        UoWTracer.Span approvalExec = result.startSpan(UoWEnums.SpanPhase.APPROVAL_REQUEST, 'Requesting approval for transaction');

        // Resolve approval channel from resolver
        UoWInterfaces.IApprovalChannel approvalChannel = UoWApprovalChannelResolver.resolve(context, result);

        if (approvalChannel != null) {
            // Delegate to registered approval channel
            context.info('Approval required - delegating to channel: ' + approvalChannel.getName(), 'UoWTransactionStateService');

            // Approval channel controls full lifecycle (creates record, sends notification, returns partial result)
            UoWResult approvalResult = approvalChannel.requestApproval(context, plan, result);

            // End span AFTER channel completes
            result.endSpan(approvalExec, UoWEnums.SpanPhaseResult.SUCCESS,
                'Approval delegated to channel: ' + approvalChannel.getName());

            return approvalResult;

        } else {
            // No approval channel registered - throw helpful error
            result.endSpan(approvalExec, UoWEnums.SpanPhaseResult.FAILED,
                'Approval required but no channel registered');

            throw new UoWExceptionService.UoWException(
                'Approval required but no approval channel is registered. ' +
                'Register an approval channel via:\n' +
                '1. Runtime API: uow.withApprovalChannel(channel)\n' +
                '2. Metadata: Set ApprovalChannelClassName__c in UoWConfiguration__mdt\n' +
                '3. Install UoW Extensions package for Salesforce native approval workflows.'
            );
        }
    }

    /**
     * Execute onBeforeCommit plugins.
     * Replaces: Lines 676-679 in UnitOfWork.commitWork()
     */
    public void executeBeforeCommit() {
        // Start tracing span
        UoWTracer.Span pluginsBeforeCommitSpan = result.startSpan(
            UoWEnums.SpanPhase.PLUGINS_BEFORE_COMMIT,
            'onBeforeCommit plugins'
        );

        transitionTo(UoWEnums.OrchestratorPhase.BEFORE_COMMIT, 'Executing onBeforeCommit plugins');

        try {
            Integer executedCount = UoWPluginExecutor.executeBeforeCommit(context, plan, result);
            result.endSpan(pluginsBeforeCommitSpan,
                getPhaseResultFromCount(executedCount),
                getPluginSpanResultMessage(executedCount));
        } catch (Exception ex) {
            addDecision('onBeforeCommit plugin failed', ex.getMessage());
            result.endSpan(pluginsBeforeCommitSpan, UoWEnums.SpanPhaseResult.FAILED,
                String.format(System.Label.UoW_Span_PluginsFailed, new String[]{ ex.getMessage() }));
            throw ex;
        }
    }

    /**
     * Execute PRE_DML callouts phase.
     * IMPORTANT: PRE_DML callouts execute BEFORE savepoint (Salesforce limitation)
     * Cannot make callouts after Database.setSavepoint()
     *
     * ON_FAILURE callouts are executed separately in handleException() after
     * rollback + savepoint release.
     */
    public void executePreDmlCallouts() {
        if (!plan.hasCalloutsForPhase(UoWEnums.WorkPhase.PRE_DML)) {
            return; // Skip if no PRE_DML callouts
        }

        transitionTo(UoWEnums.OrchestratorPhase.CALLOUTS, 'Executing PRE_DML HTTP callouts');

        try {
            new UoWCalloutExecutionService(context, plan, result).execute(UoWEnums.WorkPhase.PRE_DML);
        } catch (Exception ex) {
            addDecision('PRE_DML callout execution failed', ex.getMessage());
            throw ex;
        }
    }

    /**
     * Create savepoint - Explicit savepoint lifecycle management.
     * IMPORTANT: Created AFTER PRE_DML callouts but BEFORE DML (Salesforce limitation)
     * Savepoints are ALWAYS created (except in dry-run mode) to enable:
     * - Transaction atomicity (rollback on failure)
     * - ON_FAILURE callouts (require savepoint release after rollback)
     * Replaces: UoWContext.setSavepoint() + implicit tracking
     */
    public void createSavepoint() {
        transitionTo(UoWEnums.OrchestratorPhase.SAVEPOINT_CREATION, 'Creating transaction savepoint');

        UoWTracer.Span savepointSpan = result.startSpan(
            UoWEnums.SpanPhase.SAVEPOINT,
            'Transaction savepoint'
        );

        if (!context.isDryRun) {
            context.setSavepoint();
            this.savepointCreated = true;
            addDecision('Savepoint created', 'Transaction rollback and ON_FAILURE callouts enabled');
            result.endSpan(savepointSpan, UoWEnums.SpanPhaseResult.SUCCESS, 'Transaction savepoint created');
        } else {
            addDecision('Savepoint skipped', 'Dry run mode');
            result.endSpan(savepointSpan, UoWEnums.SpanPhaseResult.NOT_APPLICABLE, 'Savepoint skipped (dry run mode)');
        }
    }

    /**
     * Execute main transaction phase.
     * PRE_DML → DML → POST_DML → ON_SUCCESS
     * Note: No wrapper span - individual phase spans are top-level
     * Replaces: Lines 704-716 in UnitOfWork.commitWork()
     */
    public void executeTransaction() {
        transitionTo(UoWEnums.OrchestratorPhase.EXECUTING, 'Executing transaction');

        // Execute PRE_DML phase (events, emails, notifications, flows)
        executeWorkTypesForPhase(UoWEnums.WorkPhase.PRE_DML);

        // Execute DML operations
        if (plan.hasDmlWork()) {
            new UoWDmlExecutionService(context, plan, result).execute(null);
        }

        // Execute POST_DML phase (events, emails, notifications, flows)
        executeWorkTypesForPhase(UoWEnums.WorkPhase.POST_DML);

        // Execute ON_SUCCESS phase (events, emails, notifications, flows)
        executeWorkTypesForPhase(UoWEnums.WorkPhase.ON_SUCCESS);
    }

    /**
     * Execute onAfterCommit plugins.
     * Replaces: Line 715 in UnitOfWork.commitWork()
     */
    public void executeAfterCommit() {
        // Start tracing span
        UoWTracer.Span pluginsAfterCommitSpan = result.startSpan(
            UoWEnums.SpanPhase.PLUGINS_AFTER_COMMIT,
            'onAfterCommit plugins'
        );

        transitionTo(UoWEnums.OrchestratorPhase.AFTER_COMMIT, 'Executing onAfterCommit plugins');

        try {
            Integer executedCount = UoWPluginExecutor.executeAfterCommit(context, result);
            result.endSpan(pluginsAfterCommitSpan,
                getPhaseResultFromCount(executedCount),
                getPluginSpanResultMessage(executedCount));
        } catch (Exception ex) {
            addDecision('onAfterCommit plugin failed', ex.getMessage());
            result.endSpan(pluginsAfterCommitSpan, UoWEnums.SpanPhaseResult.FAILED,
                String.format(System.Label.UoW_Span_PluginsFailed, new String[]{ ex.getMessage() }));
            throw ex;
        }
    }

    /**
     * Handle exception - Process exception, rollback decision, status setting.
     * Execution order:
     * 1. Decide trace commitment (ensures tracing is captured for failures)
     * 2. Execute ON_FAILURE phase for non-callout work types (events, emails, notifications, flows)
     * 3. Execute onError plugins
     * 4. Rollback transaction (if savepoint exists)
     * 5. Release savepoint (enables callouts)
     * 6. Execute ON_FAILURE callouts (after clean rollback)
     *
     * Replaces: Lines 718-749 in UnitOfWork.commitWork()
     *
     * @param ex The exception that occurred
     */
    public void handleException(Exception ex) {
        // CRITICAL: Commit trace for exception path
        // decideTraceCommitment() is normally called in processControlPolicyActions(),
        // but exceptions (policy denial, risk threshold) bypass that method.
        // Must commit trace here so audit events include timeline data.
        decideTraceCommitment();

        // Start tracing span for exception handling
        UoWTracer.Span exceptionSpan = result.startSpan(
            UoWEnums.SpanPhase.EXCEPTION_HANDLING,
            'Exception handling'
        );

        transitionTo(UoWEnums.OrchestratorPhase.ON_FAILURE, 'Handling exception: ' + ex.getMessage());

        // Add error to result ONLY if not already captured
        // Work item errors are consolidated later in consolidateErrors()
        // This handles non-work-item exceptions (policy denial, risk threshold, plugin failures)
        if (!isExceptionAdded(ex)) {
            result.addError(ex, 'UnitOfWork.commitWork');
        }

        // Execute ON_FAILURE phase for non-callout work types (events, emails, notifications, flows)
        // Callouts execute AFTER rollback + savepoint release
        try {
            executeWorkTypesForPhase(UoWEnums.WorkPhase.ON_FAILURE);
        } catch (Exception failureEx) {
            result.addError(failureEx, 'ON_FAILURE phase');
        }

        // Execute onError plugins
        UoWTracer.Span pluginsOnErrorSpan = result.startSpan(
            UoWEnums.SpanPhase.PLUGINS_ERROR,
            'onError plugins'
        );

        try {
            Integer executedCount = UoWPluginExecutor.executeOnError(context, ex, result);
            result.endSpan(pluginsOnErrorSpan,
                getPhaseResultFromCount(executedCount),
                getPluginSpanResultMessage(executedCount));
        } catch (Exception pluginEx) {
            result.addError(pluginEx, 'onError plugin');
            result.endSpan(pluginsOnErrorSpan, UoWEnums.SpanPhaseResult.FAILED,
                String.format(System.Label.UoW_Span_PluginsFailed, new String[]{ pluginEx.getMessage() }));
        }

        // ROLLBACK DECISION
        // Preserve DENIED_BY_POLICY status if already set by policy evaluation
        Boolean preserveStatus = result.transactionStatus == UoWEnums.TransactionStatus.DENIED_BY_POLICY;

        if (context.transactionSavepoint != null) {
            try {
                // Step 1: Rollback transaction
                Database.rollback(context.transactionSavepoint);
                if (!preserveStatus) {
                    result.setTransactionStatus(UoWEnums.TransactionStatus.ROLLED_BACK);
                }
                addDecision('Transaction rolled back', 'Savepoint existed');

                // Step 2: Release savepoint to enable callouts
                releaseSavepointForCallouts();

                // Step 3: Execute ON_FAILURE callouts (after clean rollback + savepoint release)
                executeOnFailureCallouts();

            } catch (Exception rollbackEx) {
                result.warn('[ROLLBACK] Failed to rollback transaction: ' + rollbackEx.getMessage());
            }
        } else {
            if (!preserveStatus) {
                result.setTransactionStatus(UoWEnums.TransactionStatus.FAILED);
            }
            addDecision('Transaction failed', 'No savepoint available');
        }

        // End exception handling span AFTER all ON_FAILURE work (including callouts)
        result.endSpan(exceptionSpan, UoWEnums.SpanPhaseResult.SUCCESS,
            String.format(System.Label.UoW_Span_ExceptionHandled, new String[]{ ex.getMessage() }));
    }

    /**
     * Release savepoint to enable callouts after rollback.
     * IMPORTANT: Must be called AFTER Database.rollback() to enable ON_FAILURE callouts.
     * Salesforce limitation: Cannot make callouts while a savepoint is active.
     */
    private void releaseSavepointForCallouts() {
        if (context.transactionSavepoint != null) {
            try {
                Database.releaseSavepoint(context.transactionSavepoint);
                addDecision('Savepoint released', 'Enabling ON_FAILURE callouts');
            } catch (Exception releaseEx) {
                // Log warning but continue - callouts may still fail but shouldn't mask original error
                result.warn('[SAVEPOINT] Failed to release savepoint: ' + releaseEx.getMessage());
            }
        }
    }

    /**
     * Execute ON_FAILURE callouts after rollback + savepoint release.
     * These callouts are used for error notification and compensation patterns.
     * Errors are captured but never re-thrown to avoid masking the original error.
     * Note: Span is created inside UoWCalloutExecutionService.execute() to avoid duplicates.
     */
    private void executeOnFailureCallouts() {
        if (!plan.hasCalloutsForPhase(UoWEnums.WorkPhase.ON_FAILURE)) {
            return; // No ON_FAILURE callouts registered
        }

        try {
            new UoWCalloutExecutionService(context, plan, result).execute(UoWEnums.WorkPhase.ON_FAILURE);
        } catch (Exception calloutEx) {
            // Capture error but don't re-throw - ON_FAILURE callout errors shouldn't mask original error
            result.addError(calloutEx, 'ON_FAILURE callout');
            result.warn('[ON_FAILURE CALLOUT] Callout failed: ' + calloutEx.getMessage() +
                ' - Original transaction error preserved');
        }
    }

    /**
     * Finalize transaction - Dispatcher that calls appropriate finalization based on completion path.
     * Called from finally block in UnitOfWork.commitWork()
     *
     * @param executionSuccess Whether execution phase succeeded
     */
    public void finalizeTransaction(Boolean executionSuccess) {
        // Dispatch to appropriate finalization based on completion path
        switch on this.completionPath {
            when EMPTY_PLAN {
                finalizeEmptyPlanTransaction();
            }
            when ASYNC_ENQUEUED {
                finalizeAsyncTransaction();
            }
            when APPROVAL_DEFERRED {
                finalizeApprovalTransaction();
            }
            when else {  // FULL_EXECUTION
                finalizeFullTransaction(executionSuccess);
            }
        }
    }

    // Finalize empty plan transaction - Minimal finalization (no work items or plugins)
    // Used when plan.isEmpty() returns true
    private void finalizeEmptyPlanTransaction() {
        transitionTo(UoWEnums.OrchestratorPhase.FINALIZING, 'Finalizing empty plan transaction');

        // Minimal finalization: skip work items and non-audit plugins
        // Don't call finalizeCoreState - status already set by prepareEmptyPlanTransaction
        result.consolidateErrors();
        executeAuditTrail();
        completeTransaction();

        // Restore parent's ambient state (or clear if no parent)
        UoWTransactionState.restorePrevious();
    }

    // Finalize async enqueued transaction - Partial finalization (async enqueued)
    // Used when transaction is enqueued for async execution
    private void finalizeAsyncTransaction() {
        transitionTo(UoWEnums.OrchestratorPhase.FINALIZING, 'Finalizing async transaction');

        // Partial finalization: skip work items and plugins (will execute in async context)
        // Don't call finalizeCoreState - status already set by enqueueAsync
        result.consolidateErrors();
        executeAuditTrail();
        completeTransaction();

        // Restore parent's ambient state (or clear if no parent)
        UoWTransactionState.restorePrevious();
    }

    // Finalize approval-required transaction - Partial finalization (pending approval)
    // Used when transaction requires approval and is deferred
    private void finalizeApprovalTransaction() {
        transitionTo(UoWEnums.OrchestratorPhase.FINALIZING, 'Finalizing approval-required transaction');

        // Partial finalization: skip work items and plugins (will execute after approval)
        // Don't call finalizeCoreState - status already set by approval channel (PENDING_APPROVAL)
        result.consolidateErrors();
        executeAuditTrail();
        completeTransaction();

        // Restore parent's ambient state (or clear if no parent)
        UoWTransactionState.restorePrevious();
    }

    // Finalize full execution transaction - Complete finalization for normal execution path
    // Replaces: Lines 754-806 in UnitOfWork.commitWork()
    private void finalizeFullTransaction(Boolean executionSuccess) {
        transitionTo(UoWEnums.OrchestratorPhase.FINALIZING, 'Finalizing transaction');

        // Full finalization: work items + plugins + core + audit
        executeFinalizationPhase();
        executeNonAuditPlugins();
        finalizeCoreState(executionSuccess);
        executeAuditTrail();
        completeTransaction();

        // Restore parent's ambient state (or clear if no parent)
        UoWTransactionState.restorePrevious();
    }

    // ============================================================================
    // PRIVATE FINALIZATION HELPERS
    // ============================================================================

    // Execute ON_FINALIZATION phase work items.
    // Note: No wrapper span here - executeWorkTypesForPhase() creates the ON_FINALIZATION span.
    private void executeFinalizationPhase() {
        try {
            executeWorkTypesForPhase(UoWEnums.WorkPhase.ON_FINALIZATION);
        } catch (Exception finalizeEx) {
            result.addError(finalizeEx, 'ON_FINALIZATION phase');
        }
    }

    // Execute non-audit plugins
    private void executeNonAuditPlugins() {
        UoWTracer.Span pluginsFinalizationSpan = result.startSpan(
            UoWEnums.SpanPhase.PLUGINS_FINALLY,
            'onFinally plugins (non-audit)'
        );
        Integer executedCount = UoWPluginExecutor.executeFinallyExceptCategory(context, result, UoWEnums.PluginCategory.AUDIT);
        result.endSpan(pluginsFinalizationSpan,
            getPhaseResultFromCount(executedCount),
            getPluginSpanResultMessage(executedCount));
    }

    // Finalize core state (work item status, error consolidation, transaction status)
    private void finalizeCoreState(Boolean executionSuccess) {
        // Finalize status for ALL work items (executed and non-executed)
        // Pass executionSuccess to determine SKIPPED vs NOT_EXECUTED for phase-conditional items
        finalizeAllWorkItemStatuses(executionSuccess);

        result.consolidateErrors();
        UoWEnums.TransactionStatus finalStatus = determineFinalStatus(executionSuccess, result);
        // Use markComplete() to set status AND capture finish governor limits
        result.markComplete(finalStatus);
        addDecision('Final status determined', finalStatus.name());
    }

    // Finalize status for all work items and ensure they're in the result.
    // Executed work items: Already finalized and added to result by execution services.
    // Non-executed work items: Need finalization and must be added to result.
    // Architecture: Plan = Intent, Result = Outcome
    // - Execution services add executed items to result during execution
    // - This method adds non-executed items to result during finalization
    // - After this method, result.getAllWorkItems() is the single source of truth
    // Ordering: NOT_EXECUTED items first, then SKIPPED items last (skipped always at end)
    private void finalizeAllWorkItemStatuses(Boolean executionSuccess) {
        // Build a set of work IDs already in result (executed items)
        Set<String> workIdsInResult = new Set<String>();
        for (UoWWorkItem workItem : result.getAllWorkItems()) {
            workIdsInResult.add(workItem.workId);
        }

        // Categorize non-executed items: NOT_EXECUTED first, SKIPPED last
        List<UoWWorkItem> notExecutedItems = new List<UoWWorkItem>();
        List<UoWWorkItem> skippedItems = new List<UoWWorkItem>();

        for (UoWWorkItem workItem : plan.getPlannedWorkItems()) {
            if (!workIdsInResult.contains(workItem.workId)) {
                // Pre-determine status to categorize
                UoWEnums.WorkStatus status = determineNonExecutedStatus(workItem, executionSuccess);
                if (status == UoWEnums.WorkStatus.SKIPPED) {
                    skippedItems.add(workItem);
                } else {
                    notExecutedItems.add(workItem);
                }
            }
        }

        // First pass: Add NOT_EXECUTED items (canonical order preserved from plan)
        for (UoWWorkItem workItem : notExecutedItems) {
            finalizeUnexecutedWorkItem(workItem, executionSuccess);
        }

        // Second pass: Add SKIPPED items last (canonical order preserved from plan)
        for (UoWWorkItem workItem : skippedItems) {
            finalizeUnexecutedWorkItem(workItem, executionSuccess);
        }
    }

    // Determine whether a non-executed work item should be SKIPPED or NOT_EXECUTED.
    // SKIPPED = intentionally skipped because phase condition wasn't met
    // NOT_EXECUTED = should have run but didn't (unexpected)
    private UoWEnums.WorkStatus determineNonExecutedStatus(UoWWorkItem workItem, Boolean executionSuccess) {
        // Get the execution phase for phase-conditional work types
        UoWEnums.WorkPhase phase = UoWUtils.getWorkItemExecutionPhase(workItem);

        // If no phase (DML) or phase is null, it should have executed → NOT_EXECUTED
        if (phase == null) {
            return UoWEnums.WorkStatus.NOT_EXECUTED;
        }

        // Phase-conditional logic:
        // - ON_FAILURE items when transaction succeeded → SKIPPED (failure phase didn't run)
        // - ON_SUCCESS items when transaction failed → SKIPPED (success phase didn't run)
        // - PRE_DML/POST_DML/ON_FINALIZATION items → NOT_EXECUTED (these phases always run)

        if (phase == UoWEnums.WorkPhase.ON_FAILURE && executionSuccess) {
            // Transaction succeeded, so ON_FAILURE phase never ran - intentionally skipped
            return UoWEnums.WorkStatus.SKIPPED;
        }

        if (phase == UoWEnums.WorkPhase.ON_SUCCESS && !executionSuccess) {
            // Transaction failed, so ON_SUCCESS phase never ran - intentionally skipped
            return UoWEnums.WorkStatus.SKIPPED;
        }

        // For all other phases (PRE_DML, POST_DML, ON_FINALIZATION), if not executed, it's unexpected
        return UoWEnums.WorkStatus.NOT_EXECUTED;
    }

    // Finalize a work item that was not executed.
    // Sets stats to zero, determines SKIPPED vs NOT_EXECUTED status,
    // assigns transaction sequence, and adds to result.
    // Status determination:
    // - SKIPPED: Phase-conditional work items where the phase didn't run
    //   - ON_FAILURE items when transaction succeeded
    //   - ON_SUCCESS items when transaction failed
    // - NOT_EXECUTED: Work items that should have executed but didn't
    //   - DML and Callout items (no phase conditions)
    //   - PRE_DML/POST_DML/ON_FINALIZATION items (always run)
    private void finalizeUnexecutedWorkItem(UoWWorkItem workItem, Boolean executionSuccess) {
        // Set stats to zero for non-executed items
        workItem.statistics.processed = 0;
        workItem.statistics.successes = 0;
        workItem.statistics.failures = 0;

        // Assign transaction sequence (after all executed items)
        workItem.transactionSequence = result.getNextExecutionSequence();

        // Determine status: SKIPPED (phase condition not met) vs NOT_EXECUTED (unexpected)
        workItem.status = determineNonExecutedStatus(workItem, executionSuccess);

        // Note: Snapshot is captured at audit publish time, not during finalization

        // Add to result so result.getAllWorkItems() is complete
        addWorkItemToResult(workItem);
    }

    // Add a work item to the appropriate result collection based on its type.
    // This enables result.getAllWorkItems() to be the single source of truth.
    private void addWorkItemToResult(UoWWorkItem workItem) {
        if (workItem == null || workItem.workType == null) {
            return;
        }

        switch on workItem.workType {
            when DML {
                result.addDmlWork((UoWDmlWorkItem) workItem);
            }
            when EVENT {
                result.addEventWork((UoWEventWorkItem) workItem);
            }
            when EMAIL {
                result.addEmailWork((UoWEmailWorkItem) workItem);
            }
            when NOTIFICATION {
                result.addNotificationWork((UoWNotificationWorkItem) workItem);
            }
            when FLOW {
                result.addFlowWork((UoWFlowWorkItem) workItem);
            }
            when CALLOUT {
                result.addCalloutWork((UoWCalloutWorkItem) workItem);
            }
        }
    }

    // Execute audit trail (audit plugins, message listeners)
    private void executeAuditTrail() {
        UoWTracer.Span pluginsAuditSpan = result.startSpan(
            UoWEnums.SpanPhase.PLUGINS_AUDIT,
            'Audit plugins'
        );
        Integer executedCount = UoWPluginExecutor.executeFinallyByCategory(context, result, UoWEnums.PluginCategory.AUDIT);
        result.endSpan(pluginsAuditSpan,
            getPhaseResultFromCount(executedCount),
            getPluginSpanResultMessage(executedCount));
    }

    // Complete transaction (mark complete, transition to terminal state)
    private void completeTransaction() {
        UoWEnums.TransactionStatus finalStatus = result.transactionStatus;
        result.markComplete(finalStatus);
        transitionTo(UoWEnums.OrchestratorPhase.COMPLETED, 'Transaction completed with status: ' + finalStatus.name());
    }

    // ============================================================================
    // PRIVATE HELPER METHODS
    // ============================================================================

    // Execute all work types for a given phase
    // Events, Emails, Notifications, Flows
    private void executeWorkTypesForPhase(UoWEnums.WorkPhase phase) {
        UoWTracer.Span phaseSpan = result.startSpan(
            getSpanPhaseForWorkPhase(phase),
            formatPhaseName(phase.name()) + ' phase'
        );

        // Execute each work type for this phase
        new UoWEventExecutionService(context, plan, result).execute(phase);
        new UoWEmailExecutionService(context, plan, result).execute(phase);
        new UoWNotificationExecutionService(context, plan, result).execute(phase);
        new UoWFlowExecutionService(context, plan, result).execute(phase);

        // Determine phase result and build result message
        Integer workItemCount = plan.getWorkItemCountForPhase(phase);
        UoWEnums.SpanPhaseResult phaseResult = workItemCount == 0 ?
            UoWEnums.SpanPhaseResult.NOT_APPLICABLE : UoWEnums.SpanPhaseResult.SUCCESS;
        String resultMessage = workItemCount == 0 ?
            String.format(System.Label.UoW_Span_PhaseSkipped, new String[]{ formatPhaseName(phase.name()) }) :
            String.format(System.Label.UoW_Span_PhaseCompleted, new String[]{ formatPhaseName(phase.name()), String.valueOf(workItemCount) });
        result.endSpan(phaseSpan, phaseResult, resultMessage);
    }

    // Map ExecutionPhase to TimelinePhase for tracing
    private UoWEnums.SpanPhase getSpanPhaseForWorkPhase(UoWEnums.WorkPhase execPhase) {
        switch on execPhase {
            when PRE_DML { return UoWEnums.SpanPhase.PRE_DML; }
            when POST_DML { return UoWEnums.SpanPhase.POST_DML; }
            when ON_SUCCESS { return UoWEnums.SpanPhase.ON_SUCCESS; }
            when ON_FAILURE { return UoWEnums.SpanPhase.ON_FAILURE; }
            when ON_FINALIZATION { return UoWEnums.SpanPhase.ON_FINALIZATION; }
            when else { return UoWEnums.SpanPhase.TRANSACT; }
        }
    }

    // Transition to new phase with validation
    private void transitionTo(UoWEnums.OrchestratorPhase newPhase, String reason) {
        // Validate transition
        if (!isValidTransition(this.currentPhase, newPhase)) {
            throw new UoWExceptionService.UoWException(
                String.format('Invalid transition: {0} → {1}',
                    new String[]{ String.valueOf(currentPhase), String.valueOf(newPhase) }));
        }

        // Record transition
        PhaseTransition transition = new PhaseTransition();
        transition.fromPhase = this.currentPhase;
        transition.toPhase = newPhase;
        transition.reason = reason;
        transition.timestamp = DateTime.now();

        // Calculate duration for previous phase
        if (!this.transitionHistory.isEmpty()) {
            PhaseTransition previousTransition = this.transitionHistory[this.transitionHistory.size() - 1];
            previousTransition.durationMs = transition.timestamp.getTime() - previousTransition.timestamp.getTime();
        }

        this.transitionHistory.add(transition);

        // Update state
        this.currentPhase = newPhase;
    }

    // Add decision to audit trail
    private void addDecision(String decision, String rationale) {
        result.addTraceEvent('[DECISION] ' + decision + ': ' + rationale);
        result.info(decision + ' - ' + rationale, 'TransactionStateService');
    }

    // Validate state transition using flexible forward progression
    // Allows skipping optional phases (POLICY_EVALUATION, RISK_ASSESSMENT, CALLOUTS, etc.)
    // while maintaining phase order integrity (no backward transitions).
    // Valid transitions:
    // - Forward progression: Any phase to any later phase in sequence
    // - Example: NOT_STARTED → STARTED (normal initialization)
    // - Example: STARTED → FINALIZING (empty plan - skips all execution phases)
    // - Example: STARTED → EXECUTING (skips policy/risk phases)
    // - Exception flow: EXECUTING → ON_FAILURE → FINALIZING → COMPLETED
    // Invalid transitions:
    // - Backward transitions: EXECUTING → BEFORE_COMMIT (disallowed)
    // - Same phase: EXECUTING → EXECUTING (disallowed)
    private Boolean isValidTransition(UoWEnums.OrchestratorPhase fromPhase, UoWEnums.OrchestratorPhase toPhase) {
        // Allow initial transition
        if (fromPhase == null && toPhase == UoWEnums.OrchestratorPhase.NOT_STARTED) {
            return true;
        }

        // Define phase order (for forward progression validation)
        // Allows skipping optional phases (e.g., POLICY_EVALUATION, RISK_ASSESSMENT, CALLOUTS)
        // while maintaining phase order integrity
        List<UoWEnums.OrchestratorPhase> phaseOrder = new List<UoWEnums.OrchestratorPhase>{
            UoWEnums.OrchestratorPhase.NOT_STARTED,
            UoWEnums.OrchestratorPhase.STARTED,
            UoWEnums.OrchestratorPhase.POLICY_EVALUATION,
            UoWEnums.OrchestratorPhase.RISK_ASSESSMENT,
            UoWEnums.OrchestratorPhase.BEFORE_COMMIT,
            UoWEnums.OrchestratorPhase.CALLOUTS,
            UoWEnums.OrchestratorPhase.SAVEPOINT_CREATION,
            UoWEnums.OrchestratorPhase.EXECUTING,
            UoWEnums.OrchestratorPhase.AFTER_COMMIT,
            UoWEnums.OrchestratorPhase.ON_FAILURE,
            UoWEnums.OrchestratorPhase.FINALIZING,
            UoWEnums.OrchestratorPhase.COMPLETED
        };

        Integer fromIndex = phaseOrder.indexOf(fromPhase);
        Integer toIndex = phaseOrder.indexOf(toPhase);

        // Special case: Allow ON_FAILURE from EXECUTING (error path)
        if (fromPhase == UoWEnums.OrchestratorPhase.EXECUTING &&
            toPhase == UoWEnums.OrchestratorPhase.ON_FAILURE) {
            return true;
        }

        // Special case: Allow ON_FAILURE from AFTER_COMMIT (error in after-commit plugins)
        if (fromPhase == UoWEnums.OrchestratorPhase.AFTER_COMMIT &&
            toPhase == UoWEnums.OrchestratorPhase.ON_FAILURE) {
            return true;
        }

        // Allow forward progression (can skip optional phases)
        // Example: NOT_STARTED → FINALIZING is valid (skips all intermediate phases)
        if (toIndex > fromIndex) {
            return true;
        }

        // Disallow backward transitions (toIndex <= fromIndex)
        return false;
    }

    // Determine final transaction status
    // Replaces: Lines 825-845 in UnitOfWork.commitWork()
    private UoWEnums.TransactionStatus determineFinalStatus(Boolean executionSuccess, UoWResult result) {
        // Exception occurred - status already set in handleException()
        if (!executionSuccess) {
            return result.transactionStatus;  // ROLLED_BACK or FAILED
        }

        // Execution succeeded - determine status based on results
        if (!result.hasErrors()) {
            return UoWEnums.TransactionStatus.SUCCESS;  // All succeeded
        }

        // Has errors - determine if partial or complete failure
        return result.hasSuccessfulWork()
            ? UoWEnums.TransactionStatus.PARTIAL_SUCCESS  // Some succeeded, some failed
            : UoWEnums.TransactionStatus.FAILED;          // All failed
    }

    // Decide whether to commit or discard optimistically buffered trace
    // Based on current tracing configuration (after policy evaluation)
    private void decideTraceCommitment() {
        if (context.getFeatureSettings().getEnableTracing()) {
            result.commitTrace();  // Config/runtime/policy enabled tracing
        } else {
            result.discardTrace();  // Tracing not enabled by any means
        }
    }

    // Check if exception is already captured (in result or work items).
    // Prevents duplicate error entries when exceptions bubble up.
    private Boolean isExceptionAdded(Exception ex) {
        if (ex == null) {
            return false;
        }

        String exMessage = ex.getMessage();
        String exType = ex.getTypeName();

        // Check result's existing errors
        for (UoWExceptionService.ErrorInfo error : result.getErrors()) {
            if (error.errorMessage == exMessage && error.errorType == exType) {
                return true;
            }
        }

        // Check all work items in the plan
        for (UoWWorkItem workItem : plan.getPlannedWorkItems()) {
            for (UoWExceptionService.ErrorInfo error : workItem.errors) {
                if (error.errorMessage == exMessage && error.errorType == exType) {
                    return true;
                }
            }
        }

        return false;
    }

    // ============================================================================
    // PUBLIC API - AUDIT TRAIL
    // ============================================================================

    /**
     * Get transition history for audit/debugging.
     *
     * @return List of phase transitions with timestamps and durations
     */
    public List<PhaseTransition> getTransitionHistory() {
        return this.transitionHistory;
    }

    /**
     * Get current transaction phase.
     *
     * @return Current phase
     */
    public UoWEnums.OrchestratorPhase getCurrentPhase() {
        return this.currentPhase;
    }

    // ============================================================================
    // PRIVATE HELPER METHODS - SPAN MESSAGING
    // ============================================================================

    // Get phase result based on execution count
    // 0 = NOT_APPLICABLE (no plugins executed), >0 = SUCCESS
    private UoWEnums.SpanPhaseResult getPhaseResultFromCount(Integer executedCount) {
        return executedCount == 0 ?
            UoWEnums.SpanPhaseResult.NOT_APPLICABLE :
            UoWEnums.SpanPhaseResult.SUCCESS;
    }

    // Get result message for plugin spans based on execution count
    private String getPluginSpanResultMessage(Integer executedCount) {
        return executedCount == 0 ?
            System.Label.UoW_Span_PluginsSkipped :
            String.format(System.Label.UoW_Span_PluginsExecuted, new String[]{ String.valueOf(executedCount) });
    }

    // Format phase name from SNAKE_CASE to Title Case
    // e.g., PRE_DML → Pre DML, ON_SUCCESS → On Success
    private String formatPhaseName(String phaseName) {
        if (String.isBlank(phaseName)) {
            return phaseName;
        }

        // Handle known acronyms that should stay uppercase
        Set<String> acronyms = new Set<String>{ 'DML' };

        List<String> words = phaseName.split('_');
        List<String> formattedWords = new List<String>();

        for (String word : words) {
            String upperWord = word.toUpperCase();
            if (acronyms.contains(upperWord)) {
                formattedWords.add(upperWord);
            } else {
                formattedWords.add(word.toLowerCase().capitalize());
            }
        }

        return String.join(formattedWords, ' ');
    }

    // ============================================================================
    // INNER CLASSES
    // ============================================================================

    /**
     * Phase transition record for audit trail.
     */
    public class PhaseTransition {
        public UoWEnums.OrchestratorPhase fromPhase;
        public UoWEnums.OrchestratorPhase toPhase;
        public String reason;
        public DateTime timestamp;
        public Long durationMs;  // Calculated when next transition occurs
    }
}