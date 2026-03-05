//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * @description Audit plugin for UnitOfWork framework.
 *              Thin orchestrator that delegates to specialized services.
 *
 *              Architecture:
 *              - UoWAuditPlugin: Orchestrates audit flow (this class)
 *              - UoWAuditEventPublisher: Publishes to platform events
 *              - UoWAuditEventHandler: Invocable for Flow-based event processing
 *
 *              Settings (via UoWPluginSetting__mdt.Settings__c JSON):
 *              - storageMode: NONE, CUSTOM_OBJECT, BIG_OBJECT, PLATFORM_EVENT (default: CUSTOM_OBJECT)
 *              - retentionDays: Days to retain records before archival (default: 30)
 *              - archivalMode: PURGE or ARCHIVE (default: PURGE)
 *
 *              Storage Modes:
 *              - NONE: Auditing disabled (no events published)
 *              - Any other mode: Events published (handler determines storage)
 *
 *              Design Note:
 *              Work items are retrieved from Result (outcome), not Plan (intent).
 *              After execution, Result contains ALL work items - both executed and
 *              non-executed items are added during finalization.
 *
 * @author Vipul Taylor
 */
public class UoWAuditPlugin extends UoWBasePlugin {

    // ============================================================================
    // PRIVATE PROPERTIES - AUDIT SETTINGS
    // ============================================================================

    private UoWAuditEnums.AuditStorageMode storageMode = UoWAuditEnums.AuditStorageMode.CUSTOM_OBJECT;
    private UoWAuditEnums.AuditArchivalMode archivalMode = UoWAuditEnums.AuditArchivalMode.PURGE;
    private Integer retentionDays = 30;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    public UoWAuditPlugin() {
        super('AuditPlugin', UoWEnums.PluginCategory.AUDIT);
    }

    // ============================================================================
    // PUBLIC API - INITIALIZATION
    // ============================================================================

    /**
     * @description Initialize plugin with settings from metadata.
     *              Parses storageMode, retentionDays, and archivalMode from Settings__c JSON.
     * @param pluginSetting The plugin setting CMT record
     */
    public override void initialize(UoWPluginSetting__mdt pluginSetting) {
        super.initialize(pluginSetting);

        if (pluginSetting == null || String.isBlank(pluginSetting.Settings__c)) {
            return;
        }

        Map<String, Object> settings = (Map<String, Object>) JSON.deserializeUntyped(pluginSetting.Settings__c);

        // Parse storageMode
        Object storageModeValue = settings.get('storageMode');
        if (storageModeValue != null) {
            this.storageMode = UoWAuditEnums.AuditStorageMode.valueOf(String.valueOf(storageModeValue));
        }

        // Parse archivalMode
        Object archivalModeValue = settings.get('archivalMode');
        if (archivalModeValue != null) {
            this.archivalMode = UoWAuditEnums.AuditArchivalMode.valueOf(String.valueOf(archivalModeValue));
        }

        // Parse retentionDays
        Object retentionDaysValue = settings.get('retentionDays');
        if (retentionDaysValue != null) {
            this.retentionDays = Integer.valueOf(retentionDaysValue);
        }
    }

    // ============================================================================
    // PUBLIC API - PLUGIN CONFIGURATION
    // ============================================================================

    /**
     * @description Audit plugins are non-critical - failures should not block transactions.
     *              Audit data is important but not worth failing business operations.
     * @return false (non-critical)
     */
    public override Boolean isCritical() {
        return false;
    }

    // ============================================================================
    // PUBLIC API - SETTINGS ACCESSORS
    // ============================================================================

    /**
     * @description Get the configured storage mode.
     * @return Storage mode enum value
     */
    public UoWAuditEnums.AuditStorageMode getStorageMode() {
        return this.storageMode;
    }

    /**
     * @description Get the configured archival mode.
     * @return Archival mode enum value
     */
    public UoWAuditEnums.AuditArchivalMode getArchivalMode() {
        return this.archivalMode;
    }

    /**
     * @description Get the configured retention days.
     * @return Retention days
     */
    public Integer getRetentionDays() {
        return this.retentionDays;
    }

    /**
     * @description Check if auditing is enabled (storage mode is not NONE).
     * @return True if auditing should occur
     */
    public Boolean isAuditingEnabled() {
        return this.storageMode != UoWAuditEnums.AuditStorageMode.NONE;
    }

    // ============================================================================
    // PUBLIC API - PLUGIN HOOKS
    // ============================================================================

    /**
     * @description Publish audit events in finally block for guaranteed capture
     *              Platform events are committed independently of the transaction.
     *              Uses Result.getAllWorkItems() to get the outcome (both executed
     *              and non-executed work items are available in Result after finalization).
     * @param ctx The UoW context
     * @param result The result object containing all work items
     * @return PhaseResult.EXECUTED if audit events were published, SKIPPED if auditing disabled
     */
    public override UoWPluginExecutor.PhaseResult onFinally(UoWContext ctx, UoWResult result) {
        // Check if auditing is enabled based on plugin settings
        if (!isAuditingEnabled()) {
            return UoWPluginExecutor.PhaseResult.SKIPPED; // Auditing disabled
        }

        // Publish audit events via publisher service, passing this plugin for settings access
        UoWAuditEventPublisher.PublishResult publishResult = UoWAuditEventPublisher.publishAuditEvents(ctx, result, this);

        // Log publish outcome
        if (publishResult.isSuccess) {
            result.fine(
                String.format(
                    'Audit events published: {0} transaction, {1} work items',
                    new String[]{
                        publishResult.transactionEventBuilt ? '1' : '0',
                        String.valueOf(publishResult.workItemEventsBuilt)
                    }
                ),
                'UoWAuditPlugin'
            );
        } else {
            // Log warnings for any publish failures
            for (UoWAuditEventPublisher.PublishError err : publishResult.errors) {
                result.warn(
                    String.format(
                        'Audit event publish error [{0}]: {1} - {2}',
                        new String[]{ err.eventIdentifier, err.errorCode, err.errorMessage }
                    ),
                    'UoWAuditPlugin'
                );
            }
        }

        return UoWPluginExecutor.PhaseResult.EXECUTED;
    }
}