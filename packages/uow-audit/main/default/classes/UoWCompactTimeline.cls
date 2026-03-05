//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * @description Compact timeline format for audit storage within Salesforce field limits.
 *
 *              This class provides a size-optimized representation of UoWTracer.TraceSummary
 *              for storage in LongTextArea fields (131KB limit). The compact format uses
 *              abbreviated property names to reduce JSON size by 50-60% while maintaining
 *              all data needed for timeline visualization.
 *
 *              DESIGN RATIONALE - Why Short Property Names:
 *              ============================================
 *              Salesforce LongTextArea fields have a 131,072 character limit. A typical
 *              transaction with 20 spans generates ~110KB of JSON in full OTel format.
 *              This leaves no room for growth. By using short property names, we reduce
 *              size to ~40-50KB, allowing for larger transactions and future expansion.
 *
 *              Since we use JSON.serialize() and JSON.deserialize() with strongly-typed
 *              classes, there's no risk of property name mismatches - the compiler
 *              enforces correctness at build time.
 *
 *              SPAN FILTERING:
 *              ===============
 *              Spans with SpanPhaseResult.NOT_APPLICABLE are excluded from the timeline
 *              as they add no value (e.g., plugin phases where no plugins executed).
 *              This filtering happens during conversion via includeInTimeline().
 *
 *              SPAN SUBTYPES:
 *              ==============
 *              Spans have a subType (SpanSubType enum) that determines their classification:
 *              - PHASE: Framework phase spans (policy, risk, plugins, work phases)
 *              - WORK_ITEM: User-registered work item spans (DML, event, email, etc.)
 *
 *              WORK ITEM OPTIMIZATION:
 *              =======================
 *              Work item spans are NOT stored as separate CompactSpan objects. Instead,
 *              their IDs are collected in the parent phase span's 'wk' (workItemIds) field.
 *              This reduces storage by ~80% for complex transactions with many work items.
 *              The timeline controller hydrates work item details from UoWAuditWorkItem__c
 *              records using these IDs.
 *
 *              PROPERTY NAME MAPPING:
 *              ======================
 *              CompactTrace:
 *              Compact  | Full Name       | Description
 *              ---------|-----------------|------------------------------------------
 *              td       | totalDurationMs | Total trace duration in milliseconds
 *              sc       | spanCount       | Total number of spans
 *              sp       | spans           | List of compact spans (flat structure)
 *
 *              CompactSpan:
 *              Compact  | Full Name       | Description
 *              ---------|-----------------|------------------------------------------
 *              id       | spanId          | Sequential span identifier (1, 2, 3...)
 *              pid      | parentSpanId    | Parent span's sequential ID (null for root)
 *              n        | name            | Human-readable span name/description
 *              s        | startTimeMs     | Start timestamp in epoch milliseconds
 *              e        | endTimeMs       | End timestamp in epoch milliseconds
 *              d        | durationMs      | Duration in milliseconds
 *              l        | level           | Nesting level (1 = root, 2 = child, etc.)
 *              p        | phase           | UoW phase enum name (e.g., "DML_EXECUTION")
 *              c        | category        | Phase category enum name (e.g., "DML")
 *              st       | statusCode      | OTel status: "OK", "ERROR", or "UNSET"
 *              ev       | events          | List of compact span events
 *              wk       | workItemIds     | List of work item IDs for hydration
 *
 *              CompactEvent:
 *              Compact  | Full Name       | Description
 *              ---------|-----------------|------------------------------------------
 *              n        | name            | Event name/description (prefix removed)
 *              t        | timestampMs     | Event timestamp in epoch milliseconds
 *              ty       | eventType       | Event type code: S=State, D=Decision,
 *                       |                 | R=Risk, E=Error, W=Warning, I=Info
 *              seq      | sequence        | Event sequence number within trace
 *
 *              ARCHITECTURE:
 *              =============
 *              - Compact format is used for Platform Event and Custom Object storage
 *              - Full OTel format remains available at runtime via UoWTracer
 *              - Future UoWOtelExporter can export full format to external systems
 *              - Controller expands compact format back to full names for LWC
 *
 * @author Vipul Taylor
 * @see UoWTracer
 * @see UoWAuditTimelineController
 */
