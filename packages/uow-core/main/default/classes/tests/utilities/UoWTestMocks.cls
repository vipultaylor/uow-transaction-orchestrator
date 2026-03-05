//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Consolidated test mocks for UoW framework testing. Contains all mock implementations
 * as inner classes including channels, strategies, plugins, policies, and risk assessors.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Test Utilities
 * @see UoWTestHelpers
 * @see UoWMockResultBuilder
 * @see UoWChaosEngine
 */
@isTest
@SuppressWarnings('PMD.CognitiveComplexity')
public class UoWTestMocks {

    // ============================================================================
    // STATIC TRACKING FOR DYNAMICALLY INSTANTIATED HANDLERS
    // ============================================================================

    /** Tracks handleFailure() calls when MockEventPublishFailureHandler is instantiated via Type.forName() */
    public static Integer eventFailureHandlerCallCount = 0;

    /** Captures the failure context when MockEventPublishFailureHandler is instantiated via Type.forName() */
    public static UoWEventPublishFailureContext eventFailureCapturedContext;

    /** When true, MockEventPublishFailureHandler.handleFailure() throws an exception */
    public static Boolean eventFailureHandlerShouldThrow = false;

    /**
     * Reset static tracking fields for test isolation.
     */
    public static void resetEventFailureHandlerTracking() {
        eventFailureHandlerCallCount = 0;
        eventFailureCapturedContext = null;
        eventFailureHandlerShouldThrow = false;
    }

    // ============================================================================
    // DML STRATEGY MOCKS
    // ============================================================================

    /**
     * Mock DML strategy for testing without real database operations.
     * TRUE MOCK - Does NOT execute real DML, simulates success/failure via UoWMockResultBuilder.
     *
     * Benefits:
     * - No database operations (faster tests)
     * - No custom required field issues (org-independent)
     * - Consistent test behavior across all orgs
     * - Integrates with UoWChaosEngine for failure simulation
     *
     * Usage:
     *   // Setup mock
     *   MockDmlStrategy strategy = new UoWTestMocks.MockDmlStrategy();
     *   uow.withDmlStrategy(Account.SObjectType, strategy);
     *
     *   // Configure failures via ChaosEngine
     *   UoWChaosEngine.alwaysFail(UoWChaosEngine.Point.DML_INSERT,
     *       new UoWChaosEngine.ChaosDmlException('Validation error'));
     */
    public class MockDmlStrategy implements UoWInterfaces.IDmlStrategy {
        private String strategyName;

        public MockDmlStrategy(){
            this.strategyName = 'MockDmlStrategy';
        }

        public MockDmlStrategy(String name){
            this.strategyName = name;
        }

        public String getName() {
            return this.strategyName;
        }

        public void executeInsert(UoWDmlWorkItem workItem, UoWContext ctx) {
            // Check for complete failure (exception-based)
            UoWChaosEngine.hit(UoWChaosEngine.Point.DML_INSERT);

            // Check for partial failure (result-based)
            UoWChaosEngine.PartialFailureConfig partialConfig =
                UoWChaosEngine.getPartialFailureConfig(UoWChaosEngine.Point.DML_INSERT);

            if (partialConfig != null) {
                // CRITICAL: When continueOnError=false (fail-fast/allOrNone=true),
                // Salesforce throws DmlException on first failure instead of returning partial results
                if (!workItem.continueOnError && !partialConfig.failureIndexes.isEmpty()) {
                    throw UoWChaosEngine.sampleInsertDmlException();
                }

                // continueOnError=true: Return partial results
                workItem.saveResults = UoWMockResultBuilder.createPartialSaveResults(
                    workItem.getOriginalRecords(),
                    partialConfig.failureIndexes,
                    partialConfig.failureMessage,
                    partialConfig.statusCode
                );
            } else {
                // All success
                workItem.saveResults = UoWMockResultBuilder.createSuccessfulSaveResults(workItem.getOriginalRecords());
            }
        }

