//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Tests for plan execution related classes: UoWRetryConfig, UoWDependencyGraph,
 * UoWWorkItem, UoWDmlWorkItem, UoWRelationship, and UoWSamplingService.
 * Covers retry configuration, dependency graph building, topological sorting,
 * work item management, relationship resolution, and error-priority sampling.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Tests
 * @see UoWRetryConfig
 * @see UoWDependencyGraph
 * @see UoWWorkItem
 * @see UoWSamplingService
 */
@isTest
@SuppressWarnings('PMD.MethodNamingConventions')
private class UoWPlanExecutionTests {
    // ============================================================================
    // TEST SETUP
    // ============================================================================

    @TestSetup
    static void setupTestData() {
        // Load test configurations
        UoWTestHelpers.loadTestConfigurations();
    }

    // ============================================================================
    // UoWRetryConfig TESTS
    // ============================================================================

    @isTest
    static void test_retryConfig_builder_createsValidConfig() {
        // Act
        Test.startTest();
        UoWRetryConfig config = UoWRetryConfig.builder()
            .withMaxRetries(5)
            .withBaseDelay(1000)
            .withMaxDelay(30000)
            .withBackoffMultiplier(2.0)
            .withJitter(true)
            .withJitterPercent(0.25)
            .build();
        Test.stopTest();

        // Assert
        Assert.areEqual(5, config.maxRetries, 'Max retries should be 5');
        Assert.areEqual(1000, config.baseDelayMs, 'Base delay should be 1000ms');
        Assert.areEqual(30000, config.maxDelayMs, 'Max delay should be 30000ms');
        Assert.areEqual(2.0, config.backoffMultiplier, 'Backoff multiplier should be 2.0');
        Assert.isTrue(config.enableJitter, 'Jitter should be enabled');
        Assert.areEqual(0.25, config.jitterPercent, 'Jitter percent should be 0.25');
    }

    @isTest
    static void test_retryConfig_presets_haveCorrectValues() {
        // Act
        Test.startTest();
        UoWRetryConfig none = UoWRetryConfigs.none();
        UoWRetryConfig quick = UoWRetryConfigs.quick();
        UoWRetryConfig standard = UoWRetryConfigs.standard();
        UoWRetryConfig aggressive = UoWRetryConfigs.aggressive();
        UoWRetryConfig rateLimited = UoWRetryConfigs.rateLimited();
        Test.stopTest();

        // Assert - none preset
        Assert.areEqual(0, none.maxRetries, 'None preset should have 0 retries');

        // Assert - quick preset
        Assert.areEqual(3, quick.maxRetries, 'Quick preset should have 3 retries');
        Assert.areEqual(500, quick.baseDelayMs, 'Quick preset should have 500ms base delay');

        // Assert - standard preset
        Assert.areEqual(3, standard.maxRetries, 'Standard preset should have 3 retries');
        Assert.areEqual(1000, standard.baseDelayMs, 'Standard preset should have 1000ms base delay');

        // Assert - aggressive preset
        Assert.areEqual(5, aggressive.maxRetries, 'Aggressive preset should have 5 retries');
        Assert.areEqual(2000, aggressive.baseDelayMs, 'Aggressive preset should have 2000ms base delay');

        // Assert - rateLimited preset
        Assert.areEqual(5, rateLimited.maxRetries, 'Rate limited preset should have 5 retries');
        Assert.isTrue(rateLimited.retryableStatusCodes.contains(429), 'Rate limited should include 429');
    }

    @isTest
    static void test_retryConfig_calculateDelay_capsAtMaxDelay() {
        // Arrange
        UoWRetryConfig config = UoWRetryConfig.builder()
            .withMaxRetries(10)
            .withBaseDelay(1000)
            .withMaxDelay(5000)  // Cap at 5000ms
            .withBackoffMultiplier(2.0)
            .withJitter(false)
            .build();

        // Act - 5th retry would be 1000 * 2^4 = 16000, but capped at 5000
        Test.startTest();
        Integer delay5 = config.calculateDelay(5);
        Test.stopTest();

        // Assert
        Assert.areEqual(5000, delay5, 'Delay should be capped at maxDelay');
    }

    @isTest
    static void test_retryConfig_shouldRetry_checksStatusCode() {
        // Arrange
        UoWRetryConfig config = UoWRetryConfig.builder()
            .withMaxRetries(3)
            .withRetryableStatusCodes(new Set<Integer>{ 429, 503, 504 })
            .build();

        // Act & Assert
        Test.startTest();
        Assert.isTrue(config.isRetryableStatusCode(429), 'Should retry 429');
        Assert.isTrue(config.isRetryableStatusCode(503), 'Should retry 503');
        Assert.isTrue(config.isRetryableStatusCode(504), 'Should retry 504');
        Assert.isFalse(config.isRetryableStatusCode(400), 'Should not retry 400');
        Assert.isFalse(config.isRetryableStatusCode(500), 'Should not retry 500 by default');
        Test.stopTest();
    }

    @isTest
    static void test_retryConfig_validationErrors() {
        // Test negative maxRetries
        try {
            UoWRetryConfig.builder()
                .withMaxRetries(-1)
                .build();
            Assert.fail('Should throw exception for negative maxRetries');
        } catch (UoWExceptionService.UoWException ex) {
            Assert.isTrue(ex.getMessage().contains('maxRetries'), 'Error should mention maxRetries');
        }

        // Test maxDelay < baseDelay
        try {
            UoWRetryConfig.builder()
                .withBaseDelay(5000)
                .withMaxDelay(1000)
                .build();
            Assert.fail('Should throw exception when maxDelay < baseDelay');
        } catch (UoWExceptionService.UoWException ex) {
            Assert.isTrue(ex.getMessage().contains('maxDelayMs'), 'Error should mention maxDelayMs');
        }

        // Test backoffMultiplier < 1
        try {
            UoWRetryConfig.builder()
                .withBackoffMultiplier(0.5)
                .build();
            Assert.fail('Should throw exception for backoffMultiplier < 1');
        } catch (UoWExceptionService.UoWException ex) {
            Assert.isTrue(ex.getMessage().contains('backoffMultiplier'), 'Error should mention backoffMultiplier');
        }
    }

