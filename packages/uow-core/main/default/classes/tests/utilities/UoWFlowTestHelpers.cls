//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Test helper utilities for UoW framework tests for flow actions. Provides assertion helpers,
 * test data generation methods, and debugging utilities for comprehensive testing.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Test Utilities
 * @see UoWFlowActionsTests
 */
@isTest
public with sharing class UoWFlowTestHelpers {

    // ============================================================================
    // TRANSACTION MANAGEMENT
    // ============================================================================

    /**
     * Initialize a Flow transaction.
     *
     * @return Transaction ID
     */
    public static String initializeTransaction() {
        UoWFlowInitializeAction.InitializeRequest request = new UoWFlowInitializeAction.InitializeRequest();
        request.configurationName = 'TestConfigAllMocks';

        List<UoWFlowInitializeAction.InitializeResult> results = UoWFlowInitializeAction.initialize(new List<UoWFlowInitializeAction.InitializeRequest>{ request });

        return results[0].transactionId;
    }

    /**
     * Commit a Flow transaction.
     *
     * @param transactionId Transaction ID from initialize
     * @return Commit result
     */
    public static UoWFlowCommitAction.CommitResult commitTransaction(String transactionId) {
        UoWFlowCommitAction.CommitRequest request = new UoWFlowCommitAction.CommitRequest();
        request.transactionId = transactionId;

        List<UoWFlowCommitAction.CommitResult> results = UoWFlowCommitAction.commitTransaction(new List<UoWFlowCommitAction.CommitRequest>{ request });

        return results[0];
    }

    // ============================================================================
    // REQUEST BUILDERS
    // ============================================================================
    public static UoWFlowRegisterInsertAction.RegistrationRequest buildRegisterInsertRequest(String transactionId, List<SObject> records) {
        UoWFlowRegisterInsertAction.RegistrationRequest insertRequest = new UoWFlowRegisterInsertAction.RegistrationRequest();
        insertRequest.transactionId = transactionId;
        insertRequest.records = records;
        insertRequest.continueOnError = false;
        insertRequest.flowName = 'My Agent Flow';
        return insertRequest;
    }

    public static UoWFlowRegisterUpsertAction.RegistrationRequest buildRegisterUpsertRequest(String transactionId, List<SObject> records) {
        UoWFlowRegisterUpsertAction.RegistrationRequest upsertRequest = new UoWFlowRegisterUpsertAction.RegistrationRequest();
        upsertRequest.transactionId = transactionId;
        upsertRequest.records = records;
        upsertRequest.externalIdField = 'Id';
        upsertRequest.continueOnError = false;
        upsertRequest.flowName = 'My Agent Flow';
        return upsertRequest;
    }

    public static UoWFlowRegisterUpdateAction.RegistrationRequest buildRegisterUpdateRequest(String transactionId, List<SObject> records) {
        UoWFlowRegisterUpdateAction.RegistrationRequest updateRequest = new UoWFlowRegisterUpdateAction.RegistrationRequest();
        updateRequest.transactionId = transactionId;
        updateRequest.records = records;
        updateRequest.continueOnError = false;
        updateRequest.flowName = 'My Agent Flow';
        return updateRequest;
    }

    public static UoWFlowRegisterDeleteAction.RegistrationRequest buildRegisterDeleteRequest(String transactionId, List<SObject> records) {
        UoWFlowRegisterDeleteAction.RegistrationRequest deleteRequest = new UoWFlowRegisterDeleteAction.RegistrationRequest();
        deleteRequest.transactionId = transactionId;
        deleteRequest.records = records;
        deleteRequest.continueOnError = false;
        deleteRequest.flowName = 'My Agent Flow';
        return deleteRequest;
    }

    public static UoWFlowRegisterUndeleteAction.RegistrationRequest buildRegisterUndeleteRequest(String transactionId, List<SObject> records) {
        UoWFlowRegisterUndeleteAction.RegistrationRequest undeleteRequest = new UoWFlowRegisterUndeleteAction.RegistrationRequest();
        undeleteRequest.transactionId = transactionId;
        undeleteRequest.records = records;
        undeleteRequest.continueOnError = false;
        undeleteRequest.flowName = 'My Agent Flow';
        return undeleteRequest;
    }

    public static UoWFlowRegisterPlatformEventAction.RegistrationRequest buildRegisterPlatformEventRequest(String transactionId, List<SObject> records) {
        UoWFlowRegisterPlatformEventAction.RegistrationRequest platformEventRequest = new UoWFlowRegisterPlatformEventAction.RegistrationRequest();
        platformEventRequest.transactionId = transactionId;
        platformEventRequest.platformEvents = records;
        platformEventRequest.executionPhase = UoWEnums.WorkPhase.POST_DML.name();
        platformEventRequest.continueOnError = false;
        platformEventRequest.flowName = 'My Agent Flow';
        return platformEventRequest;
    }

    public static UoWFlowRegisterEmailAction.RegistrationRequest buildRegisterEmailRequest(String transactionId, String toAddresses) {
        UoWFlowRegisterEmailAction.RegistrationRequest emailRequest = new UoWFlowRegisterEmailAction.RegistrationRequest();
        emailRequest.transactionId = transactionId;
        emailRequest.toAddresses = toAddresses;
        emailRequest.ccAddresses = 'cc@example.com';
        emailRequest.bccAddresses = 'bcc@example.com';
        emailRequest.subject = 'Test Subject';
        emailRequest.plainTextBody = 'Plain text';
        emailRequest.htmlBody = '<html>HTML body</html>';
        emailRequest.saveAsActivity = true;
        emailRequest.executionPhase = UoWEnums.WorkPhase.ON_SUCCESS.name();
        emailRequest.flowName = 'My Agent Flow';
        return emailRequest;
    }

    public static UoWFlowRegisterNotificationAction.RegistrationRequest buildRegisterNotificationRequest(String transactionId) {
        UoWFlowRegisterNotificationAction.RegistrationRequest notificationRequest = new UoWFlowRegisterNotificationAction.RegistrationRequest();
        notificationRequest.transactionId = transactionId;
        notificationRequest.notificationTypeId = UoWTestHelpers.generateFakeId(CustomNotificationType.SObjectType, 1);
        notificationRequest.notificationTypeName = 'TestNotification';
        notificationRequest.recipientUserIds = new List<String>{ UserInfo.getUserId(), UoWTestHelpers.generateFakeId(User.SObjectType, 1) };
        notificationRequest.title = 'Test Notification';
        notificationRequest.body = 'Test body';
        notificationRequest.targetRecordId = UserInfo.getUserId();
        notificationRequest.executionPhase = UoWEnums.WorkPhase.ON_SUCCESS.name();
        notificationRequest.continueOnError = false;
        notificationRequest.flowName = 'My Agent Flow';
        return notificationRequest;
    }

    public static UoWFlowRegisterFlowExecutionAction.RegistrationRequest buildRegisterFlowExecutionRequest(String transactionId, String flowApiName) {
        UoWFlowRegisterFlowExecutionAction.RegistrationRequest flowExecutionRequest = new UoWFlowRegisterFlowExecutionAction.RegistrationRequest();
        flowExecutionRequest.transactionId = transactionId;
        flowExecutionRequest.flowApiName = flowApiName;
        flowExecutionRequest.flowInputVariablesJson = '{"recordId":"001000000000000","status":"Active"}';
        flowExecutionRequest.executionPhase = UoWEnums.WorkPhase.POST_DML.name();
        flowExecutionRequest.continueOnError = false;
        flowExecutionRequest.flowName = 'My Agent Flow';
        return flowExecutionRequest;
    }

    public static UoWFlowRegisterCalloutAction.RegistrationRequest buildRegisterCalloutRequest(String transactionId, String endpoint) {
        UoWFlowRegisterCalloutAction.RegistrationRequest calloutRequest = new UoWFlowRegisterCalloutAction.RegistrationRequest();
        calloutRequest.transactionId = transactionId;
        calloutRequest.endpoint = endpoint;
        calloutRequest.executionPhase = UoWEnums.WorkPhase.PRE_DML.name();
        calloutRequest.httpMethod = 'POST';
        calloutRequest.requestBody = '{"test":"data"}';
        calloutRequest.contentType = 'application/json';
        calloutRequest.customHeadersJson = '{"Authorization":"Bearer token","X-Custom-Header":"value"}';
        calloutRequest.queryParamsJson = '{"param1":"value1","param2":"value2"}';
        calloutRequest.timeoutMs = 30000;
        calloutRequest.continueOnError = false;
        calloutRequest.flowName = 'My Agent Flow';
        return calloutRequest;
    }

}