//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * @description Record-page component that shows the UoW audit activity for the current business
 *              record. Resolves, via the UoWAuditRecordIndex__c reverse-lookup index, which audit
 *              transactions (and the work items within them) touched this record, grouped by
 *              transaction and most-recent-first. Drop it onto any object's Lightning record page.
 *
 *              Only sampled records are indexed, so the list is a subset of all activity - the
 *              footer note communicates this to users.
 *
 * @see UoWAuditRecordAuditTrailController
 */
import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { WORK_TYPE_TOKENS, STATUS_TOKENS, getToken } from 'c/uowSharedDesignTokens';
import getAuditActivityForRecord from '@salesforce/apex/UoWAuditRecordAuditTrailController.getAuditActivityForRecord';

// Work item / transaction status -> STATUS_TOKENS key
const STATUS_TOKEN_KEY = {
    SUCCESS: 'SUCCESS',
    PARTIAL_SUCCESS: 'WARNING',
    FAILED: 'ERROR',
    NOT_EXECUTED: 'WARNING'
};

export default class UowRecordAuditActivity extends NavigationMixin(LightningElement) {
    // ============================================================================
    // PUBLIC API
    // ============================================================================

    /** The host record Id (injected on a Lightning record page). */
    @api recordId;

    /** Card title (configurable in Lightning App Builder). */
    @api cardTitle = 'Audit Activity';

    // ============================================================================
    // STATE
    // ============================================================================

    _groups = [];
    _collapsedIds = new Set();
    error;
    loaded = false;

    // ============================================================================
    // WIRE
    // ============================================================================

    @wire(getAuditActivityForRecord, { recordId: '$recordId' })
    wiredActivity({ data, error }) {
        if (data) {
            this._groups = data.map((txn) => this.decorateTransaction(txn));
            // Default: most-recent (first) expanded, older groups collapsed.
            this._collapsedIds = new Set(this._groups.slice(1).map((g) => g.transactionId));
            this.error = undefined;
            this.loaded = true;
        } else if (error) {
            this.error = this.reduceError(error);
            this._groups = [];
            this.loaded = true;
        }
    }

    // ============================================================================
    // GETTERS
    // ============================================================================

    get transactions() {
        return this._groups.map((group) => {
            const expanded = !this._collapsedIds.has(group.transactionId);
            return {
                ...group,
                expanded,
                toggleIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright',
                bodyClass: expanded ? 'uow-txn-body' : 'uow-txn-body slds-hide'
            };
        });
    }

    get hasActivity() {
        return this._groups.length > 0;
    }

    get showEmptyState() {
        return this.loaded && !this.error && this._groups.length === 0;
    }

    // ============================================================================
    // DECORATION
    // ============================================================================

    decorateTransaction(txn) {
        const statusToken = getToken(STATUS_TOKENS, STATUS_TOKEN_KEY[txn.status] || 'WARNING');
        const meta = [];
        if (txn.commitMode) {
            meta.push(this.titleCase(txn.commitMode));
        }
        if (txn.executionTimeMs != null) {
            meta.push(`${txn.executionTimeMs} ms`);
        }
        return {
            transactionId: txn.transactionId,
            name: txn.name,
            status: txn.status,
            statusIcon: statusToken.icon,
            statusBadgeClass: `slds-badge uow-status-badge uow-status-badge_${statusToken.suffix}`,
            // Normalize the Apex Datetime to epoch millis so lightning-relative-date-time can
            // parse it reliably (raw value may arrive as a number or an ISO string).
            startTimeMs: this.toEpochMillis(txn.startTime),
            metaLine: meta.join(' · '),
            workItems: (txn.workItems || []).map((wi) => this.decorateWorkItem(wi))
        };
    }

    decorateWorkItem(wi) {
        const typeToken = getToken(WORK_TYPE_TOKENS, wi.workType);
        const statusToken = getToken(STATUS_TOKENS, STATUS_TOKEN_KEY[wi.status] || 'WARNING');
        return {
            workItemId: wi.workItemId,
            label: this.workItemLabel(wi),
            iconName: typeToken.icon,
            iconClass: `uow-work-item-icon uow-work-item-icon-${typeToken.suffix}`,
            statusIcon: statusToken.icon,
            statusText: this.titleCase(wi.status),
            countLabel: wi.recordCount != null ? `${wi.recordCount} record(s)` : ''
        };
    }

    workItemLabel(wi) {
        if (wi.workType === 'DML' && wi.sobjectType) {
            return wi.operation ? `${wi.sobjectType} · ${wi.operation}` : wi.sobjectType;
        }
        return wi.sobjectType || wi.workType || 'Work Item';
    }

    toEpochMillis(value) {
        if (value == null) {
            return null;
        }
        // Already epoch millis
        if (typeof value === 'number') {
            return value;
        }
        const parsed = new Date(value).getTime();
        return Number.isNaN(parsed) ? null : parsed;
    }

    titleCase(value) {
        if (!value) {
            return '';
        }
        return value
            .toLowerCase()
            .split('_')
            .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
            .join(' ');
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unknown error';
    }

    // ============================================================================
    // EVENT HANDLERS
    // ============================================================================

    handleToggle(event) {
        const id = event.currentTarget.dataset.id;
        const next = new Set(this._collapsedIds);
        if (next.has(id)) {
            next.delete(id);
        } else {
            next.add(id);
        }
        this._collapsedIds = next;
    }

    handleTransactionNav(event) {
        event.preventDefault();
        event.stopPropagation();
        this.navigateToRecord(event.currentTarget.dataset.id);
    }

    handleWorkItemNav(event) {
        event.preventDefault();
        event.stopPropagation();
        this.navigateToRecord(event.currentTarget.dataset.id);
    }

    navigateToRecord(recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                actionName: 'view'
            }
        });
    }
}
