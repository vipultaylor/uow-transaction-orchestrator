//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * @description Apex controller for UoW Audit Timeline LWC components.
 *              Provides data access for visualizing transaction timeline spans.
 *
 *              Timeline data is stored as compact JSON in UoWAuditTransaction__c.Timeline__c
 *              using UoWCompactTimeline format. This controller expands the compact format
 *              to full property names for LWC consumption and builds the hierarchical
 *              tree structure for nested accordion display.
 *
 *              WORK ITEM HYDRATION:
 *              Work items are stored as ID references in the compact timeline (wk field).
 *              This controller hydrates them from UoWAuditWorkItem__c records and attaches
 *              them to their parent phase spans for display. This approach reduces timeline
 *              JSON storage by ~80% while maintaining full work item detail on display.
 *
 *              OTel-Aligned Naming:
 *              - Uses "spans" instead of "phases"
 *              - Uses "name" for span description (OTel standard)
 *              - Uses "phase" for UoW phase (from attributes['uow.phase'])
 *              - Uses "category" for UoW category (from attributes['uow.category'])
 *              - Uses "statusCode" for OTel status (OK, ERROR, UNSET)
 *
 *              Property Expansion (Compact -> LWC):
 *              - id  -> spanId
 *              - pid -> parentSpanId
 *              - n   -> name
 *              - s   -> startTimeMs, startTime (DateTime)
 *              - e   -> endTimeMs
 *              - d   -> durationMs
 *              - l   -> level
 *              - p   -> phase
 *              - c   -> category
 *              - st  -> statusCode
 *              - ev  -> events
 *              - wk  -> workItemIds (hydrated to workItems list)
 *
 * @author Vipul Taylor
 * @see UoWCompactTimeline
 */
