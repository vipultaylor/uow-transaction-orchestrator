//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * @description Service class for archiving audit records to Big Object storage.
 *              Provides both invocable actions for Flow integration and batch processing
 *              for large volume handling.
 *
 *              Design:
 *              - Invocable action for Flow-based archival (called by scheduled Flow)
 *              - Batch processing for large volumes (programmatic use)
 *              - Queries transactions with work items, transforms to Big Object, then deletes
 *
 *              ARCHIVE Mode:
 *              - Reads Custom Object records (UoWAuditTransaction__c, UoWAuditWorkItem__c)
 *              - Transforms them into denormalized Big Object records (UoWAuditHistory__b)
 *              - Uses direct field mapping for simplicity and performance
 *              - Uses Database.insertAsync() for Big Object insertion
 *              - Deletes Custom Object records after successful archival
 *
 *              Note: Big Object retention/cleanup is NOT managed by this framework.
 *              Users should implement their own Big Object cleanup if needed.
 *
 * @author Vipul Taylor
 * @group UoW Audit
 */
public class UoWAuditArchivalService implements Database.Batchable<SObject> {

    // ============================================================================
    // PRIVATE FIELDS
    // ============================================================================

    private Date archivalDate;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * @description Default constructor - archives records eligible as of today
     */
    public UoWAuditArchivalService() {
        this(Date.today());
    }

    /**
     * @description Constructor with custom archival date
     * @param archivalDate Records with ArchiveDate__c <= this date are eligible
     */
    public UoWAuditArchivalService(Date archivalDate) {
        this.archivalDate = archivalDate;
    }

    // ============================================================================
    // INVOCABLE API
    // ============================================================================

    /**
     * @description Archive audit transactions to Big Object then delete from Custom Object.
     *              Called by scheduled Flow to handle ARCHIVE mode records.
     * @param transactionIds List of transaction record IDs to archive
     */
    @InvocableMethod(
        label='Archive Audit Transactions'
        description='Archives audit transactions to Big Object (UoWAuditHistory__b) then deletes from Custom Object. Use for ARCHIVE mode records.'
        category='UoW Audit'
    )
    public static void archiveTransactions(List<String> transactionIds) {
        if (transactionIds == null || transactionIds.isEmpty()) {
            return;
        }

        // Query full transaction data with work items
        List<UoWAuditTransaction__c> transactions = UoWAuditDataSelector.getInstance()
            .getTransactionsWithWorkItems(new Set<Id>((List<Id>) transactionIds));

        if (transactions.isEmpty()) {
            return;
        }

        // Archive and delete
        archiveAndDeleteTransactions(transactions);
    }

    // ============================================================================
    // BATCHABLE INTERFACE
    // ============================================================================

    /**
     * @description Query transactions eligible for archival (ARCHIVE mode only)
     *              Includes all fields needed for Big Object archival
     * @param bc Batch context
     * @return Query locator for eligible transactions
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return UoWAuditDataSelector.getInstance().getArchivableTransactionsLocator(this.archivalDate);
    }

    /**
     * @description Process batch of transactions - archive to Big Object then delete
     * @param bc Batch context
     * @param scope List of transactions to process
     */
    public void execute(Database.BatchableContext bc, List<UoWAuditTransaction__c> scope) {
        if (scope.isEmpty()) {
            return;
        }

        archiveAndDeleteTransactions(scope);
    }

    /**
     * @description Finish batch processing
     * @param bc Batch context
     */
    public void finish(Database.BatchableContext bc) {
        if (bc == null) {
            return;
        }

        AsyncApexJob job = UoWAuditDataSelector.getInstance().getAsyncJobStatus(bc.getJobId());

        if (job != null) {
            System.debug(LoggingLevel.INFO,
                String.format(
                    'UoW Audit Archival Service completed. Status: {0}, Items Processed: {1}, Errors: {2}',
                    new String[]{
                        job.Status,
                        String.valueOf(job.JobItemsProcessed),
                        String.valueOf(job.NumberOfErrors)
                    }
                )
            );
        }
    }

    // ============================================================================
    // PRIVATE HELPER METHODS - ARCHIVAL
    // ============================================================================

    /**
     * @description Archive transactions to Big Object then delete from Custom Object.
     *              Creates denormalized Big Object records with full transaction context.
     * @param transactions Transactions to archive (must include WorkItems__r subquery)
     */
    private static void archiveAndDeleteTransactions(List<UoWAuditTransaction__c> transactions) {
        // Create Big Object records from Custom Object data
        List<UoWAuditHistory__b> historyRecords = new List<UoWAuditHistory__b>();

        for (UoWAuditTransaction__c txn : transactions) {
            if (txn.WorkItems__r == null || txn.WorkItems__r.isEmpty()) {
                // Transaction without work items - create a transaction-level record
                historyRecords.add(createHistoryRecord(txn, null, 0));
            } else {
                // Create one Big Object record per work item with denormalized transaction context
                Integer sequence = 0;
                for (UoWAuditWorkItem__c workItem : txn.WorkItems__r) {
                    historyRecords.add(createHistoryRecord(txn, workItem, sequence));
                    sequence++;
                }
            }
        }

        // Insert to Big Object
        if (!historyRecords.isEmpty()) {
            if (!insertToBigObject(historyRecords)) {
                // Don't delete Custom Object records if archival failed
                return;
            }
        }

        // Delete Custom Object records after successful archival
        // Master-Detail cascade delete handles work items automatically
        deleteTransactions(transactions);
    }