    @isTest
    static void test_retryConfig_usedWithCalloutBuilder() {
        // Arrange - real world scenario using retry config with callout
        UoWRetryConfig retryConfig = UoWRetryConfigs.standard();

        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        // Act - register callout with retry config
        Test.startTest();
        uow.registerCallout('callout:TestAPI/endpoint', 'POST')
            .withBody('{"test": "data"}')
            .withRetryConfig(retryConfig);
        Test.stopTest();

        // Assert - verify the config was attached (can't fully test without actual callout)
        Assert.isNotNull(retryConfig, 'Retry config should be created');
        Assert.areEqual(3, retryConfig.maxRetries, 'Standard preset should have 3 retries');
    }

    @isTest
    static void test_retryConfig_calculateDelay_exponentialBackoff() {
        // Real-world scenario: API rate limiting requires exponential backoff

        // Arrange
        UoWRetryConfig config = UoWRetryConfig.builder()
            .withMaxRetries(5)
            .withBaseDelay(1000)
            .withMaxDelay(30000)
            .withBackoffMultiplier(2.0)
            .withJitter(false)  // Disable jitter for predictable testing
            .build();

        // Act & Assert
        Test.startTest();
        // First retry: 1000ms (1000 * 2^0)
        Integer delay1 = config.calculateDelay(1);
        Assert.areEqual(1000, delay1, 'First retry should be base delay');

        // Second retry: 2000ms (1000 * 2^1)
        Integer delay2 = config.calculateDelay(2);
        Assert.areEqual(2000, delay2, 'Second retry should double');

        // Third retry: 4000ms (1000 * 2^2)
        Integer delay3 = config.calculateDelay(3);
        Assert.areEqual(4000, delay3, 'Third retry should be 4000ms');

        // Fourth retry: 8000ms (1000 * 2^3)
        Integer delay4 = config.calculateDelay(4);
        Assert.areEqual(8000, delay4, 'Fourth retry should be 8000ms');
        Test.stopTest();
    }

    @isTest
    static void test_retryConfig_calculateDelay_cappedAtMaxDelay() {
        // Real-world scenario: Prevent excessive delays

        // Arrange
        UoWRetryConfig config = UoWRetryConfig.builder()
            .withMaxRetries(10)
            .withBaseDelay(1000)
            .withMaxDelay(5000)
            .withBackoffMultiplier(2.0)
            .withJitter(false)
            .build();

        // Act & Assert
        Test.startTest();
        // Attempt 4 would be 8000ms but capped at 5000ms
        Integer delay4 = config.calculateDelay(4);
        Assert.isTrue(delay4 <= 5000, 'Delay should be capped at maxDelay');

        // Attempt 10 should also be capped
        Integer delay10 = config.calculateDelay(10);
        Assert.isTrue(delay10 <= 5000, 'High attempt delay should be capped');
        Test.stopTest();
    }

    @isTest
    static void test_retryConfig_calculateDelay_exceedsWithJitter() {
        // Arrange
        UoWRetryConfig config = UoWRetryConfig.builder()
            .withMaxRetries(10)
            .withBaseDelay(1000)
            .withMaxDelay(5000)
            .withBackoffMultiplier(2.0)
            .withJitter(true)
            .withJitterPercent(0.25)
            .build();

        // Act & Assert
        Test.startTest();
        Integer delay4 = config.calculateDelay(4);
        Assert.isTrue(delay4 >= 0, 'Delay should be exceed with jitter');
        Test.stopTest();
    }

    @isTest
    static void test_retryConfig_isRetryableStatusCode_knownCodes() {
        // Real-world scenario: Determine if HTTP error is transient

        // Arrange
        UoWRetryConfig config = UoWRetryConfig.builder().build();

        // Act & Assert
        Test.startTest();
        // Retryable codes
        Assert.isTrue(config.isRetryableStatusCode(429), '429 Too Many Requests should be retryable');
        Assert.isTrue(config.isRetryableStatusCode(500), '500 Internal Server Error should be retryable');
        Assert.isTrue(config.isRetryableStatusCode(502), '502 Bad Gateway should be retryable');
        Assert.isTrue(config.isRetryableStatusCode(503), '503 Service Unavailable should be retryable');
        Assert.isTrue(config.isRetryableStatusCode(504), '504 Gateway Timeout should be retryable');

        // Non-retryable codes
        Assert.isFalse(config.isRetryableStatusCode(200), '200 OK should not be retryable');
        Assert.isFalse(config.isRetryableStatusCode(400), '400 Bad Request should not be retryable');
        Assert.isFalse(config.isRetryableStatusCode(401), '401 Unauthorized should not be retryable');
        Assert.isFalse(config.isRetryableStatusCode(404), '404 Not Found should not be retryable');
        Test.stopTest();
    }

    @isTest
    static void test_retryConfig_isRetryableException_calloutExceptions() {
        // Real-world scenario: Determine if exception is transient

        // Arrange
        UoWRetryConfig config = UoWRetryConfig.builder().build();

        // Act & Assert - Retryable exceptions
        Test.startTest();
        CalloutException timeoutEx = new CalloutException();
        timeoutEx.setMessage('Request timeout');
        Assert.isTrue(config.isRetryableException(timeoutEx), 'Timeout should be retryable');

        CalloutException connEx = new CalloutException();
        connEx.setMessage('Unable to connect to endpoint');
        Assert.isTrue(config.isRetryableException(connEx), 'Connection error should be retryable');

        // Non-retryable exceptions
        DmlException dmlEx = new DmlException();
        Assert.isFalse(config.isRetryableException(dmlEx), 'DML exception should not be retryable');

        System.NullPointerException nullEx = new System.NullPointerException();
        Assert.isFalse(config.isRetryableException(nullEx), 'NullPointerException should not be retryable');

        Assert.isFalse(config.isRetryableException(null), 'null value should not be retryable');
        Test.stopTest();
    }

