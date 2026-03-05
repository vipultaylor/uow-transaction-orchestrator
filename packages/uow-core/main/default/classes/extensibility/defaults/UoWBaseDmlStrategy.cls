//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Base implementation for DML strategies.
 * Provides default all-or-none synchronous DML execution.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWInterfaces.IDmlStrategy, UoWDmlStrategyRegistry
 */
public virtual inherited sharing class UoWBaseDmlStrategy implements UoWInterfaces.IDmlStrategy {

    // ============================================================================
    // PROTECTED PROPERTIES
    // ============================================================================

    protected String strategyName; // Strategy name for identification

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Default constructor - sets default strategy name
     */
    public UoWBaseDmlStrategy() {
        this('Default DML Strategy');
    }

    /**
     * Constructor with custom name (for derived classes)
     * @param name Strategy name
     */
    public UoWBaseDmlStrategy(String name) {
        this.strategyName = name;
    }

    // ============================================================================
    // PUBLIC API - CONFIGURATION
    // ============================================================================

    /**
     * Get strategy name
     * @return Strategy name
     */
    public virtual String getName() {
        return this.strategyName;
    }

    // ============================================================================
    // PUBLIC API - DML OPERATIONS
    // ============================================================================

    /**
     * Execute insert operation
     * @param workItem The DML work item
     * @param ctx The execution context
     */
    public virtual void executeInsert(UoWDmlWorkItem workItem, UoWContext ctx) {
        List<SObject> records = workItem.getOriginalRecords();
        if (records == null || records.isEmpty()) {
            return;
        }

        // Apply CRUD/FLS enforcement if configured
        List<SObject> recordsForDml = enforceSecurityIfNeeded(records, AccessType.CREATABLE, ctx);

        // Always capture results for ID syncing
        // Invert continueOnError: false (fail-fast) → allOrNone=true, true (partial success) → allOrNone=false
        workItem.saveResults = Database.insert(recordsForDml, !workItem.continueOnError);
    }

    /**
     * Execute update operation
     * @param workItem The DML work item
     * @param ctx The execution context
     */
    public virtual void executeUpdate(UoWDmlWorkItem workItem, UoWContext ctx) {
        List<SObject> records = workItem.getOriginalRecords();
        if (records == null || records.isEmpty()) {
            return;
        }

        // Apply CRUD/FLS enforcement if configured
        List<SObject> recordsForDml = enforceSecurityIfNeeded(records, AccessType.UPDATABLE, ctx);

        // Always capture results
        // Invert continueOnError: false (fail-fast) → allOrNone=true, true (partial success) → allOrNone=false
        workItem.saveResults = Database.update(recordsForDml, !workItem.continueOnError);
    }

    /**
     * Execute upsert operation
     * @param workItem The DML work item
     * @param ctx The execution context
     */
    public virtual void executeUpsert(UoWDmlWorkItem workItem, UoWContext ctx) {
        List<SObject> records = workItem.getOriginalRecords();
        if (records == null || records.isEmpty()) {
            return;
        }

        // Apply CRUD/FLS enforcement if configured (UPSERTABLE = CREATABLE + UPDATABLE)
        List<SObject> recordsForDml = enforceSecurityIfNeeded(records, AccessType.UPSERTABLE, ctx);

        // Always capture results for ID syncing
        // Invert continueOnError: false (fail-fast) → allOrNone=true, true (partial success) → allOrNone=false
        if (workItem.externalIdField != null) {
            workItem.upsertResults = Database.upsert(recordsForDml, workItem.externalIdField, !workItem.continueOnError);
        } else {
            workItem.upsertResults = Database.upsert(recordsForDml, !workItem.continueOnError);
        }
    }

    /**
     * Execute delete operation
     * @param workItem The DML work item
     * @param ctx The execution context
     */
    public virtual void executeDelete(UoWDmlWorkItem workItem, UoWContext ctx) {
        List<SObject> records = workItem.getOriginalRecords();
        if (records == null || records.isEmpty()) {
            return;
        }

        // Apply CRUD/FLS enforcement if configured (READABLE - need read access to delete)
        List<SObject> recordsForDml = enforceSecurityIfNeeded(records, AccessType.READABLE, ctx);

        // Always capture results
        // Invert continueOnError: false (fail-fast) → allOrNone=true, true (partial success) → allOrNone=false
        workItem.deleteResults = Database.delete(recordsForDml, !workItem.continueOnError);
    }

    /**
     * Execute undelete operation
     * @param workItem The DML work item
     * @param ctx The execution context
     */
    public virtual void executeUndelete(UoWDmlWorkItem workItem, UoWContext ctx) {
        List<SObject> records = workItem.getOriginalRecords();
        if (records == null || records.isEmpty()) {
            return;
        }

        // Apply CRUD/FLS enforcement if configured (CREATABLE - undelete is like re-creating)
        List<SObject> recordsForDml = enforceSecurityIfNeeded(records, AccessType.CREATABLE, ctx);

        // Always capture results
        // Invert continueOnError: false (fail-fast) → allOrNone=true, true (partial success) → allOrNone=false
        workItem.undeleteResults = Database.undelete(recordsForDml, !workItem.continueOnError);
    }

    // ============================================================================
    // PROTECTED METHODS
    // ============================================================================

    /**
     * Apply CRUD/FLS security enforcement if configured.
     * Protected visibility allows testable subclasses to access this method
     * for unit testing security enforcement in isolation.
     * @param records Records to enforce security on
     * @param accessType Type of access being performed (CREATABLE, UPDATABLE, etc.)
     * @param ctx Execution context containing security settings
     * @return Records after security enforcement (may have fields stripped if no access)
     */
    @TestVisible
    protected List<SObject> enforceSecurityIfNeeded(List<SObject> records, System.AccessType accessType, UoWContext ctx) {
        // Check security mode from feature settings
        UoWEnums.SecurityMode securityMode = ctx.getFeatureSettings()?.getDmlSecurityMode();

        // PERMISSIVE mode - no enforcement (system context or trusted operations)
        if (securityMode == null || securityMode == UoWEnums.SecurityMode.PERMISSIVE) {
            return records;
        }

        // ENFORCED mode - apply Security.stripInaccessible()
        try {
            SObjectAccessDecision decision = Security.stripInaccessible(accessType, records);

            // Log warning if fields were removed due to FLS
            if (!decision.getRemovedFields().isEmpty()) {
                Map<String, Set<String>> removedFields = decision.getRemovedFields();
                for (String sObjectName : removedFields.keySet()) {
                    Set<String> fields = removedFields.get(sObjectName);
                    ctx.warn(
                        String.format('Security enforcement removed {0} inaccessible fields from {1}: {2}',
                            new String[]{ String.valueOf(fields.size()), sObjectName, String.join(new List<String>(fields), ', ') }),
                        'UoWBaseDmlStrategy'
                    );
                }
            }

            return decision.getRecords();
        } catch (Exception ex) {
            // stripInaccessible failed - log error and re-throw
            ctx.error(
                String.format('Security enforcement failed for {0} operation: {1}',
                    new String[]{ accessType.name(), ex.getMessage() }),
                'UoWBaseDmlStrategy'
            );
            throw ex;
        }
    }
}