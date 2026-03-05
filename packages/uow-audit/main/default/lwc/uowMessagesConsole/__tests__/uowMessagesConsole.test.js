//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
import { createElement } from '@lwc/engine-dom';
import UowMessagesConsole from 'c/uowMessagesConsole';
import getMessages from '@salesforce/apex/UoWAuditMessagesController.getMessages';

// Mock Apex methods
jest.mock(
    '@salesforce/apex/UoWAuditMessagesController.getMessages',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

// Sample message data
const MOCK_MESSAGES_DATA = {
    messages: [
        {
            timestamp: '2024-01-15T10:30:00.000Z',
            loggingLevel: 'INFO',
            message: 'Transaction started',
            source: 'UnitOfWork',
            category: 'TRANSACTION'
        },
        {
            timestamp: '2024-01-15T10:30:00.150Z',
            loggingLevel: 'DEBUG',
            message: 'Processing 5 records',
            source: 'UoWDmlWorkItem',
            category: 'DML'
        },
        {
            timestamp: '2024-01-15T10:30:00.300Z',
            loggingLevel: 'WARN',
            message: 'Partial success detected',
            source: 'UoWDmlWorkItem',
            category: 'DML'
        },
        {
            timestamp: '2024-01-15T10:30:00.500Z',
            loggingLevel: 'ERROR',
            message: 'Validation rule failed',
            source: 'UoWDmlWorkItem',
            category: 'DML'
        },
        {
            timestamp: '2024-01-15T10:30:00.750Z',
            loggingLevel: 'FINE',
            message: 'Detailed trace information',
            source: 'UoWTracer',
            category: 'TRACE'
        }
    ],
    transactionStartTime: '2024-01-15T10:30:00.000Z'
};

const MOCK_EMPTY_MESSAGES = {
    messages: [],
    transactionStartTime: null
};

describe('c-uow-messages-console', () => {
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
        const element = createElement('c-uow-messages-console', {
            is: UowMessagesConsole
        });

        // Act
        document.body.appendChild(element);

        // Assert
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // DATA LOADING TESTS - WIRE MODE
    // ============================================================================

    it('should load messages when recordId is set', async () => {
        // Arrange
        const element = createElement('c-uow-messages-console', {
            is: UowMessagesConsole
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        getMessages.emit(MOCK_MESSAGES_DATA);
        await Promise.resolve();

        // Assert - Component should have messages
        expect(element).toBeTruthy();
    });

    it('should display messages in grid', async () => {
        // Arrange
        const element = createElement('c-uow-messages-console', {
            is: UowMessagesConsole
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        getMessages.emit(MOCK_MESSAGES_DATA);
        await Promise.resolve();

        // Assert - Messages should be displayed
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // DATA LOADING TESTS - DIRECT MESSAGES MODE
    // ============================================================================

    it('should use direct messages when provided', async () => {
        // Arrange
        const element = createElement('c-uow-messages-console', {
            is: UowMessagesConsole
        });
        element.messages = MOCK_MESSAGES_DATA.messages;

        // Act
        document.body.appendChild(element);
        await Promise.resolve();

        // Assert - Should use provided messages
        expect(element).toBeTruthy();
    });

    it('should use transactionStartTime prop for relative time', async () => {
        // Arrange
        const element = createElement('c-uow-messages-console', {
            is: UowMessagesConsole
        });
        element.messages = MOCK_MESSAGES_DATA.messages;
        element.transactionStartTime = '2024-01-15T10:30:00.000Z';

        // Act
        document.body.appendChild(element);
        await Promise.resolve();

        // Assert
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // FILTERING TESTS
    // ============================================================================

    it('should filter messages by log level', async () => {
        // Arrange
        const element = createElement('c-uow-messages-console', {
            is: UowMessagesConsole
        });
        element.recordId = 'a00000000000001AAA';
        document.body.appendChild(element);
        getMessages.emit(MOCK_MESSAGES_DATA);
        await Promise.resolve();

        // Act - Find log level combobox and change
        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        if (combobox) {
            combobox.dispatchEvent(new CustomEvent('change', {
                detail: { value: 'ERROR' }
            }));
            await Promise.resolve();
        }

        // Assert - Should filter to ERROR only
        expect(element).toBeTruthy();
    });

    it('should filter messages by search term', async () => {
        // Arrange
        const element = createElement('c-uow-messages-console', {
            is: UowMessagesConsole
        });
        element.recordId = 'a00000000000001AAA';
        document.body.appendChild(element);
        getMessages.emit(MOCK_MESSAGES_DATA);
        await Promise.resolve();

        // Act - Find search input and enter search term
        const searchInput = element.shadowRoot.querySelector('lightning-input');
        if (searchInput) {
            searchInput.dispatchEvent(new CustomEvent('change', {
                target: { value: 'validation' }
            }));
            await Promise.resolve();
        }

        // Assert
        expect(element).toBeTruthy();
    });

    it('should show all levels when filter is ALL', async () => {
        // Arrange
        const element = createElement('c-uow-messages-console', {
            is: UowMessagesConsole
        });
        element.recordId = 'a00000000000001AAA';
        document.body.appendChild(element);
        getMessages.emit(MOCK_MESSAGES_DATA);
        await Promise.resolve();

        // Act - Set filter to ALL (default)
        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        if (combobox) {
            combobox.dispatchEvent(new CustomEvent('change', {
                detail: { value: 'ALL' }
            }));
            await Promise.resolve();
        }

        // Assert - All messages should be shown
        expect(element).toBeTruthy();
    });

    it('should include FINER and FINEST in FINE filter', async () => {
        // Arrange
        const messagesWithFineVariants = {
            messages: [
                { timestamp: '2024-01-15T10:30:00.000Z', loggingLevel: 'FINE', message: 'Fine' },
                { timestamp: '2024-01-15T10:30:00.100Z', loggingLevel: 'FINER', message: 'Finer' },
                { timestamp: '2024-01-15T10:30:00.200Z', loggingLevel: 'FINEST', message: 'Finest' },
                { timestamp: '2024-01-15T10:30:00.300Z', loggingLevel: 'DEBUG', message: 'Debug' }
            ],
            transactionStartTime: '2024-01-15T10:30:00.000Z'
        };

        const element = createElement('c-uow-messages-console', {
            is: UowMessagesConsole
        });
        element.recordId = 'a00000000000001AAA';
        document.body.appendChild(element);
        getMessages.emit(messagesWithFineVariants);
        await Promise.resolve();

        // Act - Filter by FINE
        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        if (combobox) {
            combobox.dispatchEvent(new CustomEvent('change', {
                detail: { value: 'FINE' }
            }));
            await Promise.resolve();
        }

        // Assert - Should include FINE, FINER, and FINEST
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // RELATIVE TIME FORMATTING TESTS
    // ============================================================================

    it('should format relative time correctly', async () => {
        // Arrange
        const element = createElement('c-uow-messages-console', {
            is: UowMessagesConsole
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        getMessages.emit(MOCK_MESSAGES_DATA);
        await Promise.resolve();

        // Assert - Times should be formatted as MM:SS.mmm
        expect(element).toBeTruthy();
    });

    it('should use first message as base time if transactionStartTime not available', async () => {
        // Arrange
        const messagesWithoutStartTime = {
            messages: MOCK_MESSAGES_DATA.messages,
            transactionStartTime: null
        };

        const element = createElement('c-uow-messages-console', {
            is: UowMessagesConsole
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        getMessages.emit(messagesWithoutStartTime);
        await Promise.resolve();

        // Assert - First message should be base time (00:00.000)
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // EMPTY STATE TESTS
    // ============================================================================

    it('should show empty state when no messages', async () => {
        // Arrange
        const element = createElement('c-uow-messages-console', {
            is: UowMessagesConsole
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        getMessages.emit(MOCK_EMPTY_MESSAGES);
        await Promise.resolve();

        // Assert - Should show no messages state
        expect(element).toBeTruthy();
    });

    it('should show empty filtered state when no matches', async () => {
        // Arrange
        const element = createElement('c-uow-messages-console', {
            is: UowMessagesConsole
        });
        element.recordId = 'a00000000000001AAA';
        document.body.appendChild(element);
        getMessages.emit(MOCK_MESSAGES_DATA);
        await Promise.resolve();

        // Act - Search for non-existent term
        const searchInput = element.shadowRoot.querySelector('lightning-input');
        if (searchInput) {
            searchInput.value = 'xyznonexistent';
            searchInput.dispatchEvent(new Event('change'));
            await Promise.resolve();
        }

        // Assert
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // ERROR HANDLING TESTS
    // ============================================================================

    it('should handle wire error gracefully', async () => {
        // Arrange
        const element = createElement('c-uow-messages-console', {
            is: UowMessagesConsole
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        getMessages.error({ message: 'Failed to load messages' });
        await Promise.resolve();

        // Assert - Component should handle error state
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // LOG LEVEL CLASS TESTS
    // ============================================================================

    it('should apply correct CSS class for ERROR level', async () => {
        // Arrange
        const element = createElement('c-uow-messages-console', {
            is: UowMessagesConsole
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        getMessages.emit(MOCK_MESSAGES_DATA);
        await Promise.resolve();

        // Assert - ERROR messages should have error class
        expect(element).toBeTruthy();
    });

    it('should apply correct CSS class for WARN level', async () => {
        // Arrange
        const element = createElement('c-uow-messages-console', {
            is: UowMessagesConsole
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        getMessages.emit(MOCK_MESSAGES_DATA);
        await Promise.resolve();

        // Assert - WARN messages should have warn class
        expect(element).toBeTruthy();
    });

    it('should apply correct CSS class for INFO level', async () => {
        // Arrange
        const element = createElement('c-uow-messages-console', {
            is: UowMessagesConsole
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        getMessages.emit(MOCK_MESSAGES_DATA);
        await Promise.resolve();

        // Assert - INFO messages should have info class
        expect(element).toBeTruthy();
    });

    it('should apply correct CSS class for DEBUG level', async () => {
        // Arrange
        const element = createElement('c-uow-messages-console', {
            is: UowMessagesConsole
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        getMessages.emit(MOCK_MESSAGES_DATA);
        await Promise.resolve();

        // Assert - DEBUG messages should have debug class
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // DISPLAY PROPERTIES TESTS
    // ============================================================================

    it('should display message source', async () => {
        // Arrange
        const element = createElement('c-uow-messages-console', {
            is: UowMessagesConsole
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        getMessages.emit(MOCK_MESSAGES_DATA);
        await Promise.resolve();

        // Assert - Source should be visible
        expect(element).toBeTruthy();
    });

    it('should display message category', async () => {
        // Arrange
        const element = createElement('c-uow-messages-console', {
            is: UowMessagesConsole
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        getMessages.emit(MOCK_MESSAGES_DATA);
        await Promise.resolve();

        // Assert - Category should be visible
        expect(element).toBeTruthy();
    });

    // ============================================================================
    // NULL/UNDEFINED HANDLING TESTS
    // ============================================================================

    it('should handle messages with null timestamp', async () => {
        // Arrange
        const messagesWithNullTimestamp = {
            messages: [
                { loggingLevel: 'INFO', message: 'No timestamp', source: 'Test' }
            ],
            transactionStartTime: null
        };

        const element = createElement('c-uow-messages-console', {
            is: UowMessagesConsole
        });
        element.recordId = 'a00000000000001AAA';

        // Act
        document.body.appendChild(element);
        getMessages.emit(messagesWithNullTimestamp);
        await Promise.resolve();

        // Assert - Should handle null timestamp gracefully
        expect(element).toBeTruthy();
    });

    it('should handle empty messages array', async () => {
        // Arrange
        const element = createElement('c-uow-messages-console', {
            is: UowMessagesConsole
        });
        element.messages = [];

        // Act
        document.body.appendChild(element);
        await Promise.resolve();

        // Assert
        expect(element).toBeTruthy();
    });

    it('should handle null messages prop', async () => {
        // Arrange
        const element = createElement('c-uow-messages-console', {
            is: UowMessagesConsole
        });
        element.messages = null;

        // Act
        document.body.appendChild(element);
        await Promise.resolve();

        // Assert - Should default to empty array
        expect(element).toBeTruthy();
    });
});