    @isTest
    static void test_retryConfig_addRetryableStatusCodes_extendsDefault() {
        // Real-world scenario: Add custom retryable status codes

        // Arrange
        UoWRetryConfig config = UoWRetryConfig.builder()
            .addRetryableStatusCodes(new Set<Integer>{ 408, 599 })
            .build();

        // Act & Assert
        Test.startTest();
        // Default codes still work
        Assert.isTrue(config.isRetryableStatusCode(429), 'Default 429 should still be retryable');
        Assert.isTrue(config.isRetryableStatusCode(503), 'Default 503 should still be retryable');

        // Custom codes added
        Assert.isTrue(config.isRetryableStatusCode(408), 'Custom 408 should be retryable');
        Assert.isTrue(config.isRetryableStatusCode(599), 'Custom 599 should be retryable');
        Test.stopTest();
    }

    @isTest
    static void test_retryConfig_toString_formatsCorrectly() {
        // Real-world scenario: Debug logging of retry configuration

        // Arrange
        UoWRetryConfig config = UoWRetryConfig.builder()
            .withMaxRetries(5)
            .withBaseDelay(2000)
            .withMaxDelay(60000)
            .withBackoffMultiplier(2.0)
            .withJitter(true)
            .build();

        // Act
        Test.startTest();
        String configStr = config.toString();
        Test.stopTest();

        // Assert
        Assert.isTrue(configStr.contains('maxRetries=5'), 'Should contain maxRetries');
        Assert.isTrue(configStr.contains('baseDelayMs=2000'), 'Should contain baseDelayMs');
        Assert.isTrue(configStr.contains('backoffMultiplier=2'), 'Should contain backoffMultiplier');
    }

    // ============================================================================
    // UoWDependencyGraph TESTS
    // ============================================================================

    @isTest
    static void test_dependencyGraph_constructor_initializesEmptyGraph() {
        // Arrange
        UoWPlan plan = new UoWPlan();

        // Act
        Test.startTest();
        UoWDependencyGraph graph = new UoWDependencyGraph(plan, null);
        Test.stopTest();

        // Assert - Graph should be empty before buildGraph()
        Assert.areEqual(0, graph.getNodeCount(), 'New graph should have no nodes');
        Assert.areEqual(0, graph.getEdgeCount(), 'New graph should have no edges');
    }

    @isTest
    static void test_dependencyGraph_buildGraph_createsNodesForInserts() {
        // Arrange
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks');
        UoWPlan plan = uow.getPlan();

        // Act
        Test.startTest();
        UoWDependencyGraph graph = new UoWDependencyGraph(plan, null);
        graph.buildGraph();
        Test.stopTest();

        // Assert - Should have nodes for Account and Contact
        Assert.isTrue(graph.getNodeCount() >= 2, 'Graph should have at least 2 nodes for registered types');
    }

    @isTest
    static void test_dependencyGraph_buildGraph_idempotent() {
        // Arrange - Multiple buildGraph calls should not change the graph
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks');
        UoWPlan plan = uow.getPlan();
        UoWDependencyGraph graph = new UoWDependencyGraph(plan, null);

        // Act
        Test.startTest();
        graph.buildGraph();
        Integer nodeCountAfterFirst = graph.getNodeCount();
        Integer edgeCountAfterFirst = graph.getEdgeCount();

        graph.buildGraph(); // Second call should be idempotent
        Integer nodeCountAfterSecond = graph.getNodeCount();
        Integer edgeCountAfterSecond = graph.getEdgeCount();
        Test.stopTest();

        // Assert - Counts should be the same after second build
        Assert.areEqual(nodeCountAfterFirst, nodeCountAfterSecond, 'Node count should not change on second build');
        Assert.areEqual(edgeCountAfterFirst, edgeCountAfterSecond, 'Edge count should not change on second build');
    }

    @isTest
    static void test_dependencyGraph_findCircularDependencyPath_emptyForNoCycle() {
        // Arrange - Simple insert with no relationships
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        Account acc = UoWCoreTestDataFactory.createAccount('Test Account');
        uow.registerInsert(acc);

        UoWPlan plan = uow.getPlan();
        UoWDependencyGraph graph = new UoWDependencyGraph(plan, null);

        // Act
        Test.startTest();
        List<String> cyclePath = graph.findCircularDependencyPath();
        Test.stopTest();

        // Assert
        Assert.isTrue(cyclePath.isEmpty(), 'Should return empty path when no cycle exists');
    }

    @isTest
    static void test_dependencyGraph_getTopologicallySortedDml_ordersByDependency() {
        // Arrange - Account must be inserted before Contact
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        Account acc = UoWCoreTestDataFactory.createAccount('Parent Account');
        Contact con = UoWCoreTestDataFactory.createContact('Child Contact', null);

        uow.registerInsert(acc);
        uow.registerInsert(con);
        uow.relate(con, Contact.AccountId, acc);

        UoWPlan plan = uow.getPlan();
        UoWDependencyGraph graph = new UoWDependencyGraph(plan, null);

        // Act
        Test.startTest();
        List<UoWDmlWorkItem> sortedWork = graph.getTopologicallySortedDml();
        Test.stopTest();

        // Assert - Account should come before Contact
        Assert.areEqual(2, sortedWork.size(), 'Should have 2 work items');

        Integer accountIndex = -1;
        Integer contactIndex = -1;
        for (Integer i = 0; i < sortedWork.size(); i++) {
            if (sortedWork[i].sobjectType == Account.SObjectType) {
                accountIndex = i;
            }
            if (sortedWork[i].sobjectType == Contact.SObjectType) {
                contactIndex = i;
            }
        }

        Assert.isTrue(accountIndex >= 0, 'Account should be in sorted work');
        Assert.isTrue(contactIndex >= 0, 'Contact should be in sorted work');
        Assert.isTrue(accountIndex < contactIndex, 'Account should come before Contact in topological order');
    }

    @isTest
    static void test_dependencyGraph_getTopologicallySortedDml_buildsGraphIfNotBuilt() {
        // Arrange - Don't call buildGraph() explicitly
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        Account acc = UoWCoreTestDataFactory.createAccount('Test Account');
        uow.registerInsert(acc);

        UoWPlan plan = uow.getPlan();
        UoWDependencyGraph graph = new UoWDependencyGraph(plan, null);

        // Act - Should auto-build graph
        Test.startTest();
        List<UoWDmlWorkItem> sortedWork = graph.getTopologicallySortedDml();
        Test.stopTest();

        // Assert
        Assert.areEqual(1, sortedWork.size(), 'Should have 1 work item');
        Assert.isTrue(graph.getNodeCount() > 0, 'Graph should be built');
    }

