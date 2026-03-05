//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Centralized data access layer for UoW Audit objects.
 * Consolidates all queries for UoWAuditTransaction__c and UoWAuditWorkItem__c
 * in a single location for consistent access control and maintainability.
 *
 * Design Principles (inspired by Nebula Logger's LogManagementDataSelector):
 * - Singleton pattern with @TestVisible mock injection support
 * - Virtual class to allow test overrides
 * - Grouped methods by queried object type
 * - Consistent security enforcement via USER_MODE for LWC queries
 * - WITHOUT SHARING for internal/batch operations
 *
 * Query Method Naming Conventions:
 * - getTransactionById() - Single record by Id
 * - getTransactionsByIds() - Multiple records by Ids
 * - getTransactionByTransactionId() - By external TransactionId__c
 * - getWorkItemsByTransactionId() - Child records by parent
 * - getArchivableTransactions() - Batch query locator
 *
 * @author Vipul Taylor
 * @group UoW Audit
 * @see UoWAuditTransaction__c
 * @see UoWAuditWorkItem__c
 * @see UoWAuditHistory__b
 */
@SuppressWarnings('PMD.ExcessivePublicCount, PMD.ApexCRUDViolation')
public virtual without sharing class UoWAuditDataSelector {

    // ============================================================================
    // SINGLETON PATTERN
    // ============================================================================

    private static UoWAuditDataSelector instance = new UoWAuditDataSelector();

    /**
     * Private constructor to enforce singleton pattern.
     */
    @SuppressWarnings('PMD.EmptyStatementBlock')
    protected UoWAuditDataSelector() {
        // Protected for testability
    }

    /**
     * Get the singleton instance.
     *
     * @return The UoWAuditDataSelector instance
     */
    public static UoWAuditDataSelector getInstance() {
        return instance;
    }

    /**
     * Set a custom instance (for testing with mocks).
     *
     * @param selectorInstance The mock instance to use
     */
    @TestVisible
    private static void setInstance(UoWAuditDataSelector selectorInstance) {
        instance = selectorInstance;
    }

    // ============================================================================
    // TRANSACTION QUERIES - SINGLE RECORD
    // ============================================================================

    /**
     * Get transaction by Salesforce record Id with USER_MODE security.
     * Used by LWC controllers for record page display.
     *
     * @param transactionId The Salesforce record Id
     * @return Transaction record or null if not found
     */
    public virtual UoWAuditTransaction__c getTransactionById(Id transactionId) {
        if (transactionId == null) {
            return null;
        }

        List<UoWAuditTransaction__c> results = [
            SELECT Id, Name, TransactionId__c, CorrelationId__c, CommitMode__c,
                   TransactionStatus__c, ConfigurationName__c,
                   StartTime__c, EndTime__c, ExecutionTimeMs__c,
                   HasErrors__c, ErrorCount__c, ErrorDetails__c,
                   Timeline__c, Messages__c, ConfigurationSnapshot__c
            FROM UoWAuditTransaction__c
            WHERE Id = :transactionId
            WITH USER_MODE
            LIMIT 1
        ];

        return results.isEmpty() ? null : results[0];
    }

    /**
     * Get transaction timeline data by record Id.
     * Minimal fields for timeline visualization.
     *
     * @param transactionId The Salesforce record Id
     * @return Transaction with timeline fields
     */
    public virtual UoWAuditTransaction__c getTransactionForTimeline(Id transactionId) {
        if (transactionId == null) {
            return null;
        }

        List<UoWAuditTransaction__c> results = [
            SELECT Id, Name, CorrelationId__c, CommitMode__c,
                   StartTime__c, EndTime__c, TransactionStatus__c,
                   Timeline__c, ExecutionTimeMs__c
            FROM UoWAuditTransaction__c
            WHERE Id = :transactionId
            WITH USER_MODE
            LIMIT 1
        ];

        return results.isEmpty() ? null : results[0];
    }

    /**
     * Get transaction messages by record Id.
     * Minimal fields for message console.
     *
     * @param transactionId The Salesforce record Id
     * @return Transaction with messages fields
     */
    public virtual UoWAuditTransaction__c getTransactionForMessages(Id transactionId) {
        if (transactionId == null) {
            return null;
        }

        List<UoWAuditTransaction__c> results = [
            SELECT Id, Messages__c, StartTime__c
            FROM UoWAuditTransaction__c
            WHERE Id = :transactionId
            WITH USER_MODE
            LIMIT 1
        ];

        return results.isEmpty() ? null : results[0];
    }

    /**
     * Get transaction configuration by record Id.
     * Minimal fields for configuration inspector.
     *
     * @param transactionId The Salesforce record Id
     * @return Transaction with configuration fields
     */
    public virtual UoWAuditTransaction__c getTransactionForConfiguration(Id transactionId) {
        if (transactionId == null) {
            return null;
        }

        List<UoWAuditTransaction__c> results = [
            SELECT Id, TransactionId__c, ConfigurationSnapshot__c, ConfigurationName__c
            FROM UoWAuditTransaction__c
            WHERE Id = :transactionId
            WITH USER_MODE
            LIMIT 1
        ];

        return results.isEmpty() ? null : results[0];
    }

    /**
     * Get transaction error details by record Id.
     *
     * @param transactionId The Salesforce record Id
     * @return Transaction with error details
     */
    public virtual UoWAuditTransaction__c getTransactionForErrors(Id transactionId) {
        if (transactionId == null) {
            return null;
        }

        List<UoWAuditTransaction__c> results = [
            SELECT Id, ErrorDetails__c
            FROM UoWAuditTransaction__c
            WHERE Id = :transactionId
            WITH USER_MODE
            LIMIT 1
        ];

        return results.isEmpty() ? null : results[0];
    }

    // ============================================================================
    // TRANSACTION QUERIES - MULTIPLE RECORDS
    // ============================================================================

    /**
     * Get transactions by external TransactionId__c values.
     * Used for parent relationship resolution (without sharing).
     *
     * @param transactionIds Set of TransactionId__c values
     * @return Map of TransactionId__c to record Id
     */
    public virtual Map<String, Id> getTransactionIdToRecordIdMap(Set<String> transactionIds) {
        if (transactionIds == null || transactionIds.isEmpty()) {
            return new Map<String, Id>();
        }

        Map<String, Id> result = new Map<String, Id>();
        for (UoWAuditTransaction__c txn : [
            SELECT Id, TransactionId__c
            FROM UoWAuditTransaction__c
            WHERE TransactionId__c IN :transactionIds
        ]) {
            result.put(txn.TransactionId__c, txn.Id);
        }
        return result;
    }

    /**
     * Get full transaction records by external TransactionId__c values.
     * Used for bulkified parent relationship resolution with field updates.
     * Includes fields needed for HasChildTransactions__c and status updates.
     *
     * @param transactionIds Set of TransactionId__c values
     * @return Map of TransactionId__c to full record
     */
    public virtual Map<String, UoWAuditTransaction__c> getTransactionIdToRecordMap(Set<String> transactionIds) {
        if (transactionIds == null || transactionIds.isEmpty()) {
            return new Map<String, UoWAuditTransaction__c>();
        }

        Map<String, UoWAuditTransaction__c> result = new Map<String, UoWAuditTransaction__c>();
        for (UoWAuditTransaction__c txn : [
            SELECT Id, TransactionId__c, CorrelationId__c, HasChildTransactions__c, TransactionStatus__c
            FROM UoWAuditTransaction__c
            WHERE TransactionId__c IN :transactionIds
        ]) {
            result.put(txn.TransactionId__c, txn);
        }
        return result;
    }

    /**
     * Get transactions by record IDs with all fields and work items subquery.
     * Used by UoWAuditArchivalService invocable method for Flow-based archival.
     * Uses dynamic SOQL to query all fields from both objects.
     *
     * @param transactionIds Set of Salesforce record IDs
     * @return List of transactions with work items
     */
    public virtual List<UoWAuditTransaction__c> getTransactionsWithWorkItems(Set<Id> transactionIds) {
        if (transactionIds == null || transactionIds.isEmpty()) {
            return new List<UoWAuditTransaction__c>();
        }

        String query = buildArchivalQuery('Id IN :transactionIds', null);
        return Database.query(query);
    }

    // ============================================================================
    // TRANSACTION QUERIES - BATCH/ARCHIVAL
    // ============================================================================

    /**
     * Get query locator for archivable transactions.
     * Used by UoWAuditArchivalService batch process.
     * Uses dynamic SOQL to query all fields from both objects.
     *
     * @param archivalDate Records with ArchiveDate__c <= this date are eligible
     * @return QueryLocator for batch processing
     */
    public virtual Database.QueryLocator getArchivableTransactionsLocator(Date archivalDate) {
        String query = buildArchivalQuery('ArchiveDate__c <= :archivalDate', 'ArchiveDate__c ASC');
        return Database.getQueryLocator(query);
    }

    // ============================================================================
    // PRIVATE HELPER METHODS - DYNAMIC QUERY BUILDING
    // ============================================================================

    /**
     * Build dynamic SOQL query for archival operations.
     * Queries all fields from UoWAuditTransaction__c and includes work items subquery.
     *
     * @param whereClause WHERE clause without 'WHERE' keyword (e.g., 'Id IN :ids')
     * @param orderByClause ORDER BY clause without 'ORDER BY' keyword (can be null)
     * @return Complete SOQL query string
     */
    private static String buildArchivalQuery(String whereClause, String orderByClause) {
        // Get all transaction fields
        String transactionFields = getAllFieldsForObject(
            UoWAuditTransaction__c.SObjectType,
            new Set<String>{ 'ParentTransaction__r.TransactionId__c' }  // Additional relationship fields
        );

        // Get all work item fields for subquery
        String workItemFields = getAllFieldsForObject(UoWAuditWorkItem__c.SObjectType, null);

        // Build the query
        String query = 'SELECT ' + transactionFields +
            ', (SELECT ' + workItemFields + ' FROM WorkItems__r ORDER BY Sequence__c ASC)' +
            ' FROM UoWAuditTransaction__c' +
            ' WHERE ' + whereClause;

        if (String.isNotBlank(orderByClause)) {
            query += ' ORDER BY ' + orderByClause;
        }

        return query;
    }

    /**
     * Get comma-separated list of all queryable fields for an SObject.
     * Excludes compound fields and includes optional additional fields.
     * Uses UoWCacheService for cached schema describes.
     *
     * @param sobjectType The SObject type to describe
     * @param additionalFields Optional set of additional fields to include (e.g., relationship fields)
     * @return Comma-separated field list
     */
    private static String getAllFieldsForObject(Schema.SObjectType sobjectType, Set<String> additionalFields) {
        Schema.DescribeSObjectResult describe = UoWCacheService.getDescribe(sobjectType);
        Map<String, Schema.SObjectField> fieldMap = describe.fields.getMap();

        List<String> fields = new List<String>();

        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = UoWCacheService.getFieldDescribe(fieldMap.get(fieldName));

            // Skip compound fields (like Address, Geolocation) - they're not directly queryable
            if (fieldDescribe.getType() == Schema.DisplayType.ADDRESS ||
                fieldDescribe.getType() == Schema.DisplayType.LOCATION) {
                continue;
            }

            fields.add(fieldDescribe.getName());
        }

        // Add any additional relationship fields
        if (additionalFields != null) {
            fields.addAll(additionalFields);
        }

        // Sort for consistent ordering (helps with debugging/testing)
        fields.sort();

        return String.join(fields, ', ');
    }

    // ============================================================================
    // WORK ITEM QUERIES - SINGLE RECORD
    // ============================================================================

    /**
     * Get work item by Salesforce record Id with USER_MODE security.
     * Used by LWC controllers for work item viewer.
     *
     * @param recordId The Salesforce record Id
     * @return Work item record or null if not found
     */
    public virtual UoWAuditWorkItem__c getWorkItemById(Id recordId) {
        UoWExceptionService.requireNonBlank(recordId, 'Work Item Record Id');

        List<UoWAuditWorkItem__c> results = [
            SELECT Id, Name,
                   WorkType__c, WorkItemStatus__c,
                   PlannedCount__c, ProcessedCount__c, SuccessCount__c, FailureCount__c,
                   ExecutionTimeMs__c,
                   Snapshot__c,
                   AuditTransaction__c, AuditTransaction__r.Name,
                   SObjectType__c, DmlOperation__c,
                   Endpoint__c, HttpMethod__c, FlowApiName__c, NotificationType__c,
                   ExecutionPhase__c,
                   HasErrors__c, ErrorCount__c, ErrorMessage__c, ErrorDetails__c
            FROM UoWAuditWorkItem__c
            WHERE Id = :recordId
            WITH USER_MODE
            LIMIT 1
        ];

        return results.isEmpty() ? null : results[0];
    }

    /**
     * Get work item error details by record Id.
     *
     * @param recordId The Salesforce record Id
     * @return Work item with error details
     */
    public virtual UoWAuditWorkItem__c getWorkItemForErrors(Id recordId) {
        UoWExceptionService.requireNonBlank(recordId, 'Work Item Record Id');

        List<UoWAuditWorkItem__c> results = [
            SELECT Id, ErrorDetails__c
            FROM UoWAuditWorkItem__c
            WHERE Id = :recordId
            WITH USER_MODE
            LIMIT 1
        ];

        return results.isEmpty() ? null : results[0];
    }

    // ============================================================================
    // WORK ITEM QUERIES - MULTIPLE RECORDS
    // ============================================================================

    /**
     * Get work items by Name values.
     * Used for work item ID resolution in error display.
     *
     * @param workItemNames Set of work item Name values (e.g., WORK-1234567890)
     * @return Map of Name to record Id
     */
    public virtual Map<String, Id> getWorkItemNameToRecordIdMap(Set<String> workItemNames) {
        if (workItemNames == null || workItemNames.isEmpty()) {
            return new Map<String, Id>();
        }

        Map<String, Id> result = new Map<String, Id>();
        for (UoWAuditWorkItem__c wi : [
            SELECT Id, Name
            FROM UoWAuditWorkItem__c
            WHERE Name IN :workItemNames
            WITH USER_MODE
        ]) {
            result.put(wi.Name, wi.Id);
        }
        return result;
    }

    // ============================================================================
    // TRANSACTION QUERIES - HIERARCHY
    // ============================================================================

    /**
     * Get all transactions in a correlation chain for hierarchy display.
     * Returns transactions with fields needed for hierarchy visualization.
     *
     * @param correlationId The correlation ID to query
     * @return List of transactions in the chain ordered by depth and time
     */
    public virtual List<UoWAuditTransaction__c> getTransactionsByCorrelationId(String correlationId) {
        if (String.isBlank(correlationId)) {
            return new List<UoWAuditTransaction__c>();
        }

        return [
            SELECT Id, TransactionId__c, ParentTransaction__c, AsyncDepth__c,
                   TransactionStatus__c, Description__c, TotalWorkItems__c, HasChildTransactions__c
            FROM UoWAuditTransaction__c
            WHERE CorrelationId__c = :correlationId
            WITH USER_MODE
            ORDER BY AsyncDepth__c ASC, StartTime__c ASC
        ];
    }

    /**
     * Get correlation ID for a transaction by its record ID.
     *
     * @param transactionRecordId The Salesforce record ID
     * @return The correlation ID or null if not found
     */
    public virtual String getCorrelationIdByTransactionId(Id transactionRecordId) {
        if (transactionRecordId == null) {
            return null;
        }

        List<UoWAuditTransaction__c> results = [
            SELECT CorrelationId__c
            FROM UoWAuditTransaction__c
            WHERE Id = :transactionRecordId
            WITH USER_MODE
            LIMIT 1
        ];

        return results.isEmpty() ? null : results[0].CorrelationId__c;
    }

    /**
     * Get recent root transactions (transactions with no parent).
     * Used for hierarchy list view.
     *
     * @param queryLimit Maximum number of records to return
     * @return List of root transactions with child subquery
     */
    public virtual List<UoWAuditTransaction__c> getRecentRootTransactions(Integer queryLimit) {
        Integer effectiveLimit = (queryLimit != null && queryLimit > 0) ? queryLimit : 20;

        return [
            SELECT Id, Name, TransactionId__c, CorrelationId__c, TransactionStatus__c,
                   CommitMode__c, StartTime__c, ExecutionTimeMs__c, TotalWorkItems__c,
                   ParentTransaction__c, (SELECT Id FROM UoWAuditTransactions__r)
            FROM UoWAuditTransaction__c
            WHERE ParentTransaction__c = NULL
            WITH USER_MODE
            ORDER BY StartTime__c DESC
            LIMIT :effectiveLimit
        ];
    }

    // ============================================================================
    // ARCHIVE QUERIES - BIG OBJECT
    // ============================================================================

    /**
     * Get a single archive record by its unique index key fields.
     * Big Objects require querying by all indexed fields.
     *
     * @param correlationId The CorrelationId__c value
     * @param sequence The Sequence__c value
     * @param createdTimestamp The CreatedTimestamp__c value
     * @return Archive record or null if not found or inputs invalid
     */
    public virtual UoWAuditHistory__b getArchiveByKey(
        String correlationId,
        Decimal sequence,
        DateTime createdTimestamp
    ) {
        if (String.isBlank(correlationId) || createdTimestamp == null) {
            return null;
        }

        List<UoWAuditHistory__b> results = [
            SELECT
                CorrelationId__c, Sequence__c, CreatedTimestamp__c,
                TransactionId__c, WorkId__c, WorkType__c, DmlOperation__c,
                TransactionStatus__c, WorkItemStatus__c,
                SObjectType__c, ExecutionPhase__c, ExecutionContext__c,
                StartTime__c, EndTime__c, TransactionStartTime__c, TransactionEndTime__c,
                TransactionDurationMs__c, ExecutionTimeMs__c,
                PlannedCount__c, ProcessedCount__c, SuccessCount__c, FailureCount__c,
                TotalWorkItems__c, TotalErrors__c, WorkItemCount__c,
                ErrorMessage__c, ErrorDetails__c, ErrorStackTrace__c,
                Username__c, UserId__c, UserType__c, UserProfileName__c, UserRoleName__c,
                UserIsImpersonated__c, UserLocale__c, UserTimeZone__c, UserLicenseName__c,
                OrganizationName__c, OrganizationId__c, OrganizationInstanceName__c, OrganizationIsSandbox__c,
                ConfigurationName__c, RequestId__c, RequestOrigin__c, SourceIp__c,
                LoginType__c, SessionType__c, ParentTransactionId__c,
                RiskLevel__c, RiskScore__c, RiskEvaluated__c, PolicyEvaluated__c, RequiresApproval__c,
                IsDryRun__c, ContinueOnError__c, RetentionDays__c, ArchiveDate__c,
                MaskingApplied__c, MaskedFields__c,
                OriginClassName__c, OriginMethodName__c, OriginLineNumber__c, OriginMetadataType__c,
                OriginApiVersion__c, OriginSourceMetadata__c, OriginSnippetStartLine__c, OriginLastModifiedDate__c,
                FlowApiName__c, FlowInputs__c, FlowOutputs__c,
                Endpoint__c, HttpMethod__c, ResponseStatusCode__c, RetryCount__c,
                NotificationType__c, TransactionScenarioName__c, Description__c,
                AgentId__c, AgentName__c, AgentIntent__c, AgentModelId__c,
                AgentConfidenceScore__c, AgentPromptHash__c, IsAgentTransaction__c
            FROM UoWAuditHistory__b
            WHERE CorrelationId__c = :correlationId
                AND Sequence__c = :sequence
                AND CreatedTimestamp__c = :createdTimestamp
            LIMIT 1
        ];

        return results.isEmpty() ? null : results[0];
    }

    /**
     * Query archive records with filters and cursor-based pagination.
     * Big Objects require indexed fields in WHERE clause and ORDER BY.
     *
     * @param correlationId Optional correlation ID filter
     * @param startDate Optional start date filter (inclusive)
     * @param endDate Optional end date filter (inclusive)
     * @param cursorTimestamp Optional cursor for pagination (records before this timestamp)
     * @param queryLimit Maximum records to return
     * @return List of archive records ordered by CreatedTimestamp__c DESC
     */
    public virtual List<UoWAuditHistory__b> queryArchiveRecords(
        String correlationId,
        Date startDate,
        Date endDate,
        DateTime cursorTimestamp,
        Integer queryLimit
    ) {
        String query = 'SELECT ' +
            'CorrelationId__c, Sequence__c, CreatedTimestamp__c, ' +
            'TransactionId__c, WorkId__c, WorkType__c, DmlOperation__c, ' +
            'TransactionStatus__c, WorkItemStatus__c, ' +
            'SObjectType__c, ExecutionPhase__c, ExecutionContext__c, ' +
            'StartTime__c, EndTime__c, TransactionDurationMs__c, ExecutionTimeMs__c, ' +
            'PlannedCount__c, ProcessedCount__c, SuccessCount__c, FailureCount__c, ' +
            'TotalWorkItems__c, TotalErrors__c, ' +
            'ErrorMessage__c, ErrorDetails__c, ' +
            'Username__c, UserId__c, UserProfileName__c, UserRoleName__c, ' +
            'ConfigurationName__c, RiskLevel__c, RiskScore__c, ' +
            'SourceIp__c, LoginType__c, RequestOrigin__c, ' +
            'IsAgentTransaction__c, AgentName__c, AgentId__c, TransactionScenarioName__c, Description__c, ' +
            'FlowApiName__c, Endpoint__c, HttpMethod__c, ResponseStatusCode__c ' +
            'FROM UoWAuditHistory__b';

        List<String> conditions = new List<String>();
        Map<String, Object> bindVars = new Map<String, Object>();

        if (String.isNotBlank(correlationId)) {
            conditions.add('CorrelationId__c = :correlationId');
            bindVars.put('correlationId', correlationId);
        }

        if (startDate != null) {
            DateTime startDateTime = DateTime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));
            conditions.add('CreatedTimestamp__c >= :startDateTime');
            bindVars.put('startDateTime', startDateTime);
        }

        if (endDate != null) {
            DateTime endDateTime = DateTime.newInstance(endDate, Time.newInstance(23, 59, 59, 999));
            conditions.add('CreatedTimestamp__c <= :endDateTime');
            bindVars.put('endDateTime', endDateTime);
        }

        if (cursorTimestamp != null) {
            conditions.add('CreatedTimestamp__c < :cursorTimestamp');
            bindVars.put('cursorTimestamp', cursorTimestamp);
        }

        if (!conditions.isEmpty()) {
            query += ' WHERE ' + String.join(conditions, ' AND ');
        }

        query += ' ORDER BY CreatedTimestamp__c DESC';
        query += ' LIMIT ' + queryLimit;

        return Database.queryWithBinds(query, bindVars, AccessLevel.USER_MODE);
    }

    // ============================================================================
    // ASYNC JOB QUERIES
    // ============================================================================

    /**
     * Get async job status by job Id.
     * Used for batch job monitoring in finish() method.
     *
     * @param jobId The batch job Id
     * @return AsyncApexJob record
     */
    public virtual AsyncApexJob getAsyncJobStatus(Id jobId) {
        if (jobId == null) {
            return null;
        }

        List<AsyncApexJob> results = [
            SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];

        return results.isEmpty() ? null : results[0];
    }
}