public with sharing class UoWAuditTimelineController {

    // ============================================================================
    // PUBLIC API
    // ============================================================================

    /**
     * @description Get transaction with timeline data
     * @param transactionId UoWAuditTransaction__c record ID
     * @return Transaction record with timeline fields
     */
    @AuraEnabled(cacheable=true)
    public static UoWAuditTransaction__c getTransaction(Id transactionId) {
        try {
            UoWAuditTransaction__c txn = UoWAuditDataSelector.getInstance().getTransactionForTimeline(transactionId);
            if (txn == null) {
                throw UoWExceptionService.buildAuraException('Transaction not found');
            }
            return txn;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw UoWExceptionService.buildAuraException('Failed to load transaction: ' + e.getMessage());
        }
    }

    /**
     * @description Get hierarchical timeline data structure from Timeline__c JSON.
     *              Parses compact format (UoWCompactTimeline) and builds hierarchy.
     *              Work items are hydrated from UoWAuditWorkItem__c records.
     * @param transactionId UoWAuditTransaction__c record ID
     * @return TimelineData wrapper with transaction, hierarchical spans, and hydrated work items
     */
    @AuraEnabled(cacheable=true)
    public static TimelineData getTimelineData(Id transactionId) {
        try {
            UoWAuditTransaction__c txn = getTransaction(transactionId);

            // Parse spans from Timeline__c JSON (compact format)
            List<SpanNode> rootSpans = new List<SpanNode>();
            Integer totalSpans = 0;
            Set<String> allWorkItemIds = new Set<String>();

            if (String.isNotBlank(txn.Timeline__c)) {
                rootSpans = parseCompactTimeline(txn.Timeline__c, allWorkItemIds);
                totalSpans = countTotalSpans(rootSpans);
            }

            // Hydrate work items from database
            Map<String, UoWAuditWorkItem__c> workItemsByName = hydrateWorkItems(allWorkItemIds, transactionId);

            // Attach hydrated work items to their parent spans
            attachWorkItemsToSpans(rootSpans, workItemsByName);

            return new TimelineData(txn, rootSpans, totalSpans);
        } catch (Exception e) {
            throw UoWExceptionService.buildAuraException('Failed to load timeline data: ' + e.getMessage());
        }
    }

    // ============================================================================
    // PRIVATE METHODS - PARSING
    // ============================================================================

    /**
     * @description Parse compact timeline JSON using UoWCompactTimeline classes.
     *              Uses JSON.deserialize() for type-safe parsing - no string literals.
     *              Collects all work item IDs for subsequent hydration.
     * @param timelineJson The compact JSON string from Timeline__c field
     * @param workItemIds Output set to collect all work item IDs found in spans
     * @return List of root-level SpanNode objects with nested children
     */
    private static List<SpanNode> parseCompactTimeline(String timelineJson, Set<String> workItemIds) {
        UoWCompactTimeline.CompactTrace compact = UoWCompactTimeline.fromJson(timelineJson);

        if (compact == null || compact.sp == null) {
            return new List<SpanNode>();
        }

        // Convert compact spans to SpanNodes
        Map<Integer, SpanNode> nodesById = new Map<Integer, SpanNode>();
        Map<Integer, List<SpanNode>> childrenByParentId = new Map<Integer, List<SpanNode>>();

        // First pass: Create all nodes and collect work item IDs
        for (UoWCompactTimeline.CompactSpan span : compact.sp) {
            SpanNode node = new SpanNode(span);
            nodesById.put(span.id, node);

            // Collect work item IDs for hydration
            if (span.wk != null) {
                workItemIds.addAll(span.wk);
            }
        }

        // Second pass: Build parent-child relationships
        List<SpanNode> rootNodes = new List<SpanNode>();
        for (SpanNode node : nodesById.values()) {
            if (node.parentSpanId == null) {
                // Root level span
                rootNodes.add(node);
            } else {
                // Child span - add to parent's children
                Integer parentId = Integer.valueOf(node.parentSpanId);
                if (!childrenByParentId.containsKey(parentId)) {
                    childrenByParentId.put(parentId, new List<SpanNode>());
                }
                childrenByParentId.get(parentId).add(node);
            }
        }

        // Third pass: Assign children to parent nodes
        for (Integer spanId : nodesById.keySet()) {
            SpanNode node = nodesById.get(spanId);
            if (childrenByParentId.containsKey(spanId)) {
                node.children = childrenByParentId.get(spanId);
                node.hasChildren = true;
            }
        }

        // Sort root nodes by sequence/start time
        rootNodes.sort();

        return rootNodes;
    }

    /**
     * @description Hydrate work items from UoWAuditWorkItem__c records.
     * @param workItemIds Set of work item Name values (e.g., "WORK-1234567890-123456")
     * @param transactionId Transaction record ID for filtering
     * @return Map of work item Name to SObject record
     */
    private static Map<String, UoWAuditWorkItem__c> hydrateWorkItems(Set<String> workItemIds, Id transactionId) {
        Map<String, UoWAuditWorkItem__c> result = new Map<String, UoWAuditWorkItem__c>();

        if (workItemIds == null || workItemIds.isEmpty()) {
            return result;
        }

        // Query work items by Name (the work item ID stored in compact timeline)
        List<UoWAuditWorkItem__c> workItems = [
            SELECT Id, Name, WorkType__c, WorkItemStatus__c, SObjectType__c, DmlOperation__c,
                   ExecutionPhase__c, SuccessCount__c, ProcessedCount__c, FailureCount__c,
                   DurationMs__c, Sequence__c, Operation__c, ResultSummary__c,
                   Endpoint__c, HttpMethod__c, FlowApiName__c, NotificationType__c
            FROM UoWAuditWorkItem__c
            WHERE Name IN :workItemIds
            AND AuditTransaction__c = :transactionId
            WITH USER_MODE
            ORDER BY Sequence__c ASC
        ];

        for (UoWAuditWorkItem__c wi : workItems) {
            result.put(wi.Name, wi);
        }

        return result;
    }

    /**
     * @description Attach hydrated work items to their parent spans.
     *              Recursively processes all spans in the hierarchy.
     * @param spans List of span nodes to process
     * @param workItemsByName Map of work item Name to SObject record
     */
    private static void attachWorkItemsToSpans(List<SpanNode> spans, Map<String, UoWAuditWorkItem__c> workItemsByName) {
        if (spans == null) {
            return;
        }

        for (SpanNode span : spans) {
            // Attach work items to this span
            if (span.workItemIds != null && !span.workItemIds.isEmpty()) {
                span.workItems = new List<UoWAuditWorkItem__c>();
                for (String workItemId : span.workItemIds) {
                    UoWAuditWorkItem__c workItem = workItemsByName.get(workItemId);
                    if (workItem != null) {
                        span.workItems.add(workItem);
                    }
                }
                span.hasWorkItems = !span.workItems.isEmpty();
            }

            // Recursively process children
            if (span.children != null) {
                attachWorkItemsToSpans(span.children, workItemsByName);
            }
        }
    }

    /**
     * @description Count total spans including nested children
     * @param spans List of span nodes
     * @return Total count
     */
    private static Integer countTotalSpans(List<SpanNode> spans) {
        Integer count = 0;
        for (SpanNode span : spans) {
            count++;
            if (span.children != null) {
                count += countTotalSpans(span.children);
            }
        }
        return count;
    }

    // ============================================================================
    // WRAPPER CLASSES
    // ============================================================================

    /**
     * @description Complete timeline data wrapper.
     *              Note: Uses "phases" property name for LWC compatibility,
     *              but the data structure is OTel-aligned SpanNode objects.
     */
    public class TimelineData {
        @AuraEnabled public UoWAuditTransaction__c txnRecord { get; set; }
        @AuraEnabled public List<SpanNode> phases { get; set; }
        @AuraEnabled public Integer totalPhases { get; set; }

        public TimelineData(UoWAuditTransaction__c txn, List<SpanNode> spans, Integer total) {
            this.txnRecord = txn;
            this.phases = spans;
            this.totalPhases = total;
        }
    }

    /**
     * @description Hierarchical span node for tree rendering.
     *              Uses OTel-aligned naming convention for consistency:
     *              - name (OTel span name - descriptive title)
     *              - phase (UoW phase from attributes)
     *              - category (UoW category from attributes)
     *              - statusCode (OTel status: OK, ERROR, UNSET)
     *
     *              Implements Comparable for sorting by startTimeMs/sequence.
     */
    public class SpanNode implements Comparable {
        // OTel-aligned properties (exposed to LWC)
        @AuraEnabled public String spanId { get; set; }
        @AuraEnabled public String parentSpanId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String phase { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public String statusCode { get; set; }

        // Timing
        @AuraEnabled public DateTime startTime { get; set; }
        @AuraEnabled public Long startTimeMs { get; set; }
        @AuraEnabled public Long endTimeMs { get; set; }
        @AuraEnabled public Long durationMs { get; set; }

        // Hierarchy
        @AuraEnabled public Integer level { get; set; }
        @AuraEnabled public Integer sequence { get; set; }
        @AuraEnabled public List<SpanNode> children { get; set; }
        @AuraEnabled public Boolean hasChildren { get; set; }

        // Events within this span
        @AuraEnabled public List<EventNode> events { get; set; }

        // Work Items - IDs for lookup, hydrated records for display
        @AuraEnabled public List<String> workItemIds { get; set; }
        @AuraEnabled public List<UoWAuditWorkItem__c> workItems { get; set; }
        @AuraEnabled public Boolean hasWorkItems { get; set; }

        /**
         * @description Constructor from compact format span.
         *              Maps abbreviated property names to full OTel-aligned names.
         * @param span The compact span from UoWCompactTimeline
         */
        public SpanNode(UoWCompactTimeline.CompactSpan span) {
            this.spanId = String.valueOf(span.id);
            this.parentSpanId = span.pid != null ? String.valueOf(span.pid) : null;
            this.name = span.n;
            this.phase = span.p;
            this.category = span.c;
            this.statusCode = span.st;
            this.startTimeMs = span.s;
            this.endTimeMs = span.e;
            this.durationMs = span.d;
            this.level = span.l;
            this.sequence = span.id; // Use span ID as sequence

            // Convert epoch ms to DateTime for LWC
            if (span.s != null) {
                this.startTime = DateTime.newInstance(span.s);
            }

            // Convert events
            if (span.ev != null && !span.ev.isEmpty()) {
                this.events = new List<EventNode>();
                for (UoWCompactTimeline.CompactEvent ev : span.ev) {
                    this.events.add(new EventNode(ev));
                }
            }

            // Work item IDs - will be hydrated separately
            this.workItemIds = span.wk;
            this.hasWorkItems = span.wk != null && !span.wk.isEmpty();

            this.children = new List<SpanNode>();
            this.hasChildren = false;
        }

        /**
         * @description Comparable implementation - sort by startTimeMs then sequence
         * @param other The other SpanNode to compare to
         * @return Comparison result
         */
        public Integer compareTo(Object other) {
            SpanNode otherNode = (SpanNode) other;

            // Primary sort: startTimeMs
            if (this.startTimeMs != null && otherNode.startTimeMs != null) {
                if (this.startTimeMs > otherNode.startTimeMs) {
                    return 1;
                }
                if (this.startTimeMs < otherNode.startTimeMs) {
                    return -1;
                }
            }

            // Secondary sort: sequence
            if (this.sequence != null && otherNode.sequence != null) {
                return this.sequence - otherNode.sequence;
            }

            return 0;
        }
    }

    /**
     * @description Event node for span events (point-in-time occurrences).
     *              Uses OTel-aligned naming convention.
     */
    public class EventNode {
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String eventType { get; set; }
        @AuraEnabled public Long timestampMs { get; set; }
        @AuraEnabled public DateTime timestamp { get; set; }
        @AuraEnabled public Integer sequence { get; set; }

        /**
         * @description Constructor from compact event.
         *              Maps abbreviated property names to full names.
         * @param ev The compact event from UoWCompactTimeline
         */
        public EventNode(UoWCompactTimeline.CompactEvent ev) {
            this.name = ev.n;
            this.eventType = expandEventType(ev.ty);
            this.timestampMs = ev.t;
            this.sequence = ev.seq;

            // Convert epoch ms to DateTime
            if (ev.t != null) {
                this.timestamp = DateTime.newInstance(ev.t);
            }
        }

        /**
         * @description Expand compact event type code to full name
         * @param typeCode The compact type code (S, D, R, E, W, I)
         * @return Full event type name
         */
        private String expandEventType(String typeCode) {
            if (typeCode == UoWCompactTimeline.EVENT_TYPE_STATE) {
                return 'STATE';
            } else if (typeCode == UoWCompactTimeline.EVENT_TYPE_DECISION) {
                return 'DECISION';
            } else if (typeCode == UoWCompactTimeline.EVENT_TYPE_RISK) {
                return 'RISK';
            } else if (typeCode == UoWCompactTimeline.EVENT_TYPE_ERROR) {
                return 'ERROR';
            } else if (typeCode == UoWCompactTimeline.EVENT_TYPE_WARNING) {
                return 'WARNING';
            }
            return 'INFO';
        }
    }

}