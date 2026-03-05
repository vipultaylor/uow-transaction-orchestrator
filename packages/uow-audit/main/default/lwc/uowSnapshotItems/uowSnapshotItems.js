//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * @description Snapshot Items component for UoW Audit Work Item record pages.
 *              Displays enriched snapshot items (records, events, emails) with
 *              expandable details showing fields, success/failure status, and errors.
 *
 *              Features:
 *              - Expandable rows (all collapsed by default)
 *              - Dynamic field extraction from SObject/EmailMetadata
 *              - Success/failure status badges
 *              - Inline error display with field information
 *              - Navigatable record IDs for DML inserts
 *
 * @see UoWAuditWorkItemController
 * @see UoWDmlWorkItem.RecordSnapshot
 * @see UoWEventWorkItem.EventSnapshot
 * @see UoWEmailWorkItem.EmailSnapshot
 */
import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getWorkItemForViewer from '@salesforce/apex/UoWAuditWorkItemController.getWorkItemForViewer';

// Constants
const MAX_VALUE_LENGTH = 50;
const MAX_PREVIEW_FIELDS = 4;
const MAX_PREVIEW_VALUE_LENGTH = 20;

export default class UowSnapshotItems extends NavigationMixin(LightningElement) {

    // ============================================================================
    // PUBLIC API
    // ============================================================================

    @api recordId;

    // ============================================================================
    // PRIVATE STATE
    // ============================================================================

    workItem;
    error;
    @track expandedRows = new Set();

    // ============================================================================
    // WIRE ADAPTERS
    // ============================================================================

    @wire(getWorkItemForViewer, { recordId: '$recordId' })
    wiredWorkItem({ error, data }) {
        if (data) {
            this.workItem = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.workItem = undefined;
        }
    }

    // ============================================================================
    // COMPUTED PROPERTIES - STATE
    // ============================================================================

    get isLoading() {
        return !this.workItem && !this.error;
    }

    get hasError() {
        return !!this.error;
    }

    get errorMessage() {
        if (!this.error) return '';
        if (this.error.body?.message) return this.error.body.message;
        if (this.error.message) return this.error.message;
        return 'An unknown error occurred';
    }

    get hasSnapshots() {
        return this.snapshots && this.snapshots.length > 0;
    }

    get hasNoSnapshots() {
        return !this.isLoading && !this.hasError && !this.hasSnapshots;
    }

    // ============================================================================
    // COMPUTED PROPERTIES - DATA
    // ============================================================================

    get workType() {
        return this.workItem?.WorkType__c;
    }

    get snapshots() {
        if (!this.workItem?.Snapshot__c) return [];
        try {
            const parsed = JSON.parse(this.workItem.Snapshot__c);
            // Handle both array format and object with snapshots property
            if (Array.isArray(parsed)) {
                return parsed;
            }
            if (parsed.snapshots && Array.isArray(parsed.snapshots)) {
                return parsed.snapshots;
            }
            return [];
        } catch (e) {
            return [];
        }
    }

    get totalCount() {
        return this.workItem?.PlannedCount__c || this.snapshots.length;
    }

    get displayCount() {
        const sampled = this.snapshots.length;
        const total = this.totalCount;
        if (sampled === total) {
            return `${sampled}`;
        }
        return `${sampled} sampled of ${total}`;
    }

    get headerTitle() {
        return `Items (${this.displayCount})`;
    }

    // ============================================================================
    // COMPUTED PROPERTIES - DISPLAY SNAPSHOTS
    // ============================================================================

    get displaySnapshots() {
        return this.snapshots.map((snap, index) => {
            const isExpanded = this.expandedRows.has(index);
            const fields = this.extractFields(snap);
            const isSuccess = snap.ok === true;
            const hasErrors = snap.errs && snap.errs.length > 0;

            // Record ID (DML only)
            const rid = snap.rid;
            const hasRecordId = !!rid;
            const ridShort = rid ? this.truncateId(rid) : null;

            // Original index from snapshot (for display), array index for expansion tracking
            const originalIdx = snap.idx ?? index;

            return {
                key: `snap-${index}`,
                idx: originalIdx,              // Original index for display (e.g., "#29")
                rowIndex: index,               // Array index for expansion tracking
                isExpanded,
                expandIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',

                // Status
                isSuccess,
                statusLabel: isSuccess ? 'OK' : 'FAIL',
                badgeClass: isSuccess ? 'uow-badge-success' : 'uow-badge-error',
                rowClass: 'slds-item',

                // Record ID
                hasRecordId,
                rid,
                ridShort,

                // Preview
                preview: this.generatePreview(fields),
                previewFull: this.generatePreviewFull(fields),

                // Fields for expanded view
                fields,

                // Errors
                hasErrors,
                displayErrors: hasErrors ? this.formatErrors(snap.errs) : [],

                // Upsert created indicator (DML only)
                showCreated: snap.created !== null && snap.created !== undefined,
                createdLabel: snap.created ? 'Created (Insert)' : 'Updated (Existing)'
            };
        });
    }

    // ============================================================================
    // FIELD EXTRACTION
    // ============================================================================

    extractFields(snapshot) {
        switch (this.workType) {
            case 'DML':
                return this.extractSObjectFields(snapshot.rec);
            case 'EVENT':
                return this.extractSObjectFields(snapshot.evt);
            case 'EMAIL':
                return this.extractEmailFields(snapshot.meta);
            default:
                // Try to detect based on snapshot structure
                if (snapshot.rec) return this.extractSObjectFields(snapshot.rec);
                if (snapshot.evt) return this.extractSObjectFields(snapshot.evt);
                if (snapshot.meta) return this.extractEmailFields(snapshot.meta);
                return [];
        }
    }

