//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Manages dependency graph and topological sorting for DML operations.
 * Uses Kahn's algorithm for cycle detection and ordering.
 *
 * Dependency Resolution Priority:
 * 1. Explicit relate() edges (HIGHEST - always wins)
 * 2. UoWObjectPrecedence__mdt configuration (when no explicit edge exists)
 * 3. Registration order (LOWEST - when no precedence configured)
 *
 * @author Vipul Taylor
 */
public inherited sharing class UoWDependencyGraph {

    // ============================================================================
    // PRIVATE FIELDS - INSTANCE
    // ============================================================================

    private UoWPlan executionPlan;
    private UoWContext context;
    private Map<String, GraphNode> nodeMap;
    private List<GraphEdge> edges;
    private Set<String> edgeLookup;  // PERFORMANCE: O(1) edge existence check
    private Boolean isBuilt;
    private Map<String, UoWEnums.DmlOperation> typeOperationCache;  // PERFORMANCE: O(1) operation lookup

    // ============================================================================
    // PRIVATE FIELDS - STATIC CACHE
    // ============================================================================

    private static Map<String, Integer> precedenceCache;
    private static Boolean precedenceCacheLoaded = false;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * Create a dependency graph for the given plan and context.
     *
     * @param plan Execution plan containing DML work items
     * @param ctx Execution context for logging
     */
    public UoWDependencyGraph(UoWPlan plan, UoWContext ctx) {
        this.executionPlan = plan;
        this.context = ctx;
        this.nodeMap = new Map<String, GraphNode>();
        this.edges = new List<GraphEdge>();
        this.edgeLookup = new Set<String>();  // PERFORMANCE: O(1) edge existence check
        this.isBuilt = false;
        this.typeOperationCache = new Map<String, UoWEnums.DmlOperation>();

        // Ensure precedence cache is loaded
        loadPrecedenceCache();
    }

    // ============================================================================
    // PUBLIC API - GRAPH BUILDING
    // ============================================================================

    /**
     * Build dependency graph from plan.
     * Only uses explicit relate() relationships and configured precedence.
     */
    public void buildGraph() {
        if (isBuilt) {
            return;
        }

        // Create nodes for each SObject type in DML operations
        createNodesFromDmlWork();

        // PERFORMANCE: Build type→operation cache for O(1) lookups
        buildTypeOperationCache();

        // Build edges based on explicit relate() relationships
        buildEdgesFromRelationships();

        // Apply configured precedence (only when no explicit edge exists)
        applyConfiguredPrecedence();

        isBuilt = true;
    }

    // ============================================================================
    // PUBLIC API - TOPOLOGICAL SORT
    // ============================================================================

    /**
     * Perform topological sort and return ordered work items.
     * OPTIMIZED: Cycle detection integrated into Kahn's algorithm (single pass).
     * PERFORMANCE: Uses pre-computed node.nodeKey throughout (no string concatenation).
     *
     * @return List of DML work items in topologically sorted order
     * @throws UoWException if circular dependencies are detected
     */
    public List<UoWDmlWorkItem> getTopologicallySortedDml() {
        if (!isBuilt) {
            buildGraph();
        }

        // Kahn's algorithm with integrated cycle detection
        List<GraphNode> sortedNodes = new List<GraphNode>();
        List<GraphNode> queue = new List<GraphNode>();

        // Clone in-degree values (don't modify originals)
        // PERFORMANCE: Use pre-computed node.nodeKey
        Map<String, Integer> inDegreeMap = new Map<String, Integer>();
        Integer totalNodes = 0;
        for (GraphNode node : nodeMap.values()) {
            inDegreeMap.put(node.nodeKey, node.inDegree);
            totalNodes++;

            if (node.inDegree == 0) {
                queue.add(node);
            }
        }

        // Process queue
        while (!queue.isEmpty()) {
            GraphNode current = queue.remove(0);
            sortedNodes.add(current);

            // Reduce in-degree of neighbors
            for (GraphEdge edge : current.outgoingEdges) {
                // PERFORMANCE: Use pre-computed nodeKey from neighbor node
                String neighborKey = edge.toNode.nodeKey;
                Integer currentInDegree = inDegreeMap.get(neighborKey);
                currentInDegree--;
                inDegreeMap.put(neighborKey, currentInDegree);

                if (currentInDegree == 0) {
                    queue.add(edge.toNode);
                }
            }
        }

        // CYCLE DETECTION: If sorted nodes < total nodes, cycle exists
        if (sortedNodes.size() < totalNodes) {
            // Find the cycle path for error message (only when cycle detected)
            List<String> cyclePath = findCircularDependencyPath();
            String detectedCycle = String.join(cyclePath, ' → ');
            String errorMsg = System.Label.UoW_Error_CircularDependency;

            if (!cyclePath.isEmpty()) {
                errorMsg += '\n\nDetected cycle: ' + detectedCycle;
                errorMsg += '\n\nSuggestion: Remove the relationship causing the cycle, or split the transaction into multiple operations. ' +
                           'For example, create parent records first, then create child records in a separate transaction.';
            }

            throw new UoWExceptionService.UoWException(errorMsg);
        }

        // Convert sorted nodes to work items
        return convertNodesToWorkItems(sortedNodes);
    }

    // ============================================================================
    // PUBLIC API - CYCLE DETECTION
    // ============================================================================

    /**
     * Detect circular dependencies using DFS.
     * PERFORMANCE: Uses pre-computed node.nodeKey (no string concatenation).
     *
     * @return True if circular dependencies exist
     */
    public Boolean hasCircularDependencies() {
        if (!isBuilt) {
            buildGraph();
        }

        Set<String> visited = new Set<String>();
        Set<String> recursionStack = new Set<String>();

        for (GraphNode node : nodeMap.values()) {
            // PERFORMANCE: Use pre-computed nodeKey
            if (!visited.contains(node.nodeKey)) {
                if (hasCycleDFS(node, visited, recursionStack)) {
                    return true;
                }
            }
        }

        return false;
    }

    /**
     * Detect circular dependencies and return the cycle path.
     * PERFORMANCE: Uses pre-computed node.nodeKey (no string concatenation).
     *
     * @return List of SObject names forming the cycle, or empty list if no cycle
     */
    public List<String> findCircularDependencyPath() {
        if (!isBuilt) {
            buildGraph();
        }

        Set<String> visited = new Set<String>();
        Set<String> recursionStack = new Set<String>();
        List<String> path = new List<String>();

        for (GraphNode node : nodeMap.values()) {
            // PERFORMANCE: Use pre-computed nodeKey
            if (!visited.contains(node.nodeKey)) {
                if (findCycleDFS(node, visited, recursionStack, path)) {
                    return path;
                }
            }
        }

        return new List<String>();
    }

    // ============================================================================
    // PUBLIC API - GRAPH STATISTICS
    // ============================================================================

    /**
     * Get node count.
     *
     * @return Number of nodes in the graph
     */
    public Integer getNodeCount() {
        return nodeMap.size();
    }

    /**
     * Get edge count.
     *
     * @return Number of edges in the graph
     */
    public Integer getEdgeCount() {
        return edges.size();
    }

    // ============================================================================
    // PUBLIC API - PRECEDENCE CONFIGURATION (STATIC)
    // ============================================================================

    /**
     * Check if precedence is configured for a given SObject type.
     *
     * @param sobjectTypeName The API name of the SObject
     * @return True if precedence is configured
     */
    public static Boolean hasPrecedenceConfigured(String sobjectTypeName) {
        loadPrecedenceCache();
        return precedenceCache.containsKey(sobjectTypeName);
    }

    /**
     * Get configured precedence for a given SObject type.
     *
     * @param sobjectTypeName The API name of the SObject
     * @return Precedence value or null if not configured
     */
    public static Integer getPrecedence(String sobjectTypeName) {
        loadPrecedenceCache();
        return precedenceCache.get(sobjectTypeName);
    }

    // Reset precedence cache (for testing)
    @TestVisible
    private static void resetPrecedenceCache() {
        precedenceCache = null;
        precedenceCacheLoaded = false;
    }

    // ============================================================================
    // PRIVATE METHODS - CACHE LOADING
    // ============================================================================

    // Load precedence configuration from UoWObjectPrecedence__mdt. Uses static cache for efficiency across multiple graph instances.
    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static void loadPrecedenceCache() {
        if (precedenceCacheLoaded) {
            return;
        }

        precedenceCache = new Map<String, Integer>();

        for (UoWObjectPrecedence__mdt prec : [SELECT SObjectType__c, Precedence__c
                                                FROM UoWObjectPrecedence__mdt
                                                LIMIT 2000]) {
            if (String.isNotBlank(prec.SObjectType__c) && prec.Precedence__c != null) {
                precedenceCache.put(prec.SObjectType__c, Integer.valueOf(prec.Precedence__c));
            }
        }

        precedenceCacheLoaded = true;
    }

    // ============================================================================
    // PRIVATE METHODS - NODE CREATION
    // ============================================================================

    // Create graph nodes from DML work items - PERFORMANCE: iterate work items directly to get type names
    private void createNodesFromDmlWork() {
        // Insert operations
        for (UoWDmlWorkItem workItem : executionPlan.getPlannedInsertWork()) {
            createOrGetNode(workItem.sobjectTypeName, UoWEnums.DmlOperation.INSERT_OP);
        }

        // Upsert operations
        for (UoWDmlWorkItem workItem : executionPlan.getPlannedUpsertWork()) {
            createOrGetNode(workItem.sobjectTypeName, UoWEnums.DmlOperation.UPSERT_OP);
        }

        // Update operations
        for (UoWDmlWorkItem workItem : executionPlan.getPlannedUpdateWork()) {
            createOrGetNode(workItem.sobjectTypeName, UoWEnums.DmlOperation.UPDATE_OP);
        }

        // Delete operations (reverse dependencies)
        for (UoWDmlWorkItem workItem : executionPlan.getPlannedDeleteWork()) {
            createOrGetNode(workItem.sobjectTypeName, UoWEnums.DmlOperation.DELETE_OP);
        }

        // Undelete operations
        for (UoWDmlWorkItem workItem : executionPlan.getPlannedUndeleteWork()) {
            createOrGetNode(workItem.sobjectTypeName, UoWEnums.DmlOperation.UNDELETE_OP);
        }
    }

    // Create or get existing node - PERFORMANCE: use String type name directly
    private GraphNode createOrGetNode(String typeName, UoWEnums.DmlOperation operation) {
        // PERFORMANCE: Build key once, reuse for check and put
        String nodeKey = typeName + ':' + operation.name();

        GraphNode existingNode = nodeMap.get(nodeKey);
        if (existingNode != null) {
            return existingNode;
        }

        GraphNode newNode = new GraphNode(typeName, operation);
        nodeMap.put(newNode.nodeKey, newNode);  // Use pre-computed nodeKey from GraphNode
        return newNode;
    }

    // ============================================================================
    // PRIVATE METHODS - EDGE BUILDING
    // ============================================================================

    // Build edges from explicit relate() relationships. These edges have highest priority and always win over precedence.
    // PERFORMANCE: Uses String type names directly from relationship (no describe calls)
    private void buildEdgesFromRelationships() {
        for (UoWRelationship rel : executionPlan.getRelationships()) {
            // Get parent and child type names (PERFORMANCE: uses cached names from relationship)
            String parentTypeName = rel.getParentTypeName();
            String childTypeName = rel.getChildTypeName();

            if (String.isBlank(parentTypeName) || String.isBlank(childTypeName)) {
                continue;
            }

            // Parent must be processed before child
            // Weight 10 = highest priority (explicit relationship)
            addEdge(parentTypeName, childTypeName, 'Explicit relate() relationship', 10);

            // Validate against configured precedence (warn if conflict)
            validatePrecedenceConflict(parentTypeName, childTypeName);
        }
    }

    // Validate if relate() relationship conflicts with configured precedence. Logs warning but does NOT prevent the relationship (explicit wins).
    // PERFORMANCE: Accepts String type names directly (no describe calls)
    private void validatePrecedenceConflict(String parentTypeName, String childTypeName) {
        Integer parentPrecedence = precedenceCache.get(parentTypeName);
        Integer childPrecedence = precedenceCache.get(childTypeName);

        // Only validate if BOTH have configured precedence
        if (parentPrecedence == null || childPrecedence == null) {
            return;
        }

        // Conflict: Child precedence is LOWER (earlier) than parent
        // This means configured precedence says child should execute first,
        // but relate() says parent must execute first
        if (childPrecedence < parentPrecedence) {
            String warning = String.format(
                'Precedence conflict: relate() declares {0} depends on {1}, but configured precedence ' +
                'says {0} ({2}) should execute BEFORE {1} ({3}). The explicit relate() relationship takes priority.',
                new List<String>{
                    childTypeName,
                    parentTypeName,
                    String.valueOf(childPrecedence),
                    String.valueOf(parentPrecedence)
                }
            );

            // Log warning (use context if available, otherwise System.debug)
            if (context != null) {
                context.warn(warning, 'UoWDependencyGraph');
            } else {
                System.debug(LoggingLevel.WARN, '[UoWDependencyGraph] ' + warning);
            }
        }
    }

    // Apply configured precedence from UoWObjectPrecedence__mdt. Only creates edges when no explicit relate() edge exists.
    // PERFORMANCE: Works with String type names throughout - no Schema.SObjectType or describe calls
    private void applyConfiguredPrecedence() {
        // Collect all type names that have configured precedence
        // PERFORMANCE: Use nodeMap keys which already contain type names
        Map<String, Integer> typesWithPrecedence = new Map<String, Integer>();

        for (String nodeKey : nodeMap.keySet()) {
            // nodeKey format is "TypeName:OPERATION"
            String typeName = nodeKey.substringBefore(':');
            Integer prec = precedenceCache.get(typeName);
            if (prec != null && !typesWithPrecedence.containsKey(typeName)) {
                typesWithPrecedence.put(typeName, prec);
            }
        }

        // Convert to list for indexed iteration
        List<String> typeNameList = new List<String>(typesWithPrecedence.keySet());

        for (Integer i = 0; i < typeNameList.size(); i++) {
            for (Integer j = i + 1; j < typeNameList.size(); j++) {
                String typeName1 = typeNameList[i];
                String typeName2 = typeNameList[j];

                Integer precedence1 = typesWithPrecedence.get(typeName1);
                Integer precedence2 = typesWithPrecedence.get(typeName2);

                // Skip if precedence is equal (no ordering needed)
                if (precedence1 == precedence2) {
                    continue;
                }

                // Determine which should execute first (lower precedence = earlier)
                String firstTypeName = precedence1 < precedence2 ? typeName1 : typeName2;
                String secondTypeName = precedence1 < precedence2 ? typeName2 : typeName1;

                // Check for existing explicit edges (in either direction) - O(1) with edgeLookup Set
                Boolean hasExplicitEdge = hasDirectedEdge(firstTypeName, secondTypeName) ||
                                          hasDirectedEdge(secondTypeName, firstTypeName);

                if (!hasExplicitEdge) {
                    // Add precedence-based edge (weight 1 = lower priority than explicit)
                    addEdge(firstTypeName, secondTypeName, 'Configured precedence', 1);
                }
            }
        }
    }

    // Add edge to graph - PERFORMANCE: uses String type names directly
    private void addEdge(String fromTypeName, String toTypeName, String reason, Integer weight) {
        // For delete operations, reverse the edge direction
        UoWEnums.DmlOperation fromOp = getOperationForTypeName(fromTypeName);
        UoWEnums.DmlOperation toOp = getOperationForTypeName(toTypeName);

        if (fromOp == UoWEnums.DmlOperation.DELETE_OP || toOp == UoWEnums.DmlOperation.DELETE_OP) {
            // Reverse: children must be deleted before parents
            String temp = fromTypeName;
            fromTypeName = toTypeName;
            toTypeName = temp;
            // Also swap operations
            UoWEnums.DmlOperation tempOp = fromOp;
            fromOp = toOp;
            toOp = tempOp;
        }

        // PERFORMANCE: Get nodes directly using pre-computed nodeKey format
        String fromKey = fromTypeName + ':' + fromOp.name();
        String toKey = toTypeName + ':' + toOp.name();

        // Don't add self-loops
        if (fromKey.equals(toKey)) {
            return;
        }

        GraphNode fromNode = nodeMap.get(fromKey);
        GraphNode toNode = nodeMap.get(toKey);

        if (fromNode != null && toNode != null) {
            GraphEdge edge = new GraphEdge(fromNode, toNode, reason, weight);
            edges.add(edge);

            // PERFORMANCE: Add to lookup set for O(1) edge existence check
            edgeLookup.add(getEdgeLookupKey(fromTypeName, toTypeName));

            fromNode.outgoingEdges.add(edge);
            toNode.incomingEdges.add(edge);
            toNode.inDegree++;
        }
    }

    // Check if a DIRECTED edge exists from type1 to type2 (unidirectional)
    // PERFORMANCE: O(1) lookup using Set instead of O(m) iteration through edges
    private Boolean hasDirectedEdge(String fromTypeName, String toTypeName) {
        return edgeLookup.contains(getEdgeLookupKey(fromTypeName, toTypeName));
    }

    // Generate lookup key for edge existence check - PERFORMANCE: no describe call
    private String getEdgeLookupKey(String fromTypeName, String toTypeName) {
        return fromTypeName + '->' + toTypeName;
    }

    // ============================================================================
    // PRIVATE METHODS - UTILITIES
    // ============================================================================

    // Build type→operation cache for O(1) lookups (called once during buildGraph)
    // PERFORMANCE: Reduces 5 sequential map lookups to 1 per getOperationForTypeName() call
    private void buildTypeOperationCache() {
        // Cache INSERT operations
        for (UoWDmlWorkItem item : executionPlan.getPlannedInsertWork()) {
            typeOperationCache.put(item.sobjectTypeName, UoWEnums.DmlOperation.INSERT_OP);
        }
        // Cache UPSERT operations
        for (UoWDmlWorkItem item : executionPlan.getPlannedUpsertWork()) {
            typeOperationCache.put(item.sobjectTypeName, UoWEnums.DmlOperation.UPSERT_OP);
        }
        // Cache UPDATE operations
        for (UoWDmlWorkItem item : executionPlan.getPlannedUpdateWork()) {
            typeOperationCache.put(item.sobjectTypeName, UoWEnums.DmlOperation.UPDATE_OP);
        }
        // Cache DELETE operations
        for (UoWDmlWorkItem item : executionPlan.getPlannedDeleteWork()) {
            typeOperationCache.put(item.sobjectTypeName, UoWEnums.DmlOperation.DELETE_OP);
        }
        // Cache UNDELETE operations
        for (UoWDmlWorkItem item : executionPlan.getPlannedUndeleteWork()) {
            typeOperationCache.put(item.sobjectTypeName, UoWEnums.DmlOperation.UNDELETE_OP);
        }
    }

    // Get operation for a type name - PERFORMANCE: O(1) cached lookup
    private UoWEnums.DmlOperation getOperationForTypeName(String typeName) {
        UoWEnums.DmlOperation operation = typeOperationCache.get(typeName);
        return operation != null ? operation : UoWEnums.DmlOperation.INSERT_OP;
    }

    // NOTE: getNodeKeyFromName() removed - now using pre-computed GraphNode.nodeKey instead

    // Convert sorted nodes to work items - PERFORMANCE: uses String-based plan getters
    private List<UoWDmlWorkItem> convertNodesToWorkItems(List<GraphNode> sortedNodes) {
        List<UoWDmlWorkItem> sortedWork = new List<UoWDmlWorkItem>();

        for (GraphNode node : sortedNodes) {
            UoWDmlWorkItem workItem = null;

            switch on node.operation {
                when INSERT_OP {
                    workItem = executionPlan.getPlannedInsertWork(node.sobjectTypeName);
                }
                when UPSERT_OP {
                    workItem = executionPlan.getPlannedUpsertWork(node.sobjectTypeName);
                }
                when UPDATE_OP {
                    workItem = executionPlan.getPlannedUpdateWork(node.sobjectTypeName);
                }
                when DELETE_OP {
                    workItem = executionPlan.getPlannedDeleteWork(node.sobjectTypeName);
                }
                when UNDELETE_OP {
                    workItem = executionPlan.getPlannedUndeleteWork(node.sobjectTypeName);
                }
            }

            if (workItem != null) {
                sortedWork.add(workItem);
            }
        }

        return sortedWork;
    }

    // ============================================================================
    // PRIVATE METHODS - CYCLE DETECTION (DFS)
    // ============================================================================

    // DFS-based cycle detection - PERFORMANCE: uses pre-computed nodeKey
    private Boolean hasCycleDFS(GraphNode node, Set<String> visited, Set<String> recursionStack) {
        // PERFORMANCE: Use pre-computed nodeKey
        visited.add(node.nodeKey);
        recursionStack.add(node.nodeKey);

        // Check all neighbors
        for (GraphEdge edge : node.outgoingEdges) {
            GraphNode neighbor = edge.toNode;
            // PERFORMANCE: Use pre-computed nodeKey from neighbor

            if (!visited.contains(neighbor.nodeKey)) {
                if (hasCycleDFS(neighbor, visited, recursionStack)) {
                    return true;
                }
            } else if (recursionStack.contains(neighbor.nodeKey)) {
                // Back edge found - cycle detected
                return true;
            }
        }

        recursionStack.remove(node.nodeKey);
        return false;
    }

    // DFS to find cycle path - PERFORMANCE: uses pre-computed nodeKey
    private Boolean findCycleDFS(GraphNode node, Set<String> visited, Set<String> recursionStack, List<String> path) {
        // PERFORMANCE: Use pre-computed nodeKey
        visited.add(node.nodeKey);
        recursionStack.add(node.nodeKey);
        path.add(node.sobjectTypeName);

        for (GraphEdge edge : node.outgoingEdges) {
            GraphNode neighbor = edge.toNode;
            // PERFORMANCE: Use pre-computed nodeKey from neighbor

            if (!visited.contains(neighbor.nodeKey)) {
                if (findCycleDFS(neighbor, visited, recursionStack, path)) {
                    return true;
                }
            } else if (recursionStack.contains(neighbor.nodeKey)) {
                path.add(neighbor.sobjectTypeName);
                return true;
            }
        }

        recursionStack.remove(node.nodeKey);
        path.remove(path.size() - 1);
        return false;
    }

    // ============================================================================
    // INNER CLASSES
    // ============================================================================

    /**
     * Graph node representing an SObject type with operation.
     */
    public class GraphNode {
        public String sobjectTypeName;  // PERFORMANCE: Use String instead of Schema.SObjectType
        public UoWEnums.DmlOperation operation;
        public String nodeKey;  // PERFORMANCE: Pre-computed key to avoid repeated string concatenation
        public Integer inDegree;
        public List<GraphEdge> incomingEdges;
        public List<GraphEdge> outgoingEdges;

        // Create a new graph node
        public GraphNode(String typeName, UoWEnums.DmlOperation op) {
            this.sobjectTypeName = typeName;
            this.operation = op;
            this.nodeKey = typeName + ':' + op.name();  // PERFORMANCE: Compute once during construction
            this.inDegree = 0;
            this.incomingEdges = new List<GraphEdge>();
            this.outgoingEdges = new List<GraphEdge>();
        }
    }

    /**
     * Graph edge representing a dependency.
     */
    public class GraphEdge {
        public GraphNode fromNode;
        public GraphNode toNode;
        public String reason;
        public Integer weight;

        /**
         * Create a new graph edge.
         *
         * @param fromVertex Source node
         * @param toVertex Target node
         * @param edgeReason Reason for the dependency
         * @param edgeWeight Edge weight (higher = higher priority)
         */
        public GraphEdge(GraphNode fromVertex, GraphNode toVertex, String edgeReason, Integer edgeWeight) {
            this.fromNode = fromVertex;
            this.toNode = toVertex;
            this.reason = edgeReason;
            this.weight = edgeWeight;
        }
    }
}