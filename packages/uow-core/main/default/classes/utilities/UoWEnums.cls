//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Enumeration types for the UnitOfWork framework.
 * Contains all framework-wide enums for work types, operations, and modes.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Core
 * @see UoWRiskTypes
 */
public inherited sharing class UoWEnums {

    // ============================================================================
    // ENUMS - WORK TYPE
    // ============================================================================

    // Work types supported by the framework (in canonical order)
    // Order: DML → EVENT → FLOW → EMAIL → NOTIFICATION → CALLOUT
    public enum WorkType {
        DML,            // 1. Database operations
        EVENT,          // 2. Platform events
        FLOW,           // 3. Flow executions
        EMAIL,          // 4. Email sends
        NOTIFICATION,   // 5. Custom notifications
        CALLOUT         // 6. HTTP callouts
    }

    // ============================================================================
    // ENUMS - DML OPERATIONS
    // ============================================================================

    // DML operation types supported by the framework (in canonical order)
    // Order: INSERT → UPSERT → UPDATE → DELETE → UNDELETE
    public enum DmlOperation {
        INSERT_OP,      // 1. Create new records
        UPSERT_OP,      // 2. Insert or update based on external ID
        UPDATE_OP,      // 3. Modify existing records
        DELETE_OP,      // 4. Remove records (soft or hard delete)
        UNDELETE_OP     // 5. Restore deleted records
    }

    // Security enforcement modes for DML operations
    // ENFORCED: Strict CRUD/FLS enforcement using Security.stripInaccessible()
    // PERMISSIVE: No enforcement - for system context and trusted operations
    public enum SecurityMode {
        ENFORCED,           // Strict - enforce CRUD/FLS with stripInaccessible
        PERMISSIVE          // No enforcement - trusted system operations
    }

    // ============================================================================
    // ENUMS - ORCHESTRATION PHASES
    // ============================================================================

    // Transaction orchestration phases for state machine (coarse-grained)
    // Used by UoWTransactionStateService to manage transaction lifecycle
    // Canonical order (for understanding): NOT_STARTED → STARTED → POLICY_EVALUATION → RISK_ASSESSMENT
    //                                      → BEFORE_COMMIT → CALLOUTS → SAVEPOINT_CREATION
    //                                      → EXECUTING → AFTER_COMMIT → FINALIZING → COMPLETED
    // Exception flow: Any → ON_FAILURE → FINALIZING → COMPLETED
    public enum OrchestratorPhase {
        NOT_STARTED,           // Initial state
        STARTED,               // Begin Transaction
        POLICY_EVALUATION,     // Evaluating policies
        RISK_ASSESSMENT,       // Assessing risk
        BEFORE_COMMIT,         // onBeforeCommit plugins
        CALLOUTS,              // HTTP callouts (BEFORE savepoint - Salesforce limitation)
        SAVEPOINT_CREATION,    // Create savepoint
        EXECUTING,             // Executor running (PRE_DML → DML → POST_DML → ON_SUCCESS)
        AFTER_COMMIT,          // onAfterCommit plugins
        ON_FAILURE,            // Exception handling phase
        FINALIZING,            // onFinally phase
        COMPLETED              // Transaction complete (terminal state)
    }

    // Work execution phases for non-DML work items (fine-grained)
    // Determines WHEN work items (events, emails, flows, notifications, callouts) execute
    // Used by work item executors to schedule execution relative to DML operations
    //
    // CALLOUT RESTRICTIONS (Salesforce platform limitation):
    // Callouts only support PRE_DML and ON_FAILURE phases because:
    // - Cannot make callouts after Database.setSavepoint() is called
    // - Cannot make callouts after DML commits (POST_DML/ON_SUCCESS/ON_FINALIZATION impossible)
    // Attempting to register a callout with unsupported phases throws UoWException at registration time.
    public enum WorkPhase {
        PRE_DML,            // Before DML operations (callouts: before savepoint)
        POST_DML,           // After DML operations (NOT supported for callouts)
        ON_SUCCESS,         // Only if transaction succeeds (NOT supported for callouts)
        ON_FAILURE,         // Only if transaction fails (callouts: after rollback + savepoint release)
        ON_FINALIZATION     // Always executes (NOT supported for callouts)
    }

    // ============================================================================
    // ENUMS - TRANSACTION STATUS
    // ============================================================================

    // Commit strategies for transaction execution
    public enum CommitMode {
        SYNC,               // Synchronous execution (default)
        ASYNC               // Asynchronous via Queueable
    }

    // Transaction status lifecycle states (in lifecycle order)
    // Maps directly to TransactionStatus__c picklist field on UoWAuditTransaction__c
    // Order: IN_PROGRESS → ENQUEUED → PENDING_APPROVAL → APPROVED → SUCCESS/PARTIAL_SUCCESS/FAILED/ROLLED_BACK → REJECTED → DENIED_BY_POLICY → SKIPPED
    public enum TransactionStatus {
        IN_PROGRESS,        // 1. Transaction is currently executing
        ENQUEUED,           // 2. Transaction successfully enqueued for async execution
        PENDING_APPROVAL,   // 3. Awaiting human approval
        APPROVED,           // 4. Approved by human/system (continuation)
        SUCCESS,            // 5. All operations completed successfully
        PARTIAL_SUCCESS,    // 6. Some operations succeeded, others failed
        FAILED,             // 7. Transaction failed with errors
        ROLLED_BACK,        // 8. Transaction was rolled back due to errors
        REJECTED,           // 9. Rejected by human reviewer
        DENIED_BY_POLICY,   // 10. Blocked by policy evaluation
        SKIPPED             // 11. No work items registered (empty plan)
    }

    // Work status lifecycle states
    // Maps directly to WorkItemStatus__c picklist field on UoWAuditWorkItem__c
    public enum WorkStatus {
        REGISTERED,         // Work Registered
        SUCCESS,            // Work executed successfully
        PARTIAL_SUCCESS,    // Some operations succeeded, others failed
        FAILED,             // Work failed with errors
        SKIPPED,            // Work intentionally skipped (phase condition not met)
        NOT_EXECUTED        // Work not executed (unexpected - should have run but didn't)
    }

    // Transaction completion paths
    // Used to track how a transaction completed (full execution vs early completion scenarios)
    public enum TransactionCompletionPath {
        FULL_EXECUTION,     // Complete execution through all phases (normal path)
        EMPTY_PLAN,         // No work items to execute (minimal finalization)
        ASYNC_ENQUEUED,     // Enqueued for async execution (partial finalization)
        APPROVAL_DEFERRED   // Deferred pending approval (partial finalization)
    }

    // ============================================================================
    // ENUMS - PLUGIN SYSTEM
    // ============================================================================

    // Plugin execution categories
    // Used to control plugin execution order and lifecycle
    public enum PluginCategory {
        STANDARD,           // Standard plugins (idempotency, security, etc.) - execute first
        AUDIT,              // Audit/logging plugins - execute last after final status is set
        APPROVAL,           // Approval services - manage approval workflow lifecycle
        CUSTOM              // Custom user plugins - execute in between
    }

    // ============================================================================
    // ENUMS - POLICY SYSTEM
    // ============================================================================

    // Policy evaluation actions (in severity order: least → most restrictive)
    // Order: ALLOW → ALLOW_WITH_JUSTIFICATION → REQUIRE_TRACING → REQUIRE_MASKING → REQUIRE_APPROVAL → DENY
    public enum PolicyAction {
        ALLOW,                      // 1. Proceed normally (least restrictive)
        ALLOW_WITH_JUSTIFICATION,   // 2. Log warning/justification
        REQUIRE_TRACING,            // 3. Force tracing on for this transaction
        REQUIRE_MASKING,            // 4. Require masking of sensitive data
        REQUIRE_APPROVAL,           // 5. Human approval needed
        DENY                        // 6. Block operation (most restrictive)
    }

    // Policy execution categories
    // Used to categorize policies by their purpose and sensitivity
    public enum PolicyCategory {
        SECURITY,           // Security policies (authorization, access control)
        COMPLIANCE,         // Compliance policies (regulatory, audit requirements)
        DATA_QUALITY,       // Data quality policies (validation, integrity)
        BUSINESS_RULES,     // Business rule policies (workflow, approval)
        ANALYTICS,          // Analytics policies (recommendations, insights)
        CUSTOM              // Custom user policies
    }

    // ============================================================================
    // ENUMS - SAMPLING
    // ============================================================================

    public enum SamplingStrategy {
        FIRST_N,
        LAST_N,
        RANDOM,
        NONE        // No record capture (disables snapshot sampling and record-index reverse lookup)
    }

    // ============================================================================
    // ENUMS - TRACING (OPENTELEMETRY)
    // ============================================================================

    // Span phases for OpenTelemetry tracing and performance profiling (very fine-grained)
    // Used by UoWTracer to create spans for detailed observability
    // Follows OpenTelemetry semantic conventions for distributed tracing
    public enum SpanPhase {
        // Transaction lifecycle
        TRANSACT,

        // Policy and Planning
        POLICY_EVALUATION,
        POLICY_ACTIONS,
        RISK_ASSESSMENT,

        // Approval phases
        APPROVAL_REQUEST,
        APPROVAL_PENDING,
        APPROVAL_GRANTED,
        APPROVAL_DENIED,
        APPROVAL_SKIP,

        // Plugin phases
        PLUGINS_BEFORE_COMMIT,
        PLUGINS_AFTER_COMMIT,
        PLUGINS_ERROR,
        PLUGINS_FINALLY,
        PLUGINS_AUDIT,              // Audit plugins (run last after final status is set)

        // Pre-DML phases
        PRE_DML,
        VALIDATION,
        SECURITY_CHECK,

        // Execution phases
        EXECUTION,

        // DML phases (in canonical DML operation order)
        DML_EXECUTION,
        DEPENDENCY_GRAPH,
        DEPENDENCY_RESOLUTION,
        DML_INSERT,         // 1. Insert operations
        DML_UPSERT,         // 2. Upsert operations
        DML_UPDATE,         // 3. Update operations
        DML_DELETE,         // 4. Delete operations
        DML_UNDELETE,       // 5. Undelete operations

        // Post-DML phases
        POST_DML,

        // Savepoint phase
        SAVEPOINT,          // Transaction savepoint creation

        // Communication phases (in canonical work type order)
        EVENTS,             // 2. Platform events
        FLOWS,              // 3. Flow executions
        EMAILS,             // 4. Email sends
        NOTIFICATIONS,      // 5. Custom notifications
        PRE_DML_CALLOUTS,   // 6a. HTTP callouts - Pre-DML phase (before savepoint)
        ON_FAILURE_CALLOUTS, // 6b. HTTP callouts - On Failure phase (after rollback)

        // Finalization phases
        ON_SUCCESS,
        EXCEPTION_HANDLING,     // Outer span for exception handling flow
        ON_FAILURE,             // Inner span for ON_FAILURE phase work types
        ON_FINALIZATION,

        // Async phases
        ASYNC_QUEUED
        // Note: Work item spans use SpanSubType.WORK_ITEM with WorkType directly,
        // no longer need WORK_ITEM_* SpanPhase values
    }

    // Phase categories for grouping related phases
    public enum PhaseCategory {
        TRANSACT,       // Overall transaction lifecycle
        POLICY,         // Policy evaluation and compliance
        RISK,           // Risk assessment
        APPROVAL,       // Approval workflow
        PLUGIN,         // Plugin execution
        VALIDATION,     // Data Validation
        SECURITY,       // Security checks
        DML,            // DML operations
        CALLOUT,        // HTTP callouts
        PLATFORM_EVENT, // Platform events
        EMAIL,          // Email sending
        NOTIFICATION,   // Custom notifications
        FLOW,           // Flow execution
        WORK_PHASE,     // Execution phase hooks (PRE_DML, POST_DML, ON_SUCCESS, ON_FAILURE, ON_FINALIZATION)
        ERROR,      // Exception Handling
        FINALIZATION    // Cleanup and finalization
    }

    // Event types for tracing (OpenTelemetry-compatible)
    public enum SpanEventType {
        SPAN,          // Long running span (OTel: span with duration)
        EVENT          // Instant event within span (OTel: span event)
    }

    // Span subtypes - UoW-specific classification layered on OTel spans
    // Determines which result enum applies to a span
    public enum SpanSubType {
        PHASE,          // Framework phase span (policy, risk, plugins, work phases)
        WORK_ITEM       // User-registered work item span (DML, event, email, etc.)
    }

    // Result for PHASE subtype spans
    // Used when ending a phase span to indicate outcome
    // NOT_APPLICABLE phases are filtered from timeline serialization
    public enum SpanPhaseResult {
        SUCCESS,            // Phase executed with work
        FAILED,             // Phase execution failed
        NOT_APPLICABLE      // Phase had nothing to execute (no plugins, no assessor, no work items)
    }
    // Note: WORK_ITEM subtype spans use WorkStatus enum for their result

    // ============================================================================
    // STATIC CONSTANTS - SPAN PHASE MAPPINGS
    // ============================================================================

    // Phase category mapping - maps span phases to their categories
    public static final Map<SpanPhase, PhaseCategory> SPAN_TO_CATEGORY = new Map<SpanPhase, PhaseCategory>{
        // Transaction lifecycle
        SpanPhase.TRANSACT => PhaseCategory.TRANSACT,

        // Policy and Planning
        SpanPhase.POLICY_EVALUATION => PhaseCategory.POLICY,
        SpanPhase.POLICY_ACTIONS => PhaseCategory.POLICY,
        SpanPhase.RISK_ASSESSMENT => PhaseCategory.RISK,

        // Approval phases
        SpanPhase.APPROVAL_REQUEST => PhaseCategory.APPROVAL,
        SpanPhase.APPROVAL_PENDING => PhaseCategory.APPROVAL,
        SpanPhase.APPROVAL_GRANTED => PhaseCategory.APPROVAL,
        SpanPhase.APPROVAL_DENIED => PhaseCategory.APPROVAL,
        SpanPhase.APPROVAL_SKIP => PhaseCategory.APPROVAL,

        // Plugin phases
        SpanPhase.PLUGINS_BEFORE_COMMIT => PhaseCategory.PLUGIN,
        SpanPhase.PLUGINS_AFTER_COMMIT => PhaseCategory.PLUGIN,
        SpanPhase.PLUGINS_ERROR => PhaseCategory.PLUGIN,
        SpanPhase.PLUGINS_FINALLY => PhaseCategory.PLUGIN,
        SpanPhase.PLUGINS_AUDIT => PhaseCategory.PLUGIN,

        // Validation and Security phases
        SpanPhase.VALIDATION => PhaseCategory.VALIDATION,
        SpanPhase.SECURITY_CHECK => PhaseCategory.SECURITY,

        // Execution phases
        SpanPhase.EXECUTION => PhaseCategory.TRANSACT,

        // Savepoint phase
        SpanPhase.SAVEPOINT => PhaseCategory.TRANSACT,

        // DML phases
        SpanPhase.DML_EXECUTION => PhaseCategory.DML,
        SpanPhase.DEPENDENCY_GRAPH => PhaseCategory.DML,
        SpanPhase.DEPENDENCY_RESOLUTION => PhaseCategory.DML,
        SpanPhase.DML_INSERT => PhaseCategory.DML,
        SpanPhase.DML_UPSERT => PhaseCategory.DML,
        SpanPhase.DML_UPDATE => PhaseCategory.DML,
        SpanPhase.DML_DELETE => PhaseCategory.DML,
        SpanPhase.DML_UNDELETE => PhaseCategory.DML,

        // Communication phases (in canonical work type order)
        SpanPhase.EVENTS => PhaseCategory.PLATFORM_EVENT,
        SpanPhase.FLOWS => PhaseCategory.FLOW,
        SpanPhase.EMAILS => PhaseCategory.EMAIL,
        SpanPhase.NOTIFICATIONS => PhaseCategory.NOTIFICATION,
        SpanPhase.PRE_DML_CALLOUTS => PhaseCategory.CALLOUT,
        SpanPhase.ON_FAILURE_CALLOUTS => PhaseCategory.CALLOUT,

        // Work phase hooks (non-DML work type execution phases)
        SpanPhase.PRE_DML => PhaseCategory.WORK_PHASE,
        SpanPhase.POST_DML => PhaseCategory.WORK_PHASE,
        SpanPhase.ON_SUCCESS => PhaseCategory.WORK_PHASE,
        SpanPhase.ON_FAILURE => PhaseCategory.WORK_PHASE,
        SpanPhase.ON_FINALIZATION => PhaseCategory.WORK_PHASE,

        // Exception handling
        SpanPhase.EXCEPTION_HANDLING => PhaseCategory.ERROR,

        // Async phases
        SpanPhase.ASYNC_QUEUED => PhaseCategory.TRANSACT
        // Note: Work item spans derive category from WorkType directly via getCategoryForWorkType()
    };

    // DML operation to span phase mapping (in canonical DML operation order)
    public static final Map<DmlOperation, SpanPhase> DML_OP_TO_SPAN = new Map<DmlOperation, SpanPhase>{
        DmlOperation.INSERT_OP => SpanPhase.DML_INSERT,
        DmlOperation.UPSERT_OP => SpanPhase.DML_UPSERT,
        DmlOperation.UPDATE_OP => SpanPhase.DML_UPDATE,
        DmlOperation.DELETE_OP => SpanPhase.DML_DELETE,
        DmlOperation.UNDELETE_OP => SpanPhase.DML_UNDELETE
    };

}