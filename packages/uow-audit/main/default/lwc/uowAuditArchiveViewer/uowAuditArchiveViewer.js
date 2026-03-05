//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * @description Archive viewer component for UoW Audit Big Object records.
 *              Provides list view, filtering, pagination, and detail view for archived audit data.
 *
 *              Features:
 *              - Datatable with sortable columns
 *              - Filter panel (collapsible)
 *              - Cursor-based pagination (Big Object constraint)
 *              - Detail modal for full record view
 *              - Export to JSON/CSV
 *
 *              Inspired by Nebula Logger's logEntryArchives pattern.
 *
 * @see UoWAuditArchiveController
 */
import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getArchiveRecords from '@salesforce/apex/UoWAuditArchiveController.getArchiveRecords';
import getArchiveDetail from '@salesforce/apex/UoWAuditArchiveController.getArchiveDetail';
import getFilterOptions from '@salesforce/apex/UoWAuditArchiveController.getFilterOptions';
import exportArchiveRecords from '@salesforce/apex/UoWAuditArchiveController.exportArchiveRecords';

const COLUMNS = [
    {
        label: 'Created',
        fieldName: 'CreatedTimestamp__c',
        type: 'date',
        typeAttributes: {
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        },
        sortable: true,
        initialWidth: 160
    },
    {
        label: 'Transaction ID',
        fieldName: 'TransactionId__c',
        type: 'text',
        sortable: true,
        initialWidth: 140
    },
    {
        label: 'Correlation ID',
        fieldName: 'CorrelationId__c',
        type: 'text',
        sortable: true,
        initialWidth: 140
    },
    {
        label: 'Work Type',
        fieldName: 'WorkType__c',
        type: 'text',
        sortable: true,
        initialWidth: 90,
        cellAttributes: {
            class: { fieldName: '_workTypeClass' }
        }
    },
    {
        label: 'Operation',
        fieldName: 'DmlOperation__c',
        type: 'text',
        sortable: true,
        initialWidth: 90
    },
    {
        label: 'Status',
        fieldName: 'TransactionStatus__c',
        type: 'text',
        sortable: true,
        initialWidth: 120,
        cellAttributes: {
            class: { fieldName: '_statusClass' }
        }
    },
    {
        label: 'SObject/Target',
        fieldName: 'SObjectType__c',
        type: 'text',
        sortable: true,
        initialWidth: 130
    },
    {
        label: 'Risk',
        fieldName: 'RiskLevel__c',
        type: 'text',
        sortable: true,
        initialWidth: 80,
        cellAttributes: {
            class: { fieldName: '_riskClass' }
        }
    },
    {
        label: 'Context',
        fieldName: 'ExecutionContext__c',
        type: 'text',
        sortable: true,
        initialWidth: 100
    },
    {
        label: 'User',
        fieldName: 'Username__c',
        type: 'text',
        sortable: true,
        initialWidth: 160
    },
    {
        label: 'Duration',
        fieldName: 'ExecutionTimeMs__c',
        type: 'number',
        sortable: true,
        initialWidth: 90,
        cellAttributes: { alignment: 'right' }
    },
    {
        label: 'OK',
        fieldName: 'SuccessCount__c',
        type: 'number',
        sortable: true,
        initialWidth: 60,
        cellAttributes: { alignment: 'right' }
    },
    {
        label: 'Err',
        fieldName: 'FailureCount__c',
        type: 'number',
        sortable: true,
        initialWidth: 60,
        cellAttributes: { alignment: 'right' }
    },
    {
        label: 'Agent',
        fieldName: 'IsAgentTransaction__c',
        type: 'boolean',
        sortable: true,
        initialWidth: 70
    },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'View Details', name: 'view_detail' },
                { label: 'Copy Transaction ID', name: 'copy_id' },
                { label: 'Copy Correlation ID', name: 'copy_correlation' }
            ]
        }
    }
];

const DEFAULT_PAGE_SIZE = 50;

export default class UowAuditArchiveViewer extends LightningElement {
    // ============================================================================
    // PUBLIC API
    // ============================================================================

    // ============================================================================
    // PRIVATE STATE - DATA
    // ============================================================================

    @track records = [];
    @track selectedRecord = null;
    columns = COLUMNS;

    // ============================================================================
    // PRIVATE STATE - FILTERS
    // ============================================================================

    filterCorrelationId = '';
    filterTransactionId = '';
    filterWorkTypes = [];
    filterStatuses = [];
    filterUsername = '';
    filterStartDate = null;
    filterEndDate = null;
    filterAgentOnly = false;

