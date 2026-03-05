//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Origin Metadata Viewer component for UoW Audit Work Items.
 * Displays the origin source code snippet with syntax highlighting.
 * Highlights the origin line and shows class metadata
 * including API version and modification status.
 *
 * Uses the generic uowCodeViewer component for code display.
 */
import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import canViewOriginMetadata from '@salesforce/apex/UoWMetadataViewerController.canViewOriginMetadata';
import checkForModifications from '@salesforce/apex/UoWMetadataViewerController.checkForModifications';

// Import all origin metadata fields
import ORIGIN_SOURCE_METADATA_FIELD from '@salesforce/schema/UoWAuditWorkItem__c.OriginSourceMetadata__c';
import REQUEST_ORIGIN_FIELD from '@salesforce/schema/UoWAuditWorkItem__c.RequestOrigin__c';
import ORIGIN_API_VERSION_FIELD from '@salesforce/schema/UoWAuditWorkItem__c.OriginApiVersion__c';
import ORIGIN_METADATA_TYPE_FIELD from '@salesforce/schema/UoWAuditWorkItem__c.OriginMetadataType__c';
import ORIGIN_CLASS_NAME_FIELD from '@salesforce/schema/UoWAuditWorkItem__c.OriginClassName__c';
import ORIGIN_METHOD_NAME_FIELD from '@salesforce/schema/UoWAuditWorkItem__c.OriginMethodName__c';
import ORIGIN_LINE_NUMBER_FIELD from '@salesforce/schema/UoWAuditWorkItem__c.OriginLineNumber__c';
import ORIGIN_SNIPPET_START_LINE_FIELD from '@salesforce/schema/UoWAuditWorkItem__c.OriginSnippetStartLine__c';
import ORIGIN_LAST_MODIFIED_DATE_FIELD from '@salesforce/schema/UoWAuditWorkItem__c.OriginLastModifiedDate__c';

const FIELDS = [
    ORIGIN_SOURCE_METADATA_FIELD,
    REQUEST_ORIGIN_FIELD,
    ORIGIN_API_VERSION_FIELD,
    ORIGIN_METADATA_TYPE_FIELD,
    ORIGIN_CLASS_NAME_FIELD,
    ORIGIN_METHOD_NAME_FIELD,
    ORIGIN_LINE_NUMBER_FIELD,
    ORIGIN_SNIPPET_START_LINE_FIELD,
    ORIGIN_LAST_MODIFIED_DATE_FIELD
];

export default class UowMetadataViewer extends LightningElement {
    @api recordId;

    @track isLoading = true;
    @track hasPermission = false;
    @track hasMetadata = false;
    @track hasCodeBeenModified = false;
    @track modificationUnknown = false;
    @track errorMessage = null;

    // Origin metadata fields (stored directly, no JSON parsing needed)
    @track sourceSnippet = null;
    @track requestOrigin = null;
    @track originApiVersion = null;
    @track originMetadataType = null;
    @track originClassName = null;
    @track originMethodName = null;
    @track originLineNumber = null;
    @track snippetStartLine = null;
    @track originLastModifiedDate = null;

    // ============================================================================
    // WIRE ADAPTERS
    // ============================================================================

    @wire(canViewOriginMetadata)
    wiredPermission({ error, data }) {
        if (data !== undefined) {
            this.hasPermission = data;
            if (!data) {
                this.isLoading = false;
            }
        } else if (error) {
            this.hasPermission = false;
            this.isLoading = false;
            console.error('Error checking permission:', error);
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ error, data }) {
        if (data) {
            this.processRecord(data);
        } else if (error) {
            this.errorMessage = 'Error loading record data';
            this.isLoading = false;
            console.error('Error loading record:', error);
        }
    }

    // ============================================================================
    // PRIVATE METHODS
    // ============================================================================

    processRecord(data) {
        // Read all fields directly - no JSON parsing needed
        this.sourceSnippet = getFieldValue(data, ORIGIN_SOURCE_METADATA_FIELD);
        this.requestOrigin = getFieldValue(data, REQUEST_ORIGIN_FIELD);
        this.originApiVersion = getFieldValue(data, ORIGIN_API_VERSION_FIELD);
        this.originMetadataType = getFieldValue(data, ORIGIN_METADATA_TYPE_FIELD);
        this.originClassName = getFieldValue(data, ORIGIN_CLASS_NAME_FIELD);
        this.originMethodName = getFieldValue(data, ORIGIN_METHOD_NAME_FIELD);
        this.originLineNumber = getFieldValue(data, ORIGIN_LINE_NUMBER_FIELD);
        this.snippetStartLine = getFieldValue(data, ORIGIN_SNIPPET_START_LINE_FIELD);
        this.originLastModifiedDate = getFieldValue(data, ORIGIN_LAST_MODIFIED_DATE_FIELD);

        // Check if we have metadata (source snippet is required)
        if (!this.sourceSnippet) {
            this.hasMetadata = false;
            this.isLoading = false;
            return;
        }

        this.hasMetadata = true;
        this.checkModificationStatus();
    }

    async checkModificationStatus() {
        // All values come from dedicated fields now
        if (!this.originMetadataType || !this.originClassName) {
            this.isLoading = false;
            return;
        }

        try {
            const result = await checkForModifications({
                metadataType: this.originMetadataType,
                className: this.originClassName,
                capturedLastModifiedDate: this.originLastModifiedDate
            });

            if (result.hasBeenModified === true) {
                this.hasCodeBeenModified = true;
            } else if (result.hasBeenModified === null) {
                this.modificationUnknown = true;
            }

            if (result.classNotFound) {
                this.modificationUnknown = true;
            }
        } catch (ex) {
            console.error('Error checking modifications:', ex);
            this.modificationUnknown = true;
        } finally {
            this.isLoading = false;
        }
    }

    // ============================================================================
    // GETTERS
    // ============================================================================

    get showComponent() {
        return this.hasPermission && !this.isLoading;
    }

    get showNoPermission() {
        return !this.hasPermission && !this.isLoading;
    }

    get showNoMetadata() {
        return this.hasPermission && !this.hasMetadata && !this.isLoading && !this.errorMessage;
    }

    get showError() {
        return this.errorMessage && !this.isLoading;
    }

    get showMetadata() {
        return this.hasPermission && this.hasMetadata && !this.isLoading;
    }

    get metadataTypeDisplay() {
        return this.originMetadataType || 'Unknown';
    }

    get originLocationDisplay() {
        // Use RequestOrigin__c directly - it contains the full path (e.g., "OuterClass.InnerClass.method:lineNumber")
        if (this.requestOrigin) {
            // Remove the line number suffix for display (will be shown separately)
            const colonIndex = this.requestOrigin.lastIndexOf(':');
            if (colonIndex > 0) {
                return this.requestOrigin.substring(0, colonIndex);
            }
            return this.requestOrigin;
        }

        // Fallback to individual fields if RequestOrigin not available
        let display = this.originClassName || '';
        if (this.originMethodName) {
            display += '.' + this.originMethodName;
        }
        return display;
    }

    // Getters for uowCodeViewer component - now use tracked properties directly
    get sourceCode() {
        return this.sourceSnippet || '';
    }

    get codeStartLine() {
        return this.snippetStartLine;
    }

    get codeHighlightLine() {
        return this.originLineNumber;
    }
}