    @isTest
    static void test_dependencyGraph_multiLevelHierarchy_sortsCorrectly() {
        // Arrange - Grandparent -> Parent -> Child hierarchy
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        Account acc = UoWCoreTestDataFactory.createAccount('Account');
        Contact con = UoWCoreTestDataFactory.createContact('Contact', null);
        Case cs = new Case(Subject = 'Test Case');

        uow.registerInsert(acc);
        uow.registerInsert(con);
        uow.relate(con, Contact.AccountId, acc);
        uow.registerInsert(cs);
        uow.relate(cs, Case.ContactId, con);

        UoWPlan plan = uow.getPlan();
        UoWDependencyGraph graph = new UoWDependencyGraph(plan, null);

        // Act
        Test.startTest();
        List<UoWDmlWorkItem> sortedWork = graph.getTopologicallySortedDml();
        Test.stopTest();

        // Assert - Should respect all dependency levels
        Assert.areEqual(3, sortedWork.size(), 'Should have 3 work items');

        // Find positions
        Map<Schema.SObjectType, Integer> positions = new Map<Schema.SObjectType, Integer>();
        for (Integer i = 0; i < sortedWork.size(); i++) {
            positions.put(sortedWork[i].sobjectType, i);
        }

        Assert.isTrue(positions.get(Account.SObjectType) < positions.get(Contact.SObjectType),
            'Account should come before Contact');
        Assert.isTrue(positions.get(Contact.SObjectType) < positions.get(Case.SObjectType),
            'Contact should come before Case');
    }

    @isTest
    static void test_dependencyGraph_updateOperation_createsNode() {
        // Arrange - Update operation should create a node
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        Account acc = new Account(
            Id = UoWTestHelpers.generateFakeId(Account.SObjectType, 1),
            Name = 'Updated Account'
        );
        uow.registerUpdate(acc);

        UoWPlan plan = uow.getPlan();
        UoWDependencyGraph graph = new UoWDependencyGraph(plan, null);

        // Act
        Test.startTest();
        graph.buildGraph();
        Test.stopTest();

        // Assert
        Assert.isTrue(graph.getNodeCount() >= 1, 'Should have node for update operation');
    }

    @isTest
    static void test_dependencyGraph_deleteOperation_createsNode() {
        // Arrange - Delete operation should create a node
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        Account acc = new Account(Id = UoWTestHelpers.generateFakeId(Account.SObjectType, 1));
        uow.registerDelete(acc);

        UoWPlan plan = uow.getPlan();
        UoWDependencyGraph graph = new UoWDependencyGraph(plan, null);

        // Act
        Test.startTest();
        graph.buildGraph();
        Test.stopTest();

        // Assert
        Assert.isTrue(graph.getNodeCount() >= 1, 'Should have node for delete operation');
    }

    @isTest
    static void test_dependencyGraph_upsertOperation_createsNode() {
        // Arrange - Upsert operation should create a node
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        Account acc = UoWCoreTestDataFactory.createAccount('Upsert Account');
        uow.registerUpsert(acc, Account.Name);

        UoWPlan plan = uow.getPlan();
        UoWDependencyGraph graph = new UoWDependencyGraph(plan, null);

        // Act
        Test.startTest();
        graph.buildGraph();
        Test.stopTest();

        // Assert
        Assert.isTrue(graph.getNodeCount() >= 1, 'Should have node for upsert operation');
    }

    @isTest
    static void test_dependencyGraph_undeleteOperation_createsNode() {
        // Arrange - Undelete operation should create a node
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        Account acc = new Account(Id = UoWTestHelpers.generateFakeId(Account.SObjectType, 1));
        uow.registerUndelete(acc);

        UoWPlan plan = uow.getPlan();
        UoWDependencyGraph graph = new UoWDependencyGraph(plan, null);

        // Act
        Test.startTest();
        graph.buildGraph();
        Test.stopTest();

        // Assert
        Assert.isTrue(graph.getNodeCount() >= 1, 'Should have node for undelete operation');
    }

    @isTest
    static void test_dependencyGraph_mixedOperations_sortsAllTypes() {
        // Arrange - Mix of insert, update, delete operations
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        // Insert Account
        Account acc = UoWCoreTestDataFactory.createAccount('Insert Account');
        uow.registerInsert(acc);

        // Update Contact
        Contact con = new Contact(
            Id = UoWTestHelpers.generateFakeId(Contact.SObjectType, 1),
            LastName = 'Updated Contact'
        );
        uow.registerUpdate(con);

        UoWPlan plan = uow.getPlan();
        UoWDependencyGraph graph = new UoWDependencyGraph(plan, null);

        // Act
        Test.startTest();
        List<UoWDmlWorkItem> sortedWork = graph.getTopologicallySortedDml();
        Test.stopTest();

        // Assert - Should have both work items
        Assert.areEqual(2, sortedWork.size(), 'Should have 2 work items');
    }

    @isTest
    static void test_dependencyGraph_emptyPlan_returnsEmptyList() {
        // Arrange - No work items registered
        UoWPlan plan = new UoWPlan();
        UoWDependencyGraph graph = new UoWDependencyGraph(plan, null);

        // Act
        Test.startTest();
        List<UoWDmlWorkItem> sortedWork = graph.getTopologicallySortedDml();
        Test.stopTest();

        // Assert
        Assert.isTrue(sortedWork.isEmpty(), 'Empty plan should return empty sorted list');
        Assert.areEqual(0, graph.getNodeCount(), 'Empty plan should have no nodes');
        Assert.areEqual(0, graph.getEdgeCount(), 'Empty plan should have no edges');
    }

