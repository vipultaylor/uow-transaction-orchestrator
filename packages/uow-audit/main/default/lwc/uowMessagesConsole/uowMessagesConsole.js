//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * @description Messages Console LWC for UoW Audit Transaction visualization.
 *              Developer console-style log viewer displaying transaction messages
 *              with severity filtering, search, and clean grid layout.
 *
 *              Features:
 *              - Severity filtering with toggle buttons (All/None + individual levels)
 *              - Badge counts per logging level
 *              - Relative timestamps (MM:SS.mmm format)
 *              - Color-coded severity badges
 *              - Search/filter functionality
 *
 *              Usage:
 *              1. With recordId (wire to Apex):
 *                 <c-uow-messages-console record-id={recordId}></c-uow-messages-console>
 *
 *              2. With direct messages array:
 *                 <c-uow-messages-console messages={messagesArray}></c-uow-messages-console>
 *
 * @see UoWAuditMessagesController
 * @see UoWMessage
 */
import { LightningElement, api, track, wire } from 'lwc';
import getMessages from '@salesforce/apex/UoWAuditMessagesController.getMessages';

export default class UowMessagesConsole extends LightningElement {
    // ============================================================================
    // PUBLIC API
    // ============================================================================

    @api recordId; // UoWAuditTransaction__c record ID (for wire to Apex)

    // Direct messages input (for use without Apex wire)
    @api
    get messages() {
        return this._externalMessages;
    }
    set messages(value) {
        this._externalMessages = value || [];
        this._useExternalMessages = true;
    }

    // Transaction start time for relative timestamp calculation
    @api
    get transactionStartTime() {
        return this._transactionStartTime;
    }
    set transactionStartTime(value) {
        this._transactionStartTime = value ? new Date(value) : null;
    }

    // ============================================================================
    // PRIVATE STATE
    // ============================================================================

    @track _wireMessages = [];
    @track _externalMessages = [];
    @track _transactionStartTime = null;
    @track error;

    _useExternalMessages = false;

    // Filter state
    @track selectedLogLevel = 'ALL';
    @track searchTerm = '';

    // ============================================================================
    // WIRE - APEX DATA
    // ============================================================================

    @wire(getMessages, { transactionId: '$recordId' })
    wiredMessages({ error, data }) {
        // Only use wire if recordId is provided and not using external messages
        if (!this.recordId || this._useExternalMessages) {
            return;
        }

        if (data) {
            this._wireMessages = data.messages || [];
            this._transactionStartTime = data.transactionStartTime ? new Date(data.transactionStartTime) : null;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this._wireMessages = [];
            this._transactionStartTime = null;
        }
    }

    // ============================================================================
    // COMPUTED PROPERTIES - MESSAGE SOURCE
    // ============================================================================

    /**
     * Internal messages array - uses external messages if set, otherwise wire messages
     */
    get internalMessages() {
        return this._useExternalMessages ? this._externalMessages : this._wireMessages;
    }

    // ============================================================================
    // COMPUTED PROPERTIES - FILTER OPTIONS
    // ============================================================================

    get logLevelOptions() {
        return [
            { label: 'All', value: 'ALL' },
            { label: 'Error', value: 'ERROR' },
            { label: 'Warn', value: 'WARN' },
            { label: 'Info', value: 'INFO' },
            { label: 'Debug', value: 'DEBUG' },
            { label: 'Fine', value: 'FINE' }
        ];
    }

    get totalCount() {
        return this.internalMessages.length;
    }

    // ============================================================================
    // COMPUTED PROPERTIES - FILTERED MESSAGES
    // ============================================================================

    get filteredMessages() {
        let filtered = this.internalMessages;

        // Filter by level
        if (this.selectedLogLevel !== 'ALL') {
            if (this.selectedLogLevel === 'FINE') {
                // FINE includes FINE, FINER, FINEST
                filtered = filtered.filter(msg =>
                    msg.loggingLevel === 'FINE' ||
                    msg.loggingLevel === 'FINER' ||
                    msg.loggingLevel === 'FINEST'
                );
            } else {
                filtered = filtered.filter(msg => msg.loggingLevel === this.selectedLogLevel);
            }
        }

        // Filter by search term
        if (this.searchTerm) {
            const term = this.searchTerm.toLowerCase();
            filtered = filtered.filter(msg => {
                const messageText = (msg.message || '').toLowerCase();
                const sourceText = (msg.source || '').toLowerCase();
                return messageText.includes(term) || sourceText.includes(term);
            });
        }

        return filtered;
    }

    get filteredCount() {
        return this.filteredMessages.length;
    }

    // ============================================================================
    // COMPUTED PROPERTIES - DISPLAY STATE
    // ============================================================================

    get hasMessages() {
        return this.filteredMessages.length > 0;
    }

    get hasNoMessages() {
        return this.internalMessages.length === 0;
    }

    get displayMessages() {
        // Use first message timestamp as base time (more reliable than transactionStartTime)
        const firstMsgTime = this.internalMessages.length > 0 && this.internalMessages[0].timestamp
            ? new Date(this.internalMessages[0].timestamp).getTime()
            : null;
        const baseTime = firstMsgTime || (this._transactionStartTime ? this._transactionStartTime.getTime() : null);

        return this.filteredMessages.map((msg, index) => {
            // Calculate relative time from first message
            let relativeTime = '00:00.000';
            if (msg.timestamp && baseTime) {
                const msgTime = new Date(msg.timestamp).getTime();
                const relativeMs = msgTime - baseTime;
                relativeTime = this.formatRelativeTime(relativeMs);
            }

            return {
                ...msg,
                key: `msg-${index}`,
                index: index,
                relativeTime: relativeTime,
                levelClass: this.getLevelClass(msg.loggingLevel),
                levelLabel: msg.loggingLevel || 'UNKNOWN'
            };
        });
    }

    // ============================================================================
    // HELPER METHODS
    // ============================================================================

    /**
     * Format relative time in MM:SS.mmm format
     * @param {number} relativeMs - Milliseconds from transaction start
     * @returns {string} Formatted string like "00:15.032"
     */
    formatRelativeTime(relativeMs) {
        if (relativeMs == null || relativeMs < 0) {
            return '00:00.000';
        }

        const totalSeconds = Math.floor(relativeMs / 1000);
        const minutes = Math.floor(totalSeconds / 60);
        const seconds = totalSeconds % 60;
        const millis = relativeMs % 1000;

        return String(minutes).padStart(2, '0') + ':' +
               String(seconds).padStart(2, '0') + '.' +
               String(millis).padStart(3, '0');
    }

    getLevelClass(level) {
        const classes = {
            'ERROR': 'level-badge level-badge--error',
            'WARN': 'level-badge level-badge--warn',
            'INFO': 'level-badge level-badge--info',
            'DEBUG': 'level-badge level-badge--debug',
            'FINE': 'level-badge level-badge--fine',
            'FINER': 'level-badge level-badge--fine',
            'FINEST': 'level-badge level-badge--fine'
        };
        return classes[level] || 'level-badge';
    }

    // ============================================================================
    // EVENT HANDLERS
    // ============================================================================

    handleLogLevelChange(event) {
        this.selectedLogLevel = event.detail.value;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
    }
}