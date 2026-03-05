//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Enumeration types for UoW Audit functionality.
 * Contains audit-specific enums for storage modes and archival behavior.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Audit
 */
public inherited sharing class UoWAuditEnums {

    // ============================================================================
    // ENUMS - AUDIT STORAGE
    // ============================================================================

    /**
     * Audit storage modes for controlling how audit data is persisted.
     * Configured via UoWPluginSetting__mdt.Settings__c JSON field.
     */
    public enum AuditStorageMode {
        NONE,               // Auditing disabled
        PLATFORM_EVENT,     // Publish events only (external consumption via event handler)
        CUSTOM_OBJECT,      // Store in UoW audit objects (UoWAuditTransaction__c, UoWAuditWorkItem__c)
        BIG_OBJECT,         // Store in big objects (high volume scenarios)
        EXTERNAL            // Callout to external system
    }

    /**
     * Audit archival modes for controlling what happens to old audit records.
     * Configured via UoWPluginSetting__mdt.Settings__c JSON field.
     * Used by UoWAuditArchivalJob.
     */
    public enum AuditArchivalMode {
        PURGE,              // Permanently delete audit records when retention period expires
        ARCHIVE             // Move audit records to Big Object (UoWAuditHistory__b) before deletion
    }

}