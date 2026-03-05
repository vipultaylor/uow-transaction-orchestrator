//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Work item for HTTP callout operations.
 * Contains endpoint, method, headers, body, and response handling.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Work Items
 * @see UoWWorkItem
 * @see UoWCalloutExecutionService
 * @see UoWRetryConfig
 */
public inherited sharing class UoWCalloutWorkItem extends UoWWorkItem {

    // ============================================================================
    // PUBLIC PROPERTIES - REQUEST CONFIGURATION
    // ============================================================================

    public String endpoint;
    public String httpMethod;
    public Map<String, String> headers;
    public Map<String, String> queryParams;
    public String requestBody;
    public Integer timeoutMs;

    // ============================================================================
    // PUBLIC PROPERTIES - REQUEST/RESPONSE OBJECTS (transient)
    // ============================================================================

    public transient HttpRequest request;
    public transient HttpResponse response;

    // ============================================================================
    // PUBLIC PROPERTIES - RETRY CONFIGURATION
    // ============================================================================

    public UoWRetryConfig retryConfig;

    // ============================================================================
    // PUBLIC PROPERTIES - EXECUTION PHASE
    // ============================================================================

    // Execution phase for this callout (default: PRE_DML)
    // RESTRICTION: Callouts only support PRE_DML and ON_FAILURE phases
    // - PRE_DML: Executes before savepoint creation (standard callout timing)
    // - ON_FAILURE: Executes after rollback completes (for error notification/compensation)
    // POST_DML, ON_SUCCESS, ON_FINALIZATION are NOT supported due to Salesforce platform limitations
    public UoWEnums.WorkPhase executionPhase;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Create a new Callout work item with default PRE_DML phase.
     * For ON_FAILURE callouts, use the constructor that takes a phase parameter.
     *
     * @param endpointUrl The HTTP endpoint URL (can include Named Credential prefix like 'callout:MyAPI')
     * @param method The HTTP method (GET, POST, PUT, DELETE, PATCH, etc.)
     */
    public UoWCalloutWorkItem(String endpointUrl, String method) {
        this(endpointUrl, method, UoWEnums.WorkPhase.PRE_DML);
    }

    /**
     * Create a new Callout work item with specified execution phase.
     * RESTRICTION: Only PRE_DML and ON_FAILURE phases are supported for callouts.
     *
     * @param endpointUrl The HTTP endpoint URL (can include Named Credential prefix like 'callout:MyAPI')
     * @param method The HTTP method (GET, POST, PUT, DELETE, PATCH, etc.)
     * @param phase Execution phase (PRE_DML or ON_FAILURE only)
     * @throws UoWException if phase is not supported for callouts
     */
    public UoWCalloutWorkItem(String endpointUrl, String method, UoWEnums.WorkPhase phase) {
        super(UoWEnums.WorkType.CALLOUT);
        UoWExceptionService.requireNonNull(endpointUrl, 'Endpoint URL for Callout');
        UoWExceptionService.requireNonBlank(method, 'Method for Callout');
        validateCalloutPhase(phase);

        this.endpoint = endpointUrl;
        this.httpMethod = method;
        this.headers = new Map<String, String>();
        this.queryParams = new Map<String, String>();
        this.timeoutMs = 120000;
        this.statistics.planned = 1;
        this.continueOnError = false;
        this.executionPhase = phase ?? UoWEnums.WorkPhase.PRE_DML;
    }

    /**
     * Validate that the phase is supported for callouts.
     * Only PRE_DML and ON_FAILURE are valid due to Salesforce platform limitations.
     *
     * @param phase The phase to validate
     * @throws UoWException if phase is not supported
     */
    private void validateCalloutPhase(UoWEnums.WorkPhase phase) {
        if (phase != null && phase != UoWEnums.WorkPhase.PRE_DML && phase != UoWEnums.WorkPhase.ON_FAILURE) {
            throw new UoWExceptionService.UoWException(
                'Callouts only support PRE_DML and ON_FAILURE phases. ' +
                'Phase ' + phase + ' is not supported due to Salesforce platform limitations: ' +
                'cannot make callouts after Database.setSavepoint() or after DML commits.'
            );
        }
    }

    // ============================================================================
    // PUBLIC API - FLUENT CONFIGURATION
    // ============================================================================

    /**
     * Set HTTP method.
     *
     * @param method HTTP method (GET, POST, PUT, DELETE, etc.)
     * @return This work item for fluent chaining
     */
    public UoWCalloutWorkItem withMethod(String method) {
        this.httpMethod = method ?? 'GET';
        return this;
    }

    /**
     * Add HTTP header.
     *
     * @param key Header name
     * @param value Header value
     * @return This work item for fluent chaining
     */
    public UoWCalloutWorkItem withHeader(String key, String value) {
        this.headers.put(key, value);
        return this;
    }

    /**
     * Add query parameter (will be appended to endpoint URL).
     *
     * @param key Parameter name
     * @param value Parameter value
     * @return This work item for fluent chaining
     */
    public UoWCalloutWorkItem withQueryParam(String key, String value) {
        this.queryParams.put(key, value);
        return this;
    }

    /**
     * Set request body.
     *
     * @param body Request body (usually JSON or XML)
     * @return This work item for fluent chaining
     */
    public UoWCalloutWorkItem withBody(String body) {
        this.requestBody = body;
        return this;
    }

    /**
     * Set timeout in milliseconds.
     *
     * @param milliseconds Timeout in milliseconds (max 120000)
     * @return This work item for fluent chaining
     */
    public UoWCalloutWorkItem withTimeout(Integer milliseconds) {
        this.timeoutMs = milliseconds;
        return this;
    }

    /**
     * Set retry configuration for this callout.
     * Core package stores this configuration; extensions package implements actual retry logic.
     *
     * @param config Retry configuration (use UoWRetryConfigs factory for presets)
     * @return This work item for fluent chaining
     */
    public UoWCalloutWorkItem withRetryConfig(UoWRetryConfig config) {
        this.retryConfig = config;
        return this;
    }

    /**
     * Continue execution even if callout fails (don't re-throw exception).
     *
     * @return This work item for fluent chaining
     */
    public UoWCalloutWorkItem continueOnError() {
        this.continueOnError = true;
        return this;
    }

    /**
     * Fail-fast if callout fails (re-throw exception for transaction rollback).
     *
     * @return This work item for fluent chaining
     */
    public UoWCalloutWorkItem failFast() {
        this.continueOnError = false;
        return this;
    }

    // ============================================================================
    // PUBLIC API - RESULT PROCESSING
    // ============================================================================

    /**
     * Process callout execution results - calculate statistics based on response.
     * Callouts are single-item operations (1 request = 1 processed).
     * Success is determined by HTTP status code (2xx = success).
     * Called after callout execution completes.
     */
    public override void processResults() {
        this.statistics.processed = 1;

        if (this.response != null) {
            Integer statusCode = this.response.getStatusCode();
            if (statusCode >= 200 && statusCode < 300) {
                this.statistics.successes = 1;
                this.statistics.failures = 0;
            } else {
                this.statistics.successes = 0;
                this.statistics.failures = 1;
                if (this.errors.isEmpty()) {
                    UoWExceptionService.ErrorInfo error = new UoWExceptionService.ErrorInfo(
                        'CALLOUT',
                        'HTTP_' + statusCode + ': ' + this.response.getStatus()
                    );
                    error.errorContext.put('endpoint', this.endpoint);
                    error.errorContext.put('method', this.httpMethod);
                    error.errorContext.put('statusCode', statusCode);
                    this.addError(error);
                }
            }
        } else if (this.errors != null && !this.errors.isEmpty()) {
            this.statistics.successes = 0;
            this.statistics.failures = 1;
        }
    }

}