        public void executeUpdate(UoWDmlWorkItem workItem, UoWContext ctx) {
            // Check for complete failure (exception-based)
            UoWChaosEngine.hit(UoWChaosEngine.Point.DML_UPDATE);

            // Check for partial failure (result-based)
            UoWChaosEngine.PartialFailureConfig partialConfig =
                UoWChaosEngine.getPartialFailureConfig(UoWChaosEngine.Point.DML_UPDATE);

            if (partialConfig != null) {
                // When failFast (continueOnError=false), throw exception on first failure
                if (!workItem.continueOnError && !partialConfig.failureIndexes.isEmpty()) {
                    throw UoWChaosEngine.sampleInsertDmlException();
                }

                workItem.saveResults = UoWMockResultBuilder.createPartialSaveResults(
                    workItem.getOriginalRecords(),
                    partialConfig.failureIndexes,
                    partialConfig.failureMessage,
                    partialConfig.statusCode
                );
            } else {
                workItem.saveResults = UoWMockResultBuilder.createSuccessfulSaveResults(workItem.getOriginalRecords());
            }
        }

        public void executeUpsert(UoWDmlWorkItem workItem, UoWContext ctx) {
            // Check for complete failure (exception-based)
            UoWChaosEngine.hit(UoWChaosEngine.Point.DML_UPSERT);

            // Check for partial failure (result-based)
            UoWChaosEngine.PartialFailureConfig partialConfig =
                UoWChaosEngine.getPartialFailureConfig(UoWChaosEngine.Point.DML_UPSERT);

            if (partialConfig != null) {
                // When failFast (continueOnError=false), throw exception on first failure
                if (!workItem.continueOnError && !partialConfig.failureIndexes.isEmpty()) {
                    throw UoWChaosEngine.sampleInsertDmlException();
                }

                workItem.upsertResults = UoWMockResultBuilder.createPartialUpsertResults(
                    workItem.getOriginalRecords(),
                    partialConfig.failureIndexes,
                    partialConfig.failureMessage,
                    partialConfig.statusCode
                );
            } else {
                workItem.upsertResults = UoWMockResultBuilder.createSuccessfulUpsertResults(workItem.getOriginalRecords());
            }
        }

        public void executeDelete(UoWDmlWorkItem workItem, UoWContext ctx) {
            // Check for complete failure (exception-based)
            UoWChaosEngine.hit(UoWChaosEngine.Point.DML_DELETE);

            // Check for partial failure (result-based)
            UoWChaosEngine.PartialFailureConfig partialConfig =
                UoWChaosEngine.getPartialFailureConfig(UoWChaosEngine.Point.DML_DELETE);

            if (partialConfig != null) {
                // When failFast (continueOnError=false), throw exception on first failure
                if (!workItem.continueOnError && !partialConfig.failureIndexes.isEmpty()) {
                    throw UoWChaosEngine.sampleInsertDmlException();
                }

                workItem.deleteResults = UoWMockResultBuilder.createPartialDeleteResults(
                    workItem.getOriginalRecords(),
                    partialConfig.failureIndexes,
                    partialConfig.failureMessage,
                    partialConfig.statusCode
                );
            } else {
                workItem.deleteResults = UoWMockResultBuilder.createSuccessfulDeleteResults(workItem.getOriginalRecords());
            }
        }

        public void executeUndelete(UoWDmlWorkItem workItem, UoWContext ctx) {
            // Check for complete failure (exception-based)
            UoWChaosEngine.hit(UoWChaosEngine.Point.DML_UNDELETE);

            // Check for partial failure (result-based)
            UoWChaosEngine.PartialFailureConfig partialConfig =
                UoWChaosEngine.getPartialFailureConfig(UoWChaosEngine.Point.DML_UNDELETE);

            if (partialConfig != null) {
                // When failFast (continueOnError=false), throw exception on first failure
                if (!workItem.continueOnError && !partialConfig.failureIndexes.isEmpty()) {
                    throw UoWChaosEngine.sampleInsertDmlException();
                }

                workItem.undeleteResults = UoWMockResultBuilder.createPartialUndeleteResults(
                    workItem.getOriginalRecords(),
                    partialConfig.failureIndexes,
                    partialConfig.failureMessage,
                    partialConfig.statusCode
                );
            } else {
                workItem.undeleteResults = UoWMockResultBuilder.createSuccessfulUndeleteResults(workItem.getOriginalRecords());
            }
        }
    }

