//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * @description Work item event component for timeline visualization.
 *              Renders a work item as a compact event with hyperlink to detail record.
 *
 *              Work items represent user-registered operations (DML, callout, email, etc.)
 *              that are executed during a UoW transaction. They are displayed as events
 *              within their parent phase span.
 *
 * @see UowSpanItem
 * @see UowSpanEvent
 */
import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { WORK_TYPE_TOKENS, getToken } from 'c/uowSharedDesignTokens';

export default class UowWorkItemEvent extends NavigationMixin(LightningElement) {
    @api workItem;

    // ============================================================================
    // COMPUTED PROPERTIES - DISPLAY
    // ============================================================================

    get workType() {
        return this.workItem?.WorkType__c;
    }

    get config() {
        return getToken(WORK_TYPE_TOKENS, this.workType);
    }

    get iconName() {
        return this.config.icon;
    }

    get iconContainerClass() {
        return `uow-work-item-icon uow-work-item-icon-${this.config.suffix}`;
    }

    get displayName() {
        const wi = this.workItem;
        if (!wi) return '';

        switch (this.workType) {
            case 'DML':
                // Remove _OP suffix if present (e.g., INSERT_OP -> INSERT)
                const operation = wi.DmlOperation__c?.replace(/_OP$/, '') || '';
                return `${wi.SObjectType__c} ${operation}`;
            case 'CALLOUT':
                return wi.HttpMethod__c ? `${wi.HttpMethod__c} ${wi.Endpoint__c}` : wi.Endpoint__c;
            case 'EMAIL':
                return 'Email Send';
            case 'NOTIFICATION':
                return wi.NotificationType__c || 'Notification';
            case 'FLOW':
                return wi.FlowApiName__c || 'Flow Execution';
            case 'EVENT':
                return wi.SObjectType__c || 'Platform Event';
            default:
                return wi.Operation__c || this.workType;
        }
    }

    get recordUrl() {
        return `/lightning/r/UoWAuditWorkItem__c/${this.workItem?.Id}/view`;
    }

    // ============================================================================
    // COMPUTED PROPERTIES - STATUS
    // ============================================================================

    get status() {
        return this.workItem?.WorkItemStatus__c;
    }

    get resultSummary() {
        const wi = this.workItem;
        if (!wi) return '';

        let icon = '';
        switch (this.status) {
            case 'SUCCESS': icon = '✓'; break;
            case 'PARTIAL_SUCCESS': icon = '⚠'; break;
            case 'FAILED': icon = '✗'; break;
            case 'NOT_EXECUTED': icon = '○'; break;
        }

        if (wi.SuccessCount__c != null && wi.ProcessedCount__c != null) {
            return `${icon} ${wi.SuccessCount__c}/${wi.ProcessedCount__c}`;
        }

        return icon;
    }

    get summaryClass() {
        let classes = 'slds-m-left_x-small';

        switch (this.status) {
            case 'SUCCESS':
                classes += ' slds-text-color_success';
                break;
            case 'FAILED':
            case 'PARTIAL_SUCCESS':
                classes += ' slds-text-color_error';
                break;
            default:
                classes += ' slds-text-color_weak';
        }

        return classes;
    }

    // ============================================================================
    // EVENT HANDLERS
    // ============================================================================

    handleClick(event) {
        event.preventDefault();
        event.stopPropagation();

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.workItem?.Id,
                actionName: 'view'
            }
        });
    }
}