//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Container class for all UoW framework extensibility interfaces.
 * Defines contracts for plugins, policies, strategies, channels, and other extension points.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWBasePlugin, UoWBasePolicy, UoWBaseDmlStrategy, UoWBaseCalloutStrategy
 */
public inherited sharing class UoWInterfaces {

    // ============================================================================
    // DML STRATEGY INTERFACE
    // ============================================================================

    /**
     * Interface for DML execution strategies.
     * Allows different strategies for DML operations (all-or-none, partial success, async).
     * Strategies can be global or object-specific.
     */
    public interface IDmlStrategy {

        /**
         * Get strategy name
         * @return Strategy name for logging and debugging
         */
        String getName();

        /**
         * Execute insert operation with this strategy
         * @param workItem The DML work item to execute
         * @param ctx The execution context
         */
        void executeInsert(UoWDmlWorkItem workItem, UoWContext ctx);

        /**
         * Execute update operation with this strategy
         * @param workItem The DML work item to execute
         * @param ctx The execution context
         */
        void executeUpdate(UoWDmlWorkItem workItem, UoWContext ctx);

        /**
         * Execute upsert operation with this strategy
         * @param workItem The DML work item to execute
         * @param ctx The execution context
         */
        void executeUpsert(UoWDmlWorkItem workItem, UoWContext ctx);

        /**
         * Execute delete operation with this strategy
         * @param workItem The DML work item to execute
         * @param ctx The execution context
         */
        void executeDelete(UoWDmlWorkItem workItem, UoWContext ctx);

        /**
         * Execute undelete operation with this strategy
         * @param workItem The DML work item to execute
         * @param ctx The execution context
         */
        void executeUndelete(UoWDmlWorkItem workItem, UoWContext ctx);
    }

    // ============================================================================
    // CHANNEL INTERFACES
    // ============================================================================

    /**
     * Interface for Platform Event publishing channels.
     * Allows different strategies for event publishing (EventBus, logging, external).
     */
    public interface IEventChannel {

        /**
         * Get channel name
         * @return Channel name for identification
         */
        String getName();

        /**
         * Publish platform events
         * @param workItem The event work item to execute
         * @param ctx The execution context
         */
        void publishEvents(UoWEventWorkItem workItem, UoWContext ctx);
    }

    /**
     * Interface for Email sending channels.
     * Allows different strategies for email delivery (platform, logging, external).
     */
    public interface IEmailChannel {

        /**
         * Get channel name
         * @return Channel name for identification
         */
        String getName();

        /**
         * Send emails
         * @param workItem The email work item to execute
         * @param ctx The execution context
         */
        void sendEmails(UoWEmailWorkItem workItem, UoWContext ctx);
    }

    /**
     * Interface for Custom Notification channels.
     * Allows different strategies for sending notifications.
     */
    public interface INotificationChannel {

        /**
         * Get channel name
         * @return Channel name for identification
         */
        String getName();

        /**
         * Send custom notification
         * @param workItem The notification work item to execute
         * @param ctx The execution context
         */
        void sendNotification(UoWNotificationWorkItem workItem, UoWContext ctx);
    }

    /**
     * Interface for Flow execution channels.
     * Allows different strategies for flow invocation.
     */
    public interface IFlowChannel {

        /**
         * Get channel name
         * @return Channel name for identification
         */
        String getName();

        /**
         * Execute flow
         * @param workItem The flow work item to execute
         * @param ctx The execution context
         */
        void executeFlow(UoWFlowWorkItem workItem, UoWContext ctx);
    }

    // ============================================================================
    // CALLOUT STRATEGY INTERFACE
    // ============================================================================

    /**
     * Interface for HTTP callout execution strategies.
     * Allows different strategies for callout execution (immediate, retry-enabled, async).
     * Strategies are pure executors - they control HOW callouts execute, not WHEN.
     * The orchestration layer (UoWCalloutExecutionService) handles dry run checks and phase sequencing.
     */
    public interface ICalloutStrategy {

        /**
         * Get strategy name
         * @return Strategy name (e.g., "Default", "RetryEnabled", "Mock")
         */
        String getName();

        /**
         * Execute HTTP callout
         * @param workItem The callout work item to execute
         * @param ctx The execution context
         */
        void executeCallout(UoWCalloutWorkItem workItem, UoWContext ctx);
    }

    // ============================================================================
    // PLUGIN INTERFACE
    // ============================================================================

    /**
     * Interface for UnitOfWork plugins.
     * Plugins provide cross-cutting concerns like logging, security, audit, etc.
     */
    public interface IPlugin {

        /**
         * Get plugin name
         * @return Plugin name for identification
         */
        String getName();

        /**
         * Initialize plugin with settings from metadata.
         * Called after instantiation to pass configuration from UoWPluginSetting__mdt.
         * @param pluginSetting The plugin setting CMT record (may be null for runtime-registered plugins)
         */
        void initialize(UoWPluginSetting__mdt pluginSetting);

        /**
         * Get plugin category
         * @return Plugin category for execution ordering
         */
        UoWEnums.PluginCategory getCategory();

        /**
         * Indicates if this plugin is critical to transaction success.
         * If critical=true and plugin throws exception, transaction is rolled back.
         * If critical=false and plugin throws exception, warning is logged and transaction continues.
         * @return True if plugin failure should fail the transaction
         */
        Boolean isCritical();

        /**
         * Called before commit execution
         * @param ctx Execution context
         * @param plan Execution plan
         * @param result Execution result (for logging)
         * @return PhaseResult indicating whether the plugin performed work
         */
        UoWPluginExecutor.PhaseResult onBeforeCommit(UoWContext ctx, UoWPlan plan, UoWResult result);

        /**
         * Called after successful commit
         * @param ctx Execution context
         * @param result Execution result
         * @return PhaseResult indicating whether the plugin performed work
         */
        UoWPluginExecutor.PhaseResult onAfterCommit(UoWContext ctx, UoWResult result);

        /**
         * Called when an error occurs
         * @param ctx Execution context
         * @param ex Exception that occurred
         * @param result Execution result (for logging)
         * @return PhaseResult indicating whether the plugin performed work
         */
        UoWPluginExecutor.PhaseResult onError(UoWContext ctx, Exception ex, UoWResult result);

        /**
         * Called in finally block regardless of success/failure
         * @param ctx Execution context
         * @param result Execution result
         * @return PhaseResult indicating whether the plugin performed work
         */
        UoWPluginExecutor.PhaseResult onFinally(UoWContext ctx, UoWResult result);
    }

    // ============================================================================
    // POLICY INTERFACE
    // ============================================================================

    /**
     * Interface for UnitOfWork policies.
     * Policies evaluate operations and return actions (ALLOW, DENY, etc.)
     */
    public interface IPolicy {

        /**
         * Get policy name
         * @return Policy name for identification
         */
        String getName();

        /**
         * Indicates if this policy is critical to transaction success.
         * If critical=true and policy evaluation throws exception, transaction fails.
         * If critical=false and policy evaluation throws exception, warning is logged and transaction continues.
         * @return True if policy failure should fail the transaction (default: true for fail-safe)
         */
        Boolean isCritical();

        /**
         * Evaluate a work item against this policy
         * @param ctx Execution context
         * @param workItem Work item to evaluate
         * @return Policy evaluation result
         */
        UoWPolicyEvaluation.Evaluation evaluate(UoWContext ctx, UoWWorkItem workItem);

        /**
         * Evaluate the entire plan against this policy
         * @param ctx Execution context
         * @param plan Execution plan
         * @return List of policy evaluations
         */
        List<UoWPolicyEvaluation.Evaluation> evaluatePlan(UoWContext ctx, UoWPlan plan);
    }

    // ============================================================================
    // RISK ASSESSOR INTERFACE
    // ============================================================================

    /**
     * Interface for risk assessors.
     * Risk assessors evaluate the execution context and plan to calculate risk scores.
     * Policies can add risk factors before risk assessment runs.
     */
    public interface IRiskAssessor {

        /**
         * Get the name of this risk assessor
         * @return Risk assessor name for logging and debugging
         */
        String getName();

        /**
         * Evaluates risk for the given context and plan
         * @param ctx The execution context (may already have risk factors from policies)
         * @param plan The execution plan
         * @return Updated RiskAssessment with calculated score and level
         */
        UoWRiskTypes.RiskAssessment assessRisk(UoWContext ctx, UoWPlan plan);

    }

    // ============================================================================
    // APPROVAL CHANNEL INTERFACE
    // ============================================================================

    /**
     * Interface for approval channels.
     * Approval channels have full control over the approval lifecycle:
     * 1. requestApproval() - Initiates approval process (creates record, sends notification, returns partial result)
     * 2. continueAfterApproval() - Resumes transaction after approval is granted
     * Implement this in the extensions package or custom code to provide approval functionality.
     * Examples: Salesforce native approvals, Slack, Teams, custom integrations
     */
    public interface IApprovalChannel {

        /**
         * Get the channel name
         * @return Channel name for logging and debugging
         */
        String getName();

        /**
         * Initiate approval process for a transaction.
         * Creates approval record, sends notification, and returns partial result.
         * The transaction execution is paused pending approval.
         * @param context Execution context
         * @param plan Execution plan to be approved
         * @param result Current result (partial - transaction not yet executed)
         * @return Partial result with approval metadata (correlationId, approval record ID)
         */
        UoWResult requestApproval(UoWContext context, UoWPlan plan, UoWResult result);

        /**
         * Resume transaction execution after approval is granted.
         * Called by approval callback/trigger to continue the paused transaction.
         * @param approvalId Approval record ID (from requestApproval return value)
         * @param context Deserialized execution context
         * @param plan Deserialized execution plan
         * @return Final transaction result after execution
         */
        UoWResult continueAfterApproval(String approvalId, UoWContext context, UoWPlan plan);

    }

    // ============================================================================
    // EVENT PUBLISH FAILURE HANDLER INTERFACE
    // ============================================================================

    /**
     * Interface for handling asynchronous platform event delivery failures.
     * Called when EventBus fails to deliver events after transaction commit.
     *
     * This addresses the unique async gap for platform events with PublishAfterCommit
     * behavior. All other work types (DML, email, flow, callout) fail synchronously
     * and are captured in work item results. Platform events can silently fail
     * after EventBus.publish() returns success.
     *
     * IMPORTANT: The handleFailure method runs in a SEPARATE transaction
     * from the original publish call, with fresh governor limits and no
     * access to the original transaction's state.
     *
     * Core framework provides the interface only (no default implementation).
     * The audit package provides an implementation that persists failure records.
     *
     * @see EventBus.EventPublishFailureCallback
     * @see UoWDefaultPublishFailureCallback
     */
    public interface IEventPublishFailureHandler {

        /**
         * Get handler name for logging and debugging.
         *
         * @return Handler name
         */
        String getName();

        /**
         * Handle an asynchronous platform event delivery failure.
         * Called in a separate transaction when events fail to deliver after commit.
         *
         * @param failureContext Context containing transaction identity, failure details, and failed event data
         */
        void handleFailure(UoWEventPublishFailureContext failureContext);
    }

    // ============================================================================
    // TRANSACTION FINALIZER INTERFACE
    // ============================================================================

    /**
     * Interface for async transaction finalization.
     * Extends Salesforce's native Finalizer interface for platform-guaranteed execution.
     *
     * Implement this to handle post-async-execution logic:
     * - Error logging and persistence
     * - Retry logic with re-enqueuing
     * - Metrics and observability
     * - Notifications on failure
     *
     * Platform guarantees:
     * - execute() ALWAYS runs, even on unhandled exceptions
     * - Access to exception via FinalizerContext.getException()
     * - Access to job result via FinalizerContext.getResult()
     * - Can enqueue new jobs for retry scenarios
     *
     * UoW provides additional context via static accessors on UoWQueueable:
     * - UoWQueueable.getFinalizerContext() - UoWContext with correlation ID, config, metadata
     * - UoWQueueable.getFinalizerResult() - UoWResult with statistics, errors, messages
     *
     */
    public interface ITransactionFinalizer extends Finalizer {

        /**
         * Get finalizer name for logging and debugging
         * @return Finalizer name
         */
        String getName();

        // execute(FinalizerContext fc) is inherited from Finalizer interface
    }
}