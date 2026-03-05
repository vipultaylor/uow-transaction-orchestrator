//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Statistics tracking service for UnitOfWork transactions.
 * Aggregates pre-calculated statistics from work items.
 *
 * Design:
 * - Work items calculate their own stats via processResults()
 * - This tracker aggregates those pre-calculated stats
 * - No duplicate iteration through Database.*Result or Messaging.*Result
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Services
 */
@SuppressWarnings('PMD.CognitiveComplexity')
public inherited sharing class UoWStatisticsTracker {

    // ============================================================================
    // PUBLIC PROPERTIES
    // ============================================================================

    public TransactionStats stats {
        get {
            if (this.stats == null) {
                this.stats = new TransactionStats();
            }
            return this.stats;
        }
        private set;
    }

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    public UoWStatisticsTracker() {
        this.stats = new TransactionStats();
    }

    // ============================================================================
    // PUBLIC API - TRACKING
    // ============================================================================

    /**
     * Track statistics from a work item.
     *
     * @param workItem The work item to track stats from
     */
    public void trackStats(UoWWorkItem workItem){
        switch on workItem.workType {
            when DML {
                this.trackDmlWork((UoWDmlWorkItem) workItem);
            }
            when EVENT {
                this.trackEventWork((UoWEventWorkItem) workItem);
            }
            when EMAIL {
                this.trackEmailWork((UoWEmailWorkItem) workItem);
            }
            when NOTIFICATION {
                this.trackNotificationWork((UoWNotificationWorkItem) workItem);
            }
            when FLOW {
                this.trackFlowWork((UoWFlowWorkItem) workItem);
            }
            when CALLOUT {
                this.trackCalloutWork((UoWCalloutWorkItem) workItem);
            }
        }
    }

    /**
     * Set execution time.
     *
     * @param timeMs Execution time in milliseconds
     */
    public void setExecutionTime(Long timeMs) {
        this.stats.executionTimeMs = timeMs;
    }

    /**
     * Check if there is any successful work.
     *
     * @return True if any work succeeded
     */
    public Boolean hasSuccessfulWork() {
        return this.stats.getTotalSucceeded() > 0;
    }

    // ============================================================================
    // PRIVATE METHODS - DML STATISTICS
    // ============================================================================

    /**
     * Update statistics from DML work item.
     *
     * @param workItem The DML work item to track
     */
    private void trackDmlWork(UoWDmlWorkItem workItem) {
        if(workItem == null) { return; }

        switch on workItem.operation {
            when INSERT_OP {
                this.trackDmlInsertStats(workItem);
            }
            when UPSERT_OP {
                this.trackDmlUpsertStats(workItem);
            }
            when UPDATE_OP {
                this.trackDmlUpdateStats(workItem);
            }
            when DELETE_OP {
                this.trackDmlDeleteStats(workItem);
            }
            when UNDELETE_OP {
                this.trackDmlUndeleteStats(workItem);
            }
        }
    }

    private void trackDmlInsertStats(UoWDmlWorkItem workItem){
        String sObjName = workItem.sobjectTypeName;

        RecordStatistics recordStatsForTypeMap = new RecordStatistics();
        if(this.stats.dmlStats.inserts.byType.containsKey(sObjName)){
            recordStatsForTypeMap = this.stats.dmlStats.inserts.byType.get(sObjName);
        }
        RecordStatistics totalRecordStatsForTypeMap = new RecordStatistics();
        if(this.stats.dmlStats.byType.containsKey(sObjName)){
            totalRecordStatsForTypeMap = this.stats.dmlStats.byType.get(sObjName);
        }

        // Use pre-calculated stats from workItem.processResults()
        Integer processed = workItem.statistics.processed ?? 0;
        Integer successes = workItem.statistics.successes ?? 0;
        Integer failures = workItem.statistics.failures ?? 0;

        this.stats.dmlStats.records.processed += processed;
        this.stats.dmlStats.inserts.records.processed += processed;
        recordStatsForTypeMap.processed += processed;
        totalRecordStatsForTypeMap.processed += processed;

        this.stats.dmlStats.records.successes += successes;
        this.stats.dmlStats.inserts.records.successes += successes;
        recordStatsForTypeMap.successes += successes;
        totalRecordStatsForTypeMap.successes += successes;

        this.stats.dmlStats.records.errors += failures;
        this.stats.dmlStats.inserts.records.errors += failures;
        recordStatsForTypeMap.errors += failures;
        totalRecordStatsForTypeMap.errors += failures;

        //Update maps
        this.stats.dmlStats.inserts.byType.put(sObjName, recordStatsForTypeMap);
        this.stats.dmlStats.byType.put(sObjName, totalRecordStatsForTypeMap);
    }

    private void trackDmlUpsertStats(UoWDmlWorkItem workItem){
        String sObjName = workItem.sobjectTypeName;

        UpsertRecordStatistics recordStatsForTypeMap = new UpsertRecordStatistics();
        if(this.stats.dmlStats.upserts.byType.containsKey(sObjName)){
            recordStatsForTypeMap = this.stats.dmlStats.upserts.byType.get(sObjName);
        }
        RecordStatistics totalRecordStatsForTypeMap = new RecordStatistics();
        if(this.stats.dmlStats.byType.containsKey(sObjName)){
            totalRecordStatsForTypeMap = this.stats.dmlStats.byType.get(sObjName);
        }

        // Use pre-calculated stats from workItem.processResults()
        Integer processed = workItem.statistics.processed ?? 0;
        Integer successes = workItem.statistics.successes ?? 0;
        Integer failures = workItem.statistics.failures ?? 0;

        // Get upsert-specific stats from UpsertStatistics
        UoWDmlWorkItem.UpsertStatistics upsertStats = (UoWDmlWorkItem.UpsertStatistics) workItem.statistics;
        Integer inserts = upsertStats.inserts ?? 0;
        Integer updates = upsertStats.updates ?? 0;

        this.stats.dmlStats.records.processed += processed;
        this.stats.dmlStats.upserts.records.processed += processed;
        recordStatsForTypeMap.processed += processed;
        totalRecordStatsForTypeMap.processed += processed;

        this.stats.dmlStats.records.successes += successes;
        this.stats.dmlStats.upserts.records.successes += successes;
        recordStatsForTypeMap.successes += successes;
        totalRecordStatsForTypeMap.successes += successes;

        // Upsert-specific inserts vs updates
        this.stats.dmlStats.upserts.records.inserts += inserts;
        recordStatsForTypeMap.inserts += inserts;
        this.stats.dmlStats.upserts.records.updates += updates;
        recordStatsForTypeMap.updates += updates;

        this.stats.dmlStats.records.errors += failures;
        this.stats.dmlStats.upserts.records.errors += failures;
        recordStatsForTypeMap.errors += failures;
        totalRecordStatsForTypeMap.errors += failures;

        //Update maps
        this.stats.dmlStats.upserts.byType.put(sObjName, recordStatsForTypeMap);
        this.stats.dmlStats.byType.put(sObjName, totalRecordStatsForTypeMap);
    }

    private void trackDmlUpdateStats(UoWDmlWorkItem workItem){
        String sObjName = workItem.sobjectTypeName;

        RecordStatistics recordStatsForTypeMap = new RecordStatistics();
        if(this.stats.dmlStats.updates.byType.containsKey(sObjName)){
            recordStatsForTypeMap = this.stats.dmlStats.updates.byType.get(sObjName);
        }
        RecordStatistics totalRecordStatsForTypeMap = new RecordStatistics();
        if(this.stats.dmlStats.byType.containsKey(sObjName)){
            totalRecordStatsForTypeMap = this.stats.dmlStats.byType.get(sObjName);
        }

        // Use pre-calculated stats from workItem.processResults()
        Integer processed = workItem.statistics.processed ?? 0;
        Integer successes = workItem.statistics.successes ?? 0;
        Integer failures = workItem.statistics.failures ?? 0;

        this.stats.dmlStats.records.processed += processed;
        this.stats.dmlStats.updates.records.processed += processed;
        recordStatsForTypeMap.processed += processed;
        totalRecordStatsForTypeMap.processed += processed;

        this.stats.dmlStats.records.successes += successes;
        this.stats.dmlStats.updates.records.successes += successes;
        recordStatsForTypeMap.successes += successes;
        totalRecordStatsForTypeMap.successes += successes;

        this.stats.dmlStats.records.errors += failures;
        this.stats.dmlStats.updates.records.errors += failures;
        recordStatsForTypeMap.errors += failures;
        totalRecordStatsForTypeMap.errors += failures;

        //Update maps
        this.stats.dmlStats.updates.byType.put(sObjName, recordStatsForTypeMap);
        this.stats.dmlStats.byType.put(sObjName, totalRecordStatsForTypeMap);
    }

    private void trackDmlDeleteStats(UoWDmlWorkItem workItem){
        String sObjName = workItem.sobjectTypeName;

        RecordStatistics recordStatsForTypeMap = new RecordStatistics();
        if(this.stats.dmlStats.deletes.byType.containsKey(sObjName)){
            recordStatsForTypeMap = this.stats.dmlStats.deletes.byType.get(sObjName);
        }
        RecordStatistics totalRecordStatsForTypeMap = new RecordStatistics();
        if(this.stats.dmlStats.byType.containsKey(sObjName)){
            totalRecordStatsForTypeMap = this.stats.dmlStats.byType.get(sObjName);
        }

        // Use pre-calculated stats from workItem.processResults()
        Integer processed = workItem.statistics.processed ?? 0;
        Integer successes = workItem.statistics.successes ?? 0;
        Integer failures = workItem.statistics.failures ?? 0;

        this.stats.dmlStats.records.processed += processed;
        this.stats.dmlStats.deletes.records.processed += processed;
        recordStatsForTypeMap.processed += processed;
        totalRecordStatsForTypeMap.processed += processed;

        this.stats.dmlStats.records.successes += successes;
        this.stats.dmlStats.deletes.records.successes += successes;
        recordStatsForTypeMap.successes += successes;
        totalRecordStatsForTypeMap.successes += successes;

        this.stats.dmlStats.records.errors += failures;
        this.stats.dmlStats.deletes.records.errors += failures;
        recordStatsForTypeMap.errors += failures;
        totalRecordStatsForTypeMap.errors += failures;

        //Update maps
        this.stats.dmlStats.deletes.byType.put(sObjName, recordStatsForTypeMap);
        this.stats.dmlStats.byType.put(sObjName, totalRecordStatsForTypeMap);
    }

    private void trackDmlUndeleteStats(UoWDmlWorkItem workItem){
        String sObjName = workItem.sobjectTypeName;

        RecordStatistics recordStatsForTypeMap = new RecordStatistics();
        if(this.stats.dmlStats.undeletes.byType.containsKey(sObjName)){
            recordStatsForTypeMap = this.stats.dmlStats.undeletes.byType.get(sObjName);
        }
        RecordStatistics totalRecordStatsForTypeMap = new RecordStatistics();
        if(this.stats.dmlStats.byType.containsKey(sObjName)){
            totalRecordStatsForTypeMap = this.stats.dmlStats.byType.get(sObjName);
        }

        // Use pre-calculated stats from workItem.processResults()
        Integer processed = workItem.statistics.processed ?? 0;
        Integer successes = workItem.statistics.successes ?? 0;
        Integer failures = workItem.statistics.failures ?? 0;

        this.stats.dmlStats.records.processed += processed;
        this.stats.dmlStats.undeletes.records.processed += processed;
        recordStatsForTypeMap.processed += processed;
        totalRecordStatsForTypeMap.processed += processed;

        this.stats.dmlStats.records.successes += successes;
        this.stats.dmlStats.undeletes.records.successes += successes;
        recordStatsForTypeMap.successes += successes;
        totalRecordStatsForTypeMap.successes += successes;

        this.stats.dmlStats.records.errors += failures;
        this.stats.dmlStats.undeletes.records.errors += failures;
        recordStatsForTypeMap.errors += failures;
        totalRecordStatsForTypeMap.errors += failures;

        //Update maps
        this.stats.dmlStats.undeletes.byType.put(sObjName, recordStatsForTypeMap);
        this.stats.dmlStats.byType.put(sObjName, totalRecordStatsForTypeMap);
    }

    // ============================================================================
    // PRIVATE METHODS - EVENT STATISTICS
    // ============================================================================

    /**
     * Update statistics from event work item using pre-calculated stats.
     *
     * @param workItem The event work item to track
     */
    private void trackEventWork(UoWEventWorkItem workItem) {
        if (workItem == null) { return; }

        String eventTypeName = workItem.sobjectTypeName;

        EventPublishStatistics eventStatsForTypeMap = new EventPublishStatistics();
        if(this.stats.eventStats.byType.containsKey(eventTypeName)){
            eventStatsForTypeMap = this.stats.eventStats.byType.get(eventTypeName);
        }

        // Use pre-calculated stats from workItem.processResults()
        Integer processed = workItem.statistics.processed ?? 0;
        Integer successes = workItem.statistics.successes ?? 0;
        Integer failures = workItem.statistics.failures ?? 0;

        this.stats.eventStats.events.processed += processed;
        eventStatsForTypeMap.processed += processed;

        this.stats.eventStats.events.published += successes;
        eventStatsForTypeMap.published += successes;

        this.stats.eventStats.events.errors += failures;
        eventStatsForTypeMap.errors += failures;

        //Update map
        this.stats.eventStats.byType.put(eventTypeName, eventStatsForTypeMap);
    }

    // ============================================================================
    // PRIVATE METHODS - EMAIL STATISTICS
    // ============================================================================

    /**
     * Update statistics from email work item using pre-calculated stats.
     *
     * @param workItem The email work item to track
     */
    public void trackEmailWork(UoWEmailWorkItem workItem) {
        if (workItem == null) { return; }

        // Use pre-calculated stats from workItem.processResults()
        Integer processed = workItem.statistics.processed ?? 0;
        Integer successes = workItem.statistics.successes ?? 0;
        Integer failures = workItem.statistics.failures ?? 0;

        this.stats.emailStats.emails.processed += processed;
        this.stats.emailStats.emails.sent += successes;
        this.stats.emailStats.emails.errors += failures;
    }

    // ============================================================================
    // PRIVATE METHODS - NOTIFICATION STATISTICS
    // ============================================================================

    /**
     * Update statistics from notification work item using pre-calculated stats.
     *
     * @param workItem The notification work item to track
     */
    private void trackNotificationWork(UoWNotificationWorkItem workItem) {
        if (workItem == null) { return; }

        // Use pre-calculated stats from workItem.processResults()
        Integer processed = workItem.statistics.processed ?? 0;
        Integer successes = workItem.statistics.successes ?? 0;
        Integer failures = workItem.statistics.failures ?? 0;

        this.stats.notificationStats.notifications.processed += processed;
        this.stats.notificationStats.notifications.sent += successes;
        this.stats.notificationStats.notifications.errors += failures;
    }

    // ============================================================================
    // PRIVATE METHODS - FLOW STATISTICS
    // ============================================================================

    /**
     * Update statistics from flow work item using pre-calculated stats.
     *
     * @param workItem The flow work item to track
     */
    public void trackFlowWork(UoWFlowWorkItem workItem) {
        if (workItem == null) { return; }

        // Use pre-calculated stats from workItem.processResults()
        Integer processed = workItem.statistics.processed ?? 0;
        Integer successes = workItem.statistics.successes ?? 0;
        Integer failures = workItem.statistics.failures ?? 0;

        this.stats.flowStats.flows.processed += processed;
        this.stats.flowStats.flows.executed += successes;
        this.stats.flowStats.flows.errors += failures;
    }

    // ============================================================================
    // PRIVATE METHODS - CALLOUT STATISTICS
    // ============================================================================

    /**
     * Update statistics from callout work item using pre-calculated stats.
     *
     * @param workItem The callout work item to track
     */
    public void trackCalloutWork(UoWCalloutWorkItem workItem) {
        if (workItem == null) { return; }

        // Use pre-calculated stats from workItem.processResults()
        Integer processed = workItem.statistics.processed ?? 0;
        Integer successes = workItem.statistics.successes ?? 0;
        Integer failures = workItem.statistics.failures ?? 0;

        this.stats.calloutStats.callouts.processed += processed;
        this.stats.calloutStats.callouts.executed += successes;
        this.stats.calloutStats.callouts.errors += failures;
    }

    // ============================================================================
    // INNER CLASSES - TRANSACTION STATS
    // ============================================================================

    /**
     * Transaction statistics and metrics for UnitOfWork execution.
     * Tracks DML operations, events, emails, and execution time.
     */
    public class TransactionStats {

        // ============================================================================
        // PUBLIC PROPERTIES - WORK TYPE STATS
        // ============================================================================

        public DmlStatistics dmlStats;
        public EventStatistics eventStats;
        public EmailStatistics emailStats;
        public NotificationStatistics notificationStats;
        public FlowStatistics flowStats;
        public CalloutStatistics calloutStats;

        // ============================================================================
        // PUBLIC PROPERTIES - TIMING
        // ============================================================================

        public Long executionTimeMs;

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        /**
         * Constructor - initializes all counters to zero.
         */
        public TransactionStats() {
            this.dmlStats = new DmlStatistics();
            this.eventStats = new EventStatistics();
            this.emailStats = new EmailStatistics();
            this.notificationStats = new NotificationStatistics();
            this.flowStats = new FlowStatistics();
            this.calloutStats = new CalloutStatistics();

            this.executionTimeMs = 0;
        }

        // ============================================================================
        // PUBLIC API - FORMATTED OUTPUT
        // ============================================================================

        /**
         * Get formatted execution time.
         *
         * @return Formatted duration string
         */
        public String getFormattedExecutionTime() {
            return UoWUtils.formatDuration(executionTimeMs);
        }

        // ============================================================================
        // PUBLIC API - AGGREGATE COUNTS
        // ============================================================================

        /**
         * Get total processed count across all work types.
         *
         * @return Total number of items processed
         */
        public Integer getTotalProcessed() {
            return this.dmlStats.records.processed +
                   this.eventStats.events.processed +
                   this.emailStats.emails.processed +
                   this.notificationStats.notifications.processed +
                   this.flowStats.flows.processed +
                   this.calloutStats.callouts.processed;
        }

        /**
         * Get total succeeded count across all work types.
         *
         * @return Total number of items that succeeded
         */
        public Integer getTotalSucceeded() {
            return this.dmlStats.records.successes +
                   this.eventStats.events.published +
                   this.emailStats.emails.sent +
                   this.notificationStats.notifications.sent +
                   this.flowStats.flows.executed +
                   this.calloutStats.callouts.executed;
        }

        /**
         * Get total failed count across all work types.
         *
         * @return Total number of items that failed
         */
        public Integer getTotalFailed() {
            return this.dmlStats.records.errors +
                   this.eventStats.events.errors +
                   this.emailStats.emails.errors +
                   this.notificationStats.notifications.errors +
                   this.flowStats.flows.errors +
                   this.calloutStats.callouts.errors;
        }
    }

    // ============================================================================
    // INNER CLASSES - DML STATISTICS
    // ============================================================================

    /**
     * DML statistics container.
     */
    public class DmlStatistics {

        // ============================================================================
        // PUBLIC PROPERTIES
        // ============================================================================

        public RecordStatistics records;
        public Map<String, RecordStatistics> byType;

        public DmlInsertStatistics inserts;
        public DmlUpsertStatistics upserts;
        public DmlUpdateStatistics updates;
        public DmlDeleteStatistics deletes;
        public DmlUndeleteStatistics undeletes;

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public DmlStatistics(){
            this.records = new RecordStatistics();
            this.byType = new Map<String, RecordStatistics>();

            this.inserts = new DmlInsertStatistics();
            this.upserts = new DmlUpsertStatistics();
            this.updates = new DmlUpdateStatistics();
            this.deletes = new DmlDeleteStatistics();
            this.undeletes = new DmlUndeleteStatistics();
        }
    }

    /**
     * DML insert statistics.
     */
    public class DmlInsertStatistics {

        // ============================================================================
        // PUBLIC PROPERTIES
        // ============================================================================

        public RecordStatistics records;
        public Map<String, RecordStatistics> byType;

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public DmlInsertStatistics(){
            this.records = new RecordStatistics();
            this.byType = new Map<String, RecordStatistics>();
        }
    }

    /**
     * DML upsert statistics.
     */
    public class DmlUpsertStatistics {

        // ============================================================================
        // PUBLIC PROPERTIES
        // ============================================================================

        public UpsertRecordStatistics records;
        public Map<String, UpsertRecordStatistics> byType;

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public DmlUpsertStatistics(){
            this.records = new UpsertRecordStatistics();
            this.byType = new Map<String, UpsertRecordStatistics>();
        }
    }

    /**
     * DML update statistics.
     */
    public class DmlUpdateStatistics {

        // ============================================================================
        // PUBLIC PROPERTIES
        // ============================================================================

        public RecordStatistics records;
        public Map<String, RecordStatistics> byType;

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public DmlUpdateStatistics(){
            this.records = new RecordStatistics();
            this.byType = new Map<String, RecordStatistics>();
        }
    }

    /**
     * DML delete statistics.
     */
    public class DmlDeleteStatistics {

        // ============================================================================
        // PUBLIC PROPERTIES
        // ============================================================================

        public RecordStatistics records;
        public Map<String, RecordStatistics> byType;

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public DmlDeleteStatistics(){
            this.records = new RecordStatistics();
            this.byType = new Map<String, RecordStatistics>();
        }
    }

    /**
     * DML undelete statistics.
     */
    public class DmlUndeleteStatistics {

        // ============================================================================
        // PUBLIC PROPERTIES
        // ============================================================================

        public RecordStatistics records;
        public Map<String, RecordStatistics> byType;

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public DmlUndeleteStatistics(){
            this.records = new RecordStatistics();
            this.byType = new Map<String, RecordStatistics>();
        }
    }

    // ============================================================================
    // INNER CLASSES - RECORD STATISTICS
    // ============================================================================

    /**
     * Basic record statistics.
     */
    public class RecordStatistics {

        // ============================================================================
        // PUBLIC PROPERTIES
        // ============================================================================

        public Integer processed;
        public Integer successes;
        public Integer errors;

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public RecordStatistics(){
            this.processed = 0;
            this.successes = 0;
            this.errors = 0;
        }
    }

    /**
     * Upsert-specific record statistics with insert/update breakdown.
     */
    public class UpsertRecordStatistics {

        // ============================================================================
        // PUBLIC PROPERTIES
        // ============================================================================

        public Integer processed;
        public Integer successes;
        public Integer inserts;
        public Integer updates;
        public Integer errors;

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public UpsertRecordStatistics(){
            this.processed = 0;
            this.successes = 0;
            this.inserts = 0;
            this.updates = 0;
            this.errors = 0;
        }
    }

    // ============================================================================
    // INNER CLASSES - EVENT STATISTICS
    // ============================================================================

    /**
     * Event statistics container.
     */
    public class EventStatistics {

        // ============================================================================
        // PUBLIC PROPERTIES
        // ============================================================================

        public EventPublishStatistics events;
        public Map<String, EventPublishStatistics> byType;

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public EventStatistics(){
            this.events = new EventPublishStatistics();
            this.byType = new Map<String, EventPublishStatistics>();
        }
    }

    /**
     * Event publish statistics.
     */
    public class EventPublishStatistics {

        // ============================================================================
        // PUBLIC PROPERTIES
        // ============================================================================

        public Integer processed;
        public Integer published;
        public Integer errors;

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public EventPublishStatistics(){
            this.processed = 0;
            this.published = 0;
            this.errors = 0;
        }
    }

    // ============================================================================
    // INNER CLASSES - EMAIL STATISTICS
    // ============================================================================

    /**
     * Email statistics container.
     */
    public class EmailStatistics {

        // ============================================================================
        // PUBLIC PROPERTIES
        // ============================================================================

        public EmailSendStatistics emails;

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public EmailStatistics(){
            this.emails = new EmailSendStatistics();
        }
    }

    /**
     * Email send statistics.
     */
    public class EmailSendStatistics {

        // ============================================================================
        // PUBLIC PROPERTIES
        // ============================================================================

        public Integer processed;
        public Integer sent;
        public Integer errors;

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public EmailSendStatistics(){
            this.processed = 0;
            this.sent = 0;
            this.errors = 0;
        }
    }

    // ============================================================================
    // INNER CLASSES - NOTIFICATION STATISTICS
    // ============================================================================

    /**
     * Notification statistics container.
     */
    public class NotificationStatistics {

        // ============================================================================
        // PUBLIC PROPERTIES
        // ============================================================================

        public NotificationSendStatistics notifications;

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public NotificationStatistics(){
            this.notifications = new NotificationSendStatistics();
        }
    }

    /**
     * Notification send statistics.
     */
    public class NotificationSendStatistics {

        // ============================================================================
        // PUBLIC PROPERTIES
        // ============================================================================

        public Integer processed;
        public Integer sent;
        public Integer errors;

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public NotificationSendStatistics(){
            this.processed = 0;
            this.sent = 0;
            this.errors = 0;
        }
    }

    // ============================================================================
    // INNER CLASSES - FLOW STATISTICS
    // ============================================================================

    /**
     * Flow statistics container.
     */
    public class FlowStatistics {

        // ============================================================================
        // PUBLIC PROPERTIES
        // ============================================================================

        public FlowExecutionStatistics flows;

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public FlowStatistics(){
            this.flows = new FlowExecutionStatistics();
        }
    }

    /**
     * Flow execution statistics.
     */
    public class FlowExecutionStatistics {

        // ============================================================================
        // PUBLIC PROPERTIES
        // ============================================================================

        public Integer processed;
        public Integer executed;
        public Integer errors;

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public FlowExecutionStatistics(){
            this.processed = 0;
            this.executed = 0;
            this.errors = 0;
        }
    }

    // ============================================================================
    // INNER CLASSES - CALLOUT STATISTICS
    // ============================================================================

    /**
     * Callout statistics container.
     */
    public class CalloutStatistics {

        // ============================================================================
        // PUBLIC PROPERTIES
        // ============================================================================

        public CalloutExecutionStatistics callouts;

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public CalloutStatistics(){
            this.callouts = new CalloutExecutionStatistics();
        }
    }

    /**
     * Callout execution statistics.
     */
    public class CalloutExecutionStatistics {

        // ============================================================================
        // PUBLIC PROPERTIES
        // ============================================================================

        public Integer processed;
        public Integer executed;
        public Integer errors;

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public CalloutExecutionStatistics(){
            this.processed = 0;
            this.executed = 0;
            this.errors = 0;
        }
    }
}