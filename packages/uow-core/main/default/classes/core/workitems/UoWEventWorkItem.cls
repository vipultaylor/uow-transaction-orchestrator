//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Platform Event work item for publishing events.
 * Contains events, publish results, and masking support.
 *
 * STORAGE PATTERN:
 * - originalEvents (transient): Unmasked original data for event publishing
 * - maskedEvents (transient): Cached masked version for audit purposes
 * - snapshots (serializable): Enriched audit snapshots pairing events with results
 *
 * Serialization scenarios:
 * - Async execution: snapshots with events only (no result data)
 * - Audit snapshots: snapshots = enriched EventSnapshot with error-priority sampling
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Work Items
 * @see UoWWorkItem
 * @see UoWEventExecutionService
 */
public inherited sharing class UoWEventWorkItem extends UoWWorkItem {

    // ============================================================================
    // PUBLIC PROPERTIES
    // ============================================================================

    public UoWEnums.WorkPhase executionPhase;
    public String sobjectTypeName;

    // ============================================================================
    // PUBLIC PROPERTIES - TRANSIENT
    // ============================================================================

    public transient Schema.SObjectType sobjectType;
    public transient List<Database.SaveResult> publishResults;

    // ============================================================================
    // PRIVATE PROPERTIES - EVENT STORAGE
    // ============================================================================

    // Enriched snapshots - pairs events with their publish results
    // For async: contains events only (no result data)
    // For audit: contains events + result data with error-priority sampling
    @TestVisible
    private List<EventSnapshot> snapshots;

    // Original unmasked events for publishing (transient - restored via hydrate)
    @TestVisible
    private transient List<SObject> originalEvents;

    // Masked events for audit purposes (transient - rebuilt if needed)
    @TestVisible
    private transient List<SObject> maskedEvents;

    // Indices of failed events - populated during processResults()
    @TestVisible
    private transient Set<Integer> failedIndices;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Create a new Event work item.
     *
     * @param phase Execution phase (PRE_DML, POST_DML, ON_SUCCESS, etc.)
     * @param sType SObjectType of the platform event
     * @param eventRecords List of event records to publish
     */
    public UoWEventWorkItem(UoWEnums.WorkPhase phase, Schema.SObjectType sType, List<SObject> eventRecords) {
        super(UoWEnums.WorkType.EVENT);
        this.executionPhase = phase ?? UoWEnums.WorkPhase.POST_DML;
        this.sobjectType = sType;
        this.sobjectTypeName = UoWCacheService.getDescribe(sType).getName();
        this.originalEvents = eventRecords ?? new List<SObject>();
        this.statistics.planned = this.originalEvents.size();
        this.continueOnError = false;
    }

    // ============================================================================
    // PUBLIC API - FLUENT CONFIGURATION
    // ============================================================================

    /**
     * Continue execution even if event publishing fails (don't re-throw exception).
     *
     * @return This work item for fluent chaining
     */
    public UoWEventWorkItem continueOnError() {
        this.continueOnError = true;
        return this;
    }

    /**
     * Fail-fast if event publishing fails (re-throw exception for transaction rollback).
     *
     * @return This work item for fluent chaining
     */
    public UoWEventWorkItem failFast() {
        this.continueOnError = false;
        return this;
    }

    // ============================================================================
    // PUBLIC API - EVENT ACCESSORS
    // ============================================================================

    /**
     * Get snapshots for serialization/audit purposes.
     * Returns enriched snapshots pairing events with their publish results.
     *
     * @return Snapshots prepared for serialization
     */
    public List<EventSnapshot> getSnapshots() {
        return this.snapshots;
    }

    /**
     * Get original unmasked events for event publishing.
     * Use this when actual data must be published.
     * This is the authoritative source for event publishing.
     *
     * @return Original unmasked events
     */
    public List<SObject> getOriginalEvents() {
        return this.originalEvents;
    }

    /**
     * Set masked events after masking service processes them.
     * Cached for use during audit serialization.
     *
     * @param masked The masked events
     */
    public void setMaskedEvents(List<SObject> masked) {
        this.maskedEvents = masked;
    }

    // ============================================================================
    // PUBLIC API - EVENT MANAGEMENT
    // ============================================================================

    /**
     * Add events to this work item (for consolidation).
     *
     * @param newEvents Events to add
     */
    public void addEvents(List<SObject> newEvents) {
        if (newEvents == null || newEvents.isEmpty()) {
            return;
        }
        this.originalEvents.addAll(newEvents);
        this.statistics.planned += newEvents.size();
    }

    // ============================================================================
    // PUBLIC API - RESULT PROCESSING (Override)
    // ============================================================================

    /**
     * Process event publish results - extract errors and calculate statistics.
     * Single pass through Database.SaveResult objects to:
     * 1. Count successes and failures
     * 2. Extract Database.Error objects as ErrorInfo
     * 3. Track failed indices for error-priority sampling
     *
     * Handles two scenarios:
     * - Normal execution: publishResults exist
     * - Exception thrown: No results, but errors already captured via addError()
     */
    public override void processResults() {
        this.statistics.processed = this.originalEvents?.size() ?? 0;
        this.statistics.successes = 0;
        this.statistics.failures = 0;
        this.failedIndices = new Set<Integer>();

        // Scenario 2: Exception was thrown before results were populated
        if (this.publishResults == null && this.hasErrors()) {
            this.statistics.failures = this.statistics.processed;
            // Mark all as failed when exception occurred
            for (Integer i = 0; i < this.statistics.processed; i++) {
                this.failedIndices.add(i);
            }
            return;
        }

        // Scenario 1: Normal execution with results
        if (this.publishResults != null) {
            for (Integer i = 0; i < this.publishResults.size(); i++) {
                Database.SaveResult sr = this.publishResults[i];
                if (sr.isSuccess()) {
                    this.statistics.successes++;
                } else {
                    this.statistics.failures++;
                    this.failedIndices.add(i);
                    for (Database.Error err : sr.getErrors()) {
                        this.addError(new UoWExceptionService.ErrorInfo(
                            err, i, 'EVENT PUBLISH', this.sobjectTypeName
                        ));
                    }
                }
            }
        }
    }

    /**
     * Finalize work item status based on execution results.
     * Sets status to SUCCESS, PARTIAL_SUCCESS, FAILED, or NOT_EXECUTED.
     */
    public override void finalizeStatus() {
        if (!this.isExecuted) {
            this.status = UoWEnums.WorkStatus.NOT_EXECUTED;
            return;
        }

        if (this.statistics.successes > 0 && this.statistics.failures > 0) {
            this.status = UoWEnums.WorkStatus.PARTIAL_SUCCESS;
        } else if (this.statistics.failures > 0) {
            this.status = UoWEnums.WorkStatus.FAILED;
        } else {
            this.status = UoWEnums.WorkStatus.SUCCESS;
        }
    }

    // ============================================================================
    // PUBLIC API - SERIALIZATION LIFECYCLE (Override)
    // ============================================================================

    /**
     * Prepare work item for serialization (async execution).
     * Builds snapshots with events only (no result data).
     * Use this for async Queueable serialization where data must remain intact for publishing.
     */
    public override void prepareForSerialization() {
        super.prepareForSerialization();
        // For async: build snapshots with events only (no result data)
        this.snapshots = new List<EventSnapshot>();
        if (this.originalEvents != null) {
            for (Integer i = 0; i < this.originalEvents.size(); i++) {
                EventSnapshot snap = new EventSnapshot();
                snap.idx = i;
                snap.evt = this.originalEvents[i];
                this.snapshots.add(snap);
            }
        }
    }

    /**
     * Prepare work item for serialization with configuration.
     * Builds enriched snapshots with error-priority sampling and result data.
     *
     * @param config Serialization configuration controlling masking/sampling behavior
     */
    public override void prepareForSerialization(UoWSerializationConfig config) {
        UoWExceptionService.requireNonNull(config, 'Serialization config');
        super.prepareForSerialization(config);

        // Determine source events based on masking config
        List<SObject> sourceEvents = this.originalEvents;
        if (config.applyMasking && this.maskedEvents != null && !this.maskedEvents.isEmpty()) {
            sourceEvents = this.maskedEvents;
        }

        if (sourceEvents == null || sourceEvents.isEmpty()) {
            this.snapshots = new List<EventSnapshot>();
            return;
        }

        // Get sampled indices with error-priority
        List<Integer> sampledIndices = UoWSamplingService.sampleIndices(
            sourceEvents.size(),
            this.failedIndices,
            config
        );

        // Build snapshots for sampled indices
        this.snapshots = new List<EventSnapshot>();
        for (Integer idx : sampledIndices) {
            EventSnapshot snap = buildSnapshotForIndex(idx, sourceEvents);
            this.snapshots.add(snap);
        }
    }

    /**
     * Restore transient fields after deserialization.
     * Restores originalEvents from snapshots, and Schema type from name.
     */
    public override void hydrate() {
        super.hydrate();
        // Restore originalEvents from snapshots (for async publishing)
        if (this.originalEvents == null && this.snapshots != null && !this.snapshots.isEmpty()) {
            this.originalEvents = new List<SObject>();
            for (EventSnapshot snap : this.snapshots) {
                this.originalEvents.add(snap.evt);
            }
        }

        // Restore sobjectType from sobjectTypeName
        if (String.isNotBlank(this.sobjectTypeName) && this.sobjectType == null) {
            this.sobjectType = UoWCacheService.getSobjectTypeFromGlobalDescribe(this.sobjectTypeName);
        }
    }

    // ============================================================================
    // PRIVATE METHODS - SNAPSHOT BUILDING
    // ============================================================================

    // Build an EventSnapshot for the given index
    private EventSnapshot buildSnapshotForIndex(Integer idx, List<SObject> sourceEvents) {
        EventSnapshot snap = new EventSnapshot();
        snap.idx = idx;
        snap.evt = sourceEvents[idx];

        // Get result data from publishResults
        if (this.publishResults != null && idx < this.publishResults.size()) {
            Database.SaveResult sr = this.publishResults[idx];
            snap.ok = sr.isSuccess();
            if (!sr.isSuccess()) {
                snap.errs = convertErrors(sr.getErrors());
            }
        }

        return snap;
    }

    // Convert Database.Error list to SnapshotError list
    private List<SnapshotError> convertErrors(List<Database.Error> dbErrors) {
        if (dbErrors == null || dbErrors.isEmpty()) {
            return null;
        }
        List<SnapshotError> result = new List<SnapshotError>();
        for (Database.Error err : dbErrors) {
            result.add(new SnapshotError(err));
        }
        return result;
    }

    // ============================================================================
    // INNER CLASSES - SNAPSHOT
    // ============================================================================

    /**
     * Enriched snapshot pairing an event with its publish result.
     * Used for audit serialization to provide correlation between events and outcomes.
     * Short field names minimize JSON size in LongTextArea storage.
     */
    public class EventSnapshot {
        /** Original index in the events list */
        public Integer idx;

        /** The platform event SObject (may be masked) */
        public SObject evt;

        /** Success status from Database.SaveResult.isSuccess() */
        public Boolean ok;

        /** List of errors for this event (null if successful) */
        public List<SnapshotError> errs;
    }

    /**
     * Lightweight error structure for audit snapshots.
     * Captures essential Database.Error fields with short names for JSON size.
     */
    public class SnapshotError {
        /** StatusCode as string (e.g., 'FIELD_CUSTOM_VALIDATION_EXCEPTION') */
        public String code;

        /** Error message */
        public String msg;

        /** Fields that caused the error (may be null) */
        public List<String> flds;

        /**
         * Create from Database.Error.
         *
         * @param err The Database.Error to capture
         */
        public SnapshotError(Database.Error err) {
            this.code = err.getStatusCode() != null ? String.valueOf(err.getStatusCode()) : null;
            this.msg = err.getMessage();
            List<String> errorFields = err.getFields();
            this.flds = (errorFields != null && !errorFields.isEmpty()) ? errorFields : null;
        }
    }
}