    /**
     * @description Insert records to Big Object via injectable DML service.
     *              Delegates to UoWAuditBigObjectDmlService which can be
     *              stubbed via System.StubProvider in tests.
     * @param historyRecords Records to insert
     * @return true if insert succeeded, false otherwise
     */
    private static Boolean insertToBigObject(List<UoWAuditHistory__b> historyRecords) {
        return UoWAuditBigObjectDmlService.getInstance().insertRecords(historyRecords);
    }

    /**
     * @description Create a Big Object record from Custom Object data.
     *              Denormalizes transaction context into each work item record.
     * @param txn The transaction record
     * @param workItem The work item record (can be null for transaction-only record)
     * @param sequence The sequence number for indexing
     * @return The Big Object record
     */
    private static UoWAuditHistory__b createHistoryRecord(
        UoWAuditTransaction__c txn,
        UoWAuditWorkItem__c workItem,
        Integer sequence
    ) {
        DateTime now = DateTime.now();

        UoWAuditHistory__b record = new UoWAuditHistory__b();

        // Compound index fields (required)
        // Per Salesforce Big Object best practices, trim index fields for reliable querying
        record.CorrelationId__c = UoWUtils.safeTrim(txn.CorrelationId__c);
        record.Sequence__c = sequence;
        record.CreatedTimestamp__c = now;

        // Transaction identifier
        record.TransactionId__c = txn.TransactionId__c;

        // Parent transaction (for async chains)
        if (txn.ParentTransaction__c != null && txn.ParentTransaction__r != null) {
            record.ParentTransactionId__c = txn.ParentTransaction__r.TransactionId__c;
        }

        // Transaction context (denormalized)
        record.TransactionStatus__c = txn.TransactionStatus__c;
        record.ConfigurationName__c = txn.ConfigurationName__c;
        record.ExecutionContext__c = txn.ExecutionContext__c;
        record.RiskEvaluated__c = txn.RiskEvaluated__c == true ? 'true' : 'false';
        record.RiskLevel__c = txn.RiskLevel__c;
        record.RiskScore__c = txn.RiskScore__c;
        record.PolicyEvaluated__c = txn.PolicyEvaluated__c == true ? 'true' : 'false';
        record.IsDryRun__c = txn.IsDryRun__c == true ? 'true' : 'false';
        record.TransactionStartTime__c = txn.StartTime__c;
        record.TransactionEndTime__c = txn.EndTime__c;
        record.TransactionDurationMs__c = safeIntegerFromDecimal(txn.ExecutionTimeMs__c);
        record.TotalErrors__c = safeIntegerFromDecimal(txn.ErrorCount__c);
        record.RetentionDays__c = safeIntegerFromDecimal(txn.RetentionDays__c);

        // Session context - User identity
        record.UserId__c = txn.User__c;
        record.Username__c = txn.Username__c;
        record.UserProfileId__c = txn.UserProfileId__c;
        record.UserProfileName__c = txn.UserProfileName__c;
        record.UserType__c = txn.UserType__c;
        record.UserRoleId__c = txn.UserRoleId__c;
        record.UserRoleName__c = txn.UserRoleName__c;
        record.UserLicenseName__c = txn.UserLicenseName__c;

        // Session context - User preferences
        record.UserLocale__c = txn.UserLocale__c;
        record.UserTimeZone__c = txn.UserTimeZone__c;

        // Session context - Organization
        record.OrganizationId__c = txn.OrganizationId__c;
        record.OrganizationName__c = txn.OrganizationName__c;
        record.OrganizationInstanceName__c = txn.OrganizationInstanceName__c;
        record.OrganizationIsSandbox__c = txn.OrganizationIsSandbox__c == true ? 'true' : 'false';

        // Session context - Request
        record.RequestId__c = txn.RequestId__c;

        // Session context - Auth session
        record.LoginType__c = txn.LoginType__c;
        record.SessionType__c = txn.SessionType__c;
        record.SourceIp__c = txn.SourceIp__c;
        record.UserIsImpersonated__c = txn.UserIsImpersonated__c == true ? 'true' : 'false';

        // Archive date for Big Object (7 years)
        record.ArchiveDate__c = now.addDays(365 * UoWAuditParameter.ARCHIVE_RETENTION_YEARS);

        // Work item fields (if provided)
        if (workItem != null) {
            record.WorkId__c = workItem.Name;
            record.WorkType__c = workItem.WorkType__c;
            record.WorkItemStatus__c = workItem.WorkItemStatus__c;
            record.SObjectType__c = workItem.SObjectType__c;
            record.DmlOperation__c = workItem.DmlOperation__c;
            record.ExecutionPhase__c = workItem.ExecutionPhase__c;
            record.PlannedCount__c = safeIntegerFromDecimal(workItem.PlannedCount__c);
            record.ProcessedCount__c = safeIntegerFromDecimal(workItem.ProcessedCount__c);
            record.SuccessCount__c = safeIntegerFromDecimal(workItem.SuccessCount__c);
            record.FailureCount__c = safeIntegerFromDecimal(workItem.FailureCount__c);
            record.StartTime__c = workItem.StartTime__c;
            record.EndTime__c = workItem.EndTime__c;
            record.ExecutionTimeMs__c = safeIntegerFromDecimal(workItem.ExecutionTimeMs__c);
            record.ErrorMessage__c = workItem.ErrorMessage__c;
            record.ErrorDetails__c = workItem.ErrorDetails__c;
            record.RequestOrigin__c = workItem.RequestOrigin__c;
            record.ContinueOnError__c = workItem.ContinueOnError__c == true ? 'true' : 'false';
            record.MaskingApplied__c = workItem.MaskingApplied__c == true ? 'true' : 'false';
            record.MaskedFields__c = workItem.MaskedFields__c;

            // Work type specific fields (only if they exist on work item)
            record.FlowApiName__c = workItem.FlowApiName__c;
            record.Endpoint__c = workItem.Endpoint__c;
            record.HttpMethod__c = workItem.HttpMethod__c;
            record.NotificationType__c = workItem.NotificationType__c;

            // Origin fields from work item
            record.OriginClassName__c = workItem.OriginClassName__c;
            record.OriginMethodName__c = workItem.OriginMethodName__c;
            record.OriginLineNumber__c = safeIntegerFromDecimal(workItem.OriginLineNumber__c);
            record.OriginMetadataType__c = workItem.OriginMetadataType__c;
            record.OriginApiVersion__c = workItem.OriginApiVersion__c;
            record.OriginSourceMetadata__c = workItem.OriginSourceMetadata__c;
            record.OriginSnippetStartLine__c = safeIntegerFromDecimal(workItem.OriginSnippetStartLine__c);
            record.OriginLastModifiedDate__c = workItem.OriginLastModifiedDate__c;
        }

        return record;
    }

