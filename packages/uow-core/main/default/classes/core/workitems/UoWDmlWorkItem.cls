//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * DML work item for database operations (INSERT, UPDATE, UPSERT, DELETE, UNDELETE).
 * Contains records, results, and relationship support.
 *
 * STORAGE PATTERN:
 * - originalRecords (transient): Unmasked original data for DML execution
 * - records (serializable): For async serialization only
 * - maskedRecords (transient): Cached masked version for audit purposes
 * - snapshots (serializable): Enriched audit snapshots pairing records with results
 *
 * Serialization scenarios:
 * - Async execution: records = originalRecords (unmodified for DML)
 * - Audit snapshots: snapshots = enriched RecordSnapshot with error-priority sampling
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Work Items
 * @see UoWWorkItem
 * @see UoWDmlExecutionService
 */
public inherited sharing class UoWDmlWorkItem extends UoWWorkItem {

    // ============================================================================
    // PUBLIC PROPERTIES
    // ============================================================================

    // DML operation type (INSERT_OP, UPDATE_OP, UPSERT_OP, DELETE_OP, UNDELETE_OP)
    public UoWEnums.DmlOperation operation;

    // API name of the SObject type (e.g., 'Account', 'Contact')
    public String sobjectTypeName;

    // External ID field API name for UPSERT operations
    public String externalIdFieldName;

    // ============================================================================
    // PUBLIC PROPERTIES - TRANSIENT (not serialized)
    // ============================================================================

    public transient Schema.SObjectType sobjectType;

    public transient Schema.SObjectField externalIdField;

    public transient List<Database.SaveResult> saveResults;
    public transient List<Database.UpsertResult> upsertResults;
    public transient List<Database.DeleteResult> deleteResults;
    public transient List<Database.UndeleteResult> undeleteResults;

    // ============================================================================
    // PRIVATE PROPERTIES - RECORD STORAGE
    // ============================================================================

    // Enriched snapshots - pairs records with their Database results
    // For async: contains records only (no result data)
    // For audit: contains records + result data with error-priority sampling
    @TestVisible
    private List<RecordSnapshot> snapshots;

    // Original unmasked records for DML execution (transient - restored via hydrate)
    @TestVisible
    private transient List<SObject> originalRecords;

    // Masked records for audit purposes (transient - rebuilt if needed)
    @TestVisible
    private transient List<SObject> maskedRecords;

    // Indices of failed records - populated during processResults()
    @TestVisible
    private transient Set<Integer> failedIndices;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Create a new DML work item for the specified operation.
     *
     * @param op DML operation type (INSERT_OP, UPDATE_OP, UPSERT_OP, DELETE_OP, UNDELETE_OP)
     * @param stype SObjectType of the records
     * @param recs List of records to process
     */
    public UoWDmlWorkItem(UoWEnums.DmlOperation op, Schema.SObjectType stype, List<SObject> recs) {
        super(UoWEnums.WorkType.DML);
        this.operation = op;
        this.sobjectType = stype;
        this.sobjectTypeName = UoWCacheService.getDescribe(stype).getName();
        this.originalRecords = recs ?? new List<SObject>();

        // Use UpsertStatistics for UPSERT operations, base Statistics for others
        if (op == UoWEnums.DmlOperation.UPSERT_OP) {
            this.statistics = new UpsertStatistics();
        }
        this.statistics.planned = this.originalRecords.size();
        this.continueOnError = false;
    }

    // ============================================================================
    // PUBLIC API - FLUENT CONFIGURATION
    // ============================================================================

    /**
     * Allow partial success - continue execution even if some records fail.
     * When enabled, passes allOrNone=false to Database methods.
     *
     * @return This work item for fluent chaining
     */
    public UoWDmlWorkItem continueOnError() {
        this.continueOnError = true;
        return this;
    }

    /**
     * Fail-fast mode - entire operation fails if any record fails.
     * When enabled, passes allOrNone=true to Database methods (default behavior).
     *
     * @return This work item for fluent chaining
     */
    public UoWDmlWorkItem failFast() {
        this.continueOnError = false;
        return this;
    }

    // ============================================================================
    // PUBLIC API - RECORD ACCESSORS
    // ============================================================================

    /**
     * Get snapshots for serialization/audit purposes.
     * Returns enriched snapshots pairing records with their Database results.
     *
     * @return Snapshots prepared for serialization
     */
    public List<RecordSnapshot> getSnapshots() {
        return this.snapshots;
    }

    /**
     * Get original unmasked records for DML execution.
     * Use this when actual data must be persisted to the database.
     * This is the authoritative source for DML operations.
     *
     * @return Original unmasked records
     */
    public List<SObject> getOriginalRecords() {
        return this.originalRecords;
    }

    /**
     * Set masked records after masking service processes them.
     * Cached for use during audit serialization.
     *
     * @param masked The masked records
     */
    public void setMaskedRecords(List<SObject> masked) {
        this.maskedRecords = masked;
    }

    // ============================================================================
    // PUBLIC API - RECORD MANAGEMENT
    // ============================================================================

    /**
     * Add records to this work item for consolidation.
     * Used when multiple registrations of the same SObjectType are combined.
     *
     * @param newRecords Records to add to this work item
     */
    public void addRecords(List<SObject> newRecords) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }
        this.originalRecords.addAll(newRecords);
        this.statistics.planned += newRecords.size();
    }

    // ============================================================================
    // PUBLIC API - RESULT PROCESSING (Override)
    // ============================================================================

    /**
     * Process DML execution results - extract errors and calculate statistics.
     * Single pass through Database.*Result objects to count successes/failures,
     * extract Database.Error objects as ErrorInfo, and track failed indices.
     *
     * Handles two scenarios:
     * - Normal execution: Database.*Result objects exist
     * - Exception thrown: No results, but errors already captured via addError()
     */
    public override void processResults() {
        String operationName = String.valueOf(this.operation);
        this.statistics.processed = this.originalRecords?.size() ?? 0;
        this.statistics.successes = 0;
        this.statistics.failures = 0;
        this.failedIndices = new Set<Integer>();

        Boolean hasResults = this.saveResults != null ||
                            this.upsertResults != null ||
                            this.deleteResults != null ||
                            this.undeleteResults != null;

        // Scenario 2: Exception was thrown before results were populated
        if (!hasResults && this.hasErrors()) {
            this.statistics.failures = this.statistics.processed;
            // Mark all as failed when exception occurred
            for (Integer i = 0; i < this.statistics.processed; i++) {
                this.failedIndices.add(i);
            }
            return;
        }

        // Scenario 1: Normal execution with results
        if (this.saveResults != null) {
            processSaveResults(operationName);
        }

        if (this.upsertResults != null) {
            processUpsertResults(operationName);
        }

        if (this.deleteResults != null) {
            processDeleteResults(operationName);
        }

        if (this.undeleteResults != null) {
            processUndeleteResults(operationName);
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
     * Builds snapshots with records only (no result data).
     * Use this for async Queueable serialization where data must remain intact for DML.
     */
    public override void prepareForSerialization() {
        super.prepareForSerialization();
        // For async: build snapshots with records only (no result data)
        this.snapshots = new List<RecordSnapshot>();
        if (this.originalRecords != null) {
            for (Integer i = 0; i < this.originalRecords.size(); i++) {
                RecordSnapshot snap = new RecordSnapshot();
                snap.idx = i;
                snap.rec = this.originalRecords[i];
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

        // Determine source records based on masking config
        List<SObject> sourceRecords = this.originalRecords;
        if (config.applyMasking && this.maskedRecords != null && !this.maskedRecords.isEmpty()) {
            sourceRecords = this.maskedRecords;
        }

        if (sourceRecords == null || sourceRecords.isEmpty()) {
            this.snapshots = new List<RecordSnapshot>();
            return;
        }

        // Get sampled indices with error-priority
        List<Integer> sampledIndices = UoWSamplingService.sampleIndices(
            sourceRecords.size(),
            this.failedIndices,
            config
        );

        // Build snapshots for sampled indices
        this.snapshots = new List<RecordSnapshot>();
        for (Integer idx : sampledIndices) {
            RecordSnapshot snap = buildSnapshotForIndex(idx, sourceRecords);
            this.snapshots.add(snap);
        }
    }

    /**
     * Restore transient fields after deserialization.
     * Restores originalRecords from snapshots, and Schema types from names.
     */
    public override void hydrate() {
        super.hydrate();
        // Restore originalRecords from snapshots (for async DML execution)
        if (this.originalRecords == null && this.snapshots != null && !this.snapshots.isEmpty()) {
            this.originalRecords = new List<SObject>();
            for (RecordSnapshot snap : this.snapshots) {
                this.originalRecords.add(snap.rec);
            }
        }

        // Restore sobjectType from sobjectTypeName
        if (String.isNotBlank(this.sobjectTypeName) && this.sobjectType == null) {
            this.sobjectType = UoWCacheService.getSobjectTypeFromGlobalDescribe(this.sobjectTypeName);
        }

        // Restore externalIdField from externalIdFieldName (for UPSERT operations)
        if (String.isNotBlank(this.externalIdFieldName) && this.externalIdField == null && this.sobjectType != null) {
            Map<String, Schema.SObjectField> fieldMap = UoWCacheService.getDescribe(this.sobjectType).fields.getMap();
            this.externalIdField = fieldMap.get(this.externalIdFieldName);
        }
    }

    // ============================================================================
    // PRIVATE METHODS - SNAPSHOT BUILDING
    // ============================================================================

    // Build a RecordSnapshot for the given index
    private RecordSnapshot buildSnapshotForIndex(Integer idx, List<SObject> sourceRecords) {
        RecordSnapshot snap = new RecordSnapshot();
        snap.idx = idx;
        snap.rec = sourceRecords[idx];

        // Get result data based on operation type
        if (this.saveResults != null && idx < this.saveResults.size()) {
            Database.SaveResult sr = this.saveResults[idx];
            snap.ok = sr.isSuccess();
            snap.rid = sr.getId();
            if (!sr.isSuccess()) {
                snap.errs = convertErrors(sr.getErrors());
            }
        } else if (this.upsertResults != null && idx < this.upsertResults.size()) {
            Database.UpsertResult ur = this.upsertResults[idx];
            snap.ok = ur.isSuccess();
            snap.rid = ur.getId();
            snap.created = ur.isCreated();
            if (!ur.isSuccess()) {
                snap.errs = convertErrors(ur.getErrors());
            }
        } else if (this.deleteResults != null && idx < this.deleteResults.size()) {
            Database.DeleteResult dr = this.deleteResults[idx];
            snap.ok = dr.isSuccess();
            snap.rid = dr.getId();
            if (!dr.isSuccess()) {
                snap.errs = convertErrors(dr.getErrors());
            }
        } else if (this.undeleteResults != null && idx < this.undeleteResults.size()) {
            Database.UndeleteResult udr = this.undeleteResults[idx];
            snap.ok = udr.isSuccess();
            snap.rid = udr.getId();
            if (!udr.isSuccess()) {
                snap.errs = convertErrors(udr.getErrors());
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
    // PRIVATE METHODS - RESULT PROCESSING
    // ============================================================================

    // Process SaveResult objects and extract errors into statistics
    private void processSaveResults(String operationName) {
        for (Integer i = 0; i < this.saveResults.size(); i++) {
            Database.SaveResult sr = this.saveResults[i];
            if (sr.isSuccess()) {
                this.statistics.successes++;
            } else {
                this.statistics.failures++;
                this.failedIndices.add(i);
                for (Database.Error err : sr.getErrors()) {
                    this.addError(new UoWExceptionService.ErrorInfo(
                        err, i, operationName, this.sobjectTypeName
                    ));
                }
            }
        }
    }

    // Process UpsertResult objects and track inserts vs updates
    private void processUpsertResults(String operationName) {
        UpsertStatistics upsertStats = (UpsertStatistics) this.statistics;
        for (Integer i = 0; i < this.upsertResults.size(); i++) {
            Database.UpsertResult ur = this.upsertResults[i];
            if (ur.isSuccess()) {
                upsertStats.successes++;
                if (ur.isCreated()) {
                    upsertStats.inserts++;
                } else {
                    upsertStats.updates++;
                }
            } else {
                upsertStats.failures++;
                this.failedIndices.add(i);
                for (Database.Error err : ur.getErrors()) {
                    this.addError(new UoWExceptionService.ErrorInfo(
                        err, i, operationName, this.sobjectTypeName
                    ));
                }
            }
        }
    }

    // Process DeleteResult objects and extract errors into statistics
    private void processDeleteResults(String operationName) {
        for (Integer i = 0; i < this.deleteResults.size(); i++) {
            Database.DeleteResult dr = this.deleteResults[i];
            if (dr.isSuccess()) {
                this.statistics.successes++;
            } else {
                this.statistics.failures++;
                this.failedIndices.add(i);
                for (Database.Error err : dr.getErrors()) {
                    this.addError(new UoWExceptionService.ErrorInfo(
                        err, i, operationName, this.sobjectTypeName
                    ));
                }
            }
        }
    }

    // Process UndeleteResult objects and extract errors into statistics
    private void processUndeleteResults(String operationName) {
        for (Integer i = 0; i < this.undeleteResults.size(); i++) {
            Database.UndeleteResult udr = this.undeleteResults[i];
            if (udr.isSuccess()) {
                this.statistics.successes++;
            } else {
                this.statistics.failures++;
                this.failedIndices.add(i);
                for (Database.Error err : udr.getErrors()) {
                    this.addError(new UoWExceptionService.ErrorInfo(
                        err, i, operationName, this.sobjectTypeName
                    ));
                }
            }
        }
    }

    // ============================================================================
    // INNER CLASSES - STATISTICS
    // ============================================================================

    /**
     * Extended statistics for UPSERT operations.
     * Tracks how many records were inserted vs updated.
     */
    public class UpsertStatistics extends UoWWorkItem.Statistics {
        // Number of records that were newly inserted
        public Integer inserts;

        // Number of records that were updated
        public Integer updates;

        /**
         * Initialize upsert statistics with zero counts.
         */
        public UpsertStatistics() {
            super();
            this.inserts = 0;
            this.updates = 0;
        }
    }

    // ============================================================================
    // INNER CLASSES - SNAPSHOT
    // ============================================================================

    /**
     * Enriched snapshot pairing a record with its Database result.
     * Used for audit serialization to provide correlation between records and outcomes.
     * Short field names minimize JSON size in LongTextArea storage.
     */
    public class RecordSnapshot {
        /** Original index in the records list */
        public Integer idx;

        /** The SObject record (may be masked) */
        public SObject rec;

        /** Success status from Database.*Result.isSuccess() */
        public Boolean ok;

        /** Result ID (new ID for insert, existing for update/delete) */
        public Id rid;

        /** For upsert only: was this record created (true) or updated (false)? */
        public Boolean created;

        /** List of errors for this record (null if successful) */
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