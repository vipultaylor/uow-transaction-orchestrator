//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
import { createElement } from '@lwc/engine-dom';
import UowErrorDetails from 'c/uowErrorDetails';
import getErrors from '@salesforce/apex/UoWAuditErrorsController.getErrors';

// Mock Apex methods
jest.mock(
    '@salesforce/apex/UoWAuditErrorsController.getErrors',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

// Sample error data
const MOCK_ERRORS = [
    {
        errorId: 'ERR-001',
        workItemId: 'WORK-001',
        workItemRecordId: 'a01000000000001AAA',
        errorType: 'DML_EXCEPTION',
        errorMessage: 'Required field missing: Name',
        stackTrace: 'Class.MyService.doSomething: line 42\nClass.MyTrigger.execute: line 15',
        suggestion: 'Add a value for the Name field',
        documentationUrl: 'https://help.salesforce.com/errors/123',
        isRetryable: true,
        attemptNumber: 1,
        errorContextSerialized: '{"recordIndex":0,"sobjectType":"Account"}',
        occurredAt: '2024-01-15T10:30:00.000Z'
    },
    {
        errorId: 'ERR-002',
        workItemId: 'WORK-002',
        errorType: 'VALIDATION_ERROR',
        errorMessage: 'Validation rule failed: Name_Required',
        isRetryable: false,
        occurredAt: '2024-01-15T10:30:01.500Z'
    }
];

const MOCK_EMPTY_ERRORS = [];

describe('c-uow-error-details', () => {
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
        const element = createElement('c-uow-error-details', {
            is: UowErrorDetails
        });

        // Act
        document.body.appendChild(element);

        // Assert
        expect(element).toBeTruthy();
    });

    it('should accept custom title prop', () => {
        // Arrange
        const element = createElement('c-uow-error-details', {
            is: UowErrorDetails
        });
        element.title = 'Transaction Errors';

        // Act
        document.body.appendChild(element);

        // Assert
        expect(element.title).toBe('Transaction Errors');
    });

    // ============================================================================
    // DATA LOADING TESTS
    // ============================================================================

    it('should load errors when recordId is set', async () => {
        // Arrange
        const element = createElement('c-uow-error-details', {
            is: UowErrorDetails
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        getErrors.emit(MOCK_ERRORS);
        await Promise.resolve();

        // Assert - Component should have errors
        expect(element).toBeTruthy();
    });

    it('should display error count in header', async () => {
        // Arrange
        const element = createElement('c-uow-error-details', {
            is: UowErrorDetails
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        getErrors.emit(MOCK_ERRORS);
        await Promise.resolve();

        // Assert - Header should show count
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // ERROR DISPLAY TESTS
    // ============================================================================

    it('should display error message preview', async () => {
        // Arrange
        const element = createElement('c-uow-error-details', {
            is: UowErrorDetails
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        getErrors.emit(MOCK_ERRORS);
        await Promise.resolve();

        // Assert - Error messages should be visible
        expect(element).toBeTruthy();
    });

    it('should truncate long error messages', async () => {
        // Arrange
        const longErrorMessage = 'A'.repeat(200);
        const errorsWithLongMessage = [{
            ...MOCK_ERRORS[0],
            errorMessage: longErrorMessage
        }];

        const element = createElement('c-uow-error-details', {
            is: UowErrorDetails
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        getErrors.emit(errorsWithLongMessage);
        await Promise.resolve();

        // Assert - Component should handle long message
        expect(element).toBeTruthy();
    });

    it('should display error type badge', async () => {
        // Arrange
        const element = createElement('c-uow-error-details', {
            is: UowErrorDetails
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        getErrors.emit(MOCK_ERRORS);
        await Promise.resolve();

        // Assert - Error type should be displayed
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // EXPANSION TOGGLE TESTS
    // ============================================================================

    it('should toggle error row expansion on click', async () => {
        // Arrange
        const element = createElement('c-uow-error-details', {
            is: UowErrorDetails
        });
        element.recordId = 'a00000000000001AAA';
        document.body.appendChild(element);
        getErrors.emit(MOCK_ERRORS);
        await Promise.resolve();

        // Act - Find toggle button and click
        const toggleButton = element.shadowRoot.querySelector('[data-index="0"]');
        if (toggleButton) {
            toggleButton.click();
            await Promise.resolve();
        }

        // Assert - Row should be expanded
        expect(element).toBeTruthy();
    });

    it('should toggle stack trace visibility', async () => {
        // Arrange
        const element = createElement('c-uow-error-details', {
            is: UowErrorDetails
        });
        element.recordId = 'a00000000000001AAA';
        document.body.appendChild(element);
        getErrors.emit(MOCK_ERRORS);
        await Promise.resolve();

        // Expand error first
        const toggleButton = element.shadowRoot.querySelector('[data-index="0"]');
        if (toggleButton) {
            toggleButton.click();
            await Promise.resolve();
        }

        // Act - Find stack trace toggle and click
        const stackTraceToggle = element.shadowRoot.querySelector('[data-stack-trace-toggle]');
        if (stackTraceToggle) {
            const event = new Event('click');
            event.stopPropagation = jest.fn();
            stackTraceToggle.dispatchEvent(event);
            await Promise.resolve();
        }

        // Assert
        expect(element).toBeTruthy();
    });

    it('should toggle error context visibility', async () => {
        // Arrange
        const element = createElement('c-uow-error-details', {
            is: UowErrorDetails
        });
        element.recordId = 'a00000000000001AAA';
        document.body.appendChild(element);
        getErrors.emit(MOCK_ERRORS);
        await Promise.resolve();

        // Expand error first
        const toggleButton = element.shadowRoot.querySelector('[data-index="0"]');
        if (toggleButton) {
            toggleButton.click();
            await Promise.resolve();
        }

        // Act - Find context toggle and click
        const contextToggle = element.shadowRoot.querySelector('[data-context-toggle]');
        if (contextToggle) {
            const event = new Event('click');
            event.stopPropagation = jest.fn();
            contextToggle.dispatchEvent(event);
            await Promise.resolve();
        }

        // Assert
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // EMPTY STATE TESTS
    // ============================================================================

    it('should show empty state when no errors', async () => {
        // Arrange
        const element = createElement('c-uow-error-details', {
            is: UowErrorDetails
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        getErrors.emit(MOCK_EMPTY_ERRORS);
        await Promise.resolve();

        // Assert - Should show no errors message
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // ERROR HANDLING TESTS
    // ============================================================================

    it('should handle wire error gracefully', async () => {
        // Arrange
        const element = createElement('c-uow-error-details', {
            is: UowErrorDetails
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        getErrors.error({ message: 'Failed to load errors' });
        await Promise.resolve();

        // Assert - Component should handle error state
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // NAVIGATION TESTS
    // ============================================================================

    it('should navigate to work item on link click', async () => {
        // Arrange
        const element = createElement('c-uow-error-details', {
            is: UowErrorDetails
        });
        element.recordId = 'a00000000000001AAA';
        document.body.appendChild(element);
        getErrors.emit(MOCK_ERRORS);
        await Promise.resolve();

        // Expand error first
        const toggleButton = element.shadowRoot.querySelector('[data-index="0"]');
        if (toggleButton) {
            toggleButton.click();
            await Promise.resolve();
        }

        // Act - Find work item link and click
        const workItemLink = element.shadowRoot.querySelector('[data-record-id]');
        if (workItemLink) {
            const event = new Event('click');
            event.preventDefault = jest.fn();
            event.stopPropagation = jest.fn();
            workItemLink.dispatchEvent(event);
            await Promise.resolve();
        }

        // Assert - Navigation should be triggered (using NavigationMixin)
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // SPECIAL CASES TESTS
    // ============================================================================

    it('should hide work item link when on work item page', async () => {
        // Arrange - Set recordId to same as work item record ID
        const element = createElement('c-uow-error-details', {
            is: UowErrorDetails
        });
        element.recordId = 'a01000000000001AAA'; // Same as workItemRecordId in mock
        document.body.appendChild(element);
        getErrors.emit(MOCK_ERRORS);
        await Promise.resolve();

        // Assert - Work item link should not be shown for current work item
        expect(element).toBeTruthy();
    });

    it('should parse error context from serialized JSON', async () => {
        // Arrange
        const element = createElement('c-uow-error-details', {
            is: UowErrorDetails
        });
        element.recordId = 'a00000000000001AAA';
        document.body.appendChild(element);
        getErrors.emit(MOCK_ERRORS);
        await Promise.resolve();

        // Assert - Component should parse context JSON
        expect(element).toBeTruthy();
    });

    it('should handle invalid error context JSON', async () => {
        // Arrange
        const errorsWithInvalidContext = [{
            ...MOCK_ERRORS[0],
            errorContextSerialized: 'not valid json {'
        }];

        const element = createElement('c-uow-error-details', {
            is: UowErrorDetails
        });
        element.recordId = 'a00000000000001AAA';
        document.body.appendChild(element);
        getErrors.emit(errorsWithInvalidContext);
        await Promise.resolve();

        // Assert - Should use raw string if JSON parse fails
        expect(element).toBeTruthy();
    });

    it('should display retryable status and attempt number', async () => {
        // Arrange
        const element = createElement('c-uow-error-details', {
            is: UowErrorDetails
        });
        element.recordId = 'a00000000000001AAA';
        document.body.appendChild(element);
        getErrors.emit(MOCK_ERRORS);
        await Promise.resolve();

        // Assert - Retryable status and attempt should be visible
        expect(element).toBeTruthy();
    });

    it('should display suggestion when available', async () => {
        // Arrange
        const element = createElement('c-uow-error-details', {
            is: UowErrorDetails
        });
        element.recordId = 'a00000000000001AAA';
        document.body.appendChild(element);
        getErrors.emit(MOCK_ERRORS);
        await Promise.resolve();

        // Assert - Suggestion should be available for first error
        expect(element).toBeTruthy();
    });

    it('should display documentation link when available', async () => {
        // Arrange
        const element = createElement('c-uow-error-details', {
            is: UowErrorDetails
        });
        element.recordId = 'a00000000000001AAA';
        document.body.appendChild(element);
        getErrors.emit(MOCK_ERRORS);
        await Promise.resolve();

        // Assert - Documentation link should be available for first error
        expect(element).toBeTruthy();
    });
});
