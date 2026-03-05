//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Flow invocable action to register HTTP callout operations in a Unit of Work transaction.
 *
 * Registers HTTP callouts to external systems as part of the transaction. Supports full HTTP
 * method configuration with custom headers, query parameters, and request body.
 *
 * Flow Pattern (Simple GET):
 * [Register Callout]
 *   Transaction ID: {!transactionId}
 *   Endpoint: callout:MyNamedCredential/api/resource
 *   HTTP Method: GET
 *
 * Flow Pattern (POST with JSON):
 * [Register Callout]
 *   Transaction ID: {!transactionId}
 *   Endpoint: callout:MyNamedCredential/api/create
 *   HTTP Method: POST
 *   Request Body: {"name":"Test","active":true}
 *   Content Type: application/json
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Flow Actions
 * @see UoWFlowInitializeAction
 * @see UoWFlowCommitAction
 */
public inherited sharing class UoWFlowRegisterCalloutAction {
    // ============================================================================
    // INVOCABLE METHOD
    // ============================================================================

    /**
     * Register HTTP callout for execution in Unit of Work transaction
     *
     * @param requests List of callout registration requests (Flow passes single-item list)
     * @return List of registration results
     */
    @InvocableMethod(
        label='UoW: Register Callout'
        description='Register HTTP callout to be executed as part of Unit of Work transaction'
        category='Unit of Work'
    )
    public static List<RegistrationResult> registerCallout(List<RegistrationRequest> requests) {
        List<RegistrationResult> results = new List<RegistrationResult>();

        for (RegistrationRequest request : requests) {
            RegistrationResult result = new RegistrationResult();

            try {
                // Validate inputs
                UoWExceptionService.requireNonBlank(request.transactionId, 'Transaction ID');
                UoWExceptionService.requireNonBlank(request.endpoint, 'Endpoint');
                UoWExceptionService.requireNonBlank(request.httpMethod, 'HTTP Method');

                // Retrieve UnitOfWork instance
                UnitOfWork uow = UoWFlowTransactionRegistry.get(request.transactionId);

                // Parse execution phase (if specified)
                UoWEnums.WorkPhase phase = String.isNotBlank(request.executionPhase)
                    ? UoWFlowActionHelpers.parseWorkPhase(request.executionPhase)
                    : null;

                // Register callout
                UoWCalloutWorkItem workItem = uow.registerCallout(request.endpoint, request.httpMethod, phase);

                // Set Flow origin for audit tracking
                if (String.isNotBlank(request.flowName)) {
                    workItem.withOrigin(UoWFlowActionHelpers.ORIGIN_TYPE_FLOW, request.flowName);
                }

                // Configure error handling mode
                if (request.continueOnError != null) {
                    workItem.continueOnError = request.continueOnError;
                }

                // Set request body
                if (String.isNotBlank(request.requestBody)) {
                    workItem.withBody(request.requestBody);
                }

                // Set content type
                if (String.isNotBlank(request.contentType)) {
                    workItem.withHeader('Content-Type', request.contentType);
                }

                // Set custom headers from JSON
                if (String.isNotBlank(request.customHeadersJson)) {
                    Map<String, Object> headers = (Map<String, Object>)JSON.deserializeUntyped(request.customHeadersJson);
                    for (String headerName : headers.keySet()) {
                        workItem.withHeader(headerName, String.valueOf(headers.get(headerName)));
                    }
                }

                // Set query parameters from JSON
                if (String.isNotBlank(request.queryParamsJson)) {
                    Map<String, Object> params = (Map<String, Object>)JSON.deserializeUntyped(request.queryParamsJson);
                    for (String paramName : params.keySet()) {
                        workItem.withQueryParam(paramName, String.valueOf(params.get(paramName)));
                    }
                }

                // Set timeout
                if (request.timeoutMs != null && request.timeoutMs > 0) {
                    workItem.withTimeout(request.timeoutMs);
                }

                // Success
                result.success = true;
                result.workItemId = workItem.workId;
                result.message = String.format('Callout registered: {0} {1}',
                    new String[]{ request.httpMethod, request.endpoint });

            } catch (Exception ex) {
                result.success = false;
                result.message = UoWFlowActionHelpers.formatException(ex);
            }

            results.add(result);
        }

        return results;
    }

    // ============================================================================
    // INNER CLASSES - REQUEST/RESPONSE
    // ============================================================================

    /**
     * Input parameters for callout registration
     */
    public class RegistrationRequest {
        @InvocableVariable(
            label='Transaction ID'
            description='Transaction ID from Initialize Transaction action'
            required=true
        )
        public String transactionId;

        @InvocableVariable(
            label='Endpoint'
            description='HTTP endpoint URL or Named Credential (e.g., callout:MyNamedCredential/api/resource)'
            required=true
        )
        public String endpoint;

        @InvocableVariable(
            label='HTTP Method'
            description='HTTP method: GET, POST, PUT, PATCH, DELETE'
            required=true
        )
        public String httpMethod;

        // ========================================================================
        // REQUEST CONFIGURATION
        // ========================================================================

        @InvocableVariable(
            label='Request Body'
            description='Request body (typically JSON or XML)'
        )
        public String requestBody;

        @InvocableVariable(
            label='Content Type'
            description='Content-Type header (e.g., application/json, application/xml). Defaults to application/json if body provided.'
        )
        public String contentType;

        @InvocableVariable(
            label='Custom Headers (JSON)'
            description='Custom HTTP headers as JSON object: {"Header-Name":"Value","Another-Header":"Value"}'
        )
        public String customHeadersJson;

        @InvocableVariable(
            label='Query Parameters (JSON)'
            description='URL query parameters as JSON object: {"param1":"value1","param2":"value2"}'
        )
        public String queryParamsJson;

        @InvocableVariable(
            label='Timeout (ms)'
            description='Callout timeout in milliseconds (default: from configuration)'
        )
        public Integer timeoutMs;

        // ========================================================================
        // OPTIONS
        // ========================================================================

        @InvocableVariable(
            label='Execution Phase'
            description='When to execute Callout: PRE_DML (default), ON_FAILURE'
        )
        public String executionPhase;

        @InvocableVariable(
            label='Continue On Error'
            description='Continue transaction if callout fails (default: false for callouts)'
        )
        public Boolean continueOnError;

        @InvocableVariable(
            label='Origin Flow Name'
            description='Name of the calling Flow (for audit origin tracking). Due to Salesforce limitations, this cannot be automatically determined.'
            required=true
        )
        public String flowName;
    }

    /**
     * Output results from callout registration
     */
    public class RegistrationResult {
        @InvocableVariable(
            label='Success'
            description='True if registration succeeded'
        )
        public Boolean success;

        @InvocableVariable(
            label='Work Item ID'
            description='Unique ID for this work item'
        )
        public String workItemId;

        @InvocableVariable(
            label='Message'
            description='Success or error message'
        )
        public String message;
    }
}