//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * @description Error Details LWC for UoW Audit Transaction visualization.
 *              Displays transaction errors with expandable detail panels,
 *              stack traces, error context, and metadata.
 *
 *              Features:
 *              - Expandable error rows with full details
 *              - Collapsible stack traces and error context
 *              - Error type badges and metadata indicators
 *              - Retryable status and attempt tracking
 *              - Suggestion and documentation links
 *
 * @see UoWExceptionService.ErrorInfo
 */
import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getErrors from '@salesforce/apex/UoWAuditErrorsController.getErrors';

export default class UowErrorDetails extends NavigationMixin(LightningElement) {
    @api recordId; // UoWAuditTransaction__c or UoWAuditWorkItem__c record ID

    // Optional configuration
    @api title = 'Errors';

    @track errors = [];
    @track error;

    // Expansion tracking
    @track expandedErrors = new Set();
    @track expandedStackTraces = new Set();
    @track expandedContexts = new Set();

    // Wire to Apex controller
    @wire(getErrors, { recordId: '$recordId' })
    wiredErrors({ error, data }) {
        if (data) {
            this.errors = data || [];
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.errors = [];
        }
    }

    // ============================================================================
    // COMPUTED PROPERTIES - DISPLAY STATE
    // ============================================================================

    get hasErrors() {
        return this.errors.length > 0;
    }

    get hasNoErrors() {
        return this.errors.length === 0;
    }

    get errorCount() {
        return this.errors.length;
    }

    get headerTitle() {
        return `${this.title} (${this.errorCount})`;
    }

    // ============================================================================
    // COMPUTED PROPERTIES - DISPLAY ERRORS
    // ============================================================================

    get displayErrors() {
        return this.errors.map((err, index) => {
            const isExpanded = this.expandedErrors.has(index);
            const showStackTrace = this.expandedStackTraces.has(index);
            const showErrorContext = this.expandedContexts.has(index);

            // Parse error context if serialized
            let errorContextFormatted = '';
            let hasErrorContext = false;
            if (err.errorContextSerialized) {
                try {
                    const parsed = JSON.parse(err.errorContextSerialized);
                    errorContextFormatted = JSON.stringify(parsed, null, 2);
                    hasErrorContext = true;
                } catch (e) {
                    errorContextFormatted = err.errorContextSerialized;
                    hasErrorContext = true;
                }
            }

            // Work item display logic
            // Don't show work item at all if we're already on the work item page
            const isCurrentWorkItem = err.workItemRecordId === this.recordId;
            const showWorkItem = !isCurrentWorkItem && !!err.workItemId;
            const hasWorkItemLink = showWorkItem && !!err.workItemRecordId;
            const workItemIdShort = err.workItemId ? err.workItemId.substring(0, 15) + '...' : '';

            return {
                ...err,
                key: `error-${index}`,
                index: index,
                isExpanded: isExpanded,
                expandIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                errorMessagePreview: this.truncateMessage(err.errorMessage, 80),
                errorIdShort: err.errorId ? err.errorId.substring(0, 8) + '...' : '',
                formattedTime: this.formatTime(err.occurredAt),
                formattedDateTime: this.formatDateTime(err.occurredAt),
                hasStackTrace: !!err.stackTrace,
                showStackTrace: showStackTrace,
                stackTraceExpandIcon: showStackTrace ? 'utility:chevrondown' : 'utility:chevronright',
                hasErrorContext: hasErrorContext,
                showErrorContext: showErrorContext,
                contextExpandIcon: showErrorContext ? 'utility:chevrondown' : 'utility:chevronright',
                errorContextFormatted: errorContextFormatted,
                hasSuggestion: !!err.suggestion,
                hasDocumentationUrl: !!err.documentationUrl,
                hasAttempts: err.attemptNumber != null && err.attemptNumber > 0,
                attemptTitle: `Attempt ${err.attemptNumber}`,
                showWorkItem: showWorkItem,
                hasWorkItemLink: hasWorkItemLink,
                workItemIdShort: workItemIdShort
            };
        });
    }

    // ============================================================================
    // HELPER METHODS
    // ============================================================================

    /**
     * Truncate message with ellipsis
     * @param {string} message - The message to truncate
     * @param {number} maxLength - Maximum length before truncation
     * @returns {string} Truncated message
     */
    truncateMessage(message, maxLength) {
        if (!message) return '';
        if (message.length <= maxLength) return message;
        return message.substring(0, maxLength) + '...';
    }

    /**
     * Format timestamp to short time (HH:MM:SS)
     * @param {string} isoDateTime - ISO datetime string
     * @returns {string} Formatted time
     */
    formatTime(isoDateTime) {
        if (!isoDateTime) return '';
        try {
            const date = new Date(isoDateTime);
            return date.toLocaleTimeString('en-US', {
                hour: '2-digit',
                minute: '2-digit',
                second: '2-digit',
                hour12: false
            });
        } catch (e) {
            return '';
        }
    }

    /**
     * Format timestamp to full datetime
     * @param {string} isoDateTime - ISO datetime string
     * @returns {string} Formatted datetime
     */
    formatDateTime(isoDateTime) {
        if (!isoDateTime) return '';
        try {
            const date = new Date(isoDateTime);
            return date.toLocaleString('en-US', {
                year: 'numeric',
                month: 'short',
                day: 'numeric',
                hour: '2-digit',
                minute: '2-digit',
                second: '2-digit',
                hour12: false
            });
        } catch (e) {
            return isoDateTime;
        }
    }

    // ============================================================================
    // EVENT HANDLERS
    // ============================================================================

    /**
     * Toggle error row expansion
     * @param {Event} event - Click event
     */
    handleToggleError(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const newExpanded = new Set(this.expandedErrors);

        if (newExpanded.has(index)) {
            newExpanded.delete(index);
            // Also collapse nested sections
            this.expandedStackTraces.delete(index);
            this.expandedContexts.delete(index);
        } else {
            newExpanded.add(index);
        }

        this.expandedErrors = newExpanded;
    }

    /**
     * Toggle stack trace visibility
     * @param {Event} event - Click event
     */
    handleToggleStackTrace(event) {
        event.stopPropagation(); // Prevent row toggle
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const newExpanded = new Set(this.expandedStackTraces);

        if (newExpanded.has(index)) {
            newExpanded.delete(index);
        } else {
            newExpanded.add(index);
        }

        this.expandedStackTraces = newExpanded;
    }

    /**
     * Toggle error context visibility
     * @param {Event} event - Click event
     */
    handleToggleContext(event) {
        event.stopPropagation(); // Prevent row toggle
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const newExpanded = new Set(this.expandedContexts);

        if (newExpanded.has(index)) {
            newExpanded.delete(index);
        } else {
            newExpanded.add(index);
        }

        this.expandedContexts = newExpanded;
    }

    /**
     * Navigate to work item record page
     * @param {Event} event - Click event
     */
    handleNavigateToWorkItem(event) {
        event.preventDefault();
        event.stopPropagation();
        const workItemRecordId = event.currentTarget.dataset.recordId;
        if (workItemRecordId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: workItemRecordId,
                    actionName: 'view'
                }
            });
        }
    }
}