    // ============================================================================
    // CHANNEL MOCKS
    // ============================================================================

    /**
     * Mock event channel for platform event testing.
     * Replaces EventBus.publish() which is not available in test context.
     */
    public class MockEventChannel implements UoWInterfaces.IEventChannel {
        private String channelName;

        public MockEventChannel(){
            this.channelName = 'MockEventChannel';
        }

        public MockEventChannel(String name){
            this.channelName = name;
        }

        public String getName() {
            return this.channelName;
        }

        public void publishEvents(UoWEventWorkItem workItem, UoWContext ctx) {
            // ChaosEngine throws exception if configured
            UoWChaosEngine.hit(UoWChaosEngine.Point.PLATFORM_EVENT_PUBLISH);

            // Check for partial failure (result-based)
            UoWChaosEngine.PartialFailureConfig partialConfig =
                UoWChaosEngine.getPartialFailureConfig(UoWChaosEngine.Point.PLATFORM_EVENT_PUBLISH);

            if (partialConfig != null) {
                workItem.publishResults = UoWMockResultBuilder.createPartialPublishResults(
                    workItem.getOriginalEvents(),
                    partialConfig.failureIndexes,
                    partialConfig.failureMessage,
                    partialConfig.statusCode
                );
            } else {
                workItem.publishResults = UoWMockResultBuilder.createSuccessfulPublishResults(workItem.getOriginalEvents());
            }
        }
    }

    /**
     * Mock email channel for email sending testing.
     * TRUE MOCK - Does NOT send real emails, simulates success/failure via UoWMockResultBuilder.
     *
     * Benefits:
     * - No actual email sends (faster tests)
     * - No org-specific email configuration required
     * - Can simulate specific failure scenarios
     *
     * Usage:
     *   MockEmailChannel mockChannel = new UoWTestMocks.MockEmailChannel();
     *   uow.withEmailChannel(mockChannel);
     */
    public class MockEmailChannel implements UoWInterfaces.IEmailChannel {
        private String channelName;

        public MockEmailChannel(){
            this.channelName = 'MockEmailChannel';
        }

        public MockEmailChannel(String name){
            this.channelName = name;
        }

        public String getName() {
            return this.channelName;
        }

        public void sendEmails(UoWEmailWorkItem workItem, UoWContext ctx) {
            // Check for complete failure (exception-based)
            UoWChaosEngine.hit(UoWChaosEngine.Point.EMAIL_SEND);

            Integer emailCount = workItem.getEmails()?.size() ?? 1;

            // Check for partial failure (result-based)
            UoWChaosEngine.PartialFailureConfig partialConfig =
                UoWChaosEngine.getPartialFailureConfig(UoWChaosEngine.Point.EMAIL_SEND);

            if (partialConfig != null) {
                // CRITICAL: When continueOnError=false (fail-fast/allOrNone=true),
                // Salesforce throws EmailException on first failure instead of returning partial results
                if (!workItem.continueOnError && !partialConfig.failureIndexes.isEmpty()) {
                    throw UoWChaosEngine.sampleEmailException();
                }

                // Create mixed results (some succeed, some fail)
                workItem.sendResults = UoWMockResultBuilder.createPartialEmailResults(
                    emailCount,
                    partialConfig.failureIndexes,
                    partialConfig.failureMessage
                );

                // FALLBACK: Messaging.SendEmailError doesn't deserialize properly from JSON
                // If getErrors() returns empty despite isSuccess=false, add explicit errors
                for (Integer i = 0; i < workItem.sendResults.size(); i++) {
                    Messaging.SendEmailResult result = workItem.sendResults[i];
                    if (!result.isSuccess() && (result.getErrors() == null || result.getErrors().isEmpty())) {
                        // Manually create error since JSON deserialization failed
                        UoWExceptionService.ErrorInfo error = new UoWExceptionService.ErrorInfo(
                            'EMAIL_SEND_FAILED',
                            String.format('Email send failed at index {0}: {1}',
                                new String[]{ String.valueOf(i), partialConfig.failureMessage })
                        );
                        workItem.addError(error);
                    }
                }
            } else {
                // All success
                workItem.sendResults = UoWMockResultBuilder.createSuccessfulEmailResults(emailCount);
            }
        }
    }