    // ============================================================================
    // PRIVATE HELPER METHODS - DELETE
    // ============================================================================

    /**
     * @description Delete transaction records (cascade delete handles work items)
     * @param transactions Transactions to delete
     */
    private static void deleteTransactions(List<UoWAuditTransaction__c> transactions) {
        try {
            List<Database.DeleteResult> results = Database.delete(transactions, false);

            Integer failureCount = 0;
            for (Database.DeleteResult result : results) {
                if (!result.isSuccess()) {
                    failureCount++;
                    for (Database.Error err : result.getErrors()) {
                        System.debug(LoggingLevel.ERROR,
                            String.format(
                                'Failed to delete transaction: {0} - {1}',
                                new String[]{ err.getStatusCode().name(), err.getMessage() }
                            )
                        );
                    }
                }
            }

            if (failureCount > 0) {
                System.debug(LoggingLevel.WARN,
                    String.format(
                        'Failed to delete {0} of {1} transactions',
                        new String[]{
                            String.valueOf(failureCount),
                            String.valueOf(transactions.size())
                        }
                    )
                );
            } else {
                System.debug(LoggingLevel.INFO,
                    'Successfully deleted ' + transactions.size() + ' transactions');
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'Exception deleting transactions: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }

    // ============================================================================
    // PRIVATE HELPER METHODS - UTILITIES
    // ============================================================================

    /**
     * @description Safely convert Decimal to Integer
     */
    private static Integer safeIntegerFromDecimal(Decimal value) {
        if (value == null) {
            return null;
        }
        return value.intValue();
    }

    // ============================================================================
    // STATIC HELPER METHODS - PROGRAMMATIC EXECUTION
    // ============================================================================

    /**
     * @description Execute archival immediately as batch job
     * @return Batch job ID
     */
    public static Id executeNow() {
        return executeNow(Date.today());
    }

    /**
     * @description Execute archival immediately with custom date
     * @param archivalDate Records with ArchiveDate__c <= this date are eligible
     * @return Batch job ID
     */
    public static Id executeNow(Date archivalDate) {
        return Database.executeBatch(
            new UoWAuditArchivalService(archivalDate),
            UoWAuditParameter.DEFAULT_BATCH_SIZE
        );
    }
}