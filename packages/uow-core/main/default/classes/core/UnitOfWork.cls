//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Main UnitOfWork class providing fluent API for transaction orchestration.
 * Enterprise-grade transaction management with agent support, policies, and observability.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Core
 * @see UoWContext
 * @see UoWPlan
 * @see UoWResult
 *
 * @example Basic DML:
 * UnitOfWork uow = new UnitOfWork();
 * uow.registerInsert(acc);
 * uow.registerInsert(contacts);
 * uow.commitWork();
 *
 * @example DML with relationships:
 * UnitOfWork uow = new UnitOfWork();
 * Account acc = new Account(Name = 'Test');
 * Contact con = new Contact(LastName = 'Smith');
 * uow.registerInsert(acc);
 * uow.registerInsert(con);
 * uow.relate(con, Contact.AccountId, acc);
 * uow.commitWork();
 *
 * @example Update and delete operations:
 * UnitOfWork uow = new UnitOfWork();
 * uow.registerUpdate(existingAccount);
 * uow.registerDelete(oldContact);
 * uow.commitWork();
 *
 * @example Upsert with external ID:
 * UnitOfWork uow = new UnitOfWork();
 * uow.registerUpsert(accounts, Account.ExternalId__c);
 * uow.commitWork();
 *
 * @example Publishing platform events:
 * UnitOfWork uow = new UnitOfWork();
 * uow.registerPlatformEvent(myEvent);  // Default: POST_DML
 * uow.commitWork();
 *
 * @example Sending emails:
 * UnitOfWork uow = new UnitOfWork();
 * Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
 * email.setToAddresses(new List<String>{'user@example.com'});
 * email.setSubject('Test');
 * uow.registerEmail(email);  // Default: ON_SUCCESS
 * uow.commitWork();
 *
 * @example Making callouts:
 * UnitOfWork uow = new UnitOfWork();
 * uow.registerCallout('callout:MyNamedCredential/endpoint', 'POST')
 *    .withBody(JSON.serialize(data))
 *    .withHeader('Content-Type', 'application/json');
 * uow.commitWork();
 *
 * @example Sending custom notifications:
 * UnitOfWork uow = new UnitOfWork();
 * uow.registerNotification()  // Default: ON_SUCCESS
 *    .withNotificationType(myNotificationTypeId, 'MyNotificationType')
 *    .withRecipients(new Set<String>{ UserInfo.getUserId() })
 *    .withTitle('Record Created')
 *    .withBody('Your record has been created')
 *    .withTargetId(recordId);
 * uow.commitWork();
 *
 * @example Executing flows:
 * UnitOfWork uow = new UnitOfWork();
 * uow.registerFlowExecution('MyFlowApiName')  // Default: POST_DML
 *    .withInput('recordId', accountId)
 *    .withInput('status', 'Active');
 * uow.commitWork();
 *
 * @example Agent-aware usage with configuration:
 * UnitOfWork uow = new UnitOfWork()
 *    .withConfiguration('Agent')
 *    .withAgent(agentContext)
 *    .withRisk(UoWRiskTypes.RiskLevel.MEDIUM)
 *    .asDryRun();
 * uow.registerInsert(records);
 * UoWResult result = uow.commitWork();
 *
 * @example Complex transaction with multiple work types:
 * UnitOfWork uow = new UnitOfWork();
 * Account acc = new Account(Name = 'Test');
 * uow.registerInsert(acc);
 * uow.registerInsert(contacts);
 * uow.relate(contacts, Contact.AccountId, acc);
 * uow.registerUpdate(existingOpportunity);
 * uow.registerPlatformEvent(accountEvent);  // Default: POST_DML
 * uow.registerEmail(notificationEmail);  // Default: ON_SUCCESS
 * uow.registerCallout('callout:ExternalSystem/notify', 'POST')
 *    .withBody(JSON.serialize(acc));
 * UoWResult result = uow.commitWork();
 *
 * @example Explicit relationship registration:
 * UnitOfWork uow = new UnitOfWork();
 * uow.registerInsert(acc);
 * uow.registerInsert(con);
 * uow.relate(con, Contact.AccountId, acc);  // Explicit relationship
 * uow.commitWork();
 */
