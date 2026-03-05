//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Centralized exception handling for UnitOfWork framework.
 * Eliminates repetitive try-catch blocks and exception creation patterns.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Services
 *
 * @example
 * UoWExceptionService.requireNonNull(config, 'Config');
 * UoWExceptionService.require(records.size() > 0, 'No records to process');
 */
public inherited sharing class UoWExceptionService {

    // ============================================================================
    // PRIVATE FIELDS
    // ============================================================================

    private static final String CLASS_NAME = UoWExceptionService.class.getName();

    // ============================================================================
    // PUBLIC API - EXCEPTION CREATION
    // ============================================================================

    /**
     * Create context-aware exception with message.
     * Automatically detects execution context and throws the appropriate exception type.
     * - Aura/VF contexts: AuraHandledException
     * - All other contexts: UoWException
     *
     * @param message The error message
     * @throws AuraHandledException in Aura/VF contexts
     * @throws UoWException in all other contexts
     */
    public static void throwException(String message) {
        System.Quiddity context = UoWUtils.getExecutionContext();

        // Only use AuraHandledException in contexts that support it
        if (context == System.Quiddity.AURA || context == System.Quiddity.VF) {
            throw buildAuraException(message);
        } else {
            throw buildUoWException(message);
        }
    }

    // ============================================================================
    // PUBLIC API - VALIDATION
    // ============================================================================

    /**
     * Validate condition and throw if false
     * Automatically uses the correct exception type based on execution context
     *
     * @example
     * UoWExceptionService.require(
     *     records.size() <= Limits.getLimitDMLRows(),
     *     'Too many records for DML operation'
     * );
     */
    public static void require(Boolean condition, String errorMessage) {
        if (!condition) {
            throwException(errorMessage);
        }
    }

    /**
     * Validate object is not null.
     *
     * @param obj The object to validate
     * @param variableName The variable name for error message
     * @throws UoWException if object is null
     *
     * @example
     * UoWExceptionService.requireNonNull(config, 'Configuration');
     */
    public static void requireNonNull(Object obj, String variableName) {
        require(obj != null, String.format(System.Label.UoW_Error_NullValue, new List<String>{ variableName }));
    }

    /**
     * Validate string is not blank.
     *
     * @param str The string to validate
     * @param variableName The variable name for error message
     * @throws UoWException if string is null or blank
     *
     * @example
     * UoWExceptionService.requireNonBlank(scopeName, 'Scope name');
     */
    public static void requireNonBlank(String str, String variableName) {
        require(String.isNotBlank(str), String.format(System.Label.UoW_Error_BlankValue, new List<String>{ variableName }));
    }

    /**
     * Validate list is not empty.
     *
     * @param collection The list to validate
     * @param variableName The variable name for error message
     * @throws UoWException if list is null or empty
     *
     * @example
     * UoWExceptionService.requireNonEmpty(records, 'Records list');
     */
    public static void requireNonEmpty(List<Object> collection, String variableName) {
        require(collection != null && !collection.isEmpty(), String.format(System.Label.UoW_Error_EmptyValue, new List<String>{ variableName }));
    }

    // ============================================================================
    // PUBLIC HELPER METHODS
    // ============================================================================

    /**
     * Build AuraHandledException with proper message handling.
     * Addresses the known Salesforce quirk where AuraHandledException.getMessage()
     * returns 'Script-thrown exception' instead of the constructor message.
     *
     * @param message The error message
     * @return AuraHandledException with message properly set
     */
    public static AuraHandledException buildAuraException(String message) {
        //Build the exception
        AuraHandledException ex = new AuraHandledException(message);

        //the constructor for the AuraHandledException
        //only sets the string argument to be the message sent to the client-end,
        //while calling getMessage() on the exception through apex
        //returns a different string that the constructor defaults to the value "Script-thrown Exception".
        //to avoid that, we have to explicitly set the message to the exception
        ex.setMessage(message);

        //return the exception
        return ex;
    }

    // Build UoWException for non-Aura/VF contexts
    private static UoWException buildUoWException(String message) {
        UoWException ex = new UoWException(message);
        return ex;
    }

    // ============================================================================
    // INNER CLASSES
    // ============================================================================

    /**
     * Custom exception for UnitOfWork framework errors.
     */
    public class UoWException extends Exception {}

    /**
     * Error classification and metadata for retry and tracking.
     */
    public class ErrorInfo implements Comparable {
        public String errorId;
        public String workItemId;                // Work item ID that caused this error (for navigation)
        public String errorType;                 // Exception type name
        public String errorMessage;
        public String stackTrace;
        public Boolean isRetryable;
        public Integer attemptNumber;
        public transient Map<String, Object> errorContext;
        public String errorContextSerialized;    // JSON string for serialization
        public DateTime occurredAt;

        public ErrorInfo(Exception ex) {
            this.errorId = UoWUtils.generateId('EXCEPTION');
            this.errorMessage = ex.getMessage();
            this.stackTrace = ex.getStackTraceString();
            this.errorType = ex.getTypeName();
            this.isRetryable = isRetryableException(ex);
            this.errorContext = new Map<String, Object>();
            this.occurredAt = DateTime.now();
            this.attemptNumber = 1;
        }

        /**
         * Constructor for DML errors without Exception object.
         *
         * @param errorType The error type
         * @param errorMessage The error message
         */
        public ErrorInfo(String errorType, String errorMessage) {
            this.errorId = UoWUtils.generateId('ERROR');
            this.errorType = errorType;
            this.errorMessage = errorMessage;
            this.stackTrace = null;
            this.isRetryable = false;  // DML errors typically not retryable
            this.errorContext = new Map<String, Object>();
            this.occurredAt = DateTime.now();
            this.attemptNumber = 1;
        }

        /**
         * Constructor for Database.Error objects from DML operations.
         *
         * @param dbError Database.Error from SaveResult/DeleteResult/UpsertResult
         * @param recordIndex Index of the failed record in the batch
         * @param operation DML operation name (INSERT_OP, UPDATE_OP, etc.)
         * @param sobjectType SObject type name
         */
        @SuppressWarnings('PMD.ExcessiveParameterList')
        public ErrorInfo(Database.Error dbError, Integer recordIndex, String operation, String sobjectType) {
            this.errorId = UoWUtils.generateId('DB-ERR')+ '-' + recordIndex;
            this.errorType = dbError.getStatusCode().name();
            this.errorMessage = String.format(
                '{0} operation failed on {1} record at index {2}: {3}',
                new String[]{ operation, sobjectType, String.valueOf(recordIndex), dbError.getMessage() }
            );
            this.stackTrace = null;  // Database.Error doesn't have stack trace
            this.isRetryable = isRetryableStatusCode(dbError.getStatusCode());
            this.errorContext = new Map<String, Object>();
            this.occurredAt = DateTime.now();
            this.attemptNumber = 1;

            // Store context for debugging
            this.addContext('operation', operation);
            this.addContext('sobjectType', sobjectType);
            this.addContext('recordIndex', recordIndex);
            this.addContext('statusCode', dbError.getStatusCode().name());
            this.addContext('fields', dbError.getFields());
        }

        // Determine if exception is retryable based on type
        private Boolean isRetryableException(Exception ex) {
            String typeName = ex.getTypeName();
            return typeName.contains('LimitException') ||
                   typeName.contains('LockException') ||
                   typeName.contains('TimeoutException') ||
                   typeName.contains('UnableToLockRowException');
        }

        // Determine if Database.Error status code indicates retryable error
        private Boolean isRetryableStatusCode(System.StatusCode statusCode) {
            // Retryable status codes
            return statusCode == System.StatusCode.UNABLE_TO_LOCK_ROW ||
                   statusCode == System.StatusCode.RECORD_IN_USE_BY_WORKFLOW;
        }

        /**
         * Add context information to the error.
         *
         * @param key Context key
         * @param value Context value
         */
        public void addContext(String key, Object value) {
            if (String.isNotBlank(key)) {
                this.errorContext.put(key, value);
            }
        }

        /**
         * Capture errorContext for serialization.
         */
        public void captureContextForSerialization() {
            if (this.errorContext != null && !this.errorContext.isEmpty()) {
                this.errorContextSerialized = JSON.serialize(this.errorContext);
            }
        }

        /**
         * Restore errorContext from serialized JSON.
         */
        public void restoreContextFromSerialization() {
            if (String.isNotBlank(this.errorContextSerialized)) {
                this.errorContext = (Map<String, Object>) JSON.deserializeUntyped(this.errorContextSerialized);
            } else {
                this.errorContext = new Map<String, Object>();
            }
        }

        public Integer compareTo(Object other) {
            ErrorInfo otherError = (ErrorInfo) other;
            return this.occurredAt > otherError.occurredAt ? 1 :
                   (this.occurredAt < otherError.occurredAt ? -1 : 0);
        }
    }
}