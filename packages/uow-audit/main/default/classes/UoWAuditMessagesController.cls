//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * @description Apex controller for UoW Audit Messages Console LWC component.
 *              Provides data access for visualizing transaction messages stored
 *              in UoWAuditTransaction__c.Messages__c as JSON.
 *
 *              Uses a lightweight DTO (MessageDTO) with @AuraEnabled properties
 *              to expose message data to LWC without modifying core UoWMessage class.
 *
 * @author Vipul Taylor
 * @see UoWMessage
 */
public with sharing class UoWAuditMessagesController {

    // ============================================================================
    // PUBLIC API
    // ============================================================================

    /**
     * @description Get messages data for a transaction
     * @param transactionId UoWAuditTransaction__c record ID
     * @return MessagesData wrapper with messages and transaction start time
     */
    @AuraEnabled(cacheable=true)
    public static MessagesData getMessages(Id transactionId) {
        try {
            UoWAuditTransaction__c txn = UoWAuditDataSelector.getInstance().getTransactionForMessages(transactionId);
            if (txn == null) {
                throw UoWExceptionService.buildAuraException('Transaction not found');
            }

            List<MessageDTO> messageDTOs = new List<MessageDTO>();

            if (String.isNotBlank(txn.Messages__c)) {
                List<UoWMessage> messages = (List<UoWMessage>) JSON.deserialize(txn.Messages__c, List<UoWMessage>.class);
                for (UoWMessage msg : messages) {
                    messageDTOs.add(new MessageDTO(msg));
                }
            }

            return new MessagesData(messageDTOs, txn.StartTime__c);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw UoWExceptionService.buildAuraException('Failed to load messages: ' + e.getMessage());
        }
    }

    // ============================================================================
    // WRAPPER CLASSES
    // ============================================================================

    /**
     * @description Messages data wrapper for LWC
     */
    public class MessagesData {
        @AuraEnabled public List<MessageDTO> messages { get; set; }
        @AuraEnabled public DateTime transactionStartTime { get; set; }

        public MessagesData(List<MessageDTO> messages, DateTime startTime) {
            this.messages = messages;
            this.transactionStartTime = startTime;
        }
    }

    /**
     * @description Lightweight DTO for exposing UoWMessage data to LWC
     */
    public class MessageDTO {
        @AuraEnabled public Datetime timestamp { get; set; }
        @AuraEnabled public String loggingLevel { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String source { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public Map<String, Object> metadata { get; set; }

        public MessageDTO(UoWMessage msg) {
            this.timestamp = msg.timestamp;
            this.loggingLevel = msg.loggingLevel != null ? msg.loggingLevel.name() : null;
            this.message = msg.message;
            this.source = msg.source;
            this.category = msg.category;
            this.metadata = msg.metadata;
        }
    }
}