public inherited sharing class UnitOfWork {

    // ============================================================================
    // PRIVATE FIELDS - CORE
    // ============================================================================

    private UoWPlan plan;
    private UoWContext context;
    private Boolean isCommitted;

    // ============================================================================
    // CONSTRUCTORS (with auto-detection)
    // ============================================================================

    /**
     * Constructor with configuration - auto-detects ambient context.
     *
     * @param configurationName Configuration name from UoWConfiguration__mdt (null for default)
     */
    public UnitOfWork(String configurationName) {
        this(configurationName, (UoWTransactionState) null);
    }

    /**
     * Constructor with configuration and explicit transaction state.
     * Auto-detection only occurs if state is null AND inside a UoW transaction.
     *
     * @param configurationName Configuration name (null for default)
     * @param state Transaction state from parent transaction (null for auto-detect)
     */
    public UnitOfWork(String configurationName, UoWTransactionState state) {
        this.plan = new UoWPlan();
        this.context = new UoWContext(configurationName);
        this.isCommitted = false;

        // Determine correlation source
        UoWTransactionState effectiveState = state;

        if (effectiveState == null && UoWTransactionState.hasCurrent()) {
            // Auto-detect: inherit from ambient context
            effectiveState = UoWTransactionState.getCurrent();
        }

        // Apply state if available
        if (effectiveState != null) {
            effectiveState.applyTo(this);
        }

        // Log: Transaction initialized
        String configName = configurationName ?? 'Default';
        String parentInfo = effectiveState != null ?
            ', inherited from: ' + effectiveState.transactionId : '';
        context.fine(String.format('UnitOfWork initialized with configuration: {0}, transactionId: {1}{2}',
            new String[]{ configName, context.transactionId, parentInfo }), 'UnitOfWork');
    }

    /**
     * Constructor for async execution (used by UoWQueueable).
     * Internal use only - bypasses auto-detection.
     *
     * @param ctx Deserialized context
     * @param plan Deserialized plan
     */
    public UnitOfWork(UoWContext ctx, UoWPlan plan) {
        this.context = ctx;
        this.plan = plan;
        this.isCommitted = false;
    }

    /**
     * Opt-out: explicitly start as root transaction.
     * Ignores ambient context and creates fresh correlationId.
     * Use when you explicitly want to start a new correlation chain.
     *
     * @return This UnitOfWork for fluent chaining
     *
     * @example Start a new independent transaction chain
     * UnitOfWork uow = new UnitOfWork().asRoot();
     */
    public UnitOfWork asRoot() {
        this.context.inheritCorrelation(UoWUtils.generateUUID(), null, -1);
        return this;
    }

    // ============================================================================
    // PUBLIC API - CONTEXT ACCESS
    // ============================================================================

    /**
     * Get the execution context for this UnitOfWork.
     *
     * @return The UoWContext instance
     */
    public UoWContext getContext() {
        return this.context;
    }

    /**
     * Get the execution plan.
     *
     * @return UoWPlan instance
     */
    public UoWPlan getPlan() {
        return this.plan;
    }

    // ============================================================================
    // PUBLIC API - CONTEXT CONFIGURATION
    // ============================================================================

    /**
     * Configure agent context.
     *
     * @param agentCtx Agent context information
     * @return This UnitOfWork instance
     */
    public UnitOfWork withAgent(UoWContext.AgentContext agentCtx) {
        context.withAgent(agentCtx);
        return this;
    }

    /**
     * Enable dry run mode (preview without committing).
     *
     * @return This UnitOfWork instance
     */
    public UnitOfWork asDryRun() {
        context.isDryRun = true;
        return this;
    }

    /**
     * Set the business scenario for this transaction.
     * Used for categorizing and filtering audit transactions by business context.
     *
     * @param scenarioName The scenario name (e.g., 'Standard Mortgage', 'High Loan Amount')
     * @return This UnitOfWork instance
     */
    public UnitOfWork setScenario(String scenarioName) {
        context.scenarioName = scenarioName;
        return this;
    }

    /**
     * Set a description for this transaction.
     * Provides context about what this transaction does in audit views.
     *
     * @param description Brief description (e.g., 'Create loan application with documents')
     * @return This UnitOfWork instance
     */
    public UnitOfWork setDescription(String description) {
        context.description = description;
        return this;
    }

    // ============================================================================
    // PUBLIC API - EXTENSIBILITY CONFIGURATION (Canonical Order)
    // ============================================================================

    /**
     * Add a plugin for this transaction.
     *
     * @param plugin The plugin implementation
     * @return This UnitOfWork instance
     */
    public UnitOfWork withPlugin(UoWInterfaces.IPlugin plugin) {
        context.getFeatureSettings().addResolvedPlugin(plugin);
        return this;
    }

    /**
     * Disable a specific plugin for this transaction.
     *
     * @param pluginClassName The fully qualified plugin class name
     * @return This UnitOfWork instance
     */
    public UnitOfWork withoutPlugin(String pluginClassName) {
        context.getFeatureSettings().disablePlugin(pluginClassName);
        return this;
    }

    /**
     * Add a custom policy for this transaction.
     *
     * @param policy The policy implementation
     * @return This UnitOfWork instance
     */
    public UnitOfWork withPolicy(UoWInterfaces.IPolicy policy) {
        context.getFeatureSettings().addResolvedPolicy(policy);
        return this;
    }

    /**
     * Override DML strategy for a specific object type.
     *
     * @param objectType The SObject type
     * @param strategy The DML strategy implementation
     * @return This UnitOfWork instance
     */
    public UnitOfWork withDmlStrategy(Schema.SObjectType objectType, UoWInterfaces.IDmlStrategy strategy) {
        context.getFeatureSettings().setResolvedDmlStrategy(objectType, strategy);
        return this;
    }

    /**
     * Override risk assessor for this transaction.
     *
     * @param assessor The risk assessor implementation
     * @return This UnitOfWork instance
     */
    public UnitOfWork withRiskAssessor(UoWInterfaces.IRiskAssessor assessor) {
        context.getFeatureSettings().setResolvedRiskAssessor(assessor);
        return this;
    }

    /**
     * Override event channel for this transaction.
     *
     * @param channel The event channel implementation
     * @return This UnitOfWork instance
     */
    public UnitOfWork withEventChannel(UoWInterfaces.IEventChannel channel) {
        context.getFeatureSettings().setResolvedEventChannel(channel);
        return this;
    }

    /**
     * Override email channel for this transaction.
     *
     * @param channel The email channel implementation
     * @return This UnitOfWork instance
     */
    public UnitOfWork withEmailChannel(UoWInterfaces.IEmailChannel channel) {
        context.getFeatureSettings().setResolvedEmailChannel(channel);
        return this;
    }

    /**
     * Override notification channel for this transaction.
     *
     * @param channel The notification channel implementation
     * @return This UnitOfWork instance
     */
    public UnitOfWork withNotificationChannel(UoWInterfaces.INotificationChannel channel) {
        context.getFeatureSettings().setResolvedNotificationChannel(channel);
        return this;
    }

    /**
     * Override flow channel for this transaction.
     *
     * @param channel The flow channel implementation
     * @return This UnitOfWork instance
     */
    public UnitOfWork withFlowChannel(UoWInterfaces.IFlowChannel channel) {
        context.getFeatureSettings().setResolvedFlowChannel(channel);
        return this;
    }

    /**
     * Override callout strategy for this transaction.
     *
     * @param strategy The callout strategy implementation
     * @return This UnitOfWork instance
     */
    public UnitOfWork withCalloutStrategy(UoWInterfaces.ICalloutStrategy strategy) {
        context.getFeatureSettings().setResolvedCalloutStrategy(strategy);
        return this;
    }

    /**
     * Override approval channel for this transaction.
     *
     * @param channel The approval channel implementation
     * @return This UnitOfWork instance
     */
    public UnitOfWork withApprovalChannel(UoWInterfaces.IApprovalChannel channel) {
        context.getFeatureSettings().setResolvedApprovalChannel(channel);
        return this;
    }

    /**
     * Override transaction finalizer for this transaction.
     * The finalizer is attached to async executions and guaranteed to run
     * even on unhandled exceptions (platform guarantee via System.attachFinalizer).
     *
     * @param finalizer The transaction finalizer implementation
     * @return This UnitOfWork instance
     */
    public UnitOfWork withTransactionFinalizer(UoWInterfaces.ITransactionFinalizer finalizer) {
        context.getFeatureSettings().setResolvedTransactionFinalizer(finalizer);
        return this;
    }

    /**
     * Override event publish failure handler for this transaction.
     * The handler is called asynchronously in a separate transaction when
     * platform events fail to deliver after commit (PublishAfterCommit).
     *
     * @param handler The event publish failure handler implementation
     * @return This UnitOfWork instance
     */
    public UnitOfWork withEventPublishFailureHandler(UoWInterfaces.IEventPublishFailureHandler handler) {
        context.getFeatureSettings().setResolvedEventPublishFailureHandler(handler);
        return this;
    }

    // ============================================================================
    // PUBLIC API - TRACING CONFIGURATION
    // ============================================================================

    /**
     * Enable distributed tracing for this transaction (overrides configuration).
     *
     * @return This UnitOfWork instance
     *
     * @example Enable tracing for troubleshooting
     * UnitOfWork uow = new UnitOfWork()
     *     .enableTracing();  // Force tracing on regardless of configuration
     * UoWResult result = uow.commitWork();
     * UoWTracer.TraceSummary trace = result.getTraceSummary();
     */
    public UnitOfWork enableTracing() {
        context.getFeatureSettings().enableTracing();
        return this;
    }

    /**
     * Disable distributed tracing for this transaction (overrides configuration).
     *
     * @return This UnitOfWork instance
     *
     * @example Disable tracing for performance-critical transaction
     * UnitOfWork uow = new UnitOfWork()
     *     .disableTracing();  // Force tracing off regardless of configuration
     * uow.commitWork();
     */
    public UnitOfWork disableTracing() {
        context.getFeatureSettings().disableTracing();
        return this;
    }

    // ============================================================================
    // PUBLIC API - DML REGISTRATION
    // ============================================================================

    /**
     * Register a single record for insert.
     *
     * @param record Single record to insert
     * @return UoWDmlWorkItem for fluent chaining (continueOnError, failFast, etc.)
     */
    public UoWDmlWorkItem registerInsert(SObject record) {
        return this.registerInsert(new List<SObject>{ record });
    }

    /**
     * Register records for insert.
     *
     * @param records List of records to insert
     * @return UoWDmlWorkItem for fluent chaining (continueOnError, failFast, etc.)
     */
    public UoWDmlWorkItem registerInsert(List<SObject> records) {
        validateNotCommitted();
        return registerDmlWorkItem(records, UoWEnums.DmlOperation.INSERT_OP, null);
    }

    /**
     * Register a single record for upsert.
     *
     * @param record Single record to upsert
     * @param externalIdField External ID field for upsert
     * @return UoWDmlWorkItem for fluent chaining (continueOnError, etc.)
     */
    public UoWDmlWorkItem registerUpsert(SObject record, Schema.SObjectField externalIdField) {
        return this.registerUpsert(new List<SObject>{ record }, externalIdField);
    }

    /**
     * Register records for upsert.
     *
     * @param records List of records to upsert
     * @param externalIdField External ID field for upsert
     * @return UoWDmlWorkItem for fluent chaining (continueOnError, etc.)
     */
    public UoWDmlWorkItem registerUpsert(List<SObject> records, Schema.SObjectField externalIdField) {
        validateNotCommitted();
        return registerDmlWorkItem(records, UoWEnums.DmlOperation.UPSERT_OP, externalIdField);
    }

    /**
     * Register a single record for update.
     *
     * @param record Single record to update
     * @return UoWDmlWorkItem for fluent chaining (continueOnError, etc.)
     */
    public UoWDmlWorkItem registerUpdate(SObject record) {
        return this.registerUpdate(new List<SObject>{ record });
    }

    /**
     * Register records for update.
     *
     * @param records List of records to update
     * @return UoWDmlWorkItem for fluent chaining (continueOnError, etc.)
     */
    public UoWDmlWorkItem registerUpdate(List<SObject> records) {
        validateNotCommitted();
        return registerDmlWorkItem(records, UoWEnums.DmlOperation.UPDATE_OP, null);
    }

    /**
     * Register a single record for delete.
     *
     * @param record Single record to delete
     * @return UoWDmlWorkItem for fluent chaining (continueOnError, etc.)
     */
    public UoWDmlWorkItem registerDelete(SObject record) {
        return this.registerDelete(new List<SObject>{ record });
    }

    /**
     * Register records for delete.
     *
     * @param records List of records to delete
     * @return UoWDmlWorkItem for fluent chaining (continueOnError, etc.)
     */
    public UoWDmlWorkItem registerDelete(List<SObject> records) {
        validateNotCommitted();
        return registerDmlWorkItem(records, UoWEnums.DmlOperation.DELETE_OP, null);
    }

    /**
     * Register a single record for undelete.
     *
     * @param record Single record to undelete
     * @return UoWDmlWorkItem for fluent chaining (continueOnError, etc.)
     */
    public UoWDmlWorkItem registerUndelete(SObject record) {
        return this.registerUndelete(new List<SObject>{ record });
    }

    /**
     * Register records for undelete.
     *
     * @param records List of records to undelete
     * @return UoWDmlWorkItem for fluent chaining (continueOnError, etc.)
     */
    public UoWDmlWorkItem registerUndelete(List<SObject> records) {
        validateNotCommitted();
        return registerDmlWorkItem(records, UoWEnums.DmlOperation.UNDELETE_OP, null);
    }

    // ============================================================================
    // PUBLIC API - PLATFORM EVENT REGISTRATION
    // ============================================================================

    /**
     * Register a platform event (defaults to POST_DML phase).
     *
     * @param event Single event to publish
     * @return UoWEventWorkItem for fluent chaining (continueOnError, etc.)
     */
    public UoWEventWorkItem registerPlatformEvent(SObject event) {
        return this.registerPlatformEvent(new List<SObject>{ event });
    }

    /**
     * Register platform events (defaults to POST_DML phase).
     *
     * @param events List of events to publish
     * @return UoWEventWorkItem for fluent chaining (continueOnError, etc.)
     */
    public UoWEventWorkItem registerPlatformEvent(List<SObject> events) {
        return this.registerPlatformEvent(events, null);
    }

    /**
     * Register a platform event with explicit phase.
     *
     * @param event Single event to publish
     * @param phase Execution phase (POST_DML, ON_SUCCESS, ON_FAILURE, ON_FINALIZATION)
     * @return UoWEventWorkItem for fluent chaining (continueOnError, etc.)
     */
    public UoWEventWorkItem registerPlatformEvent(SObject event, UoWEnums.WorkPhase phase) {
        return this.registerPlatformEvent(new List<SObject>{ event }, phase);
    }

    /**
     * Register platform events with explicit phase.
     *
     * @param events List of events to publish
     * @param phase Execution phase (POST_DML, ON_SUCCESS, ON_FAILURE, ON_FINALIZATION)
     * @return UoWEventWorkItem for fluent chaining (continueOnError, etc.)
     */
    public UoWEventWorkItem registerPlatformEvent(List<SObject> events, UoWEnums.WorkPhase phase) {
        validateNotCommitted();
        UoWExceptionService.requireNonEmpty(events, 'Events');

        Schema.SObjectType sType = events[0].getSObjectType();
        UoWEventWorkItem workItem = new UoWEventWorkItem(phase, sType, events);

        // Register with plan and return the actual work item in the plan
        // (may be existing if events consolidated into existing work item)
        UoWEventWorkItem actualWorkItem = plan.registerEventWork(workItem);
        return actualWorkItem;
    }

    // ============================================================================
    // PUBLIC API - FLOW REGISTRATION
    // ============================================================================

    /**
     * Register a flow execution (defaults to POST_DML phase).
     *
     * @param flowApiName Flow API name
     * @return UoWFlowWorkItem for fluent chaining (withInput, continueOnError, etc.)
     */
    public UoWFlowWorkItem registerFlowExecution(String flowApiName) {
        return this.registerFlowExecution(flowApiName, null);
    }

    /**
     * Register a flow execution with explicit phase.
     *
     * @param flowApiName Flow API name
     * @param phase Execution phase (PRE_DML, POST_DML, ON_SUCCESS, ON_FAILURE, ON_FINALIZATION)
     * @return UoWFlowWorkItem for fluent chaining (withInput, continueOnError, etc.)
     */
    public UoWFlowWorkItem registerFlowExecution(String flowApiName, UoWEnums.WorkPhase phase) {
        validateNotCommitted();
        UoWExceptionService.requireNonBlank(flowApiName, 'Flow API name');

        UoWFlowWorkItem workItem = new UoWFlowWorkItem(flowApiName, phase);
        plan.registerFlow(workItem);
        return workItem;
    }

    // ============================================================================
    // PUBLIC API - EMAIL REGISTRATION
    // ============================================================================

    /**
     * Register an email (defaults to ON_SUCCESS phase).
     *
     * @param email Single email to send
     * @return UoWEmailWorkItem for fluent chaining (continueOnError, etc.)
     */
    public UoWEmailWorkItem registerEmail(Messaging.Email email) {
        return this.registerEmail(new List<Messaging.Email>{ email });
    }

    /**
     * Register emails (defaults to ON_SUCCESS phase).
     *
     * @param emails List of emails to send
     * @return UoWEmailWorkItem for fluent chaining (continueOnError, etc.)
     */
    public UoWEmailWorkItem registerEmail(List<Messaging.Email> emails) {
        return this.registerEmail(emails, null);
    }

    /**
     * Register an email with explicit phase.
     *
     * @param email Single email to send
     * @param phase Execution phase (ON_SUCCESS, ON_FAILURE, ON_FINALIZATION)
     * @return UoWEmailWorkItem for fluent chaining (continueOnError, etc.)
     */
    public UoWEmailWorkItem registerEmail(Messaging.Email email, UoWEnums.WorkPhase phase) {
        return this.registerEmail(new List<Messaging.Email>{ email }, phase);
    }

    /**
     * Register emails with explicit phase.
     *
     * @param emails List of emails to send
     * @param phase Execution phase (ON_SUCCESS, ON_FAILURE, ON_FINALIZATION)
     * @return UoWEmailWorkItem for fluent chaining (continueOnError, etc.)
     */
    public UoWEmailWorkItem registerEmail(List<Messaging.Email> emails, UoWEnums.WorkPhase phase) {
        validateNotCommitted();
        UoWExceptionService.requireNonEmpty(emails, 'Emails');

        UoWEmailWorkItem workItem = new UoWEmailWorkItem(phase, emails);

        // Register with plan and return the actual work item in the plan
        // (may be existing if emails consolidated into existing work item)
        UoWEmailWorkItem actualWorkItem = plan.registerEmailWork(workItem);
        return actualWorkItem;
    }

    // ============================================================================
    // PUBLIC API - NOTIFICATION REGISTRATION
    // ============================================================================

    /**
     * Register a notification (defaults to ON_SUCCESS phase).
     *
     * @return UoWNotificationWorkItem for fluent chaining (withNotificationType, withRecipients, etc.)
     */
    public UoWNotificationWorkItem registerNotification() {
        return this.registerNotification(null);
    }

    /**
     * Register a notification with explicit phase.
     *
     * @param phase Execution phase (ON_SUCCESS, ON_FAILURE, ON_FINALIZATION)
     * @return UoWNotificationWorkItem for fluent chaining (withNotificationType, withRecipients, etc.)
     */
    public UoWNotificationWorkItem registerNotification(UoWEnums.WorkPhase phase) {
        validateNotCommitted();

        UoWNotificationWorkItem workItem = new UoWNotificationWorkItem(phase);
        plan.registerNotification(workItem);
        return workItem;
    }

    // ============================================================================
    // PUBLIC API - CALLOUT REGISTRATION
    // ============================================================================

    /**
     * Register an HTTP callout (defaults to GET method, PRE_DML phase).
     *
     * @param endpoint Callout endpoint URL
     * @return UoWCalloutWorkItem for fluent chaining (withMethod, withHeader, withBody, etc.)
     */
    public UoWCalloutWorkItem registerCallout(String endpoint) {
        return this.registerCallout(endpoint, 'GET');
    }

    /**
     * Register an HTTP callout with method (defaults to PRE_DML phase).
     *
     * @param endpoint Callout endpoint URL
     * @param method HTTP method (GET, POST, etc.)
     * @return UoWCalloutWorkItem for fluent chaining (withHeader, withBody, etc.)
     */
    public UoWCalloutWorkItem registerCallout(String endpoint, String method) {
        return this.registerCallout(endpoint, method, UoWEnums.WorkPhase.PRE_DML);
    }

    /**
     * Register an HTTP callout with method and execution phase.
     * RESTRICTION: Callouts only support PRE_DML and ON_FAILURE phases.
     * - PRE_DML: Executes before savepoint creation (standard callout timing)
     * - ON_FAILURE: Executes after rollback completes (for error notification/compensation)
     *
     * @param endpoint Callout endpoint URL
     * @param method HTTP method (GET, POST, etc.)
     * @param phase Execution phase (PRE_DML or ON_FAILURE only)
     * @return UoWCalloutWorkItem for fluent chaining (withHeader, withBody, etc.)
     * @throws UoWException if phase is not supported for callouts
     */
    public UoWCalloutWorkItem registerCallout(String endpoint, String method, UoWEnums.WorkPhase phase) {
        validateNotCommitted();

        UoWCalloutWorkItem workItem = new UoWCalloutWorkItem(endpoint, method, phase);
        plan.registerCallout(workItem);
        return workItem;
    }

    // ============================================================================
    // PUBLIC API - RELATIONSHIP REGISTRATION
    // ============================================================================

    /**
     * Register a relationship between child and parent records.
     * The framework resolves the parent ID and populates the child's lookup field before DML.
     *
     * @param child Child record
     * @param relationshipField Lookup/Master-Detail field on child pointing to parent
     * @param parent Parent record
     * @return This UnitOfWork instance for fluent chaining
     *
     * @example
     * uow.registerInsert(acc);
     * uow.registerInsert(con);
     * uow.relate(con, Contact.AccountId, acc);
     */
    public UnitOfWork relate(SObject child, Schema.SObjectField relationshipField, SObject parent) {
        validateNotCommitted();
        plan.registerRelationship(child, relationshipField, parent);
        return this;
    }

    /**
     * Register relationships between multiple children and a single parent.
     * Uses bulk registration for O(1) describe calls regardless of list size.
     *
     * @param children List of child records
     * @param relationshipField Lookup/Master-Detail field on child pointing to parent
     * @param parent Parent record
     * @return This UnitOfWork instance for fluent chaining
     *
     * @example
     * uow.registerInsert(acc);
     * uow.registerInsert(contacts);
     * uow.relate(contacts, Contact.AccountId, acc);
     */
    public UnitOfWork relate(List<SObject> children, Schema.SObjectField relationshipField, SObject parent) {
        validateNotCommitted();
        plan.registerRelationship(children, relationshipField, parent);
        return this;
    }

    // ============================================================================
    // PUBLIC API - COMMIT
    // ============================================================================

    /**
     * Commit the unit of work with default SYNC strategy.
     *
     * @return Execution result
     */
    public UoWResult commitWork() {
        return commitWork(UoWEnums.CommitMode.SYNC);
    }

    /**
     * Commit the unit of work with specified strategy.
     *
     * @param mode Commit mode (SYNC or ASYNC)
     * @return Execution result (or partial result for async strategy)
     */
    public UoWResult commitWork(UoWEnums.CommitMode mode) {
        validateNotCommitted();
        logCommitStarted(mode);

        UoWResult result = new UoWResult(context).withCommitMode(mode);
        UoWTransactionStateService stateService = new UoWTransactionStateService();

        Boolean executionSuccess = false;
        Exception caughtException = null;

        try {
            stateService.beginTransaction(context, plan, result);

            // Check for early exit conditions (empty plan, async enqueue)
            if (checkEarlyExitConditions(stateService, mode)) {
                return result;
            }

            // Execute main transaction phases
            if (executeTransactionPhases(stateService, result)) {
                executionSuccess = true;
            }

        } catch (Exception ex) {
            executionSuccess = false;
            caughtException = ex;
            stateService.handleException(ex);

        } finally {
            finalizeCommit(stateService, executionSuccess, caughtException);
        }

        return result;
    }

    // ============================================================================
    // PRIVATE HELPER METHODS - COMMIT ORCHESTRATION
    // ============================================================================

    // Log transaction commit started with mode and work item count
    private void logCommitStarted(UoWEnums.CommitMode mode) {
        Integer totalWorkItems = plan.getPlannedDmlWork().size() + plan.getPlannedCalloutWork().size();
        context.info(String.format('Transaction commit started - Mode: {0}, DryRun: {1}, Work items: {2}',
            new String[]{
                String.valueOf(mode),
                String.valueOf(context.isDryRun),
                String.valueOf(totalWorkItems)
            }), 'UnitOfWork');
    }

    // Check for early exit conditions that short-circuit normal execution
    private Boolean checkEarlyExitConditions(UoWTransactionStateService stateService, UoWEnums.CommitMode mode) {
        // Empty plan - prepare for finalization and exit
        if (plan.isEmpty()) {
            stateService.prepareEmptyPlanTransaction();
            return true;
        }

        // Async enqueue - enqueue job and exit (only if NOT already async child)
        if (mode == UoWEnums.CommitMode.ASYNC && !context.isAsyncChild()) {
            stateService.enqueueAsync();
            return true;
        }

        return false;
    }

    // Execute the main transaction phases (policy, risk, DML, plugins)
    private Boolean executeTransactionPhases(UoWTransactionStateService stateService, UoWResult result) {
        // Phase 1: Policy evaluation and control actions
        stateService.evaluatePolicies();
        stateService.processControlPolicyActions();

        // Phase 2: Risk assessment
        stateService.assessRisk();

        // Phase 3: Approval check - exit if approval required
        if (result.checkIfApprovalRequired()) {
            stateService.requestApproval();
            return false;  // Not a failure, but execution didn't complete normally
        }

        // Phase 4: Pre-DML (plugins, callouts, savepoint)
        stateService.executeBeforeCommit();
        stateService.executePreDmlCallouts();
        stateService.createSavepoint();

        // Phase 5: DML execution
        stateService.executeTransaction();

        // Phase 6: Post-DML plugins
        stateService.executeAfterCommit();

        return true;
    }

    // Finalize the commit - cleanup, status determination, re-throw if configured
    private void finalizeCommit(UoWTransactionStateService stateService, Boolean executionSuccess, Exception caughtException) {
        stateService.finalizeTransaction(executionSuccess);
        isCommitted = true;

        // Re-throw exception if configured AND transaction failed
        if (!executionSuccess && caughtException != null && context.getFeatureSettings().configuration?.RethrowTransactionExceptions__c) {
            throw caughtException;
        }
    }

    // ============================================================================
    // PRIVATE HELPER METHODS - VALIDATION
    // ============================================================================

    // Validate that the UnitOfWork has not already been committed
    private void validateNotCommitted() {
        UoWExceptionService.require(!isCommitted, System.Label.UoW_Error_AlreadyCommitted);
    }

    // Internal helper to create and register DML work items
    // PERFORMANCE: Uses lazy error message evaluation and checks for existing work item
    // BEFORE creating a new one to avoid unnecessary object allocations.
    private UoWDmlWorkItem registerDmlWorkItem(List<SObject> records, UoWEnums.DmlOperation operation, Schema.SObjectField externalIdField) {
        UoWExceptionService.requireNonEmpty(records, 'Records');

        // Validate all records are same SObjectType
        // PERFORMANCE: Lazy error message evaluation - only format on error
        Schema.SObjectType stype = records[0].getSObjectType();
        for (SObject record : records) {
            if (record.getSObjectType() != stype) {
                throw new UoWExceptionService.UoWException(
                    String.format(
                        'All records must be of the same SObjectType. Expected: {0}, Got: {1}',
                        new String[]{
                            UoWCacheService.getDescribe(stype).getName(),
                            UoWCacheService.getDescribe(record.getSObjectType()).getName()
                        }
                    )
                );
            }
        }

        // Get type name once - reused for consolidation check and work item creation
        String typeName = UoWCacheService.getDescribe(stype).getName();

        // PERFORMANCE: Check for existing work item BEFORE creating a new one.
        // This avoids creating and immediately discarding temporary work items
        // when consolidating records into an existing work item.
        UoWDmlWorkItem existingWorkItem = plan.getExistingDmlWork(typeName, operation);
        if (existingWorkItem != null) {
            existingWorkItem.addRecords(records);
            return existingWorkItem;
        }

        // Create new work item only if no existing one for this type/operation
        UoWDmlWorkItem workItem = new UoWDmlWorkItem(operation, stype, records);

        // Set external ID field for upsert
        if (externalIdField != null) {
            workItem.externalIdField = externalIdField;
            workItem.externalIdFieldName = UoWCacheService.getFieldDescribe(externalIdField).getName();
        }

        // Register with plan
        plan.registerDmlWork(workItem);

        return workItem;
    }

}