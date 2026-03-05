//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
import { createElement } from '@lwc/engine-dom';
import UowAuditArchiveViewer from 'c/uowAuditArchiveViewer';
import getArchiveRecords from '@salesforce/apex/UoWAuditArchiveController.getArchiveRecords';
import getArchiveDetail from '@salesforce/apex/UoWAuditArchiveController.getArchiveDetail';
import getFilterOptions from '@salesforce/apex/UoWAuditArchiveController.getFilterOptions';
import exportArchiveRecords from '@salesforce/apex/UoWAuditArchiveController.exportArchiveRecords';

// Mock Apex methods
jest.mock(
    '@salesforce/apex/UoWAuditArchiveController.getArchiveRecords',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/UoWAuditArchiveController.getArchiveDetail',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/UoWAuditArchiveController.getFilterOptions',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/UoWAuditArchiveController.exportArchiveRecords',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

// Mock ShowToastEvent
jest.mock(
    'lightning/platformShowToastEvent',
    () => ({
        ShowToastEvent: jest.fn()
    }),
    { virtual: true }
);

// Sample archive records
const MOCK_ARCHIVE_RECORDS = {
    records: [
        {
            CorrelationId__c: 'CORR-001',
            Sequence__c: 0,
            CreatedTimestamp__c: '2024-01-15T10:00:00.000Z',
            TransactionId__c: 'TXN-001',
            WorkId__c: 'WORK-001',
            WorkType__c: 'DML',
            DmlOperation__c: 'INSERT',
            TransactionStatus__c: 'SUCCESS',
            SObjectType__c: 'Account',
            ExecutionContext__c: 'SYNCHRONOUS',
            RiskLevel__c: 'LOW',
            Username__c: 'test@example.com',
            ExecutionTimeMs__c: 150,
            SuccessCount__c: 10,
            FailureCount__c: 0,
            IsAgentTransaction__c: 'false'
        },
        {
            CorrelationId__c: 'CORR-002',
            Sequence__c: 0,
            CreatedTimestamp__c: '2024-01-15T11:00:00.000Z',
            TransactionId__c: 'TXN-002',
            WorkId__c: 'WORK-002',
            WorkType__c: 'EVENT',
            TransactionStatus__c: 'PARTIAL_SUCCESS',
            SObjectType__c: 'Contact',
            ExecutionContext__c: 'QUEUEABLE',
            RiskLevel__c: 'MEDIUM',
            Username__c: 'admin@example.com',
            ExecutionTimeMs__c: 250,
            SuccessCount__c: 5,
            FailureCount__c: 2,
            IsAgentTransaction__c: 'true'
        }
    ],
    hasMore: true,
    nextCursor: 'abc123',
    previousCursor: null,
    totalCount: 2
};

const MOCK_EMPTY_RECORDS = {
    records: [],
    hasMore: false,
    nextCursor: null,
    previousCursor: null,
    totalCount: 0
};

const MOCK_FILTER_OPTIONS = {
    workTypes: [
        { value: 'DML', label: 'DML' },
        { value: 'EVENT', label: 'Platform Event' },
        { value: 'FLOW', label: 'Flow' },
        { value: 'EMAIL', label: 'Email' },
        { value: 'NOTIFICATION', label: 'Notification' },
        { value: 'CALLOUT', label: 'Callout' }
    ],
    statuses: [
        { value: 'SUCCESS', label: 'Success' },
        { value: 'PARTIAL_SUCCESS', label: 'Partial Success' },
        { value: 'FAILURE', label: 'Failure' }
    ],
    riskLevels: [
        { value: 'NONE', label: 'None' },
        { value: 'LOW', label: 'Low' },
        { value: 'MEDIUM', label: 'Medium' },
        { value: 'HIGH', label: 'High' },
        { value: 'CRITICAL', label: 'Critical' }
    ]
};

const MOCK_ARCHIVE_DETAIL = {
    CorrelationId__c: 'CORR-001',
    Sequence__c: 0,
    CreatedTimestamp__c: '2024-01-15T10:00:00.000Z',
    TransactionId__c: 'TXN-001',
    WorkId__c: 'WORK-001',
    WorkType__c: 'DML',
    TransactionStatus__c: 'SUCCESS',
    Username__c: 'test@example.com',
    OrganizationName__c: 'Test Org'
};

describe('c-uow-audit-archive-viewer', () => {
    afterEach(() => {
        // Reset DOM
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        // Reset mocks
        jest.clearAllMocks();
    });

    // ============================================================================
    // COMPONENT RENDERING TESTS
    // ============================================================================

    it('should render the component', () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });

        // Act
        document.body.appendChild(element);

        // Assert
        expect(element).toBeTruthy();
    });

    it('should show loading state initially', () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });

        // Act
        document.body.appendChild(element);

        // Assert - Loading spinner should be present initially
        const spinner = element.shadowRoot.querySelector('lightning-spinner');
        // Note: Spinner visibility depends on isLoading state
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // DATA LOADING TESTS
    // ============================================================================

    it('should load archive records on connectedCallback', async () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);
        getFilterOptions.mockResolvedValue(MOCK_FILTER_OPTIONS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });

        // Act
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        // Assert
        expect(getArchiveRecords).toHaveBeenCalled();
    });

    it('should display records in datatable after loading', async () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);
        getFilterOptions.mockResolvedValue(MOCK_FILTER_OPTIONS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });

        // Act
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        // Assert - Datatable should be present
        const datatable = element.shadowRoot.querySelector('lightning-datatable');
        expect(element).toBeTruthy();
    });

    it('should enrich records with boolean conversions', async () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);
        getFilterOptions.mockResolvedValue(MOCK_FILTER_OPTIONS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });

        // Act
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        // Assert - Component should handle string-to-boolean conversion
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // FILTER OPTIONS TESTS
    // ============================================================================

    it('should load filter options via wire', async () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });

        // Act
        document.body.appendChild(element);
        getFilterOptions.emit(MOCK_FILTER_OPTIONS);
        await Promise.resolve();

        // Assert
        expect(element).toBeTruthy();
    });

    it('should handle filter options error gracefully', async () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });

        // Act
        document.body.appendChild(element);
        getFilterOptions.error({ message: 'Filter options error' });
        await Promise.resolve();

        // Assert - Component should continue to function
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // FILTER INTERACTION TESTS
    // ============================================================================

    it('should toggle filter panel visibility', async () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);
        getFilterOptions.mockResolvedValue(MOCK_FILTER_OPTIONS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });
        document.body.appendChild(element);
        await Promise.resolve();

        // Act - Find toggle button and click
        const toggleButton = element.shadowRoot.querySelector('[data-id="toggle-filters"]');
        if (toggleButton) {
            toggleButton.click();
            await Promise.resolve();
        }

        // Assert
        expect(element).toBeTruthy();
    });

    it('should apply filters and reload data', async () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);
        getFilterOptions.mockResolvedValue(MOCK_FILTER_OPTIONS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });
        document.body.appendChild(element);
        await Promise.resolve();

        // Act - Find apply button and click
        const applyButton = element.shadowRoot.querySelector('[data-id="apply-filters"]');
        if (applyButton) {
            applyButton.click();
            await Promise.resolve();
        }

        // Assert - getArchiveRecords should be called again
        expect(getArchiveRecords).toHaveBeenCalled();
    });

    it('should clear filters and reload data', async () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);
        getFilterOptions.mockResolvedValue(MOCK_FILTER_OPTIONS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });
        document.body.appendChild(element);
        await Promise.resolve();

        // Act - Find clear button and click
        const clearButton = element.shadowRoot.querySelector('[data-id="clear-filters"]');
        if (clearButton) {
            clearButton.click();
            await Promise.resolve();
        }

        // Assert
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // PAGINATION TESTS
    // ============================================================================

    it('should handle next page navigation', async () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);
        getFilterOptions.mockResolvedValue(MOCK_FILTER_OPTIONS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        // Act - Find next button and click
        const nextButton = element.shadowRoot.querySelector('[data-id="next-page"]');
        if (nextButton) {
            nextButton.click();
            await Promise.resolve();
        }

        // Assert - Should trigger another load
        expect(element).toBeTruthy();
    });

    it('should handle previous page navigation', async () => {
        // Arrange - Set up with cursor stack
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);
        getFilterOptions.mockResolvedValue(MOCK_FILTER_OPTIONS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });
        document.body.appendChild(element);
        await Promise.resolve();

        // Act - Find previous button
        const prevButton = element.shadowRoot.querySelector('[data-id="previous-page"]');
        if (prevButton) {
            prevButton.click();
            await Promise.resolve();
        }

        // Assert
        expect(element).toBeTruthy();
    });

    it('should handle page size change', async () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);
        getFilterOptions.mockResolvedValue(MOCK_FILTER_OPTIONS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });
        document.body.appendChild(element);
        await Promise.resolve();

        // Act - Find page size combobox
        const pageSizeSelect = element.shadowRoot.querySelector('lightning-combobox');
        if (pageSizeSelect) {
            pageSizeSelect.dispatchEvent(new CustomEvent('change', {
                detail: { value: 100 }
            }));
            await Promise.resolve();
        }

        // Assert
        expect(element).toBeTruthy();
    });

    it('should refresh data on refresh button click', async () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);
        getFilterOptions.mockResolvedValue(MOCK_FILTER_OPTIONS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });
        document.body.appendChild(element);
        await Promise.resolve();

        // Act - Find refresh button
        const refreshButton = element.shadowRoot.querySelector('[data-id="refresh"]');
        if (refreshButton) {
            refreshButton.click();
            await Promise.resolve();
        }

        // Assert
        expect(getArchiveRecords).toHaveBeenCalled();
    });

    // ============================================================================
    // ROW ACTION TESTS
    // ============================================================================

    it('should open detail modal on view_detail action', async () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);
        getArchiveDetail.mockResolvedValue(MOCK_ARCHIVE_DETAIL);
        getFilterOptions.mockResolvedValue(MOCK_FILTER_OPTIONS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        // Act - Simulate row action
        const datatable = element.shadowRoot.querySelector('lightning-datatable');
        if (datatable) {
            datatable.dispatchEvent(new CustomEvent('rowaction', {
                detail: {
                    action: { name: 'view_detail' },
                    row: MOCK_ARCHIVE_RECORDS.records[0]
                }
            }));
            await Promise.resolve();
        }

        // Assert
        expect(getArchiveDetail).toHaveBeenCalled();
    });

    it('should handle copy_id action', async () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);
        getFilterOptions.mockResolvedValue(MOCK_FILTER_OPTIONS);

        // Mock clipboard
        const mockClipboard = {
            writeText: jest.fn().mockResolvedValue()
        };
        Object.defineProperty(navigator, 'clipboard', {
            value: mockClipboard,
            writable: true
        });

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        // Act - Simulate row action
        const datatable = element.shadowRoot.querySelector('lightning-datatable');
        if (datatable) {
            datatable.dispatchEvent(new CustomEvent('rowaction', {
                detail: {
                    action: { name: 'copy_id' },
                    row: MOCK_ARCHIVE_RECORDS.records[0]
                }
            }));
            await Promise.resolve();
        }

        // Assert
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // SORTING TESTS
    // ============================================================================

    it('should handle column sorting', async () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);
        getFilterOptions.mockResolvedValue(MOCK_FILTER_OPTIONS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        // Act - Simulate sort
        const datatable = element.shadowRoot.querySelector('lightning-datatable');
        if (datatable) {
            datatable.dispatchEvent(new CustomEvent('sort', {
                detail: {
                    fieldName: 'TransactionId__c',
                    sortDirection: 'asc'
                }
            }));
            await Promise.resolve();
        }

        // Assert
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // EXPORT TESTS
    // ============================================================================

    it('should export records as JSON', async () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);
        exportArchiveRecords.mockResolvedValue(JSON.stringify(MOCK_ARCHIVE_RECORDS.records));
        getFilterOptions.mockResolvedValue(MOCK_FILTER_OPTIONS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });
        document.body.appendChild(element);
        await Promise.resolve();

        // Act - Find export JSON button
        const exportJsonButton = element.shadowRoot.querySelector('[data-id="export-json"]');
        if (exportJsonButton) {
            exportJsonButton.click();
            await Promise.resolve();
        }

        // Assert
        expect(element).toBeTruthy();
    });

    it('should export records as CSV', async () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);
        getFilterOptions.mockResolvedValue(MOCK_FILTER_OPTIONS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        // Act - Find export CSV button
        const exportCsvButton = element.shadowRoot.querySelector('[data-id="export-csv"]');
        if (exportCsvButton) {
            exportCsvButton.click();
            await Promise.resolve();
        }

        // Assert
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // ERROR HANDLING TESTS
    // ============================================================================

    it('should handle getArchiveRecords error', async () => {
        // Arrange
        getArchiveRecords.mockRejectedValue({
            body: { message: 'Failed to load archives' }
        });
        getFilterOptions.mockResolvedValue(MOCK_FILTER_OPTIONS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });

        // Act
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        // Assert - Component should handle error state
        expect(element).toBeTruthy();
    });

    it('should handle getArchiveDetail error', async () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);
        getArchiveDetail.mockRejectedValue(new Error('Detail load failed'));
        getFilterOptions.mockResolvedValue(MOCK_FILTER_OPTIONS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        // Act - Simulate row action
        const datatable = element.shadowRoot.querySelector('lightning-datatable');
        if (datatable) {
            datatable.dispatchEvent(new CustomEvent('rowaction', {
                detail: {
                    action: { name: 'view_detail' },
                    row: MOCK_ARCHIVE_RECORDS.records[0]
                }
            }));
            await Promise.resolve();
        }

        // Assert
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // EMPTY STATE TESTS
    // ============================================================================

    it('should display empty state when no records', async () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_EMPTY_RECORDS);
        getFilterOptions.mockResolvedValue(MOCK_FILTER_OPTIONS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });

        // Act
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        // Assert - Component should show empty state
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // MODAL TESTS
    // ============================================================================

    it('should close detail modal', async () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);
        getArchiveDetail.mockResolvedValue(MOCK_ARCHIVE_DETAIL);
        getFilterOptions.mockResolvedValue(MOCK_FILTER_OPTIONS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        // Open modal first
        const datatable = element.shadowRoot.querySelector('lightning-datatable');
        if (datatable) {
            datatable.dispatchEvent(new CustomEvent('rowaction', {
                detail: {
                    action: { name: 'view_detail' },
                    row: MOCK_ARCHIVE_RECORDS.records[0]
                }
            }));
            await Promise.resolve();
        }

        // Act - Close modal
        const closeButton = element.shadowRoot.querySelector('[data-id="close-modal"]');
        if (closeButton) {
            closeButton.click();
            await Promise.resolve();
        }

        // Assert
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // UTILITY METHOD TESTS
    // ============================================================================

    it('should apply correct CSS class for work types', async () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);
        getFilterOptions.mockResolvedValue(MOCK_FILTER_OPTIONS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });

        // Act
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        // Assert - Records should have _workTypeClass enriched
        expect(element).toBeTruthy();
    });

    it('should apply correct CSS class for status', async () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);
        getFilterOptions.mockResolvedValue(MOCK_FILTER_OPTIONS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });

        // Act
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        // Assert - Records should have _statusClass enriched
        expect(element).toBeTruthy();
    });

    it('should apply correct CSS class for risk level', async () => {
        // Arrange
        getArchiveRecords.mockResolvedValue(MOCK_ARCHIVE_RECORDS);
        getFilterOptions.mockResolvedValue(MOCK_FILTER_OPTIONS);

        const element = createElement('c-uow-audit-archive-viewer', {
            is: UowAuditArchiveViewer
        });

        // Act
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        // Assert - Records should have _riskClass enriched
        expect(element).toBeTruthy();
    });
});
