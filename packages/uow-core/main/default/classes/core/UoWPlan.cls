//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Represents the execution plan for a UnitOfWork transaction.
 * Contains all registered operations to be executed.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Core
 * @see UnitOfWork
 */
public inherited sharing class UoWPlan {

    // ============================================================================
    // PROPERTIES - METADATA
    // ============================================================================

    public DateTime createdAt { get; private set; }

    // ============================================================================
    // PRIVATE FIELDS - DML WORK
    // Using String keys (sobjectTypeName) for serialization compatibility.
    // Schema.SObjectType cannot be used as Map keys in JSON serialization.
    // ============================================================================

    private Map<String, UoWDmlWorkItem> insertWork;
    private Map<String, UoWDmlWorkItem> updateWork;
    private Map<String, UoWDmlWorkItem> upsertWork;
    private Map<String, UoWDmlWorkItem> deleteWork;
    private Map<String, UoWDmlWorkItem> undeleteWork;

    // ============================================================================
    // PRIVATE FIELDS - OTHER WORK TYPES
    // Using String keys (sobjectTypeName) for serialization compatibility.
    // ============================================================================

    private Map<UoWEnums.WorkPhase, Map<String, UoWEventWorkItem>> eventWork;
    private Map<UoWEnums.WorkPhase, UoWEmailWorkItem> emailWork;
    private Map<UoWEnums.WorkPhase, List<UoWFlowWorkItem>> flowWork;
    private Map<UoWEnums.WorkPhase, List<UoWNotificationWorkItem>> notificationWork;
    private Map<UoWEnums.WorkPhase, List<UoWCalloutWorkItem>> calloutWork;

    // ============================================================================
    // PRIVATE FIELDS - RELATIONSHIPS & STATISTICS
    // ============================================================================

    private Map<String, UoWRelationship> relationships;
    // PERFORMANCE: Track pending relationships BY PARENT TYPE to avoid iterating all relationships.
    // Key = parent SObject type name, Value = Set of relationship keys for that parent type.
    // When a parent type is inserted, we only iterate relationships for that specific parent type.
    private Map<String, Set<String>> pendingRelationshipsByParentType;
    private Integer totalWorkItems;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    public UoWPlan() {
        this.createdAt = DateTime.now();

        // Initialize DML work maps (String keys = sobjectTypeName for serialization)
        this.insertWork = new Map<String, UoWDmlWorkItem>();
        this.updateWork = new Map<String, UoWDmlWorkItem>();
        this.upsertWork = new Map<String, UoWDmlWorkItem>();
        this.deleteWork = new Map<String, UoWDmlWorkItem>();
        this.undeleteWork = new Map<String, UoWDmlWorkItem>();

        // Initialize other work types (String keys = sobjectTypeName for serialization)
        this.eventWork = new Map<UoWEnums.WorkPhase, Map<String, UoWEventWorkItem>>();
        this.emailWork = new Map<UoWEnums.WorkPhase, UoWEmailWorkItem>();
        this.flowWork = new Map<UoWEnums.WorkPhase, List<UoWFlowWorkItem>>();
        this.notificationWork = new Map<UoWEnums.WorkPhase, List<UoWNotificationWorkItem>>();
        this.calloutWork = new Map<UoWEnums.WorkPhase, List<UoWCalloutWorkItem>>();

        // Initialize relationships
        this.relationships = new Map<String, UoWRelationship>();
        this.pendingRelationshipsByParentType = new Map<String, Set<String>>();
        this.totalWorkItems = 0;
    }

    /**
     * Restore plan metadata from serialized data.
     * Used during deserialization to preserve original createdAt.
     *
     * @param originalCreatedAt The original creation timestamp
     */
    public void restoreMetadata(DateTime originalCreatedAt) {
        if (originalCreatedAt != null) {
            this.createdAt = originalCreatedAt;
        }
    }

    // ============================================================================
    // PUBLIC API - PLAN STATUS
    // ============================================================================

    /**
     * Check if plan is empty.
     *
     * @return True if no work items registered
     */
    public Boolean isEmpty() {
        return totalWorkItems == 0;
    }

    /**
     * Check if plan has DML work.
     *
     * @return True if any DML operations registered
     */
    public Boolean hasDmlWork() {
        return !insertWork.isEmpty() ||
               !updateWork.isEmpty() ||
               !upsertWork.isEmpty() ||
               !deleteWork.isEmpty() ||
               !undeleteWork.isEmpty();
    }

    /**
     * Check if plan has callouts (any phase).
     *
     * @return True if callout work items registered for any phase
     */
    public Boolean hasCallouts() {
        for (List<UoWCalloutWorkItem> phaseCallouts : calloutWork.values()) {
            if (phaseCallouts != null && !phaseCallouts.isEmpty()) {
                return true;
            }
        }
        return false;
    }

    /**
     * Check if plan has callouts for a specific phase.
     *
     * @param phase The execution phase to check
     * @return True if callout work items registered for this phase
     */
    public Boolean hasCalloutsForPhase(UoWEnums.WorkPhase phase) {
        List<UoWCalloutWorkItem> phaseCallouts = calloutWork.get(phase);
        return phaseCallouts != null && !phaseCallouts.isEmpty();
    }

    /**
     * Get total planned record count across all work items.
     *
     * @return Total count of records/items planned for execution
     */
    public Integer getTotalPlannedRecordCount() {
        Integer count = 0;

        for (UoWDmlWorkItem item : getPlannedDmlWork()) {
            count += item.getOriginalRecords().size();
        }
        for (UoWEventWorkItem item : getPlannedEventWork()) {
            count += item.getOriginalEvents().size();
        }

        count += getPlannedEmailWork().size();
        count += getPlannedNotificationWork().size();
        count += getPlannedFlowWork().size();
        count += getPlannedCalloutWork().size();

        return count;
    }

    /**
     * Get count of work items registered for a specific phase.
     * Counts events, emails, notifications, and flows for the given phase.
     *
     * @param phase The work phase to count items for
     * @return Number of work items registered for the phase
     */
    public Integer getWorkItemCountForPhase(UoWEnums.WorkPhase phase) {
        Integer count = 0;

        // Events for this phase
        List<UoWEventWorkItem> events = getEventWork(phase);
        if (events != null) {
            count += events.size();
        }

        // Email for this phase (single work item per phase)
        if (getEmailWork(phase) != null) {
            count += 1;
        }

        // Notifications for this phase
        List<UoWNotificationWorkItem> notifications = getNotificationWork(phase);
        if (notifications != null) {
            count += notifications.size();
        }

        // Flows for this phase
        List<UoWFlowWorkItem> flows = getFlowWork(phase);
        if (flows != null) {
            count += flows.size();
        }

        return count;
    }

    // ============================================================================
    // PUBLIC API - DML WORK GETTERS
    // ============================================================================

    /**
     * Get all planned insert work items.
     *
     * @return List of planned insert work items
     */
    public List<UoWDmlWorkItem> getPlannedInsertWork() {
        return insertWork.values();
    }

    // Get planned insert work by type name (direct map lookup - PERFORMANCE)
    public UoWDmlWorkItem getPlannedInsertWork(String typeName) {
        return insertWork.get(typeName);
    }

    // Get all planned update work items
    public List<UoWDmlWorkItem> getPlannedUpdateWork() {
        return updateWork.values();
    }

    // Get planned update work by type name (direct map lookup - PERFORMANCE)
    public UoWDmlWorkItem getPlannedUpdateWork(String typeName) {
        return updateWork.get(typeName);
    }

    // Get all planned upsert work items
    public List<UoWDmlWorkItem> getPlannedUpsertWork() {
        return upsertWork.values();
    }

    // Get planned upsert work by type name (direct map lookup - PERFORMANCE)
    public UoWDmlWorkItem getPlannedUpsertWork(String typeName) {
        return upsertWork.get(typeName);
    }

    // Get all planned delete work items
    public List<UoWDmlWorkItem> getPlannedDeleteWork() {
        return deleteWork.values();
    }

    // Get planned delete work by type name (direct map lookup - PERFORMANCE)
    public UoWDmlWorkItem getPlannedDeleteWork(String typeName) {
        return deleteWork.get(typeName);
    }

    // Get all planned undelete work items
    public List<UoWDmlWorkItem> getPlannedUndeleteWork() {
        return undeleteWork.values();
    }

    // Get planned undelete work by type name (direct map lookup - PERFORMANCE)
    public UoWDmlWorkItem getPlannedUndeleteWork(String typeName) {
        return undeleteWork.get(typeName);
    }

    /**
     * Get all planned DML work items.
     * Use this to see what DML operations were registered (intent).
     * After execution, use result.getAllDmlWork() for outcomes.
     *
     * @return List of all planned DML work items
     */
    public List<UoWDmlWorkItem> getPlannedDmlWork() {
        List<UoWDmlWorkItem> allWork = new List<UoWDmlWorkItem>();
        allWork.addAll(getPlannedInsertWork());
        allWork.addAll(getPlannedUpsertWork());
        allWork.addAll(getPlannedUpdateWork());
        allWork.addAll(getPlannedDeleteWork());
        allWork.addAll(getPlannedUndeleteWork());
        return allWork;
    }

    // ============================================================================
    // PUBLIC API - EVENT WORK GETTERS
    // ============================================================================

    /**
     * Get event work for a specific phase.
     *
     * @param phase The execution phase
     * @return List of event work items for this phase (one per SObjectType)
     */
    public List<UoWEventWorkItem> getEventWork(UoWEnums.WorkPhase phase) {
        Map<String, UoWEventWorkItem> phaseEvents = eventWork.get(phase);
        return phaseEvents?.values() ?? new List<UoWEventWorkItem>();
    }

    /**
     * Get all planned event work across all phases.
     * Use this to see what events were registered (intent).
     * After execution, use result.getAllEventWork() for outcomes.
     *
     * @return List of all planned event work items
     */
    public List<UoWEventWorkItem> getPlannedEventWork() {
        List<UoWEventWorkItem> flattened = new List<UoWEventWorkItem>();
        for (Map<String, UoWEventWorkItem> phaseEvents : eventWork.values()) {
            if (phaseEvents != null) {
                flattened.addAll(phaseEvents.values());
            }
        }
        return flattened;
    }

    // ============================================================================
    // PUBLIC API - EMAIL WORK GETTERS
    // ============================================================================

    /**
     * Get email work for a specific phase.
     *
     * @param phase The execution phase
     * @return Single email work item for this phase
     */
    public UoWEmailWorkItem getEmailWork(UoWEnums.WorkPhase phase) {
        return emailWork.get(phase);
    }

    /**
     * Get all planned email work across all phases.
     * Use this to see what emails were registered (intent).
     * After execution, use result.getAllEmailWork() for outcomes.
     *
     * @return List of all planned email work items
     */
    public List<UoWEmailWorkItem> getPlannedEmailWork() {
        return emailWork.values();
    }

    // ============================================================================
    // PUBLIC API - FLOW WORK GETTERS
    // ============================================================================

    /**
     * Get flow work by phase.
     *
     * @param phase The execution phase
     * @return List of flow work items for this phase
     */
    public List<UoWFlowWorkItem> getFlowWork(UoWEnums.WorkPhase phase) {
        return flowWork.get(phase);
    }

    /**
     * Get all planned flow work across all phases.
     * Use this to see what flows were registered (intent).
     * After execution, use result.getAllFlowWork() for outcomes.
     *
     * @return List of all planned flow work items
     */
    public List<UoWFlowWorkItem> getPlannedFlowWork() {
        List<UoWFlowWorkItem> flattened = new List<UoWFlowWorkItem>();
        for (List<UoWFlowWorkItem> items : flowWork.values()) {
            if (items != null) {
                flattened.addAll(items);
            }
        }
        return flattened;
    }

    // ============================================================================
    // PUBLIC API - NOTIFICATION WORK GETTERS
    // ============================================================================

    /**
     * Get notification work by phase.
     *
     * @param phase The execution phase
     * @return List of notification work items for this phase
     */
    public List<UoWNotificationWorkItem> getNotificationWork(UoWEnums.WorkPhase phase) {
        return notificationWork.get(phase);
    }

    /**
     * Get all planned notification work across all phases.
     * Use this to see what notifications were registered (intent).
     * After execution, use result.getAllNotificationWork() for outcomes.
     *
     * @return List of all planned notification work items
     */
    public List<UoWNotificationWorkItem> getPlannedNotificationWork() {
        List<UoWNotificationWorkItem> flattened = new List<UoWNotificationWorkItem>();
        for (List<UoWNotificationWorkItem> items : notificationWork.values()) {
            if (items != null) {
                flattened.addAll(items);
            }
        }
        return flattened;
    }

    // ============================================================================
    // PUBLIC API - CALLOUT WORK GETTERS
    // ============================================================================

    /**
     * Get callout work for a specific phase.
     *
     * @param phase The execution phase (PRE_DML or ON_FAILURE)
     * @return List of callout work items for this phase
     */
    public List<UoWCalloutWorkItem> getCalloutWork(UoWEnums.WorkPhase phase) {
        List<UoWCalloutWorkItem> phaseCallouts = calloutWork.get(phase);
        return phaseCallouts ?? new List<UoWCalloutWorkItem>();
    }

    /**
     * Get all planned callout work across all phases.
     * Use this to see what callouts were registered (intent).
     * After execution, use result.getAllCalloutWork() for outcomes.
     *
     * @return List of all planned callout work items
     */
    public List<UoWCalloutWorkItem> getPlannedCalloutWork() {
        List<UoWCalloutWorkItem> flattened = new List<UoWCalloutWorkItem>();
        for (List<UoWCalloutWorkItem> phaseCallouts : calloutWork.values()) {
            if (phaseCallouts != null) {
                flattened.addAll(phaseCallouts);
            }
        }
        return flattened;
    }

    // ============================================================================
    // PUBLIC API - AGGREGATE GETTERS
    // ============================================================================

    /**
     * Get all planned work items across all types in canonical order.
     * Canonical order: DML → EVENT → EMAIL → NOTIFICATION → FLOW → CALLOUT
     * Use this to see what work was registered (intent).
     * After execution, use result.getAllWorkItems() for outcomes.
     *
     * @return List of all planned work items (as base UoWWorkItem type)
     */
    public List<UoWWorkItem> getPlannedWorkItems() {
        List<UoWWorkItem> allWork = new List<UoWWorkItem>();
        allWork.addAll(getPlannedDmlWork());
        allWork.addAll(getPlannedEventWork());
        allWork.addAll(getPlannedEmailWork());
        allWork.addAll(getPlannedNotificationWork());
        allWork.addAll(getPlannedFlowWork());
        allWork.addAll(getPlannedCalloutWork());
        return allWork;
    }

    // ============================================================================
    // PUBLIC API - RELATIONSHIP GETTERS
    // ============================================================================

    /**
     * Get all registered relationships.
     *
     * @return List of all relationships
     */
    public List<UoWRelationship> getRelationships() {
        return relationships.values();
    }

    // ============================================================================
    // PUBLIC API - DML WORK REGISTRATION
    // ============================================================================

    /**
     * Register DML work - returns the actual work item in the plan.
     * When consolidating records into an existing work item, returns the existing item
     * so fluent API calls (continueOnError, failFast) modify the correct instance.
     *
     * @param workItem DML work item
     * @return The actual work item in the plan (may be existing if consolidated)
     */
    public UoWDmlWorkItem registerDmlWork(UoWDmlWorkItem workItem) {
        UoWExceptionService.requireNonNull(workItem, 'Work item');

        Map<String, UoWDmlWorkItem> workMap;

        switch on workItem.operation {
            when INSERT_OP {
                workMap = insertWork;
            }
            when UPDATE_OP {
                workMap = updateWork;
            }
            when UPSERT_OP {
                workMap = upsertWork;
            }
            when DELETE_OP {
                workMap = deleteWork;
            }
            when UNDELETE_OP {
                workMap = undeleteWork;
            }
            when else {
                throw new UoWExceptionService.UoWException('Unknown DML operation: ' + workItem.operation);
            }
        }

        return addDmlWork(workMap, workItem);
    }

    // ============================================================================
    // PUBLIC API - EVENT WORK REGISTRATION
    // ============================================================================

    /**
     * Register event work - consolidates by Phase + SObjectType.
     * EventBus.publish() requires same SObjectType, so we consolidate events inside WorkItem.
     * Returns the actual work item in the plan for fluent API chaining.
     *
     * @param workItem Event work item
     * @return The actual work item in the plan (existing if consolidated, new if first registration)
     */
    public UoWEventWorkItem registerEventWork(UoWEventWorkItem workItem) {
        UoWExceptionService.requireNonNull(workItem, 'Work item');
        List<SObject> events = workItem.getOriginalEvents();
        UoWExceptionService.require(events != null && !events.isEmpty(),
            'Event work item must have at least one event');

        // Use sobjectTypeName as key for serialization compatibility
        String eventTypeName = workItem.sobjectTypeName;

        if (!eventWork.containsKey(workItem.executionPhase)) {
            eventWork.put(workItem.executionPhase, new Map<String, UoWEventWorkItem>());
        }

        Map<String, UoWEventWorkItem> phaseEvents = eventWork.get(workItem.executionPhase);

        if (phaseEvents.containsKey(eventTypeName)) {
            UoWEventWorkItem existingWorkItem = phaseEvents.get(eventTypeName);
            existingWorkItem.addEvents(events);
            return existingWorkItem;
        } else {
            phaseEvents.put(eventTypeName, workItem);
            totalWorkItems++;
            return workItem;
        }
    }

    // ============================================================================
    // PUBLIC API - EMAIL WORK REGISTRATION
    // ============================================================================

    /**
     * Register email work - consolidates by Phase only.
     * Messaging.sendEmail() accepts mixed email types, so consolidate all emails in a phase.
     * Returns the actual work item in the plan for fluent API chaining.
     *
     * @param workItem Email work item
     * @return The actual work item in the plan (existing if consolidated, new if first registration)
     */
    public UoWEmailWorkItem registerEmailWork(UoWEmailWorkItem workItem) {
        UoWExceptionService.requireNonNull(workItem, 'Work item');
        UoWExceptionService.require(workItem.getEmails() != null && !workItem.getEmails().isEmpty(),
            'Email work item must have at least one email');

        if (emailWork.containsKey(workItem.executionPhase)) {
            UoWEmailWorkItem existingWorkItem = emailWork.get(workItem.executionPhase);
            existingWorkItem.addEmails(workItem.getEmails());
            return existingWorkItem;
        } else {
            emailWork.put(workItem.executionPhase, workItem);
            totalWorkItems++;
            return workItem;
        }
    }

    // ============================================================================
    // PUBLIC API - FLOW WORK REGISTRATION
    // ============================================================================

    /**
     * Register flow work.
     *
     * @param workItem Flow work item
     */
    public void registerFlow(UoWFlowWorkItem workItem) {
        if (workItem == null) {
            return;
        }

        if (!flowWork.containsKey(workItem.executionPhase)) {
            flowWork.put(workItem.executionPhase, new List<UoWFlowWorkItem>());
        }

        flowWork.get(workItem.executionPhase).add(workItem);
        totalWorkItems++;
    }

    // ============================================================================
    // PUBLIC API - NOTIFICATION WORK REGISTRATION
    // ============================================================================

    /**
     * Register notification work.
     *
     * @param workItem Notification work item
     */
    public void registerNotification(UoWNotificationWorkItem workItem) {
        if (workItem == null) {
            return;
        }

        if (!notificationWork.containsKey(workItem.executionPhase)) {
            notificationWork.put(workItem.executionPhase, new List<UoWNotificationWorkItem>());
        }

        notificationWork.get(workItem.executionPhase).add(workItem);
        totalWorkItems++;
    }

    // ============================================================================
    // PUBLIC API - CALLOUT WORK REGISTRATION
    // ============================================================================

    /**
     * Register callout work (alias for serialization support).
     *
     * @param workItem Callout work item
     */
    public void registerCallout(UoWCalloutWorkItem workItem) {
        UoWExceptionService.requireNonNull(workItem, 'Work item');

        if (!calloutWork.containsKey(workItem.executionPhase)) {
            calloutWork.put(workItem.executionPhase, new List<UoWCalloutWorkItem>());
        }

        calloutWork.get(workItem.executionPhase).add(workItem);
        totalWorkItems++;
    }

    // ============================================================================
    // PUBLIC API - RELATIONSHIP REGISTRATION
    // ============================================================================

    /**
     * Register a relationship between two SObject records using direct object references.
     * The relationship will be resolved automatically during execution.
     *
     * @param child Child record instance
     * @param relationshipField Lookup/Master-Detail field on child pointing to parent
     * @param parent Parent record instance
     */
    public void registerRelationship(SObject child, Schema.SObjectField relationshipField, SObject parent) {
        UoWExceptionService.requireNonNull(child, 'Child record');
        UoWExceptionService.requireNonNull(relationshipField, 'Relationship field');
        UoWExceptionService.requireNonNull(parent, 'Parent record');

        UoWRelationship rel = new UoWRelationship(child, relationshipField, parent);
        this.relationships.put(rel.relationshipKey, rel);
        addToPendingByParentType(rel.parentSObjectTypeName, rel.relationshipKey);
    }

    /**
     * Register relationships in bulk for performance optimization.
     * Pre-computes field metadata once and reuses for all children.
     * PERFORMANCE: Reduces describe calls from O(n) to O(1) and eliminates per-record validation.
     *
     * @param children List of child record instances
     * @param relationshipField Lookup/Master-Detail field on child pointing to parent
     * @param parent Parent record instance
     */
    public void registerRelationship(List<SObject> children, Schema.SObjectField relationshipField, SObject parent) {
        // Early exit for empty/null inputs (validation already done by caller)
        if (children == null || children.isEmpty()) {
            return;
        }

        // PERFORMANCE: Pre-compute field metadata ONCE instead of per-record
        String fieldName = UoWCacheService.getFieldDescribe(relationshipField).getName();
        String childTypeName = null;
        if (!children.isEmpty() && children[0] != null) {
            Schema.SObjectType childType = children[0].getSObjectType();
            if (childType != null) {
                childTypeName = UoWCacheService.getDescribe(childType).getName();
            }
        }
        String parentTypeName = parent != null ? UoWCacheService.getDescribe(parent.getSObjectType()).getName() : null;

        // PERFORMANCE: Get or create pending set ONCE before the loop
        if (!this.pendingRelationshipsByParentType.containsKey(parentTypeName)) {
            this.pendingRelationshipsByParentType.put(parentTypeName, new Set<String>());
        }
        Set<String> pendingSet = this.pendingRelationshipsByParentType.get(parentTypeName);

        // Create relationships and add to pending set in single loop (no post-loop extraction)
        for (SObject child : children) {
            UoWRelationship rel = new UoWRelationship();
            rel.initBulk(child, relationshipField, parent, fieldName, childTypeName, parentTypeName);
            this.relationships.put(rel.relationshipKey, rel);
            pendingSet.add(rel.relationshipKey);  // Add directly to pending set
        }
    }

    // Add a single relationship key to pending map by parent type
    private void addToPendingByParentType(String parentTypeName, String relationshipKey) {
        if (!this.pendingRelationshipsByParentType.containsKey(parentTypeName)) {
            this.pendingRelationshipsByParentType.put(parentTypeName, new Set<String>());
        }
        this.pendingRelationshipsByParentType.get(parentTypeName).add(relationshipKey);
    }

    /**
     * Resolve relationships for a specific parent type after that type has been inserted.
     * PERFORMANCE: Only iterates relationships for the specific parent type that just got IDs.
     *
     * @param parentTypeName The parent SObject type name that was just inserted
     * @param result Result for logging (optional - can be null if called before result exists)
     */
    public void resolveRelationshipsForParentType(String parentTypeName, UoWResult result) {
        // PERFORMANCE: Early exit if no pending relationships for this parent type
        Set<String> pendingKeys = this.pendingRelationshipsByParentType.get(parentTypeName);
        if (pendingKeys == null || pendingKeys.isEmpty()) {
            return;
        }

        // PERFORMANCE: Only iterate relationships for this specific parent type.
        // Example: After Account INSERT, only resolve Account->Contact, Account->Opportunity
        // NOT Opportunity->OpportunityLineItem (different parent type)
        Integer resolvedCount = 0;
        Set<String> resolvedKeys = new Set<String>();

        for (String relKey : pendingKeys) {
            UoWRelationship rel = this.relationships.get(relKey);
            if (rel != null) {
                rel.resolve();
                if (rel.isResolved()) {
                    resolvedKeys.add(relKey);
                    resolvedCount++;
                }
            }
        }

        // Remove resolved relationships from pending set for this parent type
        pendingKeys.removeAll(resolvedKeys);

        // Clean up empty sets
        if (pendingKeys.isEmpty()) {
            this.pendingRelationshipsByParentType.remove(parentTypeName);
        }

        if (result != null && resolvedCount > 0) {
            result.finer(String.format('Resolved {0} relationship(s) for parent type {1}',
                new String[]{ String.valueOf(resolvedCount), parentTypeName }), 'UoWPlan');
        }
    }

    // ============================================================================
    // PUBLIC API - DML WORK LOOKUP (Performance Optimization)
    // ============================================================================

    /**
     * Get existing DML work item for consolidation check.
     * PERFORMANCE: Allows checking for existing work item BEFORE creating a new one,
     * avoiding unnecessary object allocations during bulk registration.
     *
     * @param typeName SObject type API name
     * @param operation DML operation type
     * @return Existing work item or null if not found
     */
    public UoWDmlWorkItem getExistingDmlWork(String typeName, UoWEnums.DmlOperation operation) {
        Map<String, UoWDmlWorkItem> workMap;
        switch on operation {
            when INSERT_OP { workMap = insertWork; }
            when UPDATE_OP { workMap = updateWork; }
            when UPSERT_OP { workMap = upsertWork; }
            when DELETE_OP { workMap = deleteWork; }
            when UNDELETE_OP { workMap = undeleteWork; }
            when else { return null; }
        }
        return workMap.get(typeName);
    }

    // ============================================================================
    // PRIVATE HELPER METHODS
    // ============================================================================

    // Add DML work to map - consolidates records inside WorkItem. Returns the actual work item in the plan for fluent API chaining.
    private UoWDmlWorkItem addDmlWork(Map<String, UoWDmlWorkItem> workMap, UoWDmlWorkItem workItem) {
        // Use sobjectTypeName as key for serialization compatibility
        String typeName = workItem.sobjectTypeName;

        if (workMap.containsKey(typeName)) {
            UoWDmlWorkItem existingWorkItem = workMap.get(typeName);
            existingWorkItem.addRecords(workItem.getOriginalRecords());
            return existingWorkItem;
        } else {
            workMap.put(typeName, workItem);
            totalWorkItems++;
            return workItem;
        }
    }

    // Convert String keys (sobjectTypeName) back to Schema.SObjectType for API compatibility
    private Set<Schema.SObjectType> convertKeysToSObjectTypes(Set<String> typeNames) {
        Set<Schema.SObjectType> types = new Set<Schema.SObjectType>();
        for (String typeName : typeNames) {
            Schema.SObjectType sType = UoWCacheService.getSobjectTypeFromGlobalDescribe(typeName);
            if (sType != null) {
                types.add(sType);
            }
        }
        return types;
    }
}