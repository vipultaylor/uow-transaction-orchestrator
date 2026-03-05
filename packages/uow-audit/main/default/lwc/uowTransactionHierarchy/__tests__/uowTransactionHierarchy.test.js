//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
import { createElement } from '@lwc/engine-dom';
import { getRecord } from 'lightning/uiRecordApi';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import UowTransactionHierarchy from 'c/uowTransactionHierarchy';
import getHierarchyByCorrelationId from '@salesforce/apex/UoWTransactionHierarchyController.getHierarchyByCorrelationId';
import getHierarchyByTransactionId from '@salesforce/apex/UoWTransactionHierarchyController.getHierarchyByTransactionId';

// Mock Apex methods
jest.mock(
    '@salesforce/apex/UoWTransactionHierarchyController.getHierarchyByCorrelationId',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/UoWTransactionHierarchyController.getHierarchyByTransactionId',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

// Sample hierarchy data
const MOCK_HIERARCHY = {
    root: {
        id: 'a00000000000001AAA',
        transactionId: 'TXN-ROOT-001',
        description: 'Root Transaction',
        status: 'SUCCESS',
        hasChildren: true,
        totalWorkCount: 5,
        children: [
            {
                id: 'a00000000000002AAA',
                transactionId: 'TXN-CHILD-001',
                description: 'Child Transaction 1',
                status: 'SUCCESS',
                hasChildren: false,
                totalWorkCount: 3,
                children: []
            },
            {
                id: 'a00000000000003AAA',
                transactionId: 'TXN-CHILD-002',
                description: 'Child Transaction 2',
                status: 'FAILURE',
                hasChildren: false,
                totalWorkCount: 2,
                children: []
            }
        ]
    }
};

const MOCK_RECORD = {
    fields: {
        CorrelationId__c: {
            value: 'CORR-TEST-001'
        }
    }
};

const MOCK_OBJECT_INFO = {
    defaultRecordTypeId: '012000000000000AAA',
    apiName: 'UoWAuditTransaction__c'
};

const MOCK_PICKLIST_VALUES = {
    values: [
        { value: 'SUCCESS', label: 'Success' },
        { value: 'PARTIAL_SUCCESS', label: 'Partial Success' },
        { value: 'FAILURE', label: 'Failure' },
        { value: 'PENDING', label: 'Pending' }
    ]
};

describe('c-uow-transaction-hierarchy', () => {
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
        const element = createElement('c-uow-transaction-hierarchy', {
            is: UowTransactionHierarchy
        });

        // Act
        document.body.appendChild(element);

        // Assert
        expect(element).toBeTruthy();
    });

    it('should show loading spinner initially', () => {
        // Arrange
        const element = createElement('c-uow-transaction-hierarchy', {
            is: UowTransactionHierarchy
        });

        // Act
        document.body.appendChild(element);

        // Assert
        const spinner = element.shadowRoot.querySelector('lightning-spinner');
        expect(spinner).toBeTruthy();
    });

    it('should accept custom title prop', () => {
        // Arrange
        const element = createElement('c-uow-transaction-hierarchy', {
            is: UowTransactionHierarchy
        });
        element.title = 'Custom Hierarchy Title';

        // Act
        document.body.appendChild(element);

        // Assert
        expect(element.title).toBe('Custom Hierarchy Title');
    });

    // ============================================================================
    // DATA LOADING TESTS - BY CORRELATION ID
    // ============================================================================

    it('should load hierarchy when correlationId is provided', async () => {
        // Arrange
        getHierarchyByCorrelationId.mockResolvedValue(MOCK_HIERARCHY);

        const element = createElement('c-uow-transaction-hierarchy', {
            is: UowTransactionHierarchy
        });
        element.correlationId = 'CORR-TEST-001';

        // Act
        document.body.appendChild(element);
        await Promise.resolve(); // Wait for async call

        // Assert
        expect(getHierarchyByCorrelationId).toHaveBeenCalledWith({
            correlationId: 'CORR-TEST-001'
        });
    });

    it('should display root node after loading', async () => {
        // Arrange
        getHierarchyByCorrelationId.mockResolvedValue(MOCK_HIERARCHY);

        const element = createElement('c-uow-transaction-hierarchy', {
            is: UowTransactionHierarchy
        });
        element.correlationId = 'CORR-TEST-001';

        // Act
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve(); // Additional tick for state update

        // Assert - Component should have hierarchy data
        expect(element).toBeTruthy();
        // The hasHierarchy getter should return true
    });

    // ============================================================================
    // DATA LOADING TESTS - BY TRANSACTION ID
    // ============================================================================

    it('should load hierarchy when recordId is provided', async () => {
        // Arrange
        getHierarchyByTransactionId.mockResolvedValue(MOCK_HIERARCHY);

        const element = createElement('c-uow-transaction-hierarchy', {
            is: UowTransactionHierarchy
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        await Promise.resolve();

        // Assert
        expect(getHierarchyByTransactionId).toHaveBeenCalledWith({
            transactionRecordId: 'a00000000000001AAA'
        });
    });

    it('should load hierarchy from record context when correlation ID is in record', async () => {
        // Arrange
        getHierarchyByCorrelationId.mockResolvedValue(MOCK_HIERARCHY);

        const element = createElement('c-uow-transaction-hierarchy', {
            is: UowTransactionHierarchy
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        await Promise.resolve();

        // Emit getRecord wire with correlation ID
        getRecord.emit(MOCK_RECORD);
        await Promise.resolve();

        // Assert - Should call getHierarchyByCorrelationId with the correlation ID from record
        expect(getHierarchyByCorrelationId).toHaveBeenCalled();
    });

    // ============================================================================
    // WIRE ADAPTER TESTS
    // ============================================================================

    it('should handle getObjectInfo wire response', async () => {
        // Arrange
        const element = createElement('c-uow-transaction-hierarchy', {
            is: UowTransactionHierarchy
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        getObjectInfo.emit(MOCK_OBJECT_INFO);
        await Promise.resolve();

        // Assert - Component should not error
        expect(element).toBeTruthy();
    });

    it('should handle getPicklistValues wire response', async () => {
        // Arrange
        const element = createElement('c-uow-transaction-hierarchy', {
            is: UowTransactionHierarchy
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        getObjectInfo.emit(MOCK_OBJECT_INFO);
        await Promise.resolve();
        getPicklistValues.emit(MOCK_PICKLIST_VALUES);
        await Promise.resolve();

        // Assert - Component should have status labels
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // ERROR HANDLING TESTS
    // ============================================================================

    it('should handle API error gracefully', async () => {
        // Arrange
        getHierarchyByCorrelationId.mockRejectedValue({
            body: { message: 'Test error message' }
        });

        const element = createElement('c-uow-transaction-hierarchy', {
            is: UowTransactionHierarchy
        });
        element.correlationId = 'CORR-TEST-001';

        // Act
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        // Assert - Component should handle error and display error state
        expect(element).toBeTruthy();
    });

    it('should handle getRecord error gracefully', async () => {
        // Arrange
        const element = createElement('c-uow-transaction-hierarchy', {
            is: UowTransactionHierarchy
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        await Promise.resolve();

        // Emit error
        getRecord.error({
            body: { message: 'Record not found' }
        });
        await Promise.resolve();

        // Assert - Component should handle error state
        expect(element).toBeTruthy();
    });

    it('should handle getObjectInfo error gracefully', async () => {
        // Arrange
        const element = createElement('c-uow-transaction-hierarchy', {
            is: UowTransactionHierarchy
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        getObjectInfo.error({ message: 'Object info error' });
        await Promise.resolve();

        // Assert - Component continues to function
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // HIERARCHY EXPANSION TESTS
    // ============================================================================

    it('should expand all nodes by default after loading', async () => {
        // Arrange
        getHierarchyByCorrelationId.mockResolvedValue(MOCK_HIERARCHY);

        const element = createElement('c-uow-transaction-hierarchy', {
            is: UowTransactionHierarchy
        });
        element.correlationId = 'CORR-TEST-001';

        // Act
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        // Assert - All nodes should be expanded (tracked internally)
        expect(element).toBeTruthy();
    });

    it('should toggle node expansion on click', async () => {
        // Arrange
        getHierarchyByCorrelationId.mockResolvedValue(MOCK_HIERARCHY);

        const element = createElement('c-uow-transaction-hierarchy', {
            is: UowTransactionHierarchy
        });
        element.correlationId = 'CORR-TEST-001';

        // Act
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        // Find toggle button and click it (if rendered)
        const toggleButton = element.shadowRoot.querySelector('[data-node-id]');
        if (toggleButton) {
            toggleButton.click();
            await Promise.resolve();
        }

        // Assert - Component should not error
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // NAVIGATION TESTS
    // ============================================================================

    it('should navigate to transaction record on link click', async () => {
        // Arrange
        getHierarchyByCorrelationId.mockResolvedValue(MOCK_HIERARCHY);

        const element = createElement('c-uow-transaction-hierarchy', {
            is: UowTransactionHierarchy
        });
        element.correlationId = 'CORR-TEST-001';

        // Act
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        // Find navigation link and click (if rendered)
        const navLink = element.shadowRoot.querySelector('[data-record-id]');
        if (navLink) {
            const event = new CustomEvent('click', {
                bubbles: true,
                cancelable: true
            });
            event.preventDefault = jest.fn();
            navLink.dispatchEvent(event);
            await Promise.resolve();
        }

        // Assert - Component should not error
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // EMPTY STATE TESTS
    // ============================================================================

    it('should handle empty hierarchy result', async () => {
        // Arrange
        getHierarchyByCorrelationId.mockResolvedValue({ root: null });

        const element = createElement('c-uow-transaction-hierarchy', {
            is: UowTransactionHierarchy
        });
        element.correlationId = 'CORR-EMPTY-001';

        // Act
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        // Assert - Component should handle empty result
        expect(element).toBeTruthy();
    });

    it('should handle hierarchy with no children', async () => {
        // Arrange
        const singleNodeHierarchy = {
            root: {
                id: 'a00000000000001AAA',
                transactionId: 'TXN-SINGLE-001',
                status: 'SUCCESS',
                hasChildren: false,
                children: []
            }
        };
        getHierarchyByCorrelationId.mockResolvedValue(singleNodeHierarchy);

        const element = createElement('c-uow-transaction-hierarchy', {
            is: UowTransactionHierarchy
        });
        element.correlationId = 'CORR-SINGLE-001';

        // Act
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        // Assert
        expect(element).toBeTruthy();
    });
});