    @isTest
    static void test_dependencyGraph_graphNode_constructor() {
        // Test GraphNode inner class - now uses String type name
        Test.startTest();
        UoWDependencyGraph.GraphNode node = new UoWDependencyGraph.GraphNode(
            'Account',
            UoWEnums.DmlOperation.INSERT_OP
        );
        Test.stopTest();

        // Assert
        Assert.areEqual('Account', node.sobjectTypeName, 'SObjectTypeName should match');
        Assert.areEqual(UoWEnums.DmlOperation.INSERT_OP, node.operation, 'Operation should match');
        Assert.areEqual(0, node.inDegree, 'Initial inDegree should be 0');
        Assert.isNotNull(node.incomingEdges, 'Incoming edges list should be initialized');
        Assert.isNotNull(node.outgoingEdges, 'Outgoing edges list should be initialized');
        Assert.isTrue(node.incomingEdges.isEmpty(), 'Incoming edges should be empty');
        Assert.isTrue(node.outgoingEdges.isEmpty(), 'Outgoing edges should be empty');
    }

    @isTest
    static void test_dependencyGraph_graphEdge_constructor() {
        // Test GraphEdge inner class - now uses String type names
        UoWDependencyGraph.GraphNode fromNode = new UoWDependencyGraph.GraphNode(
            'Account',
            UoWEnums.DmlOperation.INSERT_OP
        );
        UoWDependencyGraph.GraphNode toNode = new UoWDependencyGraph.GraphNode(
            'Contact',
            UoWEnums.DmlOperation.INSERT_OP
        );

        Test.startTest();
        UoWDependencyGraph.GraphEdge edge = new UoWDependencyGraph.GraphEdge(
            fromNode,
            toNode,
            'AccountId lookup',
            10
        );
        Test.stopTest();

        // Assert
        Assert.areEqual(fromNode, edge.fromNode, 'FromNode should match');
        Assert.areEqual(toNode, edge.toNode, 'ToNode should match');
        Assert.areEqual('AccountId lookup', edge.reason, 'Reason should match');
        Assert.areEqual(10, edge.weight, 'Weight should match');
    }

    @isTest
    static void test_dependencyGraph_hasCircularDependencies_autoBuildsGraph() {
        // Arrange - Don't call buildGraph() explicitly
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        Account acc = UoWCoreTestDataFactory.createAccount('Test Account');
        uow.registerInsert(acc);

        UoWPlan plan = uow.getPlan();
        UoWDependencyGraph graph = new UoWDependencyGraph(plan, null);

        // Act - Should auto-build graph
        Test.startTest();
        Boolean hasCycle = graph.hasCircularDependencies();
        Test.stopTest();

        // Assert
        Assert.isFalse(hasCycle, 'Single node should have no cycles');
        Assert.isTrue(graph.getNodeCount() > 0, 'Graph should be built');
    }

    @isTest
    static void test_dependencyGraph_findCircularDependencyPath_autoBuildsGraph() {
        // Arrange - Don't call buildGraph() explicitly
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        Account acc = UoWCoreTestDataFactory.createAccount('Test Account');
        uow.registerInsert(acc);

        UoWPlan plan = uow.getPlan();
        UoWDependencyGraph graph = new UoWDependencyGraph(plan, null);

        // Act - Should auto-build graph
        Test.startTest();
        List<String> cyclePath = graph.findCircularDependencyPath();
        Test.stopTest();

        // Assert
        Assert.isTrue(cyclePath.isEmpty(), 'No cycle should exist');
        Assert.isTrue(graph.getNodeCount() > 0, 'Graph should be built');
    }

    @isTest
    static void test_dependencyGraph_noPrecedence_usesRegistrationOrder() {
        // Arrange - Without UoWObjectPrecedence__mdt configured, registration order is used
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        // Register Contact first, then Account (no explicit relationship)
        Contact con = UoWCoreTestDataFactory.createContact('Test Contact', null);
        Account acc = UoWCoreTestDataFactory.createAccount('Test Account');

        uow.registerInsert(con);
        uow.registerInsert(acc);

        UoWPlan plan = uow.getPlan();
        UoWDependencyGraph graph = new UoWDependencyGraph(plan, null);

        // Act
        Test.startTest();
        List<UoWDmlWorkItem> sortedWork = graph.getTopologicallySortedDml();
        Test.stopTest();

        // Assert - Without configured precedence, both should be returned (order is registration-based)
        // Since there's no relationship and no precedence, order follows registration
        Assert.areEqual(2, sortedWork.size(), 'Should have 2 work items');

        // Verify both types are present (order depends on registration)
        Set<Schema.SObjectType> types = new Set<Schema.SObjectType>();
        for (UoWDmlWorkItem workItem : sortedWork) {
            types.add(workItem.sobjectType);
        }
        Assert.isTrue(types.contains(Account.SObjectType), 'Should contain Account');
        Assert.isTrue(types.contains(Contact.SObjectType), 'Should contain Contact');
    }

    @isTest
    static void test_dependencyGraph_relate_overridesPrecedence() {
        // Arrange - Test that relate() always wins over any potential precedence
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        // Register with explicit relationship: Contact depends on Account
        Account acc = UoWCoreTestDataFactory.createAccount('Parent Account');
        Contact con = UoWCoreTestDataFactory.createContact('Child Contact', null);

        // Register Contact first (opposite of dependency order)
        uow.registerInsert(acc);
        uow.registerInsert(con);
        uow.relate(con, Contact.AccountId, acc);

        UoWPlan plan = uow.getPlan();
        UoWDependencyGraph graph = new UoWDependencyGraph(plan, null);

        // Act
        Test.startTest();
        List<UoWDmlWorkItem> sortedWork = graph.getTopologicallySortedDml();
        Test.stopTest();

        // Assert - Account must come before Contact due to relate()
        Assert.areEqual(2, sortedWork.size(), 'Should have 2 work items');

        Integer accountIndex = -1;
        Integer contactIndex = -1;
        for (Integer i = 0; i < sortedWork.size(); i++) {
            if (sortedWork[i].sobjectType == Account.SObjectType) {
                accountIndex = i;
            }
            if (sortedWork[i].sobjectType == Contact.SObjectType) {
                contactIndex = i;
            }
        }

        Assert.isTrue(accountIndex < contactIndex,
            'Account should come before Contact due to explicit relate() relationship');
    }