public inherited sharing class UoWCompactTimeline {

    // ============================================================================
    // CONSTANTS - EVENT TYPE CODES
    // ============================================================================

    /**
     * @description Event type code for State events (e.g., "[STATE] STARTED")
     */
    public static final String EVENT_TYPE_STATE = 'S';

    /**
     * @description Event type code for Decision events (e.g., "[DECISION] Savepoint created")
     */
    public static final String EVENT_TYPE_DECISION = 'D';

    /**
     * @description Event type code for Risk events (e.g., "[RISK FACTOR] DELETE operation")
     */
    public static final String EVENT_TYPE_RISK = 'R';

    /**
     * @description Event type code for Error events
     */
    public static final String EVENT_TYPE_ERROR = 'E';

    /**
     * @description Event type code for Warning events
     */
    public static final String EVENT_TYPE_WARNING = 'W';

    /**
     * @description Event type code for Info/other events
     */
    public static final String EVENT_TYPE_INFO = 'I';

    // ============================================================================
    // PUBLIC API - CONVERSION
    // ============================================================================

    /**
     * @description Convert full UoWTracer.TraceSummary to compact format
     * @param summary The full trace summary from UoWTracer
     * @return CompactTrace instance ready for JSON serialization
     */
    public static CompactTrace fromTraceSummary(UoWTracer.TraceSummary summary) {
        if (summary == null) {
            return null;
        }

        CompactTrace compact = new CompactTrace();
        compact.td = summary.totalDurationMs;
        compact.sp = new List<CompactSpan>();

        // Build span ID mapping (OTel spanId -> sequential ID) for PHASE spans only
        // Work item spans are collected as IDs under their parent phase span
        Map<String, Integer> spanIdMap = new Map<String, Integer>();
        Map<String, List<String>> workItemIdsByParentSpanId = new Map<String, List<String>>();
        Integer sequentialId = 0;
        Integer phaseSpanCount = 0;

        // First pass: assign sequential IDs to PHASE spans only, collect work item IDs
        if (summary.spans != null) {
            for (UoWTracer.Span span : summary.spans) {
                if (span.eventType != UoWEnums.SpanEventType.SPAN) {
                    continue;
                }

                if (isWorkItemSpan(span)) {
                    // Collect work item ID under parent span
                    String workItemId = (String) span.attributes?.get('work.id');
                    if (String.isNotBlank(workItemId) && String.isNotBlank(span.parentSpanId)) {
                        if (!workItemIdsByParentSpanId.containsKey(span.parentSpanId)) {
                            workItemIdsByParentSpanId.put(span.parentSpanId, new List<String>());
                        }
                        workItemIdsByParentSpanId.get(span.parentSpanId).add(workItemId);
                    }
                } else {
                    // Phase span - assign sequential ID
                    sequentialId++;
                    spanIdMap.put(span.spanId, sequentialId);
                    phaseSpanCount++;
                }
            }
        }

        compact.sc = phaseSpanCount;

        // Second pass: convert PHASE spans with resolved parent IDs and work item IDs
        if (summary.spans != null) {
            for (UoWTracer.Span span : summary.spans) {
                if (span.eventType == UoWEnums.SpanEventType.SPAN
                    && !isWorkItemSpan(span)
                    && includeInTimeline(span)) {

                    CompactSpan compactSpan = convertSpan(span, spanIdMap);

                    // Attach work item IDs if this span has any
                    List<String> workItemIds = workItemIdsByParentSpanId.get(span.spanId);
                    if (workItemIds != null && !workItemIds.isEmpty()) {
                        compactSpan.wk = workItemIds;
                    }

                    compact.sp.add(compactSpan);
                }
            }
        }

        return compact;
    }

    /**
     * @description Serialize compact trace to JSON string
     * @param compact The compact trace to serialize
     * @return JSON string representation
     */
    public static String toJson(CompactTrace compact) {
        if (compact == null) {
            return null;
        }
        return JSON.serialize(compact);
    }

    /**
     * @description Deserialize JSON string to compact trace
     * @param jsonString The JSON string to deserialize
     * @return CompactTrace instance
     */
    public static CompactTrace fromJson(String jsonString) {
        if (String.isBlank(jsonString)) {
            return null;
        }
        return (CompactTrace) JSON.deserialize(jsonString, CompactTrace.class);
    }

    /**
     * @description Convert TraceSummary directly to compact JSON string
     *              Convenience method combining fromTraceSummary() and toJson()
     * @param summary The full trace summary from UoWTracer
     * @return Compact JSON string ready for storage
     */
    public static String toCompactJson(UoWTracer.TraceSummary summary) {
        return toJson(fromTraceSummary(summary));
    }

    // ============================================================================
    // PRIVATE METHODS - CONVERSION HELPERS
    // ============================================================================

    /**
     * @description Convert a single span to compact format
     * @param span The full span from UoWTracer
     * @param spanIdMap Map of OTel spanId to sequential ID
     * @return CompactSpan instance
     */
    private static CompactSpan convertSpan(UoWTracer.Span span, Map<String, Integer> spanIdMap) {
        // Complete incomplete spans (e.g., audit plugin span captured before completion)
        if (!span.isCompleted) {
            span.complete(null);
        }

        CompactSpan compact = new CompactSpan();

        // Sequential ID from mapping
        compact.id = spanIdMap.get(span.spanId);

        // Parent ID (null for root spans)
        if (String.isNotBlank(span.parentSpanId) && spanIdMap.containsKey(span.parentSpanId)) {
            compact.pid = spanIdMap.get(span.parentSpanId);
        }

        // Core properties
        compact.n = span.name;
        compact.s = span.startTimeMs;
        compact.e = span.endTimeMs;
        compact.d = span.durationMs;
        compact.l = span.level;

        // Phase and category from transient enum fields
        compact.p = span.phase?.name();
        compact.c = span.category?.name();

        // Status (set by endSpan based on SpanPhaseResult or WorkStatus)
        compact.st = span.statusCode;

        // Note: Work item data is no longer stored here. Work item IDs are collected
        // in the wk field and hydrated from UoWAuditWorkItem__c records at display time.

        // Convert events
        if (span.events != null && !span.events.isEmpty()) {
            compact.ev = new List<CompactEvent>();
            for (UoWTracer.SpanEvent event : span.events) {
                compact.ev.add(convertEvent(event));
            }
        }

        return compact;
    }

    /**
     * @description Check if a span should be included in the timeline.
     *              Spans marked as NOT_APPLICABLE are excluded as they add no value.
     * @param span The span to check
     * @return True if span should be included in timeline
     */
    private static Boolean includeInTimeline(UoWTracer.Span span) {
        if (span == null) {
            return false;
        }
        return span.attributes?.get('phase.result') != UoWEnums.SpanPhaseResult.NOT_APPLICABLE.name();
    }

    /**
     * @description Check if a span is a work item span using subType
     * @param span The span to check
     * @return True if this is a WORK_ITEM subtype span
     */
    private static Boolean isWorkItemSpan(UoWTracer.Span span) {
        if (span == null) {
            return false;
        }
        return span.subType == UoWEnums.SpanSubType.WORK_ITEM;
    }

    /**
     * @description Convert a single span event to compact format
     * @param event The full span event from UoWTracer
     * @return CompactEvent instance
     */
    private static CompactEvent convertEvent(UoWTracer.SpanEvent event) {
        CompactEvent compact = new CompactEvent();

        // Extract event type and clean name
        String fullName = event.name;
        compact.ty = extractEventType(fullName);
        compact.n = cleanEventName(fullName);

        // Timing
        compact.t = event.timestampMs;
        compact.seq = event.sequence;

        return compact;
    }

    /**
     * @description Extract event type code from event name prefix
     * @param name Full event name (e.g., "[STATE] STARTED: Transaction initialized")
     * @return Event type code (S, D, R, E, W, I)
     */
    private static String extractEventType(String name) {
        if (String.isBlank(name)) {
            return EVENT_TYPE_INFO;
        }

        if (name.startsWith('[STATE]')) {
            return EVENT_TYPE_STATE;
        } else if (name.startsWith('[DECISION]')) {
            return EVENT_TYPE_DECISION;
        } else if (name.startsWith('[RISK') || name.startsWith('[RISK FACTOR]')) {
            return EVENT_TYPE_RISK;
        } else if (name.startsWith('[ERROR]')) {
            return EVENT_TYPE_ERROR;
        } else if (name.startsWith('[WARNING]') || name.startsWith('[WARN]')) {
            return EVENT_TYPE_WARNING;
        }

        return EVENT_TYPE_INFO;
    }

    /**
     * @description Remove event type prefix from event name
     * @param name Full event name (e.g., "[STATE] STARTED: Transaction initialized")
     * @return Cleaned name (e.g., "STARTED: Transaction initialized")
     */
    private static String cleanEventName(String name) {
        if (String.isBlank(name)) {
            return name;
        }

        // Remove known prefixes
        String cleaned = name;

        if (cleaned.startsWith('[STATE] ')) {
            cleaned = cleaned.substring(8);
        } else if (cleaned.startsWith('[DECISION] ')) {
            cleaned = cleaned.substring(11);
        } else if (cleaned.startsWith('[RISK FACTOR] ')) {
            cleaned = cleaned.substring(14);
        } else if (cleaned.startsWith('[RISK] ')) {
            cleaned = cleaned.substring(7);
        } else if (cleaned.startsWith('[ERROR] ')) {
            cleaned = cleaned.substring(8);
        } else if (cleaned.startsWith('[WARNING] ')) {
            cleaned = cleaned.substring(10);
        } else if (cleaned.startsWith('[WARN] ')) {
            cleaned = cleaned.substring(7);
        } else if (cleaned.startsWith('[INFO] ')) {
            cleaned = cleaned.substring(7);
        }

        return cleaned;
    }

    // ============================================================================
    // INNER CLASSES - COMPACT DATA STRUCTURES
    // ============================================================================

    /**
     * @description Compact trace container - root of the timeline structure.
     *              Property names are abbreviated for JSON size optimization.
     *
     *              Mapping:
     *              - td = totalDurationMs (total trace duration)
     *              - sc = spanCount (number of spans)
     *              - sp = spans (list of compact spans)
     */
    public class CompactTrace {
        /** @description Total duration in milliseconds (td = totalDurationMs) */
        public Long td;

        /** @description Total span count (sc = spanCount) */
        public Integer sc;

        /** @description List of spans in flat structure (sp = spans) */
        public List<CompactSpan> sp;
    }

    /**
     * @description Compact span representation - a single phase/operation.
     *              Property names are abbreviated for JSON size optimization.
     *
     *              IMPORTANT: Work items are NOT stored as separate CompactSpan objects.
     *              Instead, their IDs are stored in the parent phase span's 'wk' field
     *              and hydrated from UoWAuditWorkItem__c records at display time.
     *              This reduces storage by ~80% for complex transactions.
     *
     *              Mapping:
     *              - id  = spanId (sequential: 1, 2, 3...)
     *              - pid = parentSpanId (parent's sequential ID, null for root)
     *              - n   = name (span description)
     *              - s   = startTimeMs (epoch milliseconds)
     *              - e   = endTimeMs (epoch milliseconds)
     *              - d   = durationMs (duration)
     *              - l   = level (nesting: 1=root, 2=child...)
     *              - p   = phase (UoWEnums.SpanPhase name)
     *              - c   = category (UoWEnums.PhaseCategory name)
     *              - st  = statusCode (OK, ERROR, UNSET)
     *              - ev  = events (list of compact events)
     *              - wk  = workItemIds (list of work item IDs for hydration)
     */
    public class CompactSpan {
        /** @description Sequential span ID: 1, 2, 3... (id = spanId) */
        public Integer id;

        /** @description Parent span's sequential ID, null for root (pid = parentSpanId) */
        public Integer pid;

        /** @description Span name/description (n = name) */
        public String n;

        /** @description Start time in epoch milliseconds (s = startTimeMs) */
        public Long s;

        /** @description End time in epoch milliseconds (e = endTimeMs) */
        public Long e;

        /** @description Duration in milliseconds (d = durationMs) */
        public Long d;

        /** @description Nesting level: 1=root, 2=child, etc. (l = level) */
        public Integer l;

        /** @description Phase enum name, e.g., "DML_EXECUTION" (p = phase) */
        public String p;

        /** @description Category enum name, e.g., "DML" (c = category) */
        public String c;

        /** @description OTel status: "OK", "ERROR", "UNSET" (st = statusCode) */
        public String st;

        /** @description List of span events (ev = events) */
        public List<CompactEvent> ev;

        // ============================================================================
        // WORK ITEM IDS (for hydration from UoWAuditWorkItem__c records)
        // ============================================================================

        /** @description List of work item IDs for hydration (wk = workItemIds) */
        public List<String> wk;
    }

    /**
     * @description Compact span event representation - an instant event within a span.
     *              Property names are abbreviated for JSON size optimization.
     *
     *              Mapping:
     *              - n   = name (event description, prefix removed)
     *              - t   = timestampMs (epoch milliseconds)
     *              - ty  = eventType (S=State, D=Decision, R=Risk, E=Error, W=Warning, I=Info)
     *              - seq = sequence (event sequence number)
     */
    public class CompactEvent {
        /** @description Event name with prefix removed (n = name) */
        public String n;

        /** @description Timestamp in epoch milliseconds (t = timestampMs) */
        public Long t;

        /** @description Event type code: S, D, R, E, W, I (ty = eventType) */
        public String ty;

        /** @description Sequence number within trace (seq = sequence) */
        public Integer seq;
    }
}