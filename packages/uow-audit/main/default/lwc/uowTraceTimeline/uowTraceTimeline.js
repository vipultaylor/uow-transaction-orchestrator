//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * @description Main container component for UoW Trace Timeline visualization.
 *              Fetches trace data from Apex controller and renders hierarchical
 *              span tree using OTel-aligned terminology.
 *
 *              OTel Alignment:
 *              - Uses "trace" instead of "transaction" (OTel trace = distributed trace)
 *              - Uses "spans" instead of "phases" (OTel span = unit of work)
 *              - Property names align with OTel specification
 *
 * @see UoWAuditTimelineController
 */
import { LightningElement, api, track, wire } from 'lwc';
import getTimelineData from '@salesforce/apex/UoWAuditTimelineController.getTimelineData';

export default class UowTraceTimeline extends LightningElement {
    @api recordId; // UoWAuditTransaction__c record ID

    @track _spans = [];
    @track error;
    @track isLoading = true;

    // Performance metrics
    totalDurationMs = 0;

    // Wire to Apex controller to fetch timeline data
    @wire(getTimelineData, { transactionId: '$recordId' })
    wiredTimelineData({ error, data }) {
        this.isLoading = false;
        if (data) {
            // Use pre-calculated metrics from transaction record
            const txn = data.txnRecord;

            this.totalDurationMs = txn.ExecutionTimeMs__c || 0;

            // Filter out root span if it's the only top-level span - show only its children
            this._spans = this.filterSpans(data.phases || []);
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this._spans = [];
            this.totalDurationMs = 0;
        }
    }

    @api
    get spans() {
        return this._spans;
    }

    set spans(value) {
        this._spans = value || [];
    }

    get isLoaded() {
        return !this.isLoading && !this.error;
    }

    /**
     * Filter out level 1 root spans and promote their children.
     * Level 1 spans are container spans (Transact, Plugins Audit) that
     * don't add informational value - we show their children directly.
     *
     * @param {Array} spans - Array of span objects from controller
     * @returns {Array} Filtered spans with children promoted
     */
    filterSpans(spans) {
        if (!spans || spans.length === 0) {
            return [];
        }

        const result = [];

        for (const span of spans) {
            if (span.level === 1 && span.hasChildren && span.children?.length > 0) {
                // Level 1 root span - promote children
                result.push(...span.children);
            } else if (span.level !== 1) {
                // Keep non-root spans
                result.push(span);
            }
        }

        return result;
    }
}