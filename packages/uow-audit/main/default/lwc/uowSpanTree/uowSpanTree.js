//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * @description Recursive tree renderer for OTel-aligned span hierarchy.
 *              Renders an unordered list of spans, distinguishing between
 *              regular spans and span events (milestones).
 *
 *              OTel Alignment:
 *              - Uses "spans" instead of "phases"
 *              - Span events are point-in-time events within a span
 *              - Maintains hierarchical parent-child relationships
 *
 * @see UowSpanItem
 * @see UowSpanEvent
 */
import { LightningElement, api } from 'lwc';

export default class UowSpanTree extends LightningElement {
    _spans = [];
    @api totalDurationMs = 0;

    @api
    get spans() {
        return this._spans;
    }

    set spans(value) {
        // Add isEvent flag to each span for template rendering (recursively)
        let processedSpans = this.addEventFlags(value || []);
        // Propagate error state up the tree for visual indicators
        this._spans = this.propagateErrorState(processedSpans);
    }

    /**
     * Recursively add isEvent flag to spans for conditional rendering.
     * In OTel, span events are point-in-time occurrences within a span.
     * @param {Array} spans - Array of span objects
     * @returns {Array} Processed spans with isEvent flag
     */
    addEventFlags(spans) {
        return spans.map(span => {
            const processedSpan = {
                ...span,
                // Span events (formerly milestones) are rendered differently
                isEvent: span.eventType === 'EVENT' || span.eventType === 'MILESTONE'
            };

            // Recursively process children
            if (span.children && span.children.length > 0) {
                processedSpan.children = this.addEventFlags(span.children);
            }

            return processedSpan;
        });
    }

    /**
     * Recursively propagate error state up the tree.
     * Sets hasDescendantError = true on any span that has a descendant
     * with ERROR status, allowing visual indicators on parent spans.
     * @param {Array} spans - Array of span objects
     * @returns {Array} Spans with hasDescendantError flag
     */
    propagateErrorState(spans) {
        return spans.map(span => {
            const processedSpan = { ...span };

            // First, recursively process children
            if (span.children && span.children.length > 0) {
                processedSpan.children = this.propagateErrorState(span.children);

                // Check if any child has error or has descendant error
                processedSpan.hasDescendantError = processedSpan.children.some(
                    child => child.statusCode === 'ERROR' || child.hasDescendantError === true
                );
            } else {
                processedSpan.hasDescendantError = false;
            }

            return processedSpan;
        });
    }

    get hasSpans() {
        return this._spans && this._spans.length > 0;
    }
}