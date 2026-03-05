//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Apex controller for UoW Audit Configuration Snapshot LWC component.
 * Provides data access for visualizing configuration snapshots stored
 * in UoWAuditTransaction__c.ConfigurationSnapshot__c as JSON.
 *
 * The snapshot is built at audit publish time and contains the configuration
 * values that were in effect at transaction execution time.
 *
 * Returns the raw JSON string for LWC consumption, preserving the
 * historical snapshot values rather than recalculating from current metadata.
 *
 * @author Vipul Taylor
 * @see UoWFeatureSettings
 */
public with sharing class UoWAuditConfigurationController {

    // ============================================================================
    // PUBLIC API
    // ============================================================================

    /**
     * Get feature settings data for a transaction.
     *
     * @param transactionId UoWAuditTransaction__c record ID
     * @return ConfigurationData wrapper with raw JSON string and configuration name
     */
    @AuraEnabled(cacheable=true)
    public static ConfigurationData getConfiguration(Id transactionId) {
        try {
            UoWAuditTransaction__c txn = UoWAuditDataSelector.getInstance().getTransactionForConfiguration(transactionId);
            if (txn == null) {
                throw UoWExceptionService.buildAuraException('Transaction not found');
            }

            return new ConfigurationData(txn.TransactionId__c, txn.ConfigurationSnapshot__c, txn.ConfigurationName__c);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw UoWExceptionService.buildAuraException('Failed to load configuration: ' + e.getMessage());
        }
    }

    // ============================================================================
    // WRAPPER CLASSES
    // ============================================================================

    /**
     * Configuration data wrapper for LWC.
     */
    public class ConfigurationData {
        @AuraEnabled public String transactionId { get; set; }
        @AuraEnabled public String settingsJson { get; set; }
        @AuraEnabled public String configurationName { get; set; }

        public ConfigurationData(String txnId, String settingsJson, String configName) {
            this.transactionId = txnId;
            this.settingsJson = settingsJson;
            this.configurationName = configName;
        }
    }
}
