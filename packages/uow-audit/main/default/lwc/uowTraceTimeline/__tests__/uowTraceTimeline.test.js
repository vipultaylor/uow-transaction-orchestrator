//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
import { createElement } from '@lwc/engine-dom';
import UowTraceTimeline from 'c/uowTraceTimeline';

describe('c-uow-trace-timeline', () => {
    afterEach(() => {
        // The jsdom instance is shared across test cases in a single file so reset the DOM
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('should render the trace timeline component', () => {
        // Arrange
        const element = createElement('c-uow-trace-timeline', {
            is: UowTraceTimeline
        });

        // Act
        document.body.appendChild(element);

        // Assert
        expect(element).toBeTruthy();
    });
});