    /**
     * Mock notification channel for custom notification testing.
     * Replaces Messaging.CustomNotification which is not available in test context.
     *
     * Usage:
     *   MockNotificationChannel mockChannel = new UoWTestMocks.MockNotificationChannel();
     *   uow.withNotificationChannel(mockChannel);
     */
    public class MockNotificationChannel implements UoWInterfaces.INotificationChannel {
        private String channelName;

        public MockNotificationChannel(){
            this.channelName = 'MockNotificationChannel';
        }

        public MockNotificationChannel(String name){
            this.channelName = name;
        }

        public String getName() {
            return this.channelName;
        }

        public void sendNotification(UoWNotificationWorkItem workItem, UoWContext ctx) {
            // ChaosEngine throws exception if configured
            UoWChaosEngine.hit(UoWChaosEngine.Point.CUSTOM_NOTIFICATION_SEND);

            // Simulate success
        }
    }

    /**
     * Mock flow channel for flow execution testing.
     * Replaces Flow.Interview which has limited testability.
     *
     * Usage:
     *   MockFlowChannel mockChannel = new UoWTestMocks.MockFlowChannel();
     *   mockChannel.mockOutputVariables.put('OutputVar', 'MockValue');
     *   uow.withFlowChannel(mockChannel);
     */
    public class MockFlowChannel implements UoWInterfaces.IFlowChannel {
        // Configuration
        private String channelName;
        public Map<String, Object> mockOutputVariables = new Map<String, Object>();

        public MockFlowChannel(){
            this.channelName = 'MockFlowChannel';
        }

        public MockFlowChannel(String name){
            this.channelName = name;
        }

        public String getName() {
            return this.channelName;
        }

        public void executeFlow(UoWFlowWorkItem workItem, UoWContext ctx) {
            // ChaosEngine throws exception if configured
            UoWChaosEngine.hit(UoWChaosEngine.Point.FLOW_INVOKE);

            // Set mock output variables if configured
            if (!mockOutputVariables.isEmpty()) {
                workItem.flowOutputs = new Map<String, Object>(mockOutputVariables);
            }
        }
    }

    // ============================================================================
    // CALLOUT STRATEGY MOCKS
    // ============================================================================

    /**
     * Mock callout strategy for HTTP callout testing.
     * TRUE MOCK - Does NOT make real HTTP callouts, simulates responses via ChaosEngine.
     *
     * Benefits:
     * - No actual HTTP callouts (faster tests, no external dependencies)
     * - No Named Credentials required
     * - Can simulate specific failure scenarios (timeouts, HTTP errors)
     * - Phase tracking for verifying PRE_DML vs ON_FAILURE execution
     *
     * Usage:
     *   MockCalloutStrategy mockStrategy = new UoWTestMocks.MockCalloutStrategy();
     *   uow.withCalloutStrategy(mockStrategy);
     *
     * Phase verification:
     *   Assert.areEqual(1, mockStrategy.preDmlCallouts.size(), 'Should have 1 PRE_DML callout');
     *   Assert.areEqual(1, mockStrategy.onFailureCallouts.size(), 'Should have 1 ON_FAILURE callout');
     *
     * Failure simulation:
     *   UoWChaosEngine.alwaysFail(UoWChaosEngine.Point.CALLOUT,
     *       new CalloutException('Connection refused'));
     */
    public class MockCalloutStrategy implements UoWInterfaces.ICalloutStrategy {
        // Mock response for successful callouts
        private String strategyName;
        public Integer mockStatusCode = 200;
        public String mockStatus = 'OK';
        public String mockResponseBody = '{}';