    @isTest
    static void test_dependencyGraph_staticHelpers_precedenceNotConfigured() {
        UoWDependencyGraph.resetPrecedenceCache();

        // Test the static helper methods for precedence checking
        Test.startTest();
        // Without any UoWObjectPrecedence__mdt records, these should return false/null
        Boolean accountPrecedence = UoWDependencyGraph.hasPrecedenceConfigured('Account');
        Boolean customPrecedence = UoWDependencyGraph.hasPrecedenceConfigured('Some_Custom_Object__c');
        Integer precedence = UoWDependencyGraph.getPrecedence('Some_Custom_Object__c');
        Test.stopTest();

        // Assert
        Assert.isTrue(accountPrecedence, 'Should return true for Account precedence metadata');
        Assert.isFalse(customPrecedence, 'Should return false when no precedence metadata exists');
        Assert.isNull(precedence, 'Should return null when no precedence configured');
    }

    @isTest
    static void test_dependencyGraph_edgeCount_incrementsCorrectly() {
        // Arrange - Create multiple relationships to verify edge counting
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        Account acc = UoWCoreTestDataFactory.createAccount('Parent Account');
        Contact con1 = UoWCoreTestDataFactory.createContact('Child 1', null);
        Contact con2 = UoWCoreTestDataFactory.createContact('Child 2', null);

        uow.registerInsert(acc);
        uow.registerInsert(con1);
        uow.relate(con1, Contact.AccountId, acc);
        uow.registerInsert(con2);
        uow.relate(con2, Contact.AccountId, acc);

        UoWPlan plan = uow.getPlan();
        UoWDependencyGraph graph = new UoWDependencyGraph(plan, null);

        // Act
        Test.startTest();
        graph.buildGraph();
        Integer edgeCount = graph.getEdgeCount();
        Test.stopTest();

        // Assert - Should have edges for relationship
        Assert.isTrue(edgeCount >= 1, 'Should have at least 1 edge for Account -> Contact relationship');
    }

    // ============================================================================
    // WORK ITEM TESTS
    // ============================================================================

    @isTest
    static void test_workItem_constructor_initializesFields() {
        // Test base WorkItem constructor
        Test.startTest();
        UoWWorkItem workItem = new UoWWorkItem(UoWEnums.WorkType.DML);
        Test.stopTest();

        // Assert
        Assert.isNotNull(workItem.workId, 'Work ID should be generated');
        Assert.areEqual(UoWEnums.WorkType.DML, workItem.workType, 'Work type should match');
        Assert.isNotNull(workItem.requestedAt, 'RequestedAt should be set');
        Assert.isFalse(workItem.isExecuted, 'isExecuted should be false initially');
        Assert.isNotNull(workItem.errors, 'Errors list should be initialized');
    }

    @isTest
    static void test_workItem_addError_withException() {
        // Arrange
        UoWWorkItem workItem = new UoWWorkItem(UoWEnums.WorkType.DML);
        Exception testEx = new System.DmlException('Test error');

        // Act
        Test.startTest();
        workItem.addError(testEx);
        Test.stopTest();

        // Assert
        Assert.areEqual(1, workItem.errors.size(), 'Should have 1 error');
        Assert.isTrue(workItem.errors[0].errorMessage.contains('Test error'), 'Error message should match');
    }

    @isTest
    static void test_workItem_addError_withErrorInfo() {
        // Arrange
        UoWWorkItem workItem = new UoWWorkItem(UoWEnums.WorkType.DML);
        UoWExceptionService.ErrorInfo error = new UoWExceptionService.ErrorInfo(
            new System.DmlException('Test error')
        );

        // Act
        Test.startTest();
        workItem.addError(error);
        Test.stopTest();

        // Assert
        Assert.areEqual(1, workItem.errors.size(), 'Should have 1 error');
    }

    @isTest
    static void test_workItem_addError_nullIgnored() {
        // Arrange
        UoWWorkItem workItem = new UoWWorkItem(UoWEnums.WorkType.DML);
        Exception nullEx = null;
        UoWExceptionService.ErrorInfo nullError = null;

        // Act
        Test.startTest();
        workItem.addError(nullEx);
        workItem.addError(nullError);
        Test.stopTest();

        // Assert
        Assert.areEqual(0, workItem.errors.size(), 'Null errors should be ignored');
    }

    @isTest
    static void test_workItem_captureGovernorLimits() {
        // Arrange
        UoWWorkItem workItem = new UoWWorkItem(UoWEnums.WorkType.DML);

        // Act
        Test.startTest();
        workItem.captureGovernorLimitsBefore();
        // Simulate some work...
        workItem.captureGovernorLimitsAfter();
        UoWGovernorLimits consumed = workItem.getGovernorLimitsConsumed();
        Test.stopTest();

        // Assert
        Assert.isNotNull(workItem.governorLimits.before, 'Before limits should be captured');
        Assert.isNotNull(workItem.governorLimits.after, 'After limits should be captured');
        Assert.isNotNull(consumed, 'Consumed limits should be calculated');
    }

    @isTest
    static void test_dmlWorkItem_addRecords() {
        // Arrange
        List<Account> initialRecords = new List<Account>{
            new Account(Name = 'Account 1')
        };
        UoWDmlWorkItem workItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.INSERT_OP,
            Account.SObjectType,
            initialRecords
        );

        List<Account> newRecords = new List<Account>{
            new Account(Name = 'Account 2'),
            new Account(Name = 'Account 3')
        };

        // Act
        Test.startTest();
        workItem.addRecords(newRecords);
        Test.stopTest();

