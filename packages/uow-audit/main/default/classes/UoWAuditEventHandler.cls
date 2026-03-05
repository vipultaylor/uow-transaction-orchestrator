//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * @description Event handler for UoWAuditEvent__e platform events.
 *              Implements discriminator pattern with storage mode routing:
 *              - EventType = 'TRANSACTION' / 'WORK_ITEM' determines record type
 *              - StorageMode__c determines persistence target:
 *                  - CUSTOM_OBJECT: UoWAuditTransaction__c + UoWAuditWorkItem__c (default)
 *                  - BIG_OBJECT: UoWAuditHistory__b (denormalized work items)
 *                  - PLATFORM_EVENT: No persistence (events only)
 *                  - EXTERNAL: Future - external system callout
 *
 *              Pattern by Storage Mode:
 *
 *              CUSTOM_OBJECT Mode:
 *              - All events in same transaction share CorrelationId__c
 *              - TRANSACTION event creates parent record
 *              - WORK_ITEM events create child records linked via External ID lookup
 *
 *              BIG_OBJECT Mode:
 *              - No TRANSACTION events published (saves event bus usage)
 *              - WORK_ITEM events contain full transaction context (denormalized by publisher)
 *              - Each work item event has all the data needed for Big Object record
 *              - This design avoids correlation issues when events arrive in different batches
 *
 *              Flow Integration:
 *              - Designed to be called from Platform Event-Triggered Flow
 *              - Uses @InvocableMethod for declarative configuration
 *
 * @author Vipul Taylor
 */
public class UoWAuditEventHandler {

    // ============================================================================
    // PUBLIC API
    // ============================================================================

    /**
     * @description Invocable method for Flow-based event processing
     *              Allows Platform Event-Triggered Flows to call this handler
     *              Routes events to appropriate storage based on StorageMode__c
     * @param events List of UoWAuditEvent__e events from Flow
     */
    @InvocableMethod(
        label='Process Audit Events'
        description='Processes UoW Audit Events and creates Transaction/WorkItem records'
        category='Unit of Work'
    )
    public static void processEventsFromFlow(List<UoWAuditEvent__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }

        // Group events by storage mode, then by type
        Map<UoWAuditEnums.AuditStorageMode, List<UoWAuditEvent__e>> transactionEventsByMode =
            new Map<UoWAuditEnums.AuditStorageMode, List<UoWAuditEvent__e>>();
        Map<UoWAuditEnums.AuditStorageMode, List<UoWAuditEvent__e>> workItemEventsByMode =
            new Map<UoWAuditEnums.AuditStorageMode, List<UoWAuditEvent__e>>();

        for (UoWAuditEvent__e event : events) {
            // Parse storage mode from event field, default to CUSTOM_OBJECT
            UoWAuditEnums.AuditStorageMode storageMode = parseStorageMode(event.StorageMode__c);

            if (event.EventType__c == UoWAuditParameter.EVENT_TYPE_TRANSACTION) {
                if (!transactionEventsByMode.containsKey(storageMode)) {
                    transactionEventsByMode.put(storageMode, new List<UoWAuditEvent__e>());
                }
                transactionEventsByMode.get(storageMode).add(event);
            } else if (event.EventType__c == UoWAuditParameter.EVENT_TYPE_WORK_ITEM) {
                if (!workItemEventsByMode.containsKey(storageMode)) {
                    workItemEventsByMode.put(storageMode, new List<UoWAuditEvent__e>());
                }
                workItemEventsByMode.get(storageMode).add(event);
            }
        }

        // Process each storage mode
        Set<UoWAuditEnums.AuditStorageMode> allModes = new Set<UoWAuditEnums.AuditStorageMode>();
        allModes.addAll(transactionEventsByMode.keySet());
        allModes.addAll(workItemEventsByMode.keySet());

        for (UoWAuditEnums.AuditStorageMode storageMode : allModes) {
            List<UoWAuditEvent__e> txnEvents = transactionEventsByMode.get(storageMode);
            List<UoWAuditEvent__e> wiEvents = workItemEventsByMode.get(storageMode);

            if (txnEvents == null) {
                txnEvents = new List<UoWAuditEvent__e>();
            }
            if (wiEvents == null) {
                wiEvents = new List<UoWAuditEvent__e>();
            }

            routeToStorage(storageMode, txnEvents, wiEvents);
        }
    }

    // ============================================================================
    // PRIVATE HELPER METHODS - ROUTING
    // ============================================================================

    /**
     * @description Parse storage mode from string value
     * @param storageModeStr The storage mode string from event field
     * @return Parsed AuditStorageMode enum, defaults to CUSTOM_OBJECT
     */
    private static UoWAuditEnums.AuditStorageMode parseStorageMode(String storageModeStr) {
        if (String.isBlank(storageModeStr)) {
            return UoWAuditEnums.AuditStorageMode.CUSTOM_OBJECT;
        }

        try {
            return UoWAuditEnums.AuditStorageMode.valueOf(storageModeStr);
        } catch (Exception e) {
            // Invalid enum value, default to CUSTOM_OBJECT
            System.debug(LoggingLevel.WARN,
                'Invalid storage mode: ' + storageModeStr + ', defaulting to CUSTOM_OBJECT');
            return UoWAuditEnums.AuditStorageMode.CUSTOM_OBJECT;
        }
    }

    /**
     * @description Route events to appropriate storage handler based on mode
     * @param storageMode The storage mode enum
     * @param transactionEvents List of TRANSACTION type events
     * @param workItemEvents List of WORK_ITEM type events
     */
    private static void routeToStorage(
        UoWAuditEnums.AuditStorageMode storageMode,
        List<UoWAuditEvent__e> transactionEvents,
        List<UoWAuditEvent__e> workItemEvents
    ) {
        switch on storageMode {
            when CUSTOM_OBJECT {
                // Default: Custom Object storage
                UoWAuditCustomObjectWriter.writeAuditData(transactionEvents, workItemEvents);
            }
            when BIG_OBJECT {
                // Route to Big Object writer
                UoWAuditBigObjectWriter.writeAuditData(transactionEvents, workItemEvents);
            }
            when else {
                System.debug(LoggingLevel.DEBUG,
                    'Storage mode ' + storageMode.name() + ' - events published but not persisted');
            }
        }
    }

    // ============================================================================
    // INNER CLASSES
    // ============================================================================

    /**
     * @description Custom exception for audit event handler errors
     */
    public class AuditEventHandlerException extends Exception {}
}