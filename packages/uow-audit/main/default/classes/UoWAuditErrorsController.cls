//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * @description Apex controller for UoW Audit Error Details LWC component.
 *              Provides data access for visualizing errors stored in
 *              UoWAuditTransaction__c.ErrorDetails__c or UoWAuditWorkItem__c.ErrorDetails__c as JSON.
 *
 *              Supports both Transaction and Work Item record pages by detecting
 *              the SObjectType from the provided record ID.
 *
 *              Uses a lightweight DTO (ErrorDTO) with @AuraEnabled properties
 *              to expose error data to LWC without modifying core ErrorInfo class.
 *
 * @author Vipul Taylor
 * @see UoWExceptionService.ErrorInfo
 */
public with sharing class UoWAuditErrorsController {

    // ============================================================================
    // PUBLIC API
    // ============================================================================

    /**
     * @description Get errors data for a transaction or work item
     * @param recordId UoWAuditTransaction__c or UoWAuditWorkItem__c record ID
     * @return List of ErrorDTO with error details
     */
    @AuraEnabled(cacheable=true)
    public static List<ErrorDTO> getErrors(Id recordId) {
        try {
            String errorDetailsJson = getErrorDetailsJson(recordId);

            List<ErrorDTO> errorDTOs = new List<ErrorDTO>();

            if (String.isNotBlank(errorDetailsJson)) {
                List<Object> errors = (List<Object>) JSON.deserializeUntyped(errorDetailsJson);
                for (Object err : errors) {
                    Map<String, Object> errorMap = (Map<String, Object>) err;
                    errorDTOs.add(new ErrorDTO(errorMap));
                }
            }

            // Resolve work item record IDs for navigation
            resolveWorkItemRecordIds(errorDTOs);

            return errorDTOs;
        } catch (Exception e) {
            throw UoWExceptionService.buildAuraException('Failed to load errors: ' + e.getMessage());
        }
    }

    // ============================================================================
    // PRIVATE METHODS
    // ============================================================================

    // Resolve work item record IDs for navigation links
    private static void resolveWorkItemRecordIds(List<ErrorDTO> errorDTOs) {
        // Collect unique work item IDs
        Set<String> workItemIds = new Set<String>();
        for (ErrorDTO dto : errorDTOs) {
            if (String.isNotBlank(dto.workItemId)) {
                workItemIds.add(dto.workItemId);
            }
        }

        if (workItemIds.isEmpty()) {
            return;
        }

        // Query work item records by Name via selector
        Map<String, Id> workItemIdToRecordId = UoWAuditDataSelector.getInstance()
            .getWorkItemNameToRecordIdMap(workItemIds);

        // Populate workItemRecordId on each DTO
        for (ErrorDTO dto : errorDTOs) {
            if (String.isNotBlank(dto.workItemId)) {
                dto.workItemRecordId = workItemIdToRecordId.get(dto.workItemId);
            }
        }
    }

    // Get ErrorDetails__c JSON based on record type
    private static String getErrorDetailsJson(Id recordId) {
        Schema.SObjectType sobjectType = recordId.getSobjectType();
        UoWAuditDataSelector selector = UoWAuditDataSelector.getInstance();

        if (sobjectType == UoWAuditTransaction__c.SObjectType) {
            UoWAuditTransaction__c txn = selector.getTransactionForErrors(recordId);
            if (txn == null) {
                throw UoWExceptionService.buildAuraException('Transaction not found');
            }
            return txn.ErrorDetails__c;
        } else if (sobjectType == UoWAuditWorkItem__c.SObjectType) {
            UoWAuditWorkItem__c workItem = selector.getWorkItemForErrors(recordId);
            if (workItem == null) {
                throw UoWExceptionService.buildAuraException('Work item not found');
            }
            return workItem.ErrorDetails__c;
        } else {
            throw UoWExceptionService.buildAuraException('Unsupported record type. Expected UoWAuditTransaction__c or UoWAuditWorkItem__c.');
        }
    }

    // ============================================================================
    // WRAPPER CLASSES
    // ============================================================================

    /**
     * @description Lightweight DTO for exposing ErrorInfo data to LWC
     */
    public class ErrorDTO {
        @AuraEnabled public String errorId { get; set; }
        @AuraEnabled public String workItemId { get; set; }         // Work item ID from framework (e.g., WORK-1234567890)
        @AuraEnabled public Id workItemRecordId { get; set; }       // Salesforce record ID for navigation
        @AuraEnabled public String errorType { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public String stackTrace { get; set; }
        @AuraEnabled public String suggestion { get; set; }
        @AuraEnabled public String documentationUrl { get; set; }
        @AuraEnabled public Boolean isRetryable { get; set; }
        @AuraEnabled public Integer attemptNumber { get; set; }
        @AuraEnabled public String errorContextSerialized { get; set; }
        @AuraEnabled public DateTime occurredAt { get; set; }

        public ErrorDTO(Map<String, Object> errorMap) {
            this.errorId = (String) errorMap.get('errorId');
            this.workItemId = (String) errorMap.get('workItemId');
            this.errorType = (String) errorMap.get('errorType');
            this.errorMessage = (String) errorMap.get('errorMessage');
            this.stackTrace = (String) errorMap.get('stackTrace');
            this.suggestion = (String) errorMap.get('suggestion');
            this.documentationUrl = (String) errorMap.get('documentationUrl');
            this.isRetryable = errorMap.get('isRetryable') == true;
            this.attemptNumber = errorMap.get('attemptNumber') != null
                ? Integer.valueOf(errorMap.get('attemptNumber'))
                : null;

            // Handle errorContext - either as serialized string or as map
            Object contextObj = errorMap.get('errorContextSerialized');
            if (contextObj != null) {
                this.errorContextSerialized = String.valueOf(contextObj);
            } else {
                // Try to get errorContext map and serialize it
                Object contextMap = errorMap.get('errorContext');
                if (contextMap != null) {
                    this.errorContextSerialized = JSON.serialize(contextMap);
                }
            }

            // Handle occurredAt datetime
            Object occurredAtObj = errorMap.get('occurredAt');
            if (occurredAtObj != null) {
                if (occurredAtObj instanceof DateTime) {
                    this.occurredAt = (DateTime) occurredAtObj;
                } else {
                    // Parse from string (ISO format)
                    try {
                        String dateStr = String.valueOf(occurredAtObj);
                        // Handle ISO format: 2025-12-12T13:13:34.334Z
                        this.occurredAt = (DateTime) JSON.deserialize('"' + dateStr + '"', DateTime.class);
                    } catch (Exception e) {
                        this.occurredAt = null;
                    }
                }
            }
        }
    }
}