    // ============================================================================
    // PRIVATE STATE - SORTING
    // ============================================================================

    sortedBy = 'CreatedTimestamp__c';
    sortedDirection = 'desc';

    // ============================================================================
    // PRIVATE STATE - PAGINATION
    // ============================================================================

    pageSize = DEFAULT_PAGE_SIZE;
    currentCursor = null;
    cursorStack = []; // For back navigation
    hasMore = false;

    // ============================================================================
    // PRIVATE STATE - UI
    // ============================================================================

    isLoading = false;
    isExporting = false;
    showFilters = true;
    showDetailModal = false;
    error = null;

    // ============================================================================
    // PRIVATE STATE - FILTER OPTIONS
    // ============================================================================

    workTypeOptions = [];
    statusOptions = [];
    riskLevelOptions = [];

    // ============================================================================
    // WIRE ADAPTERS
    // ============================================================================

    @wire(getFilterOptions)
    wiredFilterOptions({ error, data }) {
        if (data) {
            this.workTypeOptions = data.workTypes || [];
            this.statusOptions = data.statuses || [];
            this.riskLevelOptions = data.riskLevels || [];
        } else if (error) {
            console.error('Error loading filter options:', error);
        }
    }

    // ============================================================================
    // LIFECYCLE HOOKS
    // ============================================================================

    connectedCallback() {
        // Set default date range to last 30 days
        const today = new Date();
        const thirtyDaysAgo = new Date();
        thirtyDaysAgo.setDate(today.getDate() - 30);

        this.filterEndDate = this.formatDateForInput(today);
        this.filterStartDate = this.formatDateForInput(thirtyDaysAgo);

        this.loadRecords();
    }

    // ============================================================================
    // COMPUTED PROPERTIES - STATE
    // ============================================================================

    get hasRecords() {
        return this.records && this.records.length > 0;
    }

    get hasError() {
        return this.error != null;
    }

    get isEmpty() {
        return !this.isLoading && !this.hasError && !this.hasRecords;
    }

    get recordCount() {
        return this.records ? this.records.length : 0;
    }

    get isBackDisabled() {
        return this.cursorStack.length === 0;
    }

    get isForwardDisabled() {
        return !this.hasMore;
    }

    // ============================================================================
    // COMPUTED PROPERTIES - UI
    // ============================================================================

    get filterPanelClass() {
        return this.showFilters
            ? 'slds-panel slds-panel_docked slds-panel_docked-left slds-is-open filter-panel'
            : 'slds-panel slds-panel_docked slds-panel_docked-left filter-panel';
    }

    get toggleFiltersIcon() {
        return this.showFilters ? 'utility:chevronleft' : 'utility:filterList';
    }

    get toggleFiltersLabel() {
        return this.showFilters ? 'Hide Filters' : 'Show Filters';
    }

    get pageInfo() {
        if (!this.hasRecords) {
            return 'No records';
        }
        const start = this.cursorStack.length * this.pageSize + 1;
        const end = start + this.records.length - 1;
        return `Showing ${start} - ${end}`;
    }

    get pageSizeOptions() {
        return [
            { label: '25 records', value: 25 },
            { label: '50 records', value: 50 },
            { label: '100 records', value: 100 },
            { label: '200 records', value: 200 }
        ];
    }

    get mainContentClass() {
        return this.showFilters
            ? 'main-content slds-size_3-of-4 slds-p-around_small'
            : 'main-content-full slds-p-around_small';
    }

    // ============================================================================
    // DATA LOADING
    // ============================================================================

