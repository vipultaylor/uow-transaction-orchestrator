//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * @description Span event component for OTel-aligned timeline visualization.
 *              Renders a point-in-time event within a span (formerly "milestone").
 *
 *              OTel Alignment:
 *              - In OTel, span events are point-in-time occurrences within a span
 *              - They have a name, timestamp, and optional attributes
 *              - Unlike spans, events don't have duration (instant occurrences)
 *
 * @see UowSpanTree
 * @see UowSpanItem
 */
import { LightningElement, api } from 'lwc';
import { EVENT_TYPE_TOKENS, getToken } from 'c/uowSharedDesignTokens';

export default class UowSpanEvent extends LightningElement {
    @api event;

    /**
     * Event name - the descriptive title of the event.
     * e.g., "Savepoint created", "Policy evaluation passed"
     */
    get name() {
        return this.event?.name || '';
    }

    /**
     * Event type - STATE, DECISION, RISK, ERROR, WARNING, INFO
     */
    get eventType() {
        return this.event?.eventType || 'INFO';
    }

    /**
     * Icon name based on event type
     */
    get iconName() {
        return getToken(EVENT_TYPE_TOKENS, this.eventType).icon;
    }

    /**
     * CSS class for event type styling
     */
    get eventTypeClass() {
        const type = this.eventType.toLowerCase();
        return `uow-event-type-${type}`;
    }
}