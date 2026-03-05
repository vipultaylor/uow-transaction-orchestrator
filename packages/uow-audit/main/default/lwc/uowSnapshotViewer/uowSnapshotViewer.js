//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * @description Snapshot viewer component for UoW Audit Work Items.
 *              Opens as a quick action modal to display work item snapshot data.
 *
 *              Features:
 *              - Two viewing modes: Record JSON and Log File (human-readable)
 *              - Copy to clipboard functionality
 *              - Download as file (.json or .log)
 *
 *              Inspired by Nebula Logger's logViewer pattern.
 *
 * @see UoWAuditWorkItemController
 */
import { LightningElement, api, wire } from 'lwc';
import getWorkItemForViewer from '@salesforce/apex/UoWAuditWorkItemController.getWorkItemForViewer';

export default class UowSnapshotViewer extends LightningElement {
    // ============================================================================
    // PUBLIC API
    // ============================================================================

    /**
     * Salesforce Record ID - auto-populated by Lightning quick action
     */
    @api recordId;

    // ============================================================================
    // PRIVATE STATE
    // ============================================================================

    workItem;
    error;
    isLoading = true;
    currentMode = 'json'; // 'json' or 'file'
    dataCopied = false;

    // ============================================================================
    // WIRE ADAPTERS
    // ============================================================================

    @wire(getWorkItemForViewer, { recordId: '$recordId' })
    wiredWorkItem({ error, data }) {
        this.isLoading = false;
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

    get isLoaded() {
        return !this.isLoading && !this.error && this.workItem;
    }

    get hasError() {
        return !this.isLoading && this.error;
    }

    get errorMessage() {
        if (!this.error) return '';
        if (this.error.body?.message) return this.error.body.message;
        if (this.error.message) return this.error.message;
        return 'An unknown error occurred';
    }

    // ============================================================================
    // COMPUTED PROPERTIES - HEADER
    // ============================================================================

    get title() {
        if (!this.workItem) return 'Snapshot Viewer';
        const workType = this.formatWorkType(this.workItem.WorkType__c);
        return `${workType} Work Item - ${this.workItem.Name}`;
    }

    // ============================================================================
    // COMPUTED PROPERTIES - CONTENT
    // ============================================================================

    get snapshotData() {
        if (!this.workItem?.Snapshot__c) return null;
        try {
            return JSON.parse(this.workItem.Snapshot__c);
        } catch (e) {
            return { rawSnapshot: this.workItem.Snapshot__c };
        }
    }

    get formattedJson() {
        if (!this.snapshotData) return '// No snapshot data available';
        try {
            return JSON.stringify(this.snapshotData, null, 2);
        } catch (e) {
            return this.workItem.Snapshot__c || '// No snapshot data available';
        }
    }

    get formattedLogFile() {
        if (!this.workItem) return '// No work item data available';

        const lines = [];
        lines.push('================================================================================');
        lines.push(`UoW WORK ITEM: ${this.workItem.Name}`);
        lines.push('================================================================================');
        lines.push('');

        // Work Item Metadata
        lines.push('--- METADATA ---');
        lines.push(`Work ID:          ${this.workItem.Name || 'N/A'}`);
        lines.push(`Work Type:        ${this.workItem.WorkType__c || 'N/A'}`);
        lines.push(`Status:           ${this.workItem.WorkItemStatus__c || 'N/A'}`);
        lines.push(`Execution Phase:  ${this.workItem.ExecutionPhase__c || 'N/A'}`);
        lines.push('');

        // Work Type Specific Details
        if (this.workItem.WorkType__c === 'DML') {
            lines.push('--- DML DETAILS ---');
            lines.push(`SObject Type:     ${this.workItem.SObjectType__c || 'N/A'}`);
            lines.push(`DML Operation:    ${this.workItem.DmlOperation__c || 'N/A'}`);
            lines.push('');
        } else if (this.workItem.WorkType__c === 'CALLOUT') {
            lines.push('--- CALLOUT DETAILS ---');
            lines.push(`Endpoint:         ${this.workItem.Endpoint__c || 'N/A'}`);
            lines.push(`HTTP Method:      ${this.workItem.HttpMethod__c || 'N/A'}`);
            lines.push('');
        } else if (this.workItem.WorkType__c === 'FLOW') {
            lines.push('--- FLOW DETAILS ---');
            lines.push(`Flow API Name:    ${this.workItem.FlowApiName__c || 'N/A'}`);
            lines.push('');
        } else if (this.workItem.WorkType__c === 'NOTIFICATION') {
            lines.push('--- NOTIFICATION DETAILS ---');
            lines.push(`Notification Type: ${this.workItem.NotificationType__c || 'N/A'}`);
            lines.push('');
        }

        // Metrics
        lines.push('--- METRICS ---');
        lines.push(`Planned:          ${this.workItem.PlannedCount__c ?? 0}`);
        lines.push(`Processed:        ${this.workItem.ProcessedCount__c ?? 0}`);
        lines.push(`Successes:        ${this.workItem.SuccessCount__c ?? 0}`);
        lines.push(`Failures:         ${this.workItem.FailureCount__c ?? 0}`);
        lines.push(`Execution Time:   ${this.workItem.ExecutionTimeMs__c ?? 0}ms`);
        lines.push('');

        // Error Information
        if (this.workItem.HasErrors__c) {
            lines.push('--- ERRORS ---');
            lines.push(`Error Count:      ${this.workItem.ErrorCount__c ?? 0}`);
            if (this.workItem.ErrorMessage__c) {
                lines.push(`Error Message:    ${this.workItem.ErrorMessage__c}`);
            }
            lines.push('');
        }

        return lines.join('\n');
    }

    get currentContent() {
        return this.currentMode === 'json' ? this.formattedJson : this.formattedLogFile;
    }

    // ============================================================================
    // COMPUTED PROPERTIES - BUTTONS
    // ============================================================================

    get downloadButtonLabel() {
        return this.currentMode === 'json' ? 'Download Record JSON' : 'Download Log File';
    }

    get copyButtonVariant() {
        return this.dataCopied ? 'success' : 'neutral';
    }

    // ============================================================================
    // EVENT HANDLERS
    // ============================================================================

    handleTabActivated(event) {
        this.currentMode = event.target.value;
        this.dataCopied = false; // Reset copy state when switching tabs
    }

    handleCopyToClipboard() {
        const content = this.currentContent;
        if (!content) return;

        // Use modern Clipboard API
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(content)
                .then(() => {
                    this.dataCopied = true;
                    this.resetCopyStateAfterDelay();
                })
                .catch(() => {
                    this.fallbackCopyToClipboard(content);
                });
        } else {
            this.fallbackCopyToClipboard(content);
        }
    }

