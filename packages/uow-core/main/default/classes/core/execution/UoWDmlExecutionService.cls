//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Executes DML operations with dependency resolution.
 *
 * Responsibilities:
 * - Build and validate dependency graph (detect circular dependencies)
 * - Topological sort of DML operations (respects parent-child relationships)
 * - Resolve relationships (populate parent IDs in child records)
 * - Execute DML via strategy registry
 * - Sync generated IDs to original records
 *
 * Complexity:
 * - Most complex executor (dependency graph, relationship resolution)
 * - Justifies dedicated service (vs lumping with other work types)
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Execution
 * @see UoWWorkItemExecutor
 * @see UoWDependencyGraph
 * @see UoWDmlStrategyRegistry
 */
public inherited sharing class UoWDmlExecutionService extends UoWWorkItemExecutor {

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Constructor passing the relevant context for executing DMLs.
     *
     * @param ctx Context instance
     * @param plan Plan that contains DML work items
     * @param result Result instance initialized for this execution
     */
    public UoWDmlExecutionService(UoWContext ctx, UoWPlan plan, UoWResult result) {
        super(ctx, plan, result);
    }

    // ============================================================================
    // PUBLIC API - EXECUTION
    // ============================================================================

    /**
     * Execute all registered DML work items.
     *
     * @param phase Always null as DMLs are not phase dependent
     */
    public override void execute(UoWEnums.WorkPhase phase) {
        Integer workItemCount = plan.getPlannedDmlWork().size();

        result.info(String.format('DML execution started - {0} work item(s)',
            new String[]{ String.valueOf(workItemCount) }), 'UoWDmlExecutionService');

        UoWTracer.Span dmlPhase = result.startSpan(
            UoWEnums.SpanPhase.DML_EXECUTION,
            'DML operations'
        );

        try {
            UoWDependencyGraph depGraph = buildDependencyGraph();

            List<UoWDmlWorkItem> sortedWork = depGraph.getTopologicallySortedDml();
            result.addTraceEvent(String.format('{0} DML operations ordered',
                new String[]{ String.valueOf(sortedWork.size()) }));
            result.debug(String.format('Dependency graph built - {0} operation(s) in topological order',
                new String[]{ String.valueOf(sortedWork.size()) }), 'UoWDmlExecutionService');

            Map<UoWEnums.DmlOperation, List<UoWDmlWorkItem>> workByOperation = groupByOperation(sortedWork);

            for (UoWEnums.DmlOperation operation : workByOperation.keySet()) {
                executeOperation(operation, workByOperation.get(operation));
            }

            result.info('DML execution completed', 'UoWDmlExecutionService');
        } finally {
            result.endSpan(dmlPhase, UoWEnums.SpanPhaseResult.SUCCESS,
                String.format(System.Label.UoW_Span_DmlCompleted,
                    new String[]{ String.valueOf(workItemCount) }));
        }
    }

    // ============================================================================
    // PRIVATE METHODS - DEPENDENCY GRAPH
    // ============================================================================

    // Build and validate dependency graph. Throws exception if circular dependencies detected.
    private UoWDependencyGraph buildDependencyGraph() {
        UoWTracer.Span graphPhase = result.startSpan(
            UoWEnums.SpanPhase.DEPENDENCY_GRAPH,
            'Building dependency graph'
        );

        UoWDependencyGraph depGraph = new UoWDependencyGraph(plan, context);
        depGraph.buildGraph();

        if (depGraph.hasCircularDependencies()) {
            result.endSpan(graphPhase, UoWEnums.SpanPhaseResult.FAILED,
                System.Label.UoW_Error_CircularDependency);
            throw new UoWExceptionService.UoWException(
                System.Label.UoW_Error_CircularDependency
            );
        }

        result.endSpan(graphPhase, UoWEnums.SpanPhaseResult.SUCCESS, 'Dependency graph validated');
        return depGraph;
    }

    // Group work items by operation type (INSERT, UPDATE, DELETE, UPSERT, UNDELETE).
    private Map<UoWEnums.DmlOperation, List<UoWDmlWorkItem>> groupByOperation(List<UoWDmlWorkItem> sortedWork) {
        Map<UoWEnums.DmlOperation, List<UoWDmlWorkItem>> workByOperation =
            new Map<UoWEnums.DmlOperation, List<UoWDmlWorkItem>>();

        for (UoWDmlWorkItem workItem : sortedWork) {
            if (!workByOperation.containsKey(workItem.operation)) {
                workByOperation.put(workItem.operation, new List<UoWDmlWorkItem>());
            }
            workByOperation.get(workItem.operation).add(workItem);
        }

        return workByOperation;
    }

    // ============================================================================
    // PRIVATE METHODS - OPERATION EXECUTION
    // ============================================================================

    // Execute all work items for a single operation type.
    private void executeOperation(UoWEnums.DmlOperation operation, List<UoWDmlWorkItem> workItems) {
        UoWEnums.SpanPhase spanPhase = UoWEnums.DML_OP_TO_SPAN.get(operation);
        String phaseMessage = String.format('Executing {0} operations ({1} object types)',
            new String[]{ String.valueOf(operation), String.valueOf(workItems.size()) });
        UoWTracer.Span operationPhase = result.startSpan(spanPhase, phaseMessage);

        try {
            // PERFORMANCE: Only INSERT and UPSERT operations assign new IDs to records.
            // UPDATE/DELETE/UNDELETE operate on records that already have IDs.
            // Therefore, relationship resolution is only needed after INSERT/UPSERT.
            Boolean needsRelationshipResolution =
                operation == UoWEnums.DmlOperation.INSERT_OP ||
                operation == UoWEnums.DmlOperation.UPSERT_OP;

            for (UoWDmlWorkItem workItem : workItems) {
                executeDmlWorkItem(workItem);

                // PERFORMANCE: Resolve relationships ONLY for INSERT/UPSERT operations.
                // After Account INSERT, resolve Account->Contact, Account->Opportunity.
                // Skip for UPDATE/DELETE/UNDELETE since those records already have IDs.
                if (needsRelationshipResolution) {
                    plan.resolveRelationshipsForParentType(workItem.sobjectTypeName, result);
                }
            }
        } finally {
            result.endSpan(operationPhase, UoWEnums.SpanPhaseResult.SUCCESS,
                String.format('Completed {0} operations ({1} object types)',
                    new String[]{ String.valueOf(operation), String.valueOf(workItems.size()) }));
        }
    }

    // Execute a single DML work item.
    private void executeDmlWorkItem(UoWDmlWorkItem workItem) {
        List<SObject> records = workItem.getOriginalRecords();
        if (records == null || records.isEmpty()) {
            result.fine('Skipping empty DML work item', 'UoWDmlExecutionService');
            return;
        }

        // Start work item span (child of current operation span)
        UoWTracer.Span workItemSpan = result.startSpan(workItem, null);

        prepareWorkItem(workItem);

        String objectName = UoWCacheService.getDescribe(workItem.sobjectType).getName();

        result.debug(String.format('Executing {0} on {1} record(s) - workId: {2}',
            new String[]{
                String.valueOf(workItem.operation),
                String.valueOf(records.size()),
                workItem.workId
            }), 'UoWDmlExecutionService');

        try {
            if (!context.isDryRun) {
                UoWDmlStrategyRegistry.executeDml(workItem, context, result);
            } else {
                result.fine(String.format('Skipping DML execution for {0} (dry run mode)',
                    new String[]{ objectName }), 'UoWDmlExecutionService');
            }

            syncIdsToOriginalRecords(workItem);

        } catch (Exception ex) {
            handleWorkItemException(workItem, ex);

        } finally {
            finalizeWorkItem(workItem);

            // End work item span with result summary
            result.endSpan(workItemSpan, workItem, null);

            if (workItem.hasErrors()) {
                result.warn(String.format('{0} {1} operation had {2} error(s)',
                    new String[]{
                        objectName,
                        String.valueOf(workItem.operation),
                        String.valueOf(workItem.errors.size())
                    }), 'UoWDmlExecutionService');
            }

            result.addDmlWork(workItem);
        }
    }

    // ============================================================================
    // PRIVATE METHODS - ID SYNC
    // ============================================================================

    // Sync generated IDs to original records. Only applies to INSERT and UPSERT operations.
    private void syncIdsToOriginalRecords(UoWDmlWorkItem workItem) {
        if (!isIdSyncApplicable(workItem)) {
            return;
        }

        List<SObject> originalRecords = workItem.getOriginalRecords();
        if (originalRecords == null || originalRecords.isEmpty()) {
            return;
        }

        if (workItem.saveResults != null && !workItem.saveResults.isEmpty()) {
            syncIdsFromSaveResults(workItem.saveResults, originalRecords);
        } else if (workItem.upsertResults != null && !workItem.upsertResults.isEmpty()) {
            syncIdsFromUpsertResults(workItem.upsertResults, originalRecords);
        }
    }

    // Check if ID sync is applicable for the given operation.
    private Boolean isIdSyncApplicable(UoWDmlWorkItem workItem) {
        return workItem.operation == UoWEnums.DmlOperation.INSERT_OP ||
               workItem.operation == UoWEnums.DmlOperation.UPSERT_OP;
    }

    // Sync IDs from SaveResult to original records.
    private void syncIdsFromSaveResults(List<Database.SaveResult> saveResults, List<SObject> originalRecords) {
        Integer maxIndex = Math.min(saveResults.size(), originalRecords.size());
        for (Integer i = 0; i < maxIndex; i++) {
            Database.SaveResult sr = saveResults[i];
            if (sr.isSuccess() && sr.getId() != null) {
                originalRecords[i].Id = sr.getId();
            }
        }
    }

    // Sync IDs from UpsertResult to original records.
    private void syncIdsFromUpsertResults(List<Database.UpsertResult> upsertResults, List<SObject> originalRecords) {
        Integer maxIndex = Math.min(upsertResults.size(), originalRecords.size());
        for (Integer i = 0; i < maxIndex; i++) {
            Database.UpsertResult ur = upsertResults[i];
            if (ur.isSuccess() && ur.getId() != null) {
                originalRecords[i].Id = ur.getId();
            }
        }
    }
}