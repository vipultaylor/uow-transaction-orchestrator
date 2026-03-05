//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Configuration Snapshot LWC for UoW Audit Transaction visualization.
 * Displays the configuration snapshot as formatted JSON using the uowCodeViewer component.
 *
 * Features:
 * - Copy to clipboard functionality
 * - Download as JSON file
 *
 * This simplified component is decoupled from configuration field changes -
 * any new fields added to UoWConfiguration__mdt automatically appear in the JSON.
 *
 * @see UoWAuditConfigurationController
 * @see uowCodeViewer
 */
import { LightningElement, api, wire } from 'lwc';
import getConfiguration from '@salesforce/apex/UoWAuditConfigurationController.getConfiguration';

export default class UowConfigurationSnapshot extends LightningElement {
    // ============================================================================
    // PUBLIC API
    // ============================================================================

    /**
     * Salesforce Record ID - auto-populated by Lightning record page
     */
    @api recordId;

    // ============================================================================
    // PRIVATE STATE
    // ============================================================================

    transactionId = '';
    settingsJson = '';
    configurationName = '';
    error;
    isLoading = true;
    dataCopied = false;

    // ============================================================================
    // WIRE ADAPTERS
    // ============================================================================

    @wire(getConfiguration, { transactionId: '$recordId' })
    wiredConfiguration({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.transactionId = data.transactionId || '';
            this.configurationName = data.configurationName || 'Unknown';
            // Pretty-print the JSON for readability
            this.settingsJson = data.settingsJson
                ? JSON.stringify(JSON.parse(data.settingsJson), null, 2)
                : '';
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.transactionId = '';
            this.settingsJson = '';
            this.configurationName = '';
        }
    }

    // ============================================================================
    // COMPUTED PROPERTIES - STATE
    // ============================================================================

    get isLoaded() {
        return !this.isLoading && !this.error && this.settingsJson !== '';
    }

    get hasError() {
        return !this.isLoading && this.error;
    }

    get isEmpty() {
        return !this.isLoading && !this.error && this.settingsJson === '';
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

    get configTitle() {
        return `Configuration: ${this.configurationName}`;
    }

    // ============================================================================
    // COMPUTED PROPERTIES - BUTTONS
    // ============================================================================

    get copyButtonVariant() {
        return this.dataCopied ? 'success' : 'neutral';
    }

    // ============================================================================
    // EVENT HANDLERS
    // ============================================================================

    handleCopyToClipboard() {
        if (!this.settingsJson) return;

        // Use modern Clipboard API
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(this.settingsJson)
                .then(() => {
                    this.dataCopied = true;
                    this.resetCopyStateAfterDelay();
                })
                .catch(() => {
                    this.fallbackCopyToClipboard(this.settingsJson);
                });
        } else {
            this.fallbackCopyToClipboard(this.settingsJson);
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
        if (!this.settingsJson) return;

        const fileName = this.generateFileName();
        const blob = new Blob([this.settingsJson], { type: 'application/json' });
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

    generateFileName() {
        const txnId = this.transactionId || 'unknown';
        return `${txnId}-config-snapshot.json`;
    }
}
