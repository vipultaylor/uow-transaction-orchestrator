//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Utility methods for the UnitOfWork framework.
 * Provides ID generation, execution context detection, record utilities, and date/time helpers.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Core
 */
public inherited sharing class UoWUtils {

    // ============================================================================
    // ID GENERATION
    // ============================================================================

    /**
     * Generate a UUID v4 for distributed correlation.
     *
     * @return UUID string (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
     */
    public static String generateUUID() {
        return System.UUID.randomUUID().toString();
    }

    /**
     * Generate internal transaction ID.
     *
     * @return Transaction ID (TXN-timestamp-random)
     */
    public static String generateTransactionId() {
        return generateId('TXN');
    }

    /**
     * Generate a unique work item identifier.
     *
     * @return Unique ID string
     */
    public static String generateWorkId() {
        return generateId('WORK');
    }

    /**
     * Generate a unique identifier with prefix.
     *
     * @param prefix Prefix for the ID
     * @return Unique ID string (PREFIX-timestamp-random6)
     */
    public static String generateId(String prefix) {
        String timestamp = String.valueOf(DateTime.now().getTime());
        String randomPart = String.valueOf(Math.abs(Crypto.getRandomInteger())).left(6);
        return prefix + '-' + timestamp + '-' + randomPart;
    }

    // ============================================================================
    // EXECUTION CONTEXT
    // ============================================================================

    /**
     * Get current execution context.
     *
     * @return ExecutionContext enum
     */
    public static System.Quiddity getExecutionContext() {
        return Request.getCurrent().getQuiddity();
    }

    /**
     * Check if execution is asynchronous.
     *
     * @return True if async context
     */
    public static Boolean isAsyncContext() {
        System.Quiddity ctx = getExecutionContext();
        return ctx == System.Quiddity.BATCH_APEX ||
               ctx == System.Quiddity.QUEUEABLE ||
               ctx == System.Quiddity.FUTURE ||
               ctx == System.Quiddity.SCHEDULED;
    }

    /**
     * Check if execution is in test context.
     *
     * @return True if test context
     */
    public static Boolean isTestContext() {
        System.Quiddity ctx = getExecutionContext();
        return ctx == System.Quiddity.RUNTEST_DEPLOY ||
               ctx == System.Quiddity.RUNTEST_SYNC ||
               ctx == System.Quiddity.RUNTEST_ASYNC;
    }

    // ============================================================================
    // RECORD UTILITIES
    // ============================================================================

    /**
     * Extract IDs from SObject list.
     *
     * @param records List of SObjects
     * @return Set of IDs
     */
    public static Set<Id> extractIds(List<SObject> records) {
        Set<Id> ids = new Set<Id>();
        if (records != null) {
            for (SObject record : records) {
                if (record.Id != null) {
                    ids.add(record.Id);
                }
            }
        }
        return ids;
    }

    // ============================================================================
    // STRING UTILITIES
    // ============================================================================

    /**
     * Safely trim a String value, returning null if input is null.
     * Per Salesforce Big Object best practices, index fields should be trimmed
     * to remove leading and trailing whitespace for reliable querying.
     *
     * @param value The string to trim
     * @return Trimmed string or null
     * @see https://developer.salesforce.com/docs/atlas.en-us.bigobjects.meta/bigobjects/big_object_populate.htm
     */
    public static String safeTrim(String value) {
        if (value == null) {
            return null;
        }
        return value.trim();
    }

    // ============================================================================
    // DATE/TIME UTILITIES
    // ============================================================================

    /**
     * Get current timestamp in milliseconds.
     *
     * @return Timestamp
     */
    public static Long getCurrentTimestampMs() {
        return DateTime.now().getTime();
    }

    /**
     * Calculate elapsed time in milliseconds.
     *
     * @param startTime Start timestamp
     * @return Elapsed time
     */
    public static Long getElapsedTimeMs(Long startTime) {
        return getCurrentTimestampMs() - startTime;
    }

    /**
     * Format duration in human-readable form.
     *
     * @param durationMs Duration in milliseconds
     * @return Formatted duration
     */
    public static String formatDuration(Long durationMs) {
        if (durationMs == null || durationMs < 0) {
            return '0ms';
        }

        if (durationMs < 1000) {
            return durationMs + 'ms';
        } else if (durationMs < 60000) {
            return (durationMs / 1000.0).setScale(2) + 's';
        } else {
            Long minutes = durationMs / 60000;
            Long seconds = Math.mod(durationMs, 60000) / 1000;
            return minutes + 'm ' + seconds + 's';
        }
    }

    // ============================================================================
    // WORK ITEM UTILITIES
    // ============================================================================

    // Get the execution phase from a work item, if it has one.
    // Event, Email, Notification, Flow, and Callout work items have execution phases.
    // DML work items do not have phases.
    public static UoWEnums.WorkPhase getWorkItemExecutionPhase(UoWWorkItem workItem) {
        if (workItem == null || workItem.workType == null) {
            return null;
        }

        switch on workItem.workType {
            when EVENT {
                return ((UoWEventWorkItem) workItem).executionPhase;
            }
            when EMAIL {
                return ((UoWEmailWorkItem) workItem).executionPhase;
            }
            when NOTIFICATION {
                return ((UoWNotificationWorkItem) workItem).executionPhase;
            }
            when FLOW {
                return ((UoWFlowWorkItem) workItem).executionPhase;
            }
            when CALLOUT {
                return ((UoWCalloutWorkItem) workItem).executionPhase;
            }
            when else {
                // DML doesn't have execution phases
                return null;
            }
        }
    }

}