    fallbackCopyToClipboard(content) {
        // Fallback for older browsers
        const textArea = document.createElement('textarea');
        textArea.value = content;
        textArea.style.position = 'fixed';
        textArea.style.left = '-9999px';
        document.body.appendChild(textArea);
        textArea.select();
        try {
            document.execCommand('copy');
            this.dataCopied = true;
            this.resetCopyStateAfterDelay();
        } catch (err) {
            console.error('Failed to copy to clipboard', err);
        }
        document.body.removeChild(textArea);
    }

    resetCopyStateAfterDelay() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.dataCopied = false;
        }, 2000);
    }

    handleDownload() {
        const content = this.currentContent;
        if (!content) return;

        const fileName = this.generateFileName();
        const mimeType = this.currentMode === 'json' ? 'application/json' : 'text/plain';

        const blob = new Blob([content], { type: mimeType });
        const url = URL.createObjectURL(blob);

        const link = document.createElement('a');
        link.href = url;
        link.download = fileName;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        URL.revokeObjectURL(url);
    }

    // ============================================================================
    // UTILITY METHODS
    // ============================================================================

    formatWorkType(workType) {
        if (!workType) return '';
        return workType.charAt(0) + workType.slice(1).toLowerCase();
    }

    generateFileName() {
        const name = this.workItem?.Name || 'work-item';
        const workType = (this.workItem?.WorkType__c || 'unknown').toLowerCase();
        const extension = this.currentMode === 'json' ? 'json' : 'log';
        return `${name}-${workType}.${extension}`;
    }
}