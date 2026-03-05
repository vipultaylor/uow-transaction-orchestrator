//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Flow invocable action to register email operations in a Unit of Work transaction.
 *
 * Registers emails to be sent as part of the transaction. Supports both template-based
 * and custom emails with full control over recipients, content, and execution phase.
 *
 * Flow Pattern (Simple):
 * [Register Email]
 *   Transaction ID: {!transactionId}
 *   To Addresses: user@example.com
 *   Subject: Record Created
 *   Plain Text Body: Your record has been created successfully.
 *
 * Flow Pattern (Template):
 * [Register Email]
 *   Transaction ID: {!transactionId}
 *   Email Template ID: {!templateId}
 *   Target Object ID: {!contactId}
 *   What ID: {!recordId}
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Flow Actions
 * @see UoWFlowInitializeAction
 * @see UoWFlowCommitAction
 */
public inherited sharing class UoWFlowRegisterEmailAction {
    // ============================================================================
    // INVOCABLE METHOD
    // ============================================================================

    /**
     * Register email for sending in Unit of Work transaction
     *
     * @param requests List of email registration requests (Flow passes single-item list)
     * @return List of registration results
     */
    @InvocableMethod(
        label='UoW: Register Email'
        description='Register email to be sent as part of Unit of Work transaction'
        category='Unit of Work'
    )
    public static List<RegistrationResult> registerEmail(List<RegistrationRequest> requests) {
        List<RegistrationResult> results = new List<RegistrationResult>();

        for (RegistrationRequest request : requests) {
            RegistrationResult result = new RegistrationResult();

            try {
                // Validate inputs
                UoWExceptionService.requireNonBlank(request.transactionId, 'Transaction ID');

                // Validate either addresses or template
                if (String.isBlank(request.toAddresses) && String.isBlank(request.emailTemplateId)) {
                    throw new UoWExceptionService.UoWException('Either To Addresses or Email Template ID is required');
                }

                // Retrieve UnitOfWork instance
                UnitOfWork uow = UoWFlowTransactionRegistry.get(request.transactionId);

                // Build email
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();

                // Addresses
                if (String.isNotBlank(request.toAddresses)) {
                    email.setToAddresses(request.toAddresses.split(','));
                }
                if (String.isNotBlank(request.ccAddresses)) {
                    email.setCcAddresses(request.ccAddresses.split(','));
                }
                if (String.isNotBlank(request.bccAddresses)) {
                    email.setBccAddresses(request.bccAddresses.split(','));
                }

                // Content (template or custom)
                if (String.isNotBlank(request.emailTemplateId)) {
                    email.setTemplateId(request.emailTemplateId);
                    if (String.isNotBlank(request.targetObjectId)) {
                        email.setTargetObjectId(request.targetObjectId);
                    }
                    if (String.isNotBlank(request.whatId)) {
                        email.setWhatId(request.whatId);
                    }
                } else {
                    if (String.isNotBlank(request.subject)) {
                        email.setSubject(request.subject);
                    }
                    if (String.isNotBlank(request.plainTextBody)) {
                        email.setPlainTextBody(request.plainTextBody);
                    }
                    if (String.isNotBlank(request.htmlBody)) {
                        email.setHtmlBody(request.htmlBody);
                    }
                }

                // Options
                if (String.isNotBlank(request.orgWideEmailAddressId)) {
                    email.setOrgWideEmailAddressId(request.orgWideEmailAddressId);
                }
                if (request.saveAsActivity != null) {
                    email.setSaveAsActivity(request.saveAsActivity);
                }

                // Parse execution phase (if specified)
                UoWEnums.WorkPhase phase = String.isNotBlank(request.executionPhase)
                    ? UoWFlowActionHelpers.parseWorkPhase(request.executionPhase)
                    : null;

                // Register email with phase (or use default)
                UoWEmailWorkItem workItem = uow.registerEmail(email, phase);

                // Set Flow origin for audit tracking
                if (String.isNotBlank(request.flowName)) {
                    workItem.withOrigin(UoWFlowActionHelpers.ORIGIN_TYPE_FLOW, request.flowName);
                }

                // Configure error handling mode
                if (request.continueOnError != null) {
                    workItem.continueOnError = request.continueOnError;
                }

                // Success
                result.success = true;
                result.workItemId = workItem.workId;
                result.message = 'Email registered successfully';

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
     * Input parameters for email registration
     */
    public class RegistrationRequest {
        @InvocableVariable(
            label='Transaction ID'
            description='Transaction ID from Initialize Transaction action'
            required=true
        )
        public String transactionId;

        // ========================================================================
        // RECIPIENTS
        // ========================================================================

        @InvocableVariable(
            label='To Addresses'
            description='Comma-separated email addresses (e.g., user1@example.com,user2@example.com). Required if not using template.'
        )
        public String toAddresses;

        @InvocableVariable(
            label='CC Addresses'
            description='Comma-separated CC email addresses'
        )
        public String ccAddresses;

        @InvocableVariable(
            label='BCC Addresses'
            description='Comma-separated BCC email addresses'
        )
        public String bccAddresses;

        // ========================================================================
        // CONTENT (Template or Custom)
        // ========================================================================

        @InvocableVariable(
            label='Email Template ID'
            description='Email template ID to use (alternative to Subject/Body)'
        )
        public String emailTemplateId;

        @InvocableVariable(
            label='Target Object ID'
            description='WhoId for template (typically Contact, Lead, or User ID)'
        )
        public String targetObjectId;

        @InvocableVariable(
            label='What ID'
            description='WhatId for template (related record ID for merge fields)'
        )
        public String whatId;

        @InvocableVariable(
            label='Subject'
            description='Email subject (required if not using template)'
        )
        public String subject;

        @InvocableVariable(
            label='Plain Text Body'
            description='Plain text email body'
        )
        public String plainTextBody;

        @InvocableVariable(
            label='HTML Body'
            description='HTML email body'
        )
        public String htmlBody;

        // ========================================================================
        // OPTIONS
        // ========================================================================

        @InvocableVariable(
            label='Org-Wide Email Address ID'
            description='Org-Wide Email Address ID to send from'
        )
        public String orgWideEmailAddressId;

        @InvocableVariable(
            label='Save As Activity'
            description='Create Task record for this email (default: true)'
        )
        public Boolean saveAsActivity;

        @InvocableVariable(
            label='Execution Phase'
            description='When to send email: POST_DML, ON_SUCCESS (default), ON_FAILURE, ON_FINALIZATION'
        )
        public String executionPhase;

        @InvocableVariable(
            label='Continue On Error'
            description='Continue transaction if email fails (default: true for emails)'
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
     * Output results from email registration
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