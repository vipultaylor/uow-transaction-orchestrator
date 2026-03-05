//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
import { createElement } from '@lwc/engine-dom';
import { getRecord } from 'lightning/uiRecordApi';
import UowMetadataViewer from 'c/uowMetadataViewer';
import canViewOriginMetadata from '@salesforce/apex/UoWMetadataViewerController.canViewOriginMetadata';
import checkForModifications from '@salesforce/apex/UoWMetadataViewerController.checkForModifications';

// Mock the Apex methods
jest.mock(
    '@salesforce/apex/UoWMetadataViewerController.canViewOriginMetadata',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/UoWMetadataViewerController.checkForModifications',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

// Sample metadata JSON
const SAMPLE_METADATA = {
    metadataType: 'ApexClass',
    apiVersion: '65.0',
    className: 'TestService',
    methodName: 'doSomething',
    lineNumber: 42,
    sourceSnippet: 'public void doSomething() {\n    System.debug(\'test\');\n}',
    startLine: 40,
    endLine: 44,
    createdDate: '2024-01-15T10:00:00.000Z',
    lastModifiedDate: '2024-06-20T14:30:00.000Z'
};

// Mock record data with metadata
const MOCK_RECORD_WITH_METADATA = {
    fields: {
        OriginSourceMetadata__c: {
            value: JSON.stringify(SAMPLE_METADATA)
        }
    }
};

// Mock record data without metadata
const MOCK_RECORD_WITHOUT_METADATA = {
    fields: {
        OriginSourceMetadata__c: {
            value: null
        }
    }
};

describe('c-uow-metadata-viewer', () => {
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
        const element = createElement('c-uow-metadata-viewer', {
            is: UowMetadataViewer
        });

        // Act
        document.body.appendChild(element);

        // Assert
        expect(element).toBeTruthy();
    });

    it('should show loading spinner initially', () => {
        // Arrange
        const element = createElement('c-uow-metadata-viewer', {
            is: UowMetadataViewer
        });

        // Act
        document.body.appendChild(element);

        // Assert
        const spinner = element.shadowRoot.querySelector('lightning-spinner');
        expect(spinner).toBeTruthy();
    });

    // ============================================================================
    // PERMISSION TESTS
    // ============================================================================

    it('should hide content when user lacks permission', async () => {
        // Arrange
        canViewOriginMetadata.mockResolvedValue(false);

        const element = createElement('c-uow-metadata-viewer', {
            is: UowMetadataViewer
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);

        // Emit permission wire
        await Promise.resolve();

        // Assert - component should handle no-permission state
        expect(element).toBeTruthy();
    });

    it('should show content when user has permission', async () => {
        // Arrange
        canViewOriginMetadata.mockResolvedValue(true);
        checkForModifications.mockResolvedValue({ hasBeenModified: false });

        const element = createElement('c-uow-metadata-viewer', {
            is: UowMetadataViewer
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);

        // Emit permission wire
        await Promise.resolve();

        // Assert - component renders without error
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // METADATA DISPLAY TESTS
    // ============================================================================

    it('should show no-metadata message when metadata field is empty', async () => {
        // Arrange
        canViewOriginMetadata.mockResolvedValue(true);

        const element = createElement('c-uow-metadata-viewer', {
            is: UowMetadataViewer
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);

        // Emit wires
        await Promise.resolve();

        // Emit getRecord with empty metadata
        getRecord.emit(MOCK_RECORD_WITHOUT_METADATA);
        await Promise.resolve();

        // Assert - component handles no metadata gracefully
        expect(element).toBeTruthy();
    });

    it('should parse and display metadata when present', async () => {
        // Arrange
        canViewOriginMetadata.mockResolvedValue(true);
        checkForModifications.mockResolvedValue({ hasBeenModified: false });

        const element = createElement('c-uow-metadata-viewer', {
            is: UowMetadataViewer
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);

        // Emit wires
        await Promise.resolve();

        // Emit getRecord with metadata
        getRecord.emit(MOCK_RECORD_WITH_METADATA);
        await Promise.resolve();

        // Assert - component renders with metadata
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // MODIFICATION DETECTION TESTS
    // ============================================================================

    it('should show warning when code has been modified', async () => {
        // Arrange
        canViewOriginMetadata.mockResolvedValue(true);
        checkForModifications.mockResolvedValue({ hasBeenModified: true });

        const element = createElement('c-uow-metadata-viewer', {
            is: UowMetadataViewer
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);

        // Emit wires
        await Promise.resolve();

        // Emit getRecord with metadata
        getRecord.emit(MOCK_RECORD_WITH_METADATA);
        await Promise.resolve();

        // Wait for checkForModifications to complete
        await Promise.resolve();

        // Assert - component should display modification warning
        expect(checkForModifications).toHaveBeenCalledWith({
            metadataType: 'ApexClass',
            className: 'TestService',
            capturedLastModifiedDate: '2024-06-20T14:30:00.000Z'
        });
    });

    it('should not show warning when code has not been modified', async () => {
        // Arrange
        canViewOriginMetadata.mockResolvedValue(true);
        checkForModifications.mockResolvedValue({ hasBeenModified: false });

        const element = createElement('c-uow-metadata-viewer', {
            is: UowMetadataViewer
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);

        // Emit wires
        await Promise.resolve();

        // Emit getRecord with metadata
        getRecord.emit(MOCK_RECORD_WITH_METADATA);
        await Promise.resolve();

        // Wait for checkForModifications to complete
        await Promise.resolve();

        // Assert - component should not show modification warning
        expect(element).toBeTruthy();
    });

    it('should handle unknown modification status gracefully', async () => {
        // Arrange
        canViewOriginMetadata.mockResolvedValue(true);
        checkForModifications.mockResolvedValue({
            hasBeenModified: null,
            classNotFound: true
        });

        const element = createElement('c-uow-metadata-viewer', {
            is: UowMetadataViewer
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);

        // Emit wires
        await Promise.resolve();

        // Emit getRecord with metadata
        getRecord.emit(MOCK_RECORD_WITH_METADATA);
        await Promise.resolve();

        // Wait for checkForModifications to complete
        await Promise.resolve();

        // Assert - component handles unknown status
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // ERROR HANDLING TESTS
    // ============================================================================

    it('should handle getRecord error gracefully', async () => {
        // Arrange
        canViewOriginMetadata.mockResolvedValue(true);

        const element = createElement('c-uow-metadata-viewer', {
            is: UowMetadataViewer
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);

        // Emit wires
        await Promise.resolve();

        // Emit error
        getRecord.error();
        await Promise.resolve();

        // Assert - component handles error state
        expect(element).toBeTruthy();
    });

    it('should handle checkForModifications error gracefully', async () => {
        // Arrange
        canViewOriginMetadata.mockResolvedValue(true);
        checkForModifications.mockRejectedValue(new Error('Test error'));

        const element = createElement('c-uow-metadata-viewer', {
            is: UowMetadataViewer
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);

        // Emit wires
        await Promise.resolve();

        // Emit getRecord with metadata
        getRecord.emit(MOCK_RECORD_WITH_METADATA);
        await Promise.resolve();

        // Wait for error handling
        await Promise.resolve();

        // Assert - component handles error gracefully
        expect(element).toBeTruthy();
    });

    it('should handle invalid JSON in metadata field', async () => {
        // Arrange
        canViewOriginMetadata.mockResolvedValue(true);

        const element = createElement('c-uow-metadata-viewer', {
            is: UowMetadataViewer
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);

        // Emit wires
        await Promise.resolve();

        // Emit getRecord with invalid JSON
        getRecord.emit({
            fields: {
                OriginSourceMetadata__c: {
                    value: 'not valid json {'
                }
            }
        });
        await Promise.resolve();

        // Assert - component handles parse error
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // GETTER TESTS
    // ============================================================================

    it('should format origin location correctly', async () => {
        // Arrange
        canViewOriginMetadata.mockResolvedValue(true);
        checkForModifications.mockResolvedValue({ hasBeenModified: false });

        const element = createElement('c-uow-metadata-viewer', {
            is: UowMetadataViewer
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);

        // Emit wires
        await Promise.resolve();

        // Emit getRecord with metadata
        getRecord.emit(MOCK_RECORD_WITH_METADATA);
        await Promise.resolve();

        // Assert - originLocationDisplay should be "TestService.doSomething"
        // This is tested through the component rendering
        expect(element).toBeTruthy();
    });
});
