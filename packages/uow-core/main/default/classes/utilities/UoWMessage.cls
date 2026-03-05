//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Structured message class for framework logging and diagnostics.
 * Represents a single log message with logging level, timestamp, source, and metadata.
 * Uses Salesforce standard System.LoggingLevel for consistency with platform logging.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Statistics
 * @see UoWContext
 * @see UoWResult
 */
public inherited sharing class UoWMessage {

    // ============================================================================
    // PUBLIC PROPERTIES - CORE
    // ============================================================================

    public Datetime timestamp;                  // When the message was created
    public System.LoggingLevel loggingLevel;    // Salesforce standard logging level
    public String message;                      // Message text
    public String source;                       // Source identifier (class.method)

    // ============================================================================
    // PUBLIC PROPERTIES - METADATA
    // ============================================================================

    public String category;                     // Category name (e.g., "VALIDATION", "DML")
    public Map<String, Object> metadata;        // Additional metadata key-value pairs

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Construct a message with required fields.
     *
     * @param loggingLevel Salesforce standard logging level (FINEST, FINER, FINE, DEBUG, INFO, WARN, ERROR)
     * @param message The message text
     * @param source Source identifier (class.method or component name)
     */
    public UoWMessage(System.LoggingLevel loggingLevel, String message, String source) {
        this.timestamp = Datetime.now();
        this.loggingLevel = loggingLevel;
        this.message = message;
        this.source = source;
        this.metadata = new Map<String, Object>();
    }

    // ============================================================================
    // PUBLIC API - FLUENT CONFIGURATION
    // ============================================================================

    /**
     * Fluent API - set category.
     *
     * @param category The category name (e.g., "VALIDATION", "DML", "POLICY")
     * @return This message instance for method chaining
     */
    public UoWMessage withCategory(String category) {
        this.category = category;
        return this;
    }

    /**
     * Fluent API - add metadata.
     *
     * @param key The metadata key
     * @param value The metadata value
     * @return This message instance for method chaining
     */
    public UoWMessage withMetadata(String key, Object value) {
        this.metadata.put(key, value);
        return this;
    }

    /**
     * Fluent API - set all metadata at once.
     *
     * @param metadata Map of metadata key-value pairs to add
     * @return This message instance for method chaining
     */
    public UoWMessage withMetadata(Map<String, Object> metadata) {
        this.metadata.putAll(metadata);
        return this;
    }

    // ============================================================================
    // PUBLIC API - LEVEL CHECKS
    // ============================================================================

    /**
     * Check if this is an error message.
     *
     * @return True if logging level is ERROR, false otherwise
     */
    public Boolean isError() {
        return this.loggingLevel == System.LoggingLevel.ERROR;
    }

    /**
     * Check if this is a warning message.
     *
     * @return True if logging level is WARN, false otherwise
     */
    public Boolean isWarning() {
        return this.loggingLevel == System.LoggingLevel.WARN;
    }

    /**
     * Check if this is an info message.
     *
     * @return True if logging level is INFO, false otherwise
     */
    public Boolean isInfo() {
        return this.loggingLevel == System.LoggingLevel.INFO;
    }

    /**
     * Check if this is a debug message.
     *
     * @return True if logging level is DEBUG, false otherwise
     */
    public Boolean isDebug() {
        return this.loggingLevel == System.LoggingLevel.DEBUG;
    }

    /**
     * Check if this is a fine message.
     *
     * @return True if logging level is FINE, false otherwise
     */
    public Boolean isFine() {
        return this.loggingLevel == System.LoggingLevel.FINE;
    }

    /**
     * Check if this is a finer message.
     *
     * @return True if logging level is FINER, false otherwise
     */
    public Boolean isFiner() {
        return this.loggingLevel == System.LoggingLevel.FINER;
    }

    /**
     * Check if this is a finest message.
     *
     * @return True if logging level is FINEST, false otherwise
     */
    public Boolean isFinest() {
        return this.loggingLevel == System.LoggingLevel.FINEST;
    }
}