        // Phase tracking - captured work items by phase
        public List<UoWCalloutWorkItem> preDmlCallouts = new List<UoWCalloutWorkItem>();
        public List<UoWCalloutWorkItem> onFailureCallouts = new List<UoWCalloutWorkItem>();
        public List<UoWCalloutWorkItem> allCallouts = new List<UoWCalloutWorkItem>();

        public MockCalloutStrategy(){
            this.strategyName = 'MockCalloutStrategy';
        }

        public MockCalloutStrategy(String name){
            this.strategyName = name;
        }

        public String getName() {
            return this.strategyName;
        }

        /**
         * Reset all captured callouts.
         * Call this between test scenarios if reusing the same mock instance.
         */
        public void reset() {
            preDmlCallouts.clear();
            onFailureCallouts.clear();
            allCallouts.clear();
        }

        public void executeCallout(UoWCalloutWorkItem workItem, UoWContext ctx) {
            // ChaosEngine throws exception if configured
            UoWChaosEngine.hit(UoWChaosEngine.Point.CALLOUT);

            // Track by phase for verification
            allCallouts.add(workItem);
            if (workItem.executionPhase == UoWEnums.WorkPhase.PRE_DML) {
                preDmlCallouts.add(workItem);
            } else if (workItem.executionPhase == UoWEnums.WorkPhase.ON_FAILURE) {
                onFailureCallouts.add(workItem);
            }

            // Create mock response
            HttpResponse mockResponse = new HttpResponse();
            mockResponse.setStatusCode(mockStatusCode);
            mockResponse.setStatus(mockStatus);
            mockResponse.setBody(mockResponseBody);
            workItem.response = mockResponse;
        }
    }

    /**
     * Mock HTTP callout for testing HTTP-based work items.
     * Use with Test.setMock(HttpCalloutMock.class, mockCallout).
     *
     * Usage:
     *   MockHttpCallout mockCallout = new UoWTestMocks.MockHttpCallout();
     *   mockCallout.statusCode = 200;
     *   mockCallout.responseBody = '{"success": true}';
     *   Test.setMock(HttpCalloutMock.class, mockCallout);
     */
    public class MockHttpCallout implements HttpCalloutMock {
        // Configuration
        public Integer statusCode = 200;
        public String responseBody = '{"status": "success"}';
        public Map<String, String> responseHeaders = new Map<String, String>();

        public HTTPResponse respond(HTTPRequest req) {
            // ChaosEngine throws exception if configured
            UoWChaosEngine.hit(UoWChaosEngine.Point.CALLOUT);

            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(responseBody);

            // Set custom headers if provided
            for (String headerName : responseHeaders.keySet()) {
                res.setHeader(headerName, responseHeaders.get(headerName));
            }

            return res;
        }
    }

    // ============================================================================
    // PLUGIN MOCKS
    // ============================================================================

    /**
     * Mock plugin with configurable behavior for lifecycle testing.
     * Extends UoWBasePlugin to inherit default implementations.
     *
     * Usage:
     *   MockPlugin plugin = new UoWTestMocks.MockPlugin('TestPlugin');
     *   plugin.isCriticalPlugin = true;
     *   plugin.shouldFailOnBeforeCommit = true;
     *   uow.registerPlugin(plugin);
     */
    public class MockPlugin extends UoWBasePlugin {
        // Configuration
        public Boolean isCriticalPlugin = false;
        public Boolean shouldFailOnBeforeCommit = false;
        public Boolean shouldFailOnAfterCommit = false;
        public Boolean shouldFailOnError = false;
        public Boolean shouldFailOnFinally = false;
        public String failureMessage = 'Mock plugin failure';