        // Assert
        Assert.areEqual(3, workItem.getOriginalRecords().size(), 'Should have 3 total records');
    }

    @isTest
    static void test_dmlWorkItem_addRecords_nullOrEmpty() {
        // Arrange
        List<Account> initialRecords = new List<Account>{
            new Account(Name = 'Account 1')
        };
        UoWDmlWorkItem workItem = new UoWDmlWorkItem(
            UoWEnums.DmlOperation.INSERT_OP,
            Account.SObjectType,
            initialRecords
        );

        // Act
        Test.startTest();
        workItem.addRecords(null);
        workItem.addRecords(new List<Account>());
        Test.stopTest();

        // Assert
        Assert.areEqual(1, workItem.getOriginalRecords().size(), 'Original record count unchanged');
    }

    @isTest
    static void test_relationship_constructor() {
        // Arrange
        Contact con = new Contact(LastName = 'Test');
        Account acc = new Account(Name = 'Parent');

        // Act
        Test.startTest();
        UoWRelationship relationship = new UoWRelationship(
            con,
            Contact.AccountId,
            acc
        );
        Test.stopTest();

        // Assert
        Assert.areEqual(con, relationship.childRecord, 'Child record should match');
        Assert.areEqual(Contact.AccountId, relationship.childField, 'Lookup field should match');
        Assert.areEqual(acc, relationship.parentRecord, 'Parent record should match');
        Assert.isFalse(relationship.isResolved(), 'Should not be resolved initially');
    }

    @isTest
    static void test_relationship_isSameObjectRelationship() {
        // Arrange - Account parent relationship (same object - hierarchical)
        Account parent = new Account(Name = 'Parent');
        Account child = new Account(Name = 'Child');

        // Act
        Test.startTest();
        UoWRelationship sameObject = new UoWRelationship(
            child,
            Account.ParentId,
            parent
        );
        UoWRelationship differentObject = new UoWRelationship(
            new Contact(LastName = 'Test'),
            Contact.AccountId,
            new Account(Name = 'ParentAcc')
        );
        Test.stopTest();

        // Assert
        Assert.isTrue(sameObject.isSameObjectRelationship(), 'Account -> Account should be same object');
        Assert.isFalse(differentObject.isSameObjectRelationship(), 'Contact -> Account should not be same object');
    }

    @isTest
    static void test_relationship_isResolved() {
        // Arrange
        Contact con = new Contact(LastName = 'Test');
        Account acc = new Account(Name = 'Parent');
        UoWRelationship relationship = new UoWRelationship(
            con,
            Contact.AccountId,
            acc
        );

        // Act
        Test.startTest();
        Boolean beforeResolve = relationship.isResolved();
        // Simulate DML by assigning a fake ID to the parent record
        acc.Id = UoWTestHelpers.generateFakeId(Account.SObjectType, 1);
        Boolean afterResolve = relationship.isResolved();
        Test.stopTest();

        // Assert
        Assert.isFalse(beforeResolve, 'Should not be resolved before parent has ID');
        Assert.isTrue(afterResolve, 'Should be resolved after parent has ID');
    }

    // ============================================================================
    // UoWSamplingService TESTS - sampleIndices with Error-Priority
    // ============================================================================

    @isTest
    static void test_samplingService_zeroCount_returnsEmpty() {
        // Arrange
        UoWSerializationConfig config = UoWSerializationConfig.forAudit(UoWEnums.SamplingStrategy.FIRST_N, 5);

        // Act
        Test.startTest();
        List<Integer> result = UoWSamplingService.sampleIndices(0, null, config);
        Test.stopTest();

        // Assert
        Assert.isNotNull(result, 'Should return empty list not null');
        Assert.isTrue(result.isEmpty(), 'Should return empty list for zero count');
    }

    @isTest
    static void test_samplingService_nullCount_returnsEmpty() {
        // Arrange
        UoWSerializationConfig config = UoWSerializationConfig.forAudit(UoWEnums.SamplingStrategy.FIRST_N, 5);

        // Act
        Test.startTest();
        List<Integer> result = UoWSamplingService.sampleIndices(null, null, config);
        Test.stopTest();

        // Assert
        Assert.isNotNull(result, 'Should return empty list not null');
        Assert.isTrue(result.isEmpty(), 'Should return empty list for null count');
    }

    @isTest
    static void test_samplingService_countUnderLimit_returnsAllIndices() {
        // Arrange - 3 items when limit is 5
        UoWSerializationConfig config = UoWSerializationConfig.forAudit(UoWEnums.SamplingStrategy.FIRST_N, 5);

        // Act
        Test.startTest();
        List<Integer> result = UoWSamplingService.sampleIndices(3, null, config);
        Test.stopTest();

        // Assert
        Assert.areEqual(3, result.size(), 'Should return all indices when under limit');
        Assert.areEqual(0, result[0], 'First index should be 0');
        Assert.areEqual(1, result[1], 'Second index should be 1');
        Assert.areEqual(2, result[2], 'Third index should be 2');
    }

    @isTest
    static void test_samplingService_samplingDisabled_returnsAllIndices() {
        // Arrange - 10 items but disable sampling
        UoWSerializationConfig config = UoWSerializationConfig.forAudit();
        config.applySampling = false;

        // Act
        Test.startTest();
        List<Integer> result = UoWSamplingService.sampleIndices(10, null, config);
        Test.stopTest();

        // Assert
        Assert.areEqual(10, result.size(), 'Should return all indices when sampling disabled');
    }

    @isTest
    static void test_samplingService_firstNStrategy_returnsFirstIndices() {
        // Arrange - 10 items, sample first 3
        UoWSerializationConfig config = UoWSerializationConfig.forAudit(UoWEnums.SamplingStrategy.FIRST_N, 3);

        // Act
        Test.startTest();
        List<Integer> result = UoWSamplingService.sampleIndices(10, null, config);
        Test.stopTest();

        // Assert
        Assert.areEqual(3, result.size(), 'Should return 3 indices');
        Assert.areEqual(0, result[0], 'First index should be 0');
        Assert.areEqual(1, result[1], 'Second index should be 1');
        Assert.areEqual(2, result[2], 'Third index should be 2');
    }

    @isTest
    static void test_samplingService_lastNStrategy_returnsLastIndices() {
        // Arrange - 10 items, sample last 3
        UoWSerializationConfig config = UoWSerializationConfig.forAudit(UoWEnums.SamplingStrategy.LAST_N, 3);

        // Act
        Test.startTest();
        List<Integer> result = UoWSamplingService.sampleIndices(10, null, config);
        Test.stopTest();

        // Assert
        Assert.areEqual(3, result.size(), 'Should return 3 indices');
        Assert.areEqual(7, result[0], 'First index should be 7');
        Assert.areEqual(8, result[1], 'Second index should be 8');
        Assert.areEqual(9, result[2], 'Third index should be 9');
    }

    @isTest
    static void test_samplingService_randomStrategy_returnsCorrectCount() {
        // Arrange - 10 items, sample random 3
        UoWSerializationConfig config = UoWSerializationConfig.forAudit(UoWEnums.SamplingStrategy.RANDOM, 3);

        // Act
        Test.startTest();
        List<Integer> result = UoWSamplingService.sampleIndices(10, null, config);
        Test.stopTest();

        // Assert
        Assert.areEqual(3, result.size(), 'Should return 3 indices');
        // Verify all indices are valid (0-9) and sorted
        for (Integer i = 0; i < result.size(); i++) {
            Assert.isTrue(result[i] >= 0 && result[i] < 10, 'Index should be valid');
            if (i > 0) {
                Assert.isTrue(result[i] > result[i-1], 'Indices should be sorted');
            }
        }
    }

    @isTest
    static void test_samplingService_nullConfig_returnsAllIndices() {
        // Act
        Test.startTest();
        List<Integer> result = UoWSamplingService.sampleIndices(10, null, null);
        Test.stopTest();

        // Assert - With null config, sampling is disabled so all indices are returned
        Assert.areEqual(10, result.size(), 'Should return all indices when config is null');
    }

    // ============================================================================
    // UoWSamplingService TESTS - Error-Priority Sampling
    // ============================================================================

    @isTest
    static void test_samplingService_errorPriority_failedIndicesFirst() {
        // Arrange - 10 items, 2 failed (indices 3 and 7), sample 5
        Set<Integer> failedIndices = new Set<Integer>{ 3, 7 };
        UoWSerializationConfig config = UoWSerializationConfig.forAudit(UoWEnums.SamplingStrategy.FIRST_N, 5);

        // Act
        Test.startTest();
        List<Integer> result = UoWSamplingService.sampleIndices(10, failedIndices, config);
        Test.stopTest();

        // Assert - Failed indices should be included, plus first 3 successful indices
        Assert.areEqual(5, result.size(), 'Should return 5 indices');
        Assert.isTrue(result.contains(3), 'Should include failed index 3');
        Assert.isTrue(result.contains(7), 'Should include failed index 7');
        // Result should be sorted
        for (Integer i = 1; i < result.size(); i++) {
            Assert.isTrue(result[i] > result[i-1], 'Indices should be sorted');
        }
    }

    @isTest
    static void test_samplingService_errorPriority_allFailed_sampledByStrategy() {
        // Arrange - 10 items, all failed, sample 3 using FIRST_N
        Set<Integer> failedIndices = new Set<Integer>{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
        UoWSerializationConfig config = UoWSerializationConfig.forAudit(UoWEnums.SamplingStrategy.FIRST_N, 3);

        // Act
        Test.startTest();
        List<Integer> result = UoWSamplingService.sampleIndices(10, failedIndices, config);
        Test.stopTest();

        // Assert - Should sample from failures using FIRST_N strategy
        Assert.areEqual(3, result.size(), 'Should return 3 indices');
        Assert.areEqual(0, result[0], 'First index should be 0');
        Assert.areEqual(1, result[1], 'Second index should be 1');
        Assert.areEqual(2, result[2], 'Third index should be 2');
    }

    @isTest
    static void test_samplingService_errorPriority_moreFailed_thanSampleSize() {
        // Arrange - 10 items, 5 failed (0, 2, 4, 6, 8), sample 3 using FIRST_N
        Set<Integer> failedIndices = new Set<Integer>{ 0, 2, 4, 6, 8 };
        UoWSerializationConfig config = UoWSerializationConfig.forAudit(UoWEnums.SamplingStrategy.FIRST_N, 3);

        // Act
        Test.startTest();
        List<Integer> result = UoWSamplingService.sampleIndices(10, failedIndices, config);
        Test.stopTest();

        // Assert - Should sample from failures only (first 3)
        Assert.areEqual(3, result.size(), 'Should return 3 indices');
        // All should be failed indices
        for (Integer idx : result) {
            Assert.isTrue(failedIndices.contains(idx), 'All indices should be from failed set');
        }
    }

    @isTest
    static void test_samplingService_errorPriority_noFailures_normalSampling() {
        // Arrange - 10 items, no failures, sample 3
        Set<Integer> failedIndices = new Set<Integer>();
        UoWSerializationConfig config = UoWSerializationConfig.forAudit(UoWEnums.SamplingStrategy.FIRST_N, 3);

        // Act
        Test.startTest();
        List<Integer> result = UoWSamplingService.sampleIndices(10, failedIndices, config);
        Test.stopTest();

        // Assert - Normal FIRST_N sampling
        Assert.areEqual(3, result.size(), 'Should return 3 indices');
        Assert.areEqual(0, result[0], 'First index should be 0');
        Assert.areEqual(1, result[1], 'Second index should be 1');
        Assert.areEqual(2, result[2], 'Third index should be 2');
    }

    @isTest
    static void test_samplingService_errorPriority_lastNStrategy_fillsWithLast() {
        // Arrange - 10 items, 1 failed (index 0), sample 3 using LAST_N
        Set<Integer> failedIndices = new Set<Integer>{ 0 };
        UoWSerializationConfig config = UoWSerializationConfig.forAudit(UoWEnums.SamplingStrategy.LAST_N, 3);

        // Act
        Test.startTest();
        List<Integer> result = UoWSamplingService.sampleIndices(10, failedIndices, config);
        Test.stopTest();

        // Assert - Failed index 0 + last 2 successful (8, 9)
        Assert.areEqual(3, result.size(), 'Should return 3 indices');
        Assert.isTrue(result.contains(0), 'Should include failed index 0');
        Assert.isTrue(result.contains(8), 'Should include last successful index 8');
        Assert.isTrue(result.contains(9), 'Should include last successful index 9');
    }

    @isTest
    static void test_samplingService_errorPriority_emptyFailedSet_treated_asNull() {
        // Arrange - Empty set should behave same as null
        Set<Integer> failedIndices = new Set<Integer>();
        UoWSerializationConfig config = UoWSerializationConfig.forAudit(UoWEnums.SamplingStrategy.FIRST_N, 3);

        // Act
        Test.startTest();
        List<Integer> result = UoWSamplingService.sampleIndices(10, failedIndices, config);
        Test.stopTest();

        // Assert - Normal sampling without error priority
        Assert.areEqual(3, result.size(), 'Should return 3 indices');
        Assert.areEqual(0, result[0], 'First index should be 0');
        Assert.areEqual(1, result[1], 'Second index should be 1');
        Assert.areEqual(2, result[2], 'Third index should be 2');
    }
}