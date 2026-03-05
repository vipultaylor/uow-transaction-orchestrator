//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Apex controller for UoW Audit Archive Viewer LWC component.
 * Provides data access for querying and displaying Big Object archive records.
 *
 * Big Object Query Constraints:
 * - Must use indexed fields in WHERE clause (CorrelationId__c, Sequence__c, CreatedTimestamp__c)
 * - No OFFSET support - uses cursor-based pagination with CreatedTimestamp__c
 * - No COUNT() aggregate - must track total separately or estimate
 *
 * @author Vipul Taylor
 * @group UoW Audit
 * @see UoWAuditHistory__b
 */
public with sharing class UoWAuditArchiveController {

    // ============================================================================
    // CONSTANTS
    // ============================================================================

    private static final Integer DEFAULT_PAGE_SIZE = 50;
    private static final Integer MAX_PAGE_SIZE = 200;

    // ============================================================================
    // PUBLIC API - QUERY METHODS
    // ============================================================================

    /**
     * Query archive records with filters and pagination.
     * Uses cursor-based pagination since Big Objects don't support OFFSET.
     *
     * @param params Query parameters including filters and pagination cursor
     * @return ArchiveQueryResult with records and pagination info
     */
    @AuraEnabled
    public static ArchiveQueryResult getArchiveRecords(ArchiveQueryParams params) {
        try {
            validateParams(params);

            Integer pageSize = Math.min(
                params.pageSize != null ? params.pageSize : DEFAULT_PAGE_SIZE,
                MAX_PAGE_SIZE
            );

            // Decode cursor before passing to selector
            DateTime cursorTimestamp = String.isNotBlank(params.cursor) ? decodeCursor(params.cursor) : null;

            // Build and execute query via DataSelector
            List<UoWAuditHistory__b> records = UoWAuditDataSelector.getInstance().queryArchiveRecords(
                params.correlationId, params.startDate, params.endDate, cursorTimestamp, pageSize + 1
            );

            // Check if there are more records
            Boolean hasMore = records.size() > pageSize;
            if (hasMore) {
                records.remove(records.size() - 1);
            }

            // Get cursor for next page
            String nextCursor = null;
            if (hasMore && !records.isEmpty()) {
                UoWAuditHistory__b lastRecord = records[records.size() - 1];
                nextCursor = encodeCursor(lastRecord.CreatedTimestamp__c);
            }

            return new ArchiveQueryResult(records, hasMore, nextCursor, params.cursor);
        } catch (Exception e) {
            throw UoWExceptionService.buildAuraException('Failed to query archives: ' + e.getMessage());
        }
    }

    /**
     * Get a single archive record by its unique key fields.
     * Big Objects require querying by index fields.
     *
     * @param correlationId The CorrelationId__c value
     * @param sequence The Sequence__c value
     * @param createdTimestamp The CreatedTimestamp__c value
     * @return Archive record or null
     */
    @AuraEnabled(cacheable=true)
    public static UoWAuditHistory__b getArchiveDetail(
        String correlationId,
        Decimal sequence,
        DateTime createdTimestamp
    ) {
        try {
            return UoWAuditDataSelector.getInstance().getArchiveByKey(correlationId, sequence, createdTimestamp);
        } catch (Exception e) {
            throw UoWExceptionService.buildAuraException('Failed to load archive detail: ' + e.getMessage());
        }
    }

    /**
     * Get filter options for the archive viewer.
     * Returns distinct values for picklist filters.
     *
     * @return FilterOptions with available filter values
     */
    @AuraEnabled(cacheable=true)
    public static FilterOptions getFilterOptions() {
        return new FilterOptions();
    }

    /**
     * Export archive records as JSON.
     * Returns the raw data for client-side file download.
     *
     * @param params Query parameters (same as getArchiveRecords)
     * @return JSON string of archive records
     */
    @AuraEnabled
    public static String exportArchiveRecords(ArchiveQueryParams params) {
        try {
            // Override page size for export
            params.pageSize = MAX_PAGE_SIZE;
            ArchiveQueryResult result = getArchiveRecords(params);
            return JSON.serialize(result.records);
        } catch (Exception e) {
            throw UoWExceptionService.buildAuraException('Failed to export archives: ' + e.getMessage());
        }
    }

    // ============================================================================
    // PRIVATE HELPER METHODS
    // ============================================================================

    private static void validateParams(ArchiveQueryParams params) {
        if (params == null) {
            throw UoWExceptionService.buildAuraException('Query parameters are required');
        }

        // Date range validation
        if (params.startDate != null && params.endDate != null && params.startDate > params.endDate) {
            throw UoWExceptionService.buildAuraException('Start date must be before end date');
        }
    }

    private static String encodeCursor(DateTime timestamp) {
        if (timestamp == null) {
            return null;
        }
        return EncodingUtil.base64Encode(Blob.valueOf(String.valueOf(timestamp.getTime())));
    }

    private static DateTime decodeCursor(String cursor) {
        if (String.isBlank(cursor)) {
            return null;
        }
        try {
            String decoded = EncodingUtil.base64Decode(cursor).toString();
            Long milliseconds = Long.valueOf(decoded);
            return DateTime.newInstance(milliseconds);
        } catch (Exception e) {
            throw UoWExceptionService.buildAuraException('Invalid pagination cursor');
        }
    }

    // ============================================================================
    // WRAPPER CLASSES - REQUEST
    // ============================================================================

    /**
     * Query parameters for archive search.
     */
    public class ArchiveQueryParams {
        @AuraEnabled public String correlationId { get; set; }
        @AuraEnabled public String transactionId { get; set; }
        @AuraEnabled public String searchTerm { get; set; }
        @AuraEnabled public List<String> workTypes { get; set; }
        @AuraEnabled public List<String> statuses { get; set; }
        @AuraEnabled public String username { get; set; }
        @AuraEnabled public Date startDate { get; set; }
        @AuraEnabled public Date endDate { get; set; }
        @AuraEnabled public Integer pageSize { get; set; }
        @AuraEnabled public String cursor { get; set; }
        @AuraEnabled public Boolean agentTransactionsOnly { get; set; }
    }

    // ============================================================================
    // WRAPPER CLASSES - RESPONSE
    // ============================================================================

    /**
     * Query result with records and pagination info.
     */
    public class ArchiveQueryResult {
        @AuraEnabled public List<UoWAuditHistory__b> records { get; set; }
        @AuraEnabled public Boolean hasMore { get; set; }
        @AuraEnabled public String nextCursor { get; set; }
        @AuraEnabled public String previousCursor { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }

        public ArchiveQueryResult(
            List<UoWAuditHistory__b> records,
            Boolean hasMore,
            String nextCursor,
            String previousCursor
        ) {
            this.records = records;
            this.hasMore = hasMore;
            this.nextCursor = nextCursor;
            this.previousCursor = previousCursor;
            this.totalCount = records.size();
        }
    }

    /**
     * Filter options for the UI.
     */
    public class FilterOptions {
        @AuraEnabled public List<SelectOption> workTypes { get; set; }
        @AuraEnabled public List<SelectOption> statuses { get; set; }
        @AuraEnabled public List<SelectOption> riskLevels { get; set; }

        public FilterOptions() {
            this.workTypes = new List<SelectOption>{
                new SelectOption('DML', 'DML'),
                new SelectOption('EVENT', 'Platform Event'),
                new SelectOption('FLOW', 'Flow'),
                new SelectOption('EMAIL', 'Email'),
                new SelectOption('NOTIFICATION', 'Notification'),
                new SelectOption('CALLOUT', 'Callout')
            };

            this.statuses = new List<SelectOption>{
                new SelectOption('SUCCESS', 'Success'),
                new SelectOption('PARTIAL_SUCCESS', 'Partial Success'),
                new SelectOption('FAILURE', 'Failure'),
                new SelectOption('PENDING', 'Pending'),
                new SelectOption('EXECUTED', 'Executed'),
                new SelectOption('SKIPPED', 'Skipped')
            };

            this.riskLevels = new List<SelectOption>{
                new SelectOption('NONE', 'None'),
                new SelectOption('LOW', 'Low'),
                new SelectOption('MEDIUM', 'Medium'),
                new SelectOption('HIGH', 'High'),
                new SelectOption('CRITICAL', 'Critical')
            };
        }
    }

    /**
     * Generic select option for picklists.
     */
    public class SelectOption {
        @AuraEnabled public String value { get; set; }
        @AuraEnabled public String label { get; set; }

        public SelectOption(String value, String label) {
            this.value = value;
            this.label = label;
        }
    }
}