        public MockPlugin() {
            super('MockPlugin');
        }

        public MockPlugin(String name) {
            super(name);
        }

        public override Boolean isCritical() {
            return isCriticalPlugin;
        }

        public override UoWPluginExecutor.PhaseResult onBeforeCommit(UoWContext ctx, UoWPlan plan, UoWResult result) {
            // Plugin now has direct access to result - log there
            result.info(this.getName() + ' onBeforeCommit executed', 'MockPlugin');
            if (shouldFailOnBeforeCommit) {
                throw new UoWExceptionService.UoWException(failureMessage);
            }
            return UoWPluginExecutor.PhaseResult.EXECUTED;
        }

        public override UoWPluginExecutor.PhaseResult onAfterCommit(UoWContext ctx, UoWResult result) {
            // Plugin has direct access to result - log there
            result.info(this.getName() + ' onAfterCommit executed', 'MockPlugin');
            if (shouldFailOnAfterCommit) {
                throw new UoWExceptionService.UoWException(failureMessage);
            }
            return UoWPluginExecutor.PhaseResult.EXECUTED;
        }

        public override UoWPluginExecutor.PhaseResult onError(UoWContext ctx, Exception ex, UoWResult result) {
            // Plugin now has direct access to result - log there
            result.info(this.getName() + ' onError executed', 'MockPlugin');
            if (shouldFailOnError) {
                throw new UoWExceptionService.UoWException(failureMessage);
            }
            return UoWPluginExecutor.PhaseResult.EXECUTED;
        }

        public override UoWPluginExecutor.PhaseResult onFinally(UoWContext ctx, UoWResult result) {
            // Plugin has direct access to result - log there
            result.info(this.getName() + ' onFinally executed', 'MockPlugin');
            if (shouldFailOnFinally) {
                throw new UoWExceptionService.UoWException(failureMessage);
            }
            return UoWPluginExecutor.PhaseResult.EXECUTED;
        }
    }

    // ============================================================================
    // POLICY MOCKS
    // ============================================================================

    /**
     * Mock policy with configurable actions for policy testing.
     * Extends UoWBasePolicy to inherit default implementations.
     *
     * Usage:
     *   MockPolicy policy = new UoWTestMocks.MockPolicy('TestPolicy');
     *   policy.actionToReturn = UoWEnums.PolicyAction.REQUIRE_APPROVAL;
     *   policy.reasonMessage = 'High risk detected';
     *   uow.registerPolicy(policy);
     */
    public class MockPolicy extends UoWBasePolicy {
        // Configuration
        public UoWEnums.PolicyAction actionToReturn = UoWEnums.PolicyAction.ALLOW;
        public String reasonMessage = 'Mock policy evaluation';
        public Map<String, Object> evidenceData = new Map<String, Object>();
        public List<UoWRiskTypes.RiskFactor> riskFactors = new List<UoWRiskTypes.RiskFactor>();
        public Boolean shouldThrowException = false;
        public String exceptionMessage = 'Mock policy exception';
        public Boolean mockIsCritical = true;  // Default true (fail-safe)

        public MockPolicy() {
            super('MockPolicy');
        }

        public MockPolicy(String name) {
            super(name);
        }

        public override Boolean isCritical() {
            return mockIsCritical;
        }

        public override List<UoWPolicyEvaluation.Evaluation> evaluatePlan(UoWContext ctx, UoWPlan plan) {
            if (shouldThrowException) {
                throw new UoWExceptionService.UoWException(exceptionMessage);
            }

            // Call parent to properly iterate all work types (DML, Event, Email, etc.)
            // This ensures evaluate() is called for each work item
            return super.evaluatePlan(ctx, plan);
        }

        public override UoWPolicyEvaluation.Evaluation evaluate(UoWContext ctx, UoWWorkItem workItem) {
            if (shouldThrowException) {
                throw new UoWExceptionService.UoWException(exceptionMessage);
            }

            UoWPolicyEvaluation.Evaluation eval;
            switch on actionToReturn {
                when ALLOW {
                    eval = createAllowEvaluation();
                }
                when DENY {
                    eval = createDenyEvaluation(reasonMessage);
                }
                when REQUIRE_APPROVAL {
                    eval = createApprovalRequiredEvaluation(reasonMessage);
                }
                when ALLOW_WITH_JUSTIFICATION {
                    eval = createWarningEvaluation(reasonMessage);
                }
                when else {
                    eval = new UoWPolicyEvaluation.Evaluation(this.policyName);
                    eval.action = actionToReturn;
                    eval.reason = reasonMessage;
                }
            }
            eval.evidence.putAll(evidenceData);
            return eval;
        }
    }

    // ============================================================================
    // RISK ASSESSOR MOCKS
    // ============================================================================

    /**
     * Mock risk assessor with configurable scores and levels.
     *
     * Usage:
     *   MockRiskAssessor assessor = new UoWTestMocks.MockRiskAssessor();
     *   assessor.riskScore = 85;
     *   assessor.riskLevel = UoWRiskTypes.RiskLevel.CRITICAL;
     *   uow.registerRiskAssessor(assessor);
     */
    public class MockRiskAssessor implements UoWInterfaces.IRiskAssessor {
        // Configuration
        public String assessorName;
        public Integer riskScore = 0;
        public UoWRiskTypes.RiskLevel riskLevel = UoWRiskTypes.RiskLevel.NONE;
        public Boolean requiresApproval = false;
        public Boolean shouldThrowException = false;
        public String exceptionMessage = 'Mock risk assessor exception';

        public MockRiskAssessor(){
            this.assessorName = 'MockRiskAssessor';
        }

        public MockRiskAssessor(String name){
            this.assessorName = name;
        }

        public String getName() {
            return assessorName;
        }

        public UoWRiskTypes.RiskAssessment assessRisk(UoWContext ctx, UoWPlan plan) {
            if (shouldThrowException) {
                throw new UoWExceptionService.UoWException(exceptionMessage);
            }

            UoWRiskTypes.RiskAssessment assessment = new UoWRiskTypes.RiskAssessment();
            assessment.riskScore = riskScore;
            assessment.riskLevel = riskLevel;
            assessment.requiresApproval = requiresApproval || (riskLevel == UoWRiskTypes.RiskLevel.HIGH || riskLevel == UoWRiskTypes.RiskLevel.CRITICAL);
            if(assessment.requiresApproval){
                assessment.approvalReason = 'Approval is needed for high or critical risk';
            }

            if(riskLevel == UoWRiskTypes.RiskLevel.HIGH || riskLevel == UoWRiskTypes.RiskLevel.CRITICAL){
                UoWRiskTypes.RiskFactor factor = new UoWRiskTypes.RiskFactor('High Risk Object', riskScore, assessorName)
                                                        .withCategory(UoWRiskTypes.RiskFactorCategory.CUSTOM_OBJECT);
                assessment.addRiskFactor(factor);
            }

            return assessment;
        }
    }

    // ============================================================================
    // APPROVAL CHANNEL MOCK
    // ============================================================================

    /**
     * Mock approval channel for testing approval workflows.
     *
     * Usage:
     *   MockApprovalChannel channel = new UoWTestMocks.MockApprovalChannel();
     *   UoWApprovalService.registerApprovalChannel(channel);
     */
    public class MockApprovalChannel implements UoWInterfaces.IApprovalChannel {
        private String approvalChannelName;

        public MockApprovalChannel(){
            this.approvalChannelName = 'MockApprovalChannel';
        }

        public MockApprovalChannel(String name){
            this.approvalChannelName = name;
        }

        public String getName() {
            return this.approvalChannelName;
        }

