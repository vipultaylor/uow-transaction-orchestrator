//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Helper utilities for Flow invocable actions.
 *
 * Provides shared functionality for:
 * - Schema.SObjectField resolution from string field names
 * - Error message formatting for Flow-friendly output
 * - Enum value parsing and validation
 * - Common input validation
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Flow Actions
 * @see UoWFlowInitializeAction
 * @see UoWFlowCommitAction
 */
public inherited sharing class UoWFlowActionHelpers {
    // ============================================================================
    // FIELD RESOLUTION
    // ============================================================================

    /**
     * Resolve a Schema.SObjectField from SObject type and field name string
     *
     * @param sObjectType The SObject type (e.g., Contact.SObjectType)
     * @param fieldName The field API name (e.g., 'AccountId')
     * @return Schema.SObjectField instance
     * @throws UoWException if field not found
     */
    public static Schema.SObjectField resolveField(Schema.SObjectType sObjectType, String fieldName) {
        Schema.DescribeSObjectResult describe = UoWCacheService.getDescribe(sObjectType);
        Map<String, Schema.SObjectField> fieldMap = describe.fields.getMap();

        Schema.SObjectField field = fieldMap.get(fieldName);
        if (field == null) {
            throw new UoWExceptionService.UoWException(
                String.format('Field "{0}" not found on {1}',
                    new String[]{ fieldName, describe.getName() })
            );
        }

        return field;
    }

    /**
     * Resolve a Schema.SObjectField from record list and field name
     *
     * @param records The records (must be non-empty)
     * @param fieldName The field API name
     * @return Schema.SObjectField instance
     */
    public static Schema.SObjectField resolveFieldFromRecords(List<SObject> records, String fieldName) {
        Schema.SObjectField resolvedField;

        if (records != null && !records.isEmpty()) {
            Schema.SObjectType sObjectType = records[0].getSObjectType();
            resolvedField = resolveField(sObjectType, fieldName);
        }

        return resolvedField;
    }

    // ============================================================================
    // ENUM PARSING
    // ============================================================================

    /**
     * Parse string to UoWEnums.WorkPhase
     *
     * @param phaseStr The phase string (POST_DML, ON_SUCCESS, etc.)
     * @return UoWEnums.WorkPhase value
     * @throws UoWException if invalid phase
     */
    public static UoWEnums.WorkPhase parseWorkPhase(String phaseStr) {
        try {
            return UoWEnums.WorkPhase.valueOf(phaseStr.toUpperCase());
        } catch (Exception ex) {
            throw new UoWExceptionService.UoWException('Invalid work phase: ' + phaseStr + '. Valid values: PRE_DML, POST_DML, ON_SUCCESS, ON_FAILURE, ON_FINALIZATION');
        }
    }

    /**
     * Parse string to UoWEnums.CommitMode
     *
     * @param modeStr The commit mode string (SYNC, ASYNC)
     * @return UoWEnums.CommitMode value
     * @throws UoWException if invalid mode
     */
    public static UoWEnums.CommitMode parseCommitMode(String modeStr) {
        if (String.isBlank(modeStr)) {
            return null;
        }

        try {
            return UoWEnums.CommitMode.valueOf(modeStr.toUpperCase());
        } catch (Exception ex) {
            throw new UoWExceptionService.UoWException('Invalid commit mode: ' + modeStr + '. Valid values: SYNC, ASYNC');
        }
    }

    // ============================================================================
    // WORK ITEM CONFIGURATION
    // ============================================================================

    /** Origin type constant for Flow-originated work items */
    public static final String ORIGIN_TYPE_FLOW = 'Flow';

    // ============================================================================
    // ERROR FORMATTING
    // ============================================================================

    /**
     * Generate a user-friendly error summary from UoWResult
     *
     * @param result The transaction result
     * @return Error summary string (null if no errors)
     */
    public static String generateErrorSummary(UoWResult result) {
        List<String> summaries = new List<String>();

        // DML errors
        if (result.statistics.dmlStats.records.errors > 0) {
            summaries.add(String.format('{0} DML errors',
                new String[]{ String.valueOf(result.statistics.dmlStats.records.errors) }));
        }

        // Email errors
        if (result.statistics.emailStats.emails.errors > 0) {
            summaries.add(String.format('{0} email errors',
                new String[]{ String.valueOf(result.statistics.emailStats.emails.errors) }));
        }

        // Event errors
        if (result.statistics.eventStats.events.errors > 0) {
            summaries.add(String.format('{0} event publishing errors',
                new String[]{ String.valueOf(result.statistics.eventStats.events.errors) }));
        }

        // Callout errors
        if (result.statistics.calloutStats.callouts.errors > 0) {
            summaries.add(String.format('{0} callout errors',
                new String[]{ String.valueOf(result.statistics.calloutStats.callouts.errors) }));
        }

        // Group errors by type
        Map<String, Integer> errorTypeCounts = new Map<String, Integer>();
        for (UoWExceptionService.ErrorInfo error : result.getErrors()) {
            Integer count = errorTypeCounts.get(error.errorType);
            errorTypeCounts.put(error.errorType, (count == null ? 1 : count + 1));
        }

        // Add error type breakdown
        for (String errorType : errorTypeCounts.keySet()) {
            summaries.add(String.format('{0}: {1}',
                new String[]{ errorType, String.valueOf(errorTypeCounts.get(errorType)) }));
        }

        return summaries.isEmpty() ? 'Unknown errors occurred' : String.join(summaries, '; ');
    }

    /**
     * Format exception for Flow-friendly error message
     *
     * @param ex The exception
     * @return Formatted error message
     */
    public static String formatException(Exception ex) {
        return ex.getMessage() + ' (Type: ' + ex.getTypeName() + ')';
    }
}