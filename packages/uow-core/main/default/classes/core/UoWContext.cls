//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Execution context for a UnitOfWork transaction.
 * Contains runtime state, configuration, and execution metadata.
 *
 * Session information is captured at construction time and stored in serializable
 * SessionSnapshot for async execution persistence. Live session context is available
 * via getSessionContext() for additional details not stored in snapshot.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Core
 * @see UnitOfWork
 * @see UoWResult
 * @see UoWFeatureSettings
 * @see UoWSessionContext
 */
public inherited sharing class UoWContext {

    // ============================================================================
    // PRIVATE PROPERTIES
    // ============================================================================

    private UoWFeatureSettings featureSettings;
    private List<UoWMessage> messages;

    // ============================================================================
    // PUBLIC PROPERTIES - TRANSACTION IDENTITY
    // ============================================================================

    // Internal transaction identifier (TXN-timestamp-random) - for internal tracking
    public String transactionId { get; private set; }
    // Distributed correlation identifier (UUID) - for external tracing and async linking
    public String correlationId { get; private set; }
    public String configurationName { get; private set; }
    public DateTime startedAt { get; private set; }

    // ============================================================================
    // PUBLIC PROPERTIES - EXECUTION STATE
    // ============================================================================

    public Boolean isDryRun;

    public String parentTransactionId { get; set; }
    public Integer asyncDepth { get; set; }

    public AgentContext agentContext { get; set; }

    public String scenarioName { get; set; }
    public String description { get; set; }

    public transient System.Savepoint transactionSavepoint { get; private set; }

    // ============================================================================
    // PUBLIC PROPERTIES - SESSION SNAPSHOT (serialized for async)
    // ============================================================================

    // Session snapshot captured at construction - persists through async serialization
    public SessionSnapshot sessionSnapshot { get; private set; }

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    public UoWContext(String configurationName) {
        // Transaction identity
        this.transactionId = UoWUtils.generateTransactionId();
        this.correlationId = UoWUtils.generateUUID();
        this.configurationName = configurationName;
        this.startedAt = DateTime.now();

        // Execution state
        this.isDryRun = false;
        this.asyncDepth = 0;

        // Initialize collections
        this.messages = new List<UoWMessage>();

        // Capture session snapshot (persists through async serialization)
        this.sessionSnapshot = new SessionSnapshot(UoWSessionContext.getInstance());

        // Load configuration
        loadFeatureSettings();
    }

    // ============================================================================
    // PUBLIC API - CONFIGURATION
    // ============================================================================

    /**
     * Load feature settings from configuration metadata.
     *
     * @throws UoWException if configuration loading fails (fail-fast principle)
     */
    public void loadFeatureSettings() {
        this.featureSettings = UoWFeatureSettings.loadFromConfiguration(this.configurationName);
    }

    /**
     * Get feature settings
     *
     * @return Current feature settings
     */
    public UoWFeatureSettings getFeatureSettings() {
        return this.featureSettings;
    }

    /**
     * Reload feature settings after async deserialization.
     * Resolves transient interface references (plugins, policies, strategies, channels)
     * and enum values from their stored string representations.
     * Call this at the start of async execution to restore full functionality.
     */
    public void reloadFeatureSettings() {
        if (this.featureSettings != null) {
            this.featureSettings.hydrate();
        }
    }

    // ============================================================================
    // PUBLIC API - SESSION CONTEXT
    // ============================================================================

    /**
     * Get session context containing user, organization, and auth information.
     * Session context is cached per transaction for efficiency.
     *
     * @return UoWSessionContext with user/org/auth details
     */
    public UoWSessionContext getSessionContext() {
        return UoWSessionContext.getInstance();
    }

    // ============================================================================
    // PUBLIC API - AGENT CONTEXT
    // ============================================================================

    /**
     * Set agent context
     *
     * @param agent Agent context to set
     * @return This context for fluent chaining
     */
    public UoWContext withAgent(UoWContext.AgentContext agent) {
        this.agentContext = agent;
        return this;
    }

    /**
     * Check if transaction is agent-initiated
     *
     * @return True if agent context is present
     */
    public Boolean isAgentTransaction() {
        return agentContext != null;
    }

    /**
     * Get agent confidence score
     *
     * @return Confidence score or null if not an agent transaction
     */
    public Decimal getAgentConfidence() {
        return isAgentTransaction() ? agentContext.confidenceScore : null;
    }

    // ============================================================================
    // PUBLIC API - ASYNC TRACKING
    // ============================================================================

    /**
     * Check if this transaction is an async child (has parent transaction)
     *
     * @return True if this is an async child execution (enqueued from parent), false otherwise
     */
    public Boolean isAsyncChild() {
        return String.isNotBlank(parentTransactionId);
    }

    /**
     * Establish async execution boundary by generating a new transaction ID.
     * Called when a queueable/batch job begins executing a serialized transaction.
     * Preserves the original transactionId as parentTransactionId for audit linking.
     * The correlationId remains unchanged for end-to-end distributed tracing.
     */
    public void establishAsyncExecutionBoundary() {
        this.parentTransactionId = this.transactionId;
        this.transactionId = UoWUtils.generateTransactionId();
        this.asyncDepth = (this.asyncDepth != null ? this.asyncDepth : 0) + 1;
    }

    // ============================================================================
    // PUBLIC API - TRANSACTION MANAGEMENT
    // ============================================================================

    /**
     * Create a database savepoint for potential rollback.
     * Savepoints are ALWAYS created (except in dry run mode) to enable:
     * - Transaction atomicity (rollback on failure)
     * - ON_FAILURE callouts (require savepoint release after rollback)
     * If savepoint creation fails, a warning message is logged but execution continues.
     */
    public void setSavePoint() {
        if (!this.isDryRun) {
            try {
                this.transactionSavepoint = Database.setSavepoint();
            } catch (Exception ex) {
                this.warn('[SAVEPOINT] Failed to create savepoint: ' + ex.getMessage());
            }
        }
    }

    // ============================================================================
    // PUBLIC API - MESSAGES
    // ============================================================================

    /**
     * Add a structured message.
     * Applies minimum logging level filtering based on configuration.
     *
     * @param message Message to add
     */
    public void addMessage(UoWMessage message) {
        System.LoggingLevel minLevel = this.getFeatureSettings().getMinimumLoggingLevel();
        if (message.loggingLevel.ordinal() >= minLevel.ordinal()) {
            this.messages.add(message);
        }
    }

    /**
     * Get all messages
     *
     * @return List of all messages
     */
    public List<UoWMessage> getMessages() {
        return this.messages;
    }

    /**
     * Get all messages of a specific logging level
     *
     * @param level Logging level to filter by
     * @return List of messages matching the level
     */
    public List<UoWMessage> getMessagesByLevel(System.LoggingLevel level) {
        List<UoWMessage> filtered = new List<UoWMessage>();
        for (UoWMessage msg : this.messages) {
            if (msg.loggingLevel == level) {
                filtered.add(msg);
            }
        }
        return filtered;
    }

    /**
     * Check if there are any error messages
     *
     * @return True if error messages exist
     */
    public Boolean hasErrors() {
        return !getMessagesByLevel(LoggingLevel.ERROR).isEmpty();
    }

    /**
     * Check if there are any warning messages
     *
     * @return True if warning messages exist
     */
    public Boolean hasWarnings() {
        return !getMessagesByLevel(LoggingLevel.WARN).isEmpty();
    }

    // ============================================================================
    // PUBLIC API - MESSAGE CONVENIENCE METHODS
    // ============================================================================

    /**
     * Add debug message
     *
     * @param message Message text
     */
    public void debug(String message) {
        debug(message, 'Context');
    }

    /**
     * Add debug message with source
     *
     * @param message Message text
     * @param source Source identifier
     */
    public void debug(String message, String source) {
        if (String.isNotBlank(message)) {
            addMessage(new UoWMessage(LoggingLevel.DEBUG, message, source));
        }
    }

    /**
     * Add fine message
     *
     * @param message Message text
     */
    public void fine(String message) {
        fine(message, 'Context');
    }

    /**
     * Add fine message with source
     *
     * @param message Message text
     * @param source Source identifier
     */
    public void fine(String message, String source) {
        if (String.isNotBlank(message)) {
            addMessage(new UoWMessage(LoggingLevel.FINE, message, source));
        }
    }

    /**
     * Add info message
     *
     * @param message Message text
     */
    public void info(String message) {
        info(message, 'Context');
    }

    /**
     * Add info message with source
     *
     * @param message Message text
     * @param source Source identifier
     */
    public void info(String message, String source) {
        if (String.isNotBlank(message)) {
            addMessage(new UoWMessage(LoggingLevel.INFO, message, source));
        }
    }

    /**
     * Add warning message
     *
     * @param message Message text
     */
    public void warn(String message) {
        warn(message, 'Context');
    }

    /**
     * Add warning message with source
     *
     * @param message Message text
     * @param source Source identifier
     */
    public void warn(String message, String source) {
        if (String.isNotBlank(message)) {
            addMessage(new UoWMessage(LoggingLevel.WARN, message, source));
        }
    }

    /**
     * Add error message
     *
     * @param message Message text
     */
    public void error(String message) {
        error(message, 'Context');
    }

    /**
     * Add error message with source
     *
     * @param message Message text
     * @param source Source identifier
     */
    public void error(String message, String source) {
        if (String.isNotBlank(message)) {
            addMessage(new UoWMessage(LoggingLevel.ERROR, message, source));
        }
    }

    // ============================================================================
    // INNER CLASSES
    // ============================================================================

    // Agent attribution information for agent-initiated transactions
    public class AgentContext {
        public String agentId;
        public String agentName;
        public String modelId;
        public String promptHash;
        public Decimal confidenceScore;
        public String intent;
        public DateTime invokedAt;

        public AgentContext() {
            this.invokedAt = DateTime.now();
        }

        public AgentContext(String agentId, String modelId, Decimal confidenceScore) {
            this();
            this.agentId = agentId;
            this.modelId = modelId;
            this.confidenceScore = confidenceScore;
        }

        /**
         * Check if agent confidence meets threshold
         *
         * @param threshold Minimum confidence threshold
         * @return True if confidence meets or exceeds threshold
         */
        public Boolean hasHighConfidence(Decimal threshold) {
            return confidenceScore != null && confidenceScore >= threshold;
        }

        /**
         * Check if this is an agent transaction
         *
         * @return True if agent ID is present
         */
        public Boolean isAgentTransaction() {
            return String.isNotBlank(agentId);
        }
    }

    /**
     * Serializable snapshot of session context captured at transaction creation.
     * This persists through async serialization to maintain original session context.
     */
    public class SessionSnapshot {
        // User identity
        public Id userId { get; private set; }
        public String username { get; private set; }
        public String userEmail { get; private set; }
        public String userType { get; private set; }
        public Id profileId { get; private set; }
        public String profileName { get; private set; }
        public Id userRoleId { get; private set; }
        public String userRoleName { get; private set; }
        public String userLicenseName { get; private set; }

        // User preferences
        public String locale { get; private set; }
        public String timeZoneSidKey { get; private set; }

        // Organization
        public Id organizationId { get; private set; }
        public String organizationName { get; private set; }
        public String organizationInstanceName { get; private set; }
        public Boolean isSandbox { get; private set; }

        // Request/execution context
        public String requestId { get; private set; }
        public String quiddity { get; private set; }

        // Auth session
        public String loginType { get; private set; }
        public String sessionType { get; private set; }
        public String sourceIp { get; private set; }
        public Boolean isImpersonated { get; private set; }

        // Metadata
        public DateTime capturedAt { get; private set; }

        /**
         * Default constructor for deserialization.
         */
        public SessionSnapshot() {
            this.capturedAt = DateTime.now();
        }

        /**
         * Construct from live UoWSessionContext.
         *
         * @param session The session context to snapshot
         */
        public SessionSnapshot(UoWSessionContext session) {
            this.capturedAt = DateTime.now();

            if (session == null) {
                return;
            }

            // User identity
            this.userId = session.userId;
            this.username = session.username;
            this.userEmail = session.userEmail;
            this.userType = session.userType;
            this.profileId = session.profileId;
            this.profileName = session.profileName;
            this.userRoleId = session.userRoleId;
            this.userRoleName = session.userRoleName;
            this.userLicenseName = session.userLicenseName;

            // User preferences
            this.locale = session.locale;
            this.timeZoneSidKey = session.timeZoneSidKey;

            // Organization
            this.organizationId = session.organizationId;
            this.organizationName = session.organizationName;
            this.organizationInstanceName = session.organizationInstanceName;
            this.isSandbox = session.isSandbox;

            // Request/execution context
            this.requestId = session.requestId;
            this.quiddity = session.quiddity;

            // Auth session
            if (session.authSession != null) {
                this.loginType = session.authSession.loginType;
                this.sessionType = session.authSession.sessionType;
                this.sourceIp = session.authSession.sourceIp;
                this.isImpersonated = session.authSession.isImpersonated;
            }
        }
    }

    // ============================================================================
    // CORRELATION INHERITANCE (for UoWTransactionState)
    // ============================================================================

    /**
     * Inherit correlation context from parent transaction.
     * Called by UoWTransactionState.applyTo() to set correlation on child UoW.
     *
     * @param corrId The correlation ID to inherit
     * @param parentTxnId The parent's transaction ID (becomes this context's parentTransactionId)
     * @param parentAsyncDepth The parent's async depth (will be incremented)
     */
    public void inheritCorrelation(String corrId, String parentTxnId, Integer parentAsyncDepth) {
        this.correlationId = corrId;
        this.parentTransactionId = parentTxnId;
        this.asyncDepth = (parentAsyncDepth ?? 0) + 1;
    }
}