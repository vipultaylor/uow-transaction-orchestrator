//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Email work item for sending emails.
 * Contains emails and send results.
 *
 * STORAGE PATTERN:
 * - emailsList (transient): Original Messaging.Email objects for sending
 * - snapshots (serializable): Enriched audit snapshots pairing emails with results
 *
 * Serialization scenarios:
 * - Async execution: snapshots with email metadata only (no result data)
 * - Audit snapshots: snapshots = enriched EmailSnapshot with error-priority sampling
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Work Items
 * @see UoWWorkItem
 * @see UoWEmailExecutionService
 */
public inherited sharing class UoWEmailWorkItem extends UoWWorkItem {

    // ============================================================================
    // PUBLIC PROPERTIES - EXECUTION
    // ============================================================================

    public UoWEnums.WorkPhase executionPhase;

    // ============================================================================
    // PUBLIC PROPERTIES - SEND RESULTS (transient)
    // ============================================================================

    public transient List<Messaging.SendEmailResult> sendResults;

    // ============================================================================
    // PRIVATE PROPERTIES - EMAIL STORAGE
    // ============================================================================

    // Original emails for sending (transient - Messaging.Email not serializable)
    private transient List<Messaging.Email> emailsList;

    // Enriched snapshots - pairs email metadata with send results
    // For async: contains email metadata only (no result data)
    // For audit: contains metadata + result data with error-priority sampling
    @TestVisible
    private List<EmailSnapshot> snapshots;

    // Indices of failed emails - populated during processResults()
    @TestVisible
    private transient Set<Integer> failedIndices;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Create a new Email work item.
     *
     * @param phase Execution phase (POST_DML, ON_SUCCESS, ON_FAILURE, ON_FINALIZATION)
     * @param emails List of Messaging.Email objects to send
     */
    public UoWEmailWorkItem(UoWEnums.WorkPhase phase, List<Messaging.Email> emails) {
        super(UoWEnums.WorkType.EMAIL);
        this.executionPhase = phase ?? UoWEnums.WorkPhase.ON_SUCCESS;
        this.emailsList = emails ?? new List<Messaging.Email>();
        this.statistics.planned = this.emailsList.size();
        this.continueOnError = true;
    }

    // ============================================================================
    // PUBLIC API - FLUENT CONFIGURATION
    // ============================================================================

    /**
     * Continue execution even if email sending fails (default behavior for emails).
     *
     * @return This work item for fluent chaining
     */
    public UoWEmailWorkItem continueOnError() {
        this.continueOnError = true;
        return this;
    }

    /**
     * Fail-fast if email sending fails (override default for critical emails).
     *
     * @return This work item for fluent chaining
     */
    public UoWEmailWorkItem failFast() {
        this.continueOnError = false;
        return this;
    }

    // ============================================================================
    // PUBLIC API - EMAIL ACCESS
    // ============================================================================

    /**
     * Get the list of emails in this work item.
     * This is a method (not a property) to prevent JSON serialization of
     * non-serializable Messaging.Email objects.
     *
     * @return List of Messaging.Email objects
     */
    public List<Messaging.Email> getEmails() {
        return this.emailsList;
    }

    // ============================================================================
    // PUBLIC API - EMAIL MANAGEMENT
    // ============================================================================

    /**
     * Add emails to this work item (for consolidation).
     *
     * @param newEmails Emails to add
     */
    public void addEmails(List<Messaging.Email> newEmails) {
        if (newEmails == null || newEmails.isEmpty()) { return; }
        this.emailsList.addAll(newEmails);
        this.statistics.planned += newEmails.size();
    }

    // ============================================================================
    // PUBLIC API - RESULT PROCESSING
    // ============================================================================

    /**
     * Process email send results - extract errors and calculate statistics.
     * Single pass through Messaging.SendEmailResult objects to:
     * 1. Count successes and failures
     * 2. Extract Messaging.SendEmailError objects as ErrorInfo
     * 3. Track failed indices for error-priority sampling
     * Called after email sending completes.
     *
     * Handles two scenarios:
     * 1. Normal execution: sendResults exist
     * 2. Exception thrown: No results, but errors already captured via addError()
     */
    public override void processResults() {
        initializeStatistics();

        if (this.sendResults == null && this.hasErrors()) {
            this.statistics.failures = this.statistics.processed;
            // Mark all as failed when exception occurred
            for (Integer i = 0; i < this.statistics.processed; i++) {
                this.failedIndices.add(i);
            }
            return;
        }

        if (this.sendResults != null) {
            processAllSendResults();
        }
    }

    /**
     * Finalize work item status based on execution results.
     * Sets status to SUCCESS, PARTIAL_SUCCESS, FAILED, or NOT_EXECUTED.
     */
    public override void finalizeStatus() {
        if (!this.isExecuted) {
            this.status = UoWEnums.WorkStatus.NOT_EXECUTED;
            return;
        }

        if (this.statistics.successes > 0 && this.statistics.failures > 0) {
            this.status = UoWEnums.WorkStatus.PARTIAL_SUCCESS;
        } else if (this.statistics.failures > 0) {
            this.status = UoWEnums.WorkStatus.FAILED;
        } else {
            this.status = UoWEnums.WorkStatus.SUCCESS;
        }
    }

    // ============================================================================
    // PRIVATE METHODS - RESULT PROCESSING HELPERS
    // ============================================================================

    // Initialize statistics counters
    private void initializeStatistics() {
        List<Messaging.Email> emails = this.getEmails();
        this.statistics.processed = emails?.size() ?? 0;
        this.statistics.successes = 0;
        this.statistics.failures = 0;
        this.failedIndices = new Set<Integer>();
    }

    // Process all send results, counting successes/failures and extracting errors
    private void processAllSendResults() {
        for (Integer i = 0; i < this.sendResults.size(); i++) {
            Messaging.SendEmailResult ser = this.sendResults[i];
            if (ser.isSuccess()) {
                this.statistics.successes++;
            } else {
                this.statistics.failures++;
                this.failedIndices.add(i);
                extractErrorsFromResult(ser, i);
            }
        }
    }

    // Extract errors from a failed send result
    private void extractErrorsFromResult(Messaging.SendEmailResult ser, Integer emailIndex) {
        if (ser.getErrors() == null) {
            return;
        }

        for (Messaging.SendEmailError err : ser.getErrors()) {
            this.addError(buildErrorInfo(err, emailIndex));
        }
    }

    // Build ErrorInfo from a SendEmailError
    private UoWExceptionService.ErrorInfo buildErrorInfo(Messaging.SendEmailError err, Integer emailIndex) {
        String statusCodeStr = err.getStatusCode() != null ?
            String.valueOf(err.getStatusCode()) : 'UNKNOWN';

        UoWExceptionService.ErrorInfo error = new UoWExceptionService.ErrorInfo(
            statusCodeStr,
            String.format(
                'EMAIL_SEND operation failed at index {0}: {1}',
                new String[]{ String.valueOf(emailIndex), err.getMessage() }
            )
        );

        error.errorContext.put('operation', 'EMAIL_SEND');
        error.errorContext.put('emailIndex', emailIndex);
        error.errorContext.put('statusCode', statusCodeStr);

        if (err.getTargetObjectId() != null) {
            error.errorContext.put('targetObjectId', err.getTargetObjectId());
        }

        List<String> errorFields = err.getFields();
        if (errorFields != null && !errorFields.isEmpty()) {
            error.errorContext.put('fields', errorFields);
        }

        error.isRetryable = true;

        return error;
    }

    // ============================================================================
    // PUBLIC API - SERIALIZATION LIFECYCLE (Override)
    // ============================================================================

    /**
     * Capture email metadata before serialization (async execution).
     * Builds snapshots with email metadata only (no result data).
     * Messaging.Email objects cannot be serialized, so we extract
     * properties to EmailMetadata objects stored in snapshots.
     */
    public override void prepareForSerialization() {
        super.prepareForSerialization();
        this.snapshots = new List<EmailSnapshot>();

        if (this.emailsList == null || this.emailsList.isEmpty()) {
            return;
        }

        for (Integer i = 0; i < this.emailsList.size(); i++) {
            Messaging.Email email = this.emailsList[i];
            if (email instanceof Messaging.SingleEmailMessage) {
                EmailSnapshot snap = new EmailSnapshot();
                snap.idx = i;
                snap.meta = new EmailMetadata().captureFrom((Messaging.SingleEmailMessage) email);
                this.snapshots.add(snap);
            }
            // Note: MassEmailMessage support can be added later if needed
        }
    }

    /**
     * Capture email metadata with configuration before serialization.
     * Builds enriched snapshots with error-priority sampling and result data.
     *
     * @param config Serialization configuration controlling sampling behavior
     */
    public override void prepareForSerialization(UoWSerializationConfig config) {
        UoWExceptionService.requireNonNull(config, 'Serialization config');
        super.prepareForSerialization(config);

        if (this.emailsList == null || this.emailsList.isEmpty()) {
            this.snapshots = new List<EmailSnapshot>();
            return;
        }

        // Get sampled indices with error-priority
        List<Integer> sampledIndices = UoWSamplingService.sampleIndices(
            this.emailsList.size(),
            this.failedIndices,
            config
        );

        // Build snapshots for sampled indices
        this.snapshots = new List<EmailSnapshot>();
        for (Integer idx : sampledIndices) {
            EmailSnapshot snap = buildSnapshotForIndex(idx);
            if (snap != null) {
                this.snapshots.add(snap);
            }
        }
    }

    /**
     * Restore Messaging.Email objects from snapshots after deserialization.
     */
    public override void hydrate() {
        super.hydrate();
        if (this.snapshots == null || this.snapshots.isEmpty()) {
            this.emailsList = new List<Messaging.Email>();
            return;
        }

        this.emailsList = new List<Messaging.Email>();
        for (EmailSnapshot snap : this.snapshots) {
            if (snap.meta != null) {
                Messaging.SingleEmailMessage email = snap.meta.toSingleEmailMessage();
                if (email != null) {
                    this.emailsList.add(email);
                }
            }
        }
    }

    // ============================================================================
    // PRIVATE METHODS - SNAPSHOT BUILDING
    // ============================================================================

    // Build an EmailSnapshot for the given index
    private EmailSnapshot buildSnapshotForIndex(Integer idx) {
        Messaging.Email email = this.emailsList[idx];
        if (!(email instanceof Messaging.SingleEmailMessage)) {
            return null;
        }

        EmailSnapshot snap = new EmailSnapshot();
        snap.idx = idx;
        snap.meta = new EmailMetadata().captureFrom((Messaging.SingleEmailMessage) email);

        // Get result data from sendResults
        if (this.sendResults != null && idx < this.sendResults.size()) {
            Messaging.SendEmailResult ser = this.sendResults[idx];
            snap.ok = ser.isSuccess();
            if (!ser.isSuccess()) {
                snap.errs = convertErrors(ser.getErrors());
            }
        }

        return snap;
    }

    // Convert Messaging.SendEmailError list to SnapshotError list
    private List<SnapshotError> convertErrors(List<Messaging.SendEmailError> emailErrors) {
        if (emailErrors == null || emailErrors.isEmpty()) {
            return null;
        }
        List<SnapshotError> result = new List<SnapshotError>();
        for (Messaging.SendEmailError err : emailErrors) {
            result.add(new SnapshotError(err));
        }
        return result;
    }

    // ============================================================================
    // INNER CLASSES - EMAIL METADATA
    // ============================================================================

    /**
     * Serializable snapshot of Messaging.SingleEmailMessage properties.
     * Used to preserve email data across serialization boundaries.
     */
    public class EmailMetadata {
        // Addressing
        public List<String> toAddresses;
        public List<String> ccAddresses;
        public List<String> bccAddresses;
        public String replyTo;

        // Content
        public String subject;
        public String plainTextBody;
        public String htmlBody;

        // Templates
        public String templateId;
        public String targetObjectId;
        public String whatId;

        // Sender
        public String senderDisplayName;
        public String orgWideEmailAddressId;

        // Options
        public Boolean saveAsActivity;
        public Boolean useSignature;

        // Character encoding
        public String charset;

        /**
         * Create EmailMetadata from a SingleEmailMessage.
         *
         * @param email The email to capture metadata from
         * @return EmailMetadata with captured properties
         */
        public EmailMetadata captureFrom(Messaging.SingleEmailMessage email) {
            if (email == null) {
                return this;
            }

            // Addressing
            this.toAddresses = email.getToAddresses();
            this.ccAddresses = email.getCcAddresses();
            this.bccAddresses = email.getBccAddresses();
            this.replyTo = email.getReplyTo();

            // Content
            this.subject = email.getSubject();
            this.plainTextBody = email.getPlainTextBody();
            this.htmlBody = email.getHtmlBody();

            // Templates
            this.templateId = email.getTemplateId();
            this.targetObjectId = email.getTargetObjectId();
            this.whatId = email.getWhatId();

            // Sender
            this.senderDisplayName = email.getSenderDisplayName();
            this.orgWideEmailAddressId = email.getOrgWideEmailAddressId();

            // Options
            this.saveAsActivity = email.getSaveAsActivity();
            this.useSignature = email.getUseSignature();

            // Character encoding
            this.charset = email.getCharset();

            return this;
        }

        /**
         * Factory method to create EmailMetadata from a SingleEmailMessage.
         * Note: This is an instance method because Apex inner classes cannot have static methods.
         *
         * @param email The email to capture metadata from
         * @return New EmailMetadata with captured properties
         */
        public EmailMetadata createFrom(Messaging.SingleEmailMessage email) {
            if (email == null) {
                return null;
            }
            return new EmailMetadata().captureFrom(email);
        }

        /**
         * Restore a SingleEmailMessage from this metadata.
         *
         * @return Messaging.SingleEmailMessage with restored properties
         */
        public Messaging.SingleEmailMessage toSingleEmailMessage() {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();

            // Addressing
            if (this.toAddresses != null) {
                email.setToAddresses(this.toAddresses);
            }
            if (this.ccAddresses != null) {
                email.setCcAddresses(this.ccAddresses);
            }
            if (this.bccAddresses != null) {
                email.setBccAddresses(this.bccAddresses);
            }
            if (this.replyTo != null) {
                email.setReplyTo(this.replyTo);
            }

            // Content
            if (this.subject != null) {
                email.setSubject(this.subject);
            }
            if (this.plainTextBody != null) {
                email.setPlainTextBody(this.plainTextBody);
            }
            if (this.htmlBody != null) {
                email.setHtmlBody(this.htmlBody);
            }

            // Templates
            if (this.templateId != null) {
                email.setTemplateId(this.templateId);
            }
            if (this.targetObjectId != null) {
                email.setTargetObjectId(this.targetObjectId);
            }
            if (this.whatId != null) {
                email.setWhatId(this.whatId);
            }

            // Sender
            if (this.senderDisplayName != null) {
                email.setSenderDisplayName(this.senderDisplayName);
            }
            if (this.orgWideEmailAddressId != null) {
                email.setOrgWideEmailAddressId(this.orgWideEmailAddressId);
            }

            // Options
            if (this.saveAsActivity != null) {
                email.setSaveAsActivity(this.saveAsActivity);
            }
            if (this.useSignature != null) {
                email.setUseSignature(this.useSignature);
            }

            // Character encoding
            if (this.charset != null) {
                email.setCharset(this.charset);
            }

            return email;
        }
    }

    // ============================================================================
    // INNER CLASSES - SNAPSHOT
    // ============================================================================

    /**
     * Enriched snapshot pairing an email with its send result.
     * Used for audit serialization to provide correlation between emails and outcomes.
     * Short field names minimize JSON size in LongTextArea storage.
     */
    public class EmailSnapshot {
        /** Original index in the emails list */
        public Integer idx;

        /** The email metadata (serializable form of Messaging.SingleEmailMessage) */
        public EmailMetadata meta;

        /** Success status from Messaging.SendEmailResult.isSuccess() */
        public Boolean ok;

        /** List of errors for this email (null if successful) */
        public List<SnapshotError> errs;
    }

    /**
     * Lightweight error structure for audit snapshots.
     * Captures essential Messaging.SendEmailError fields with short names for JSON size.
     */
    public class SnapshotError {
        /** StatusCode as string (e.g., 'INVALID_EMAIL_ADDRESS') */
        public String code;

        /** Error message */
        public String msg;

        /** Fields that caused the error (may be null) */
        public List<String> flds;

        /** Target object ID if applicable (may be null) */
        public Id tid;

        /**
         * Create from Messaging.SendEmailError.
         *
         * @param err The SendEmailError to capture
         */
        public SnapshotError(Messaging.SendEmailError err) {
            this.code = err.getStatusCode() != null ? String.valueOf(err.getStatusCode()) : null;
            this.msg = err.getMessage();
            List<String> errorFields = err.getFields();
            this.flds = (errorFields != null && !errorFields.isEmpty()) ? errorFields : null;
            this.tid = err.getTargetObjectId();
        }
    }
}