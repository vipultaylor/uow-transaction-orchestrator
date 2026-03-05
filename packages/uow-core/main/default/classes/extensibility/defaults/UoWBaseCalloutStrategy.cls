//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Base implementation for HTTP callout strategies.
 * Provides default synchronous callout execution.
 * Custom strategies can extend this to add retry logic, async execution, etc.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWInterfaces.ICalloutStrategy
 */
public virtual inherited sharing class UoWBaseCalloutStrategy implements UoWInterfaces.ICalloutStrategy {

    // ============================================================================
    // PROTECTED PROPERTIES
    // ============================================================================

    protected String strategyName;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Default constructor - sets default strategy name.
     */
    public UoWBaseCalloutStrategy() {
        this('Default Callout Strategy');
    }

    /**
     * Constructor with custom name (for derived classes).
     *
     * @param name Strategy name
     */
    public UoWBaseCalloutStrategy(String name) {
        this.strategyName = name;
    }

    // ============================================================================
    // PUBLIC API - CONFIGURATION
    // ============================================================================

    /**
     * Get strategy name.
     *
     * @return Strategy name
     */
    public virtual String getName() {
        return this.strategyName;
    }

    // ============================================================================
    // PUBLIC API - CALLOUT EXECUTION
    // ============================================================================

    /**
     * Execute HTTP callout.
     * Base implementation performs immediate synchronous callout.
     * Override for retry logic, async execution, or other strategies.
     *
     * @param workItem The callout work item to execute
     * @param ctx The execution context
     */
    public virtual void executeCallout(UoWCalloutWorkItem workItem, UoWContext ctx) {
        // Build HTTP request
        HttpRequest request = buildRequest(workItem);

        // Execute callout
        Http http = new Http();
        workItem.response = http.send(request);

        // Check for HTTP errors (4xx/5xx) if fail-fast mode
        if (!workItem.continueOnError && isErrorResponse(workItem.response)) {
            throw new UoWExceptionService.UoWException(
                String.format('HTTP callout failed: {0} {1}',
                    new String[]{
                        String.valueOf(workItem.response.getStatusCode()),
                        workItem.response.getStatus()
                    }
                )
            );
        }
    }

    // ============================================================================
    // PROTECTED METHODS
    // ============================================================================

    /**
     * Build HTTP request from work item.
     * Override to customize request building.
     *
     * @param workItem The callout work item
     * @return Configured HttpRequest
     */
    protected virtual HttpRequest buildRequest(UoWCalloutWorkItem workItem) {
        HttpRequest request = new HttpRequest();

        // Set endpoint with query parameters
        String fullEndpoint = buildEndpointWithParams(workItem);
        request.setEndpoint(fullEndpoint);

        // Set HTTP method
        request.setMethod(workItem.httpMethod);

        // Set timeout
        if (workItem.timeoutMs != null) {
            request.setTimeout(workItem.timeoutMs);
        }

        // Set headers
        if (workItem.headers != null) {
            for (String key : workItem.headers.keySet()) {
                request.setHeader(key, workItem.headers.get(key));
            }
        }

        // Set request body (for POST/PUT/PATCH)
        if (String.isNotBlank(workItem.requestBody) &&
            (workItem.httpMethod == 'POST' || workItem.httpMethod == 'PUT' || workItem.httpMethod == 'PATCH')) {
            request.setBody(workItem.requestBody);
        }

        //Store the request on the work item
        workItem.request = request;

        return request;
    }

    /**
     * Build full endpoint URL with query parameters.
     *
     * @param workItem The callout work item
     * @return Full endpoint URL with query string
     */
    protected virtual String buildEndpointWithParams(UoWCalloutWorkItem workItem) {
        if (workItem.queryParams == null || workItem.queryParams.isEmpty()) {
            return workItem.endpoint;
        }

        List<String> params = new List<String>();
        for (String key : workItem.queryParams.keySet()) {
            params.add(EncodingUtil.urlEncode(key, 'UTF-8') + '=' +
                       EncodingUtil.urlEncode(workItem.queryParams.get(key), 'UTF-8'));
        }

        String separator = workItem.endpoint.contains('?') ? '&' : '?';
        return workItem.endpoint + separator + String.join(params, '&');
    }

    /**
     * Check if response indicates an error (4xx/5xx status codes).
     *
     * @param response The HTTP response
     * @return True if response is an error
     */
    protected virtual Boolean isErrorResponse(HttpResponse response) {
        if (response == null) {
            return true;
        }
        Integer statusCode = response.getStatusCode();
        return statusCode >= 400;
    }
}