    extractSObjectFields(sobj) {
        if (!sobj) return [];
        const fields = [];
        for (const [key, value] of Object.entries(sobj)) {
            // Skip Salesforce metadata and Id
            if (key === 'attributes' || key === 'Id') continue;

            const displayValue = this.formatValue(value);
            const rawValue = this.getRawValue(value);

            fields.push({
                key: `field-${key}`,
                keyDt: `dt-${key}`,
                keyDd: `dd-${key}`,
                name: key,
                displayValue,
                rawValue
            });
        }
        return fields;
    }

    extractEmailFields(meta) {
        if (!meta) return [];
        const fields = [];

        // Addressing fields
        if (meta.toAddresses && meta.toAddresses.length > 0) {
            fields.push(this.createEmailField('To', meta.toAddresses.join(', ')));
        }
        if (meta.ccAddresses && meta.ccAddresses.length > 0) {
            fields.push(this.createEmailField('CC', meta.ccAddresses.join(', ')));
        }
        if (meta.bccAddresses && meta.bccAddresses.length > 0) {
            fields.push(this.createEmailField('BCC', meta.bccAddresses.join(', ')));
        }
        if (meta.replyTo) {
            fields.push(this.createEmailField('Reply-To', meta.replyTo));
        }

        // Content
        if (meta.subject) {
            fields.push(this.createEmailField('Subject', meta.subject));
        }
        if (meta.plainTextBody) {
            fields.push(this.createEmailField('Plain Text Body', meta.plainTextBody));
        }
        if (meta.htmlBody) {
            fields.push(this.createEmailField('HTML Body', meta.htmlBody));
        }

        // Templates
        if (meta.templateId) {
            fields.push(this.createEmailField('Template ID', meta.templateId));
        }
        if (meta.targetObjectId) {
            fields.push(this.createEmailField('Target Object ID', meta.targetObjectId));
        }
        if (meta.whatId) {
            fields.push(this.createEmailField('What ID', meta.whatId));
        }

        // Sender
        if (meta.senderDisplayName) {
            fields.push(this.createEmailField('Sender Name', meta.senderDisplayName));
        }
        if (meta.orgWideEmailAddressId) {
            fields.push(this.createEmailField('Org-Wide Email ID', meta.orgWideEmailAddressId));
        }

        // Options
        if (meta.saveAsActivity !== null && meta.saveAsActivity !== undefined) {
            fields.push(this.createEmailField('Save as Activity', String(meta.saveAsActivity)));
        }
        if (meta.useSignature !== null && meta.useSignature !== undefined) {
            fields.push(this.createEmailField('Use Signature', String(meta.useSignature)));
        }

        // Add keys
        return fields.map((f, i) => ({
            ...f,
            key: `field-${i}`,
            keyDt: `dt-${i}`,
            keyDd: `dd-${i}`
        }));
    }

    createEmailField(name, value) {
        return {
            name,
            displayValue: this.truncateValue(value, MAX_VALUE_LENGTH),
            rawValue: String(value)
        };
    }

    // ============================================================================
    // VALUE FORMATTING
    // ============================================================================

    formatValue(value) {
        if (value === null || value === undefined) return '';
        const str = this.getRawValue(value);
        return this.truncateValue(str, MAX_VALUE_LENGTH);
    }

    getRawValue(value) {
        if (value === null || value === undefined) return '';
        if (typeof value === 'object') {
            return JSON.stringify(value);
        }
        return String(value);
    }

    truncateValue(value, maxLength) {
        if (!value) return '';
        const str = String(value);
        if (str.length <= maxLength) return str;
        return str.substring(0, maxLength - 3) + '...';
    }

    truncateId(id) {
        if (!id) return '';
        const str = String(id);
        if (str.length <= 15) return str;
        return str.substring(0, 7) + '...' + str.substring(str.length - 4);
    }

    // ============================================================================
    // PREVIEW GENERATION
    // ============================================================================

    generatePreview(fields) {
        if (!fields || fields.length === 0) return 'No fields';
        return fields
            .slice(0, MAX_PREVIEW_FIELDS)
            .map(f => `${f.name}: ${this.truncateValue(f.rawValue, MAX_PREVIEW_VALUE_LENGTH)}`)
            .join(', ');
    }

    generatePreviewFull(fields) {
        if (!fields || fields.length === 0) return 'No fields';
        return fields
            .map(f => `${f.name}: ${f.rawValue}`)
            .join(', ');
    }

    // ============================================================================
    // ERROR FORMATTING
    // ============================================================================

    formatErrors(errs) {
        if (!errs || errs.length === 0) return [];
        return errs.map((err, i) => ({
            key: `err-${i}`,
            code: err.code || 'UNKNOWN',
            msg: err.msg || 'Unknown error',
            hasFields: err.flds && err.flds.length > 0,
            fieldsDisplay: err.flds ? err.flds.join(', ') : '',
            hasTargetId: !!err.tid,
            tid: err.tid
        }));
    }

    // ============================================================================
    // EVENT HANDLERS
    // ============================================================================

    handleToggleRow(event) {
        event.stopPropagation();
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const newExpanded = new Set(this.expandedRows);

        if (newExpanded.has(index)) {
            newExpanded.delete(index);
        } else {
            newExpanded.add(index);
        }

        this.expandedRows = newExpanded;
    }

    handleNavigateToRecord(event) {
        event.preventDefault();
        event.stopPropagation();
        const recordId = event.currentTarget.dataset.recordId;
        if (recordId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: recordId,
                    actionName: 'view'
                }
            });
        }
    }
}