        public UoWResult requestApproval(UoWContext context, UoWPlan plan, UoWResult result) {
            // Mock approval request - return partial result with PENDING_APPROVAL status
            result.setMetadata('approvalRecordId', 'MOCK_APPROVAL_ID');
            result.markComplete(UoWEnums.TransactionStatus.PENDING_APPROVAL);
            return result;
        }

        public UoWResult continueAfterApproval(String approvalId, UoWContext context, UoWPlan plan) {
            // Mock approval resumption - execute transaction and return result
            UnitOfWork uow = new UnitOfWork(context, plan);
            return uow.commitWork(UoWEnums.CommitMode.SYNC);
        }
    }

    // ============================================================================
    // TRANSACTION FINALIZER MOCK
    // ============================================================================

    /**
     * Mock implementation of ITransactionFinalizer for testing.
     * Implements the platform Finalizer interface for async execution finalization.
     *
     * To test async execution results, use UoWQueueable.getFinalizerState():
     *
     * @example Testing async execution result
     * Test.startTest();
     * UoWResult parentResult = uow.commitWork(UoWEnums.CommitMode.ASYNC);
     * Test.stopTest();
     *
     * // Get async result via static accessor (set in UoWQueueable's finally block)
     * UoWQueueable.FinalizerState asyncState = UoWQueueable.getFinalizerState();
     * UoWResult asyncResult = asyncState.result;
     * Assert.isTrue(asyncResult.isSuccess());
     */
    public class MockTransactionFinalizer implements UoWInterfaces.ITransactionFinalizer {
        public Integer executeCallCount = 0;
        public FinalizerContext capturedFinalizerContext;
        public String mockName = 'MockTransactionFinalizer';

        public String getName() {
            return mockName;
        }

        public void execute(FinalizerContext fc) {
            executeCallCount++;
            capturedFinalizerContext = fc;
        }
    }

    // ============================================================================
    // EVENT PUBLISH FAILURE HANDLER MOCK
    // ============================================================================

    /**
     * Mock implementation of IEventPublishFailureHandler for testing.
     * Captures failure context for assertion in tests.
     *
     * When dynamically instantiated (via Type.forName by UoWDefaultPublishFailureCallback),
     * use the outer-class statics for verification: UoWTestMocks.eventFailureHandlerCallCount,
     * UoWTestMocks.eventFailureCapturedContext, UoWTestMocks.eventFailureHandlerShouldThrow.
     *
     * @example Testing failure handler resolution
     * UoWTestMocks.MockEventPublishFailureHandler mockHandler =
     *     new UoWTestMocks.MockEventPublishFailureHandler();
     * UnitOfWork uow = new UnitOfWork()
     *     .withEventPublishFailureHandler(mockHandler);
     */
    public class MockEventPublishFailureHandler implements UoWInterfaces.IEventPublishFailureHandler {
        public String mockName = 'MockEventPublishFailureHandler';
        public Integer handleFailureCallCount = 0;
        public UoWEventPublishFailureContext capturedFailureContext;

        public String getName() {
            return mockName;
        }

        public void handleFailure(UoWEventPublishFailureContext failureContext) {
            handleFailureCallCount++;
            capturedFailureContext = failureContext;
            // Write to outer-class statics for dynamic instantiation verification
            UoWTestMocks.eventFailureHandlerCallCount++;
            UoWTestMocks.eventFailureCapturedContext = failureContext;
            if (UoWTestMocks.eventFailureHandlerShouldThrow) {
                throw new UoWExceptionService.UoWException('Simulated handler failure');
            }
        }
    }

    // ============================================================================
    // WRONG INTERFACE STUB (for testing interface mismatch scenarios)
    // ============================================================================

    /**
     * Stub class that exists and has a no-arg constructor but does NOT implement
     * any UoW interfaces. Used to test the UoW_Error_ExtDoesNotImplement error path
     * in UoWExtensibilityInstantiator.
     */
    public class WrongInterfaceStub {
        public String stubName;

        public WrongInterfaceStub() {
            this.stubName = 'WrongInterfaceStub';
        }
    }
}