    async loadRecords() {
        this.isLoading = true;
        this.error = null;

        try {
            const params = this.buildQueryParams();
            const result = await getArchiveRecords({ params });

            this.records = this.enrichRecords(result.records || []);
            this.hasMore = result.hasMore;

            if (result.hasMore && result.nextCursor) {
                this.currentCursor = result.nextCursor;
            }
        } catch (err) {
            this.error = this.extractErrorMessage(err);
            this.records = [];
            this.showToast('Error', this.error, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    buildQueryParams() {
        return {
            correlationId: this.filterCorrelationId || null,
            transactionId: this.filterTransactionId || null,
            workTypes: this.filterWorkTypes.length > 0 ? this.filterWorkTypes : null,
            statuses: this.filterStatuses.length > 0 ? this.filterStatuses : null,
            username: this.filterUsername || null,
            startDate: this.filterStartDate || null,
            endDate: this.filterEndDate || null,
            pageSize: this.pageSize,
            cursor: this.currentCursor,
            agentTransactionsOnly: this.filterAgentOnly
        };
    }

    enrichRecords(records) {
        return records.map(rec => ({
            ...rec,
            // Convert string booleans to actual booleans (Big Objects store as Text)
            IsAgentTransaction__c: rec.IsAgentTransaction__c === 'true',
            IsDryRun__c: rec.IsDryRun__c === 'true',
            RiskEvaluated__c: rec.RiskEvaluated__c === 'true',
            PolicyEvaluated__c: rec.PolicyEvaluated__c === 'true',
            MaskingApplied__c: rec.MaskingApplied__c === 'true',
            ContinueOnError__c: rec.ContinueOnError__c === 'true',
            OrganizationIsSandbox__c: rec.OrganizationIsSandbox__c === 'true',
            UserIsImpersonated__c: rec.UserIsImpersonated__c === 'true',
            RequiresApproval__c: rec.RequiresApproval__c === 'true',
            // UI helper classes
            _workTypeClass: this.getWorkTypeClass(rec.WorkType__c),
            _statusClass: this.getStatusClass(rec.TransactionStatus__c || rec.WorkItemStatus__c),
            _riskClass: this.getRiskClass(rec.RiskLevel__c)
        }));
    }

    getWorkTypeClass(workType) {
        const typeClasses = {
            'DML': 'work-type-dml',
            'EVENT': 'work-type-event',
            'FLOW': 'work-type-flow',
            'EMAIL': 'work-type-email',
            'NOTIFICATION': 'work-type-notification',
            'CALLOUT': 'work-type-callout'
        };
        return typeClasses[workType] || '';
    }

    getStatusClass(status) {
        if (!status) return '';
        if (status.includes('SUCCESS') && !status.includes('PARTIAL')) {
            return 'status-success';
        }
        if (status.includes('PARTIAL')) {
            return 'status-warning';
        }
        if (status.includes('FAIL') || status.includes('ERROR')) {
            return 'status-error';
        }
        return '';
    }

    getRiskClass(riskLevel) {
        const riskClasses = {
            'CRITICAL': 'risk-critical',
            'HIGH': 'risk-high',
            'MEDIUM': 'risk-medium',
            'LOW': 'risk-low',
            'NONE': 'risk-none'
        };
        return riskClasses[riskLevel] || '';
    }

    // ============================================================================
    // EVENT HANDLERS - FILTERS
    // ============================================================================

    handleToggleFilters() {
        this.showFilters = !this.showFilters;
    }

    handleCorrelationIdChange(event) {
        this.filterCorrelationId = event.target.value;
    }

    handleTransactionIdChange(event) {
        this.filterTransactionId = event.target.value;
    }

    handleWorkTypeChange(event) {
        this.filterWorkTypes = event.detail.value;
    }

    handleStatusChange(event) {
        this.filterStatuses = event.detail.value;
    }

    handleUsernameChange(event) {
        this.filterUsername = event.target.value;
    }

    handleStartDateChange(event) {
        this.filterStartDate = event.target.value;
    }

    handleEndDateChange(event) {
        this.filterEndDate = event.target.value;
    }

    handleAgentOnlyChange(event) {
        this.filterAgentOnly = event.target.checked;
    }

    handleApplyFilters() {
        this.currentCursor = null;
        this.cursorStack = [];
        this.loadRecords();
    }

    handleClearFilters() {
        this.filterCorrelationId = '';
        this.filterTransactionId = '';
        this.filterWorkTypes = [];
        this.filterStatuses = [];
        this.filterUsername = '';
        this.filterAgentOnly = false;

        // Reset date range to last 30 days
        const today = new Date();
        const thirtyDaysAgo = new Date();
        thirtyDaysAgo.setDate(today.getDate() - 30);
        this.filterEndDate = this.formatDateForInput(today);
        this.filterStartDate = this.formatDateForInput(thirtyDaysAgo);

        this.currentCursor = null;
        this.cursorStack = [];
        this.loadRecords();
    }

    // ============================================================================
    // EVENT HANDLERS - PAGINATION
    // ============================================================================

    handlePageSizeChange(event) {
        this.pageSize = parseInt(event.detail.value, 10);
        this.currentCursor = null;
        this.cursorStack = [];
        this.loadRecords();
    }

    handlePreviousPage() {
        if (this.cursorStack.length > 0) {
            this.currentCursor = this.cursorStack.pop();
            this.loadRecords();
        }
    }

    handleNextPage() {
        if (this.hasMore && this.currentCursor) {
            // Save current cursor before moving forward
            if (this.cursorStack.length === 0 || this.cursorStack[this.cursorStack.length - 1] !== this.currentCursor) {
                this.cursorStack.push(this.currentCursor);
            }
            this.loadRecords();
        }
    }

    handleRefresh() {
        this.currentCursor = null;
        this.cursorStack = [];
        this.loadRecords();
    }

    // ============================================================================
    // EVENT HANDLERS - TABLE
    // ============================================================================

    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;

        switch (action.name) {
            case 'view_detail':
                this.openDetailModal(row);
                break;
            case 'copy_id':
                this.copyToClipboard(row.TransactionId__c);
                break;
            case 'copy_correlation':
                this.copyToClipboard(row.CorrelationId__c);
                break;
            default:
                break;
        }
    }

    handleSort(event) {
        // Note: Big Objects have limited sorting - only by index fields
        // For now, we sort client-side for non-indexed fields
        const { fieldName, sortDirection } = event.detail;
        this.sortedBy = fieldName;
        this.sortedDirection = sortDirection;
        this.sortData(fieldName, sortDirection);
    }

    sortData(fieldName, sortDirection) {
        const sorted = [...this.records];
        sorted.sort((a, b) => {
            let valA = a[fieldName];
            let valB = b[fieldName];

            // Handle null/undefined
            if (valA == null && valB == null) return 0;
            if (valA == null) return sortDirection === 'asc' ? -1 : 1;
            if (valB == null) return sortDirection === 'asc' ? 1 : -1;

            // Handle dates
            if (fieldName.includes('Timestamp') || fieldName.includes('Date') || fieldName.includes('Time')) {
                valA = new Date(valA).getTime();
                valB = new Date(valB).getTime();
            } else if (typeof valA === 'string') {
                valA = valA.toLowerCase();
                valB = String(valB).toLowerCase();
            }

            let result = 0;
            if (valA > valB) result = 1;
            if (valA < valB) result = -1;

            return sortDirection === 'asc' ? result : -result;
        });
        this.records = sorted;
    }

    // ============================================================================
    // EVENT HANDLERS - DETAIL MODAL
    // ============================================================================

    async openDetailModal(record) {
        this.isLoading = true;
        try {
            const detail = await getArchiveDetail({
                correlationId: record.CorrelationId__c,
                sequence: record.Sequence__c,
                createdTimestamp: record.CreatedTimestamp__c
            });
            this.selectedRecord = detail;
            this.showDetailModal = true;
        } catch (err) {
            this.showToast('Error', 'Failed to load record details', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleCloseModal() {
        this.showDetailModal = false;
        this.selectedRecord = null;
    }

    // ============================================================================
    // EVENT HANDLERS - EXPORT
    // ============================================================================

    async handleExportJson() {
        this.isExporting = true;
        try {
            const params = this.buildQueryParams();
            const jsonData = await exportArchiveRecords({ params });
            this.downloadFile(jsonData, 'uow-audit-archives.json', 'application/json');
            this.showToast('Success', 'Export completed', 'success');
        } catch (err) {
            this.showToast('Error', 'Export failed', 'error');
        } finally {
            this.isExporting = false;
        }
    }

    handleExportCsv() {
        if (!this.hasRecords) {
            this.showToast('Warning', 'No records to export', 'warning');
            return;
        }

        const csvContent = this.convertToCSV(this.records);
        this.downloadFile(csvContent, 'uow-audit-archives.csv', 'text/csv');
        this.showToast('Success', 'Export completed', 'success');
    }

    // ============================================================================
    // UTILITY METHODS
    // ============================================================================

    formatDateForInput(date) {
        return date.toISOString().split('T')[0];
    }

    extractErrorMessage(err) {
        if (err.body?.message) return err.body.message;
        if (err.message) return err.message;
        return 'An unknown error occurred';
    }

    copyToClipboard(text) {
        if (!text) return;

        if (navigator.clipboard?.writeText) {
            navigator.clipboard.writeText(text)
                .then(() => this.showToast('Copied', text, 'success'))
                .catch(() => this.showToast('Error', 'Failed to copy', 'error'));
        }
    }

    downloadFile(content, filename, mimeType) {
        const blob = new Blob([content], { type: mimeType });
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = filename;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        URL.revokeObjectURL(url);
    }

    convertToCSV(data) {
        if (!data || data.length === 0) return '';

        const headers = Object.keys(data[0]).filter(key => !key.endsWith('Class'));
        const csvRows = [headers.join(',')];

        for (const row of data) {
            const values = headers.map(header => {
                const val = row[header];
                if (val === null || val === undefined) return '';
                const escaped = String(val).replace(/"/g, '""');
                return `"${escaped}"`;
            });
            csvRows.push(values.join(','));
        }

        return csvRows.join('\n');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}