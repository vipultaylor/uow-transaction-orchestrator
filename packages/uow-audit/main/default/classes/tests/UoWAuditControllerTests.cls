//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Test class for all UoW Audit LWC Controllers.
 * Covers: Timeline, Configuration, Messages, Errors, WorkItem, Hierarchy, Archive, Delete, Metadata
 *
 * Testing strategy:
 * - Uses real DML for custom audit objects (UoWAuditTransaction__c, UoWAuditWorkItem__c)
 * - Tests happy path and error handling for each controller method
 * - Verifies wrapper class instantiation
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Audit Tests
 */
@isTest
@SuppressWarnings('PMD.MethodNamingConventions')
private class UoWAuditControllerTests {

    // ============================================================================
    // TEST SETUP
    // ============================================================================

    @TestSetup
    static void setupTestData() {
        // Load test configurations from static resource
        UoWTestHelpers.loadTestConfigurations();

        // Create test user with UoWAuditAdmin permission set for USER_MODE queries
        // This is setup object DML (User, PermissionSetAssignment)
        User testUser = UoWAuditTestDataFactory.createAuditAdminUser();
        // Create Another test user without UoWAuditAdmin permission set for USER_MODE queries
        // This is setup object DML (User, PermissionSetAssignment)
        UoWAuditTestDataFactory.createAuditMinAccessUser();

        // Use System.runAs to create a new transaction context for non-setup objects
        // This avoids MIXED_DML_OPERATION error between setup and non-setup objects
        System.runAs(testUser) {

            // Create test transaction
            UoWAuditTransaction__c txn = new UoWAuditTransaction__c(
                TransactionId__c = 'TXN-CTRL-001',
                CorrelationId__c = 'CORR-CTRL-001',
                TransactionStatus__c = 'SUCCESS',
                StartTime__c = DateTime.now().addMinutes(-5),
                EndTime__c = DateTime.now(),
                ExecutionTimeMs__c = 150,
                Timeline__c = UoWAuditTestDataFactory.getCompactTimelineJson(),
                Messages__c = UoWAuditTestDataFactory.getMessagesJson(),
                ConfigurationSnapshot__c = '{"enableAudit":true}',
                ConfigurationName__c = 'TestConfig',
                ErrorDetails__c = UoWAuditTestDataFactory.getErrorDetailsJson(),
                HasErrors__c = true,
                ErrorCount__c = 1
            );
            insert txn;

            // Create work items
            UoWAuditWorkItem__c workItem = new UoWAuditWorkItem__c(
                AuditTransaction__c = txn.Id,
                Name = 'WORK-CTRL-001',
                WorkType__c = 'DML',
                WorkItemStatus__c = 'SUCCESS',
                SObjectType__c = 'Account',
                DmlOperation__c = 'INSERT_OP',
                ErrorDetails__c = UoWAuditTestDataFactory.getWorkItemErrorDetailsJson(),
                HasErrors__c = true,
                ErrorCount__c = 1
            );
            insert workItem;
        }
    }

    /**
     * Helper method to retrieve the test user with UoWAuditAdmin permission set.
     */
    private static User getAuditMinAccessUser() {
        return [SELECT Id FROM User WHERE Alias =: UoWAuditTestDataFactory.MIN_ACCESS_USER_ALIAS LIMIT 1];
    }

    /**
     * Helper method to retrieve the test user with UoWAuditAdmin permission set.
     */
    private static User getAuditAdminUser() {
        return [SELECT Id FROM User WHERE Alias =: UoWAuditTestDataFactory.ADMIN_USER_ALIAS LIMIT 1];
    }

    // ============================================================================
    // TIMELINE CONTROLLER TESTS
    // ============================================================================

    @isTest
    static void test_timeline_getTransaction_returnsRecord() {
        // Arrange
        UoWAuditTransaction__c txn = [SELECT Id FROM UoWAuditTransaction__c LIMIT 1];
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            Test.startTest();
            UoWAuditTransaction__c result = UoWAuditTimelineController.getTransaction(txn.Id);
            Test.stopTest();

            // Assert
            Assert.isNotNull(result, 'Should return transaction record');
            Assert.isNotNull(result.Timeline__c, 'Should include Timeline__c field');
        }
    }

    @isTest
    static void test_timeline_getTransaction_throwsOnNotFound() {
        // Arrange - Use a fake ID that doesn't exist in the database
        Id fakeId = UoWTestHelpers.generateFakeId(UoWAuditTransaction__c.SObjectType);
        User testUser = getAuditAdminUser();

        // Act & Assert
        System.runAs(testUser) {
            Test.startTest();
            try {
                UoWAuditTimelineController.getTransaction(fakeId);
                Assert.fail('Should throw AuraHandledException');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('not found'), 'Should mention not found');
            }
            Test.stopTest();
        }
    }

    @isTest
    static void test_timeline_getTimelineData_returnsDataStructure() {
        // Arrange
        UoWAuditTransaction__c txn = [SELECT Id FROM UoWAuditTransaction__c LIMIT 1];
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            Test.startTest();
            UoWAuditTimelineController.TimelineData data = UoWAuditTimelineController.getTimelineData(txn.Id);
            Test.stopTest();

            // Assert
            Assert.isNotNull(data, 'Should return TimelineData');
            Assert.isNotNull(data.txnRecord, 'Should include transaction record');
            Assert.isNotNull(data.phases, 'Should include phases list');
        }
    }

    @isTest
    static void test_timeline_spanNode_compareTo() {
        // Arrange - Create two SpanNodes with different start times
        UoWCompactTimeline.CompactSpan span1 = new UoWCompactTimeline.CompactSpan();
        span1.id = 1;
        span1.s = 1000L;
        span1.n = 'Span 1';

        UoWCompactTimeline.CompactSpan span2 = new UoWCompactTimeline.CompactSpan();
        span2.id = 2;
        span2.s = 2000L;
        span2.n = 'Span 2';

        UoWAuditTimelineController.SpanNode node1 = new UoWAuditTimelineController.SpanNode(span1);
        UoWAuditTimelineController.SpanNode node2 = new UoWAuditTimelineController.SpanNode(span2);

        // Act & Assert
        Assert.isTrue(node1.compareTo(node2) < 0, 'node1 should come before node2');
        Assert.isTrue(node2.compareTo(node1) > 0, 'node2 should come after node1');
    }

    // ============================================================================
    // CONFIGURATION CONTROLLER TESTS
    // ============================================================================

    @isTest
    static void test_config_getConfiguration_returnsData() {
        // Arrange
        UoWAuditTransaction__c txn = [SELECT Id FROM UoWAuditTransaction__c LIMIT 1];
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            Test.startTest();
            UoWAuditConfigurationController.ConfigurationData config =
                UoWAuditConfigurationController.getConfiguration(txn.Id);
            Test.stopTest();

            // Assert
            Assert.isNotNull(config, 'Should return ConfigurationData');
            Assert.isNotNull(config.settingsJson, 'Should include settings JSON');
            Assert.areEqual('TestConfig', config.configurationName, 'Should include configuration name');
        }
    }

    @isTest
    static void test_config_getConfiguration_throwsOnNotFound() {
        // Arrange - Use a fake ID that doesn't exist in the database
        Id fakeId = UoWTestHelpers.generateFakeId(UoWAuditTransaction__c.SObjectType);
        User testUser = getAuditAdminUser();

        // Act & Assert
        System.runAs(testUser) {
            Test.startTest();
            try {
                UoWAuditConfigurationController.getConfiguration(fakeId);
                Assert.fail('Should throw AuraHandledException');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('not found'), 'Should mention not found');
            }
            Test.stopTest();
        }
    }

    // ============================================================================
    // MESSAGES CONTROLLER TESTS
    // ============================================================================

    @isTest
    static void test_messages_getMessages_returnsData() {
        // Arrange
        UoWAuditTransaction__c txn = [SELECT Id FROM UoWAuditTransaction__c LIMIT 1];
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            Test.startTest();
            UoWAuditMessagesController.MessagesData messagesData =
                UoWAuditMessagesController.getMessages(txn.Id);
            Test.stopTest();

            // Assert
            Assert.isNotNull(messagesData, 'Should return MessagesData');
            Assert.isNotNull(messagesData.messages, 'Should include messages list');
            Assert.isNotNull(messagesData.transactionStartTime, 'Should include start time');
        }
    }

    @isTest
    static void test_messages_getMessages_handlesEmptyMessages() {
        // Arrange - Create transaction without messages
        UoWAuditTransaction__c txn = new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-NO-MSG-001',
            CorrelationId__c = 'CORR-NO-MSG-001',
            TransactionStatus__c = 'SUCCESS',
            StartTime__c = DateTime.now()
        );
        insert txn;
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            Test.startTest();
            UoWAuditMessagesController.MessagesData messagesData =
                UoWAuditMessagesController.getMessages(txn.Id);
            Test.stopTest();

            // Assert
            Assert.isNotNull(messagesData, 'Should return MessagesData');
            Assert.isTrue(messagesData.messages.isEmpty(), 'Messages should be empty');
        }
    }

    @isTest
    static void test_messages_getMessages_throwsOnNotFound() {
        // Arrange - Use a fake ID that doesn't exist in the database
        Id fakeId = UoWTestHelpers.generateFakeId(UoWAuditTransaction__c.SObjectType);
        User testUser = getAuditAdminUser();

        // Act & Assert
        System.runAs(testUser) {
            Test.startTest();
            try {
                UoWAuditMessagesController.getMessages(fakeId);
                Assert.fail('Should throw AuraHandledException');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('not found'), 'Should mention not found');
            }
            Test.stopTest();
        }
    }

    // ============================================================================
    // ERRORS CONTROLLER TESTS
    // ============================================================================

    @isTest
    static void test_errors_getErrors_forTransaction() {
        // Arrange
        UoWAuditTransaction__c txn = [SELECT Id FROM UoWAuditTransaction__c LIMIT 1];
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            Test.startTest();
            List<UoWAuditErrorsController.ErrorDTO> errors =
                UoWAuditErrorsController.getErrors(txn.Id);
            Test.stopTest();

            // Assert
            Assert.isNotNull(errors, 'Should return errors list');
            Assert.isFalse(errors.isEmpty(), 'Should have errors from ErrorDetails__c');
        }
    }

    @isTest
    static void test_errors_getErrors_forWorkItem() {
        // Arrange
        UoWAuditWorkItem__c workItem = [SELECT Id FROM UoWAuditWorkItem__c LIMIT 1];
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            Test.startTest();
            List<UoWAuditErrorsController.ErrorDTO> errors =
                UoWAuditErrorsController.getErrors(workItem.Id);
            Test.stopTest();

            // Assert
            Assert.isNotNull(errors, 'Should return errors list');
            Assert.isFalse(errors.isEmpty(), 'Should have errors from work item ErrorDetails__c');
        }
    }

    @isTest
    static void test_errors_getErrors_throwsForUnsupportedType() {
        // Arrange - Use an ID from a different object type
        Id userId = UserInfo.getUserId();
        User testUser = getAuditAdminUser();

        // Act & Assert
        System.runAs(testUser) {
            Test.startTest();
            try {
                UoWAuditErrorsController.getErrors(userId);
                Assert.fail('Should throw AuraHandledException');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Unsupported record type'), 'Should mention unsupported type');
            }
            Test.stopTest();
        }
    }

    // ============================================================================
    // WORK ITEM CONTROLLER TESTS
    // ============================================================================

    @isTest
    static void test_workItem_getWorkItemForViewer_returnsWorkItem() {
        // Arrange
        UoWAuditWorkItem__c workItem = [SELECT Id FROM UoWAuditWorkItem__c LIMIT 1];
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            Test.startTest();
            UoWAuditWorkItem__c result = UoWAuditWorkItemController.getWorkItemForViewer(workItem.Id);
            Test.stopTest();

            // Assert
            Assert.isNotNull(result, 'Should return work item');
            Assert.areEqual(workItem.Id, result.Id, 'Should return correct work item');
        }
    }

    @isTest
    static void test_workItem_getWorkItemForViewer_nullId_throwsAuraException() {
        // Arrange
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            Test.startTest();
            try {
                UoWAuditWorkItemController.getWorkItemForViewer(null);
                Assert.fail('Should have thrown AuraHandledException');
            } catch (AuraHandledException ex) {
                // Assert
                Assert.isTrue(ex.getMessage().contains('Failed to load work item'),
                    'Exception message should contain controller error prefix');
            }
            Test.stopTest();
        }
    }

    // ============================================================================
    // HIERARCHY CONTROLLER TESTS
    // ============================================================================

    @isTest
    static void test_hierarchy_getByCorrelationId_buildsTree() {
        // Arrange - Create parent and child transactions
        UoWAuditTransaction__c parent = new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-HIER-PARENT',
            CorrelationId__c = 'CORR-HIER-001',
            TransactionStatus__c = 'SUCCESS',
            HasChildTransactions__c = true
        );
        insert parent;

        UoWAuditTransaction__c child = new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-HIER-CHILD',
            CorrelationId__c = 'CORR-HIER-001',
            TransactionStatus__c = 'SUCCESS',
            ParentTransaction__c = parent.Id
        );
        insert child;

        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            Test.startTest();
            UoWTransactionHierarchyController.TransactionHierarchy hierarchy =
                UoWTransactionHierarchyController.getHierarchyByCorrelationId('CORR-HIER-001');
            Test.stopTest();

            // Assert
            Assert.isNotNull(hierarchy, 'Should return hierarchy');
            Assert.isNotNull(hierarchy.root, 'Should have root node');
            Assert.areEqual('TXN-HIER-PARENT', hierarchy.root.transactionId, 'Root should be parent');
        }
    }

    @isTest
    static void test_hierarchy_getByTransactionId_findsCorrelation() {
        // Arrange
        UoWAuditTransaction__c txn = [SELECT Id FROM UoWAuditTransaction__c LIMIT 1];
        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            Test.startTest();
            UoWTransactionHierarchyController.TransactionHierarchy hierarchy =
                UoWTransactionHierarchyController.getHierarchyByTransactionId(txn.Id);
            Test.stopTest();

            // Assert
            Assert.isNotNull(hierarchy, 'Should return hierarchy');
        }
    }

    @isTest
    static void test_hierarchy_getByCorrelationId_throwsOnBlank() {
        // Arrange
        User testUser = getAuditAdminUser();

        // Act & Assert
        System.runAs(testUser) {
            Test.startTest();
            try {
                UoWTransactionHierarchyController.getHierarchyByCorrelationId('');
                Assert.fail('Should throw AuraHandledException');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('required'), 'Should mention required');
            }
            Test.stopTest();
        }
    }

    @isTest
    static void test_hierarchy_getByTransactionId_throwsOnNull() {
        // Arrange
        User testUser = getAuditAdminUser();

        // Act & Assert
        System.runAs(testUser) {
            Test.startTest();
            try {
                UoWTransactionHierarchyController.getHierarchyByTransactionId(null);
                Assert.fail('Should throw AuraHandledException');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('required'), 'Should mention required');
            }
            Test.stopTest();
        }
    }

    @isTest
    static void test_hierarchy_getRecentHierarchies_returnsRoots() {
        // Arrange - Create root transaction
        UoWAuditTransaction__c root = new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-ROOT-RECENT',
            CorrelationId__c = 'CORR-ROOT-RECENT',
            TransactionStatus__c = 'SUCCESS',
            StartTime__c = DateTime.now()
        );
        insert root;

        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            Test.startTest();
            List<UoWTransactionHierarchyController.RootTransactionInfo> results =
                UoWTransactionHierarchyController.getRecentHierarchies(10);
            Test.stopTest();

            // Assert
            Assert.isNotNull(results, 'Should return list');
            Assert.isFalse(results.isEmpty(), 'Should have at least one result');
        }
    }

    // ============================================================================
    // ARCHIVE CONTROLLER TESTS
    // ============================================================================

    @isTest
    static void test_archive_getArchiveRecords_validatesParams() {
        // Arrange - null params
        Test.startTest();
        try {
            UoWAuditArchiveController.getArchiveRecords(null);
            Assert.fail('Should throw AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('required'), 'Should mention required');
        }
        Test.stopTest();
    }

    @isTest
    static void test_archive_getArchiveRecords_validatesDateRange() {
        // Arrange - Invalid date range
        UoWAuditArchiveController.ArchiveQueryParams params = new UoWAuditArchiveController.ArchiveQueryParams();
        params.startDate = Date.today();
        params.endDate = Date.today().addDays(-7); // End before start

        Test.startTest();
        try {
            UoWAuditArchiveController.getArchiveRecords(params);
            Assert.fail('Should throw AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('before'), 'Should mention date order');
        }
        Test.stopTest();
    }

    @isTest
    static void test_archive_getArchiveRecords_appliesPageSizeLimit() {
        // Arrange - Excessive page size should be capped at MAX_PAGE_SIZE (200)
        UoWAuditMocks.MockDataSelector mockSelector = UoWAuditMocks.installDataSelectorMock();

        UoWAuditArchiveController.ArchiveQueryParams params = new UoWAuditArchiveController.ArchiveQueryParams();
        params.pageSize = 1000; // Exceeds MAX_PAGE_SIZE of 200
        params.startDate = Date.today().addDays(-30);
        params.endDate = Date.today();

        // Act
        Test.startTest();
        UoWAuditArchiveController.ArchiveQueryResult result =
            UoWAuditArchiveController.getArchiveRecords(params);
        Test.stopTest();

        // Assert - queryLimit should be capped at 200 + 1 = 201
        Assert.isNotNull(result, 'Should return result');
        Assert.areEqual(201, mockSelector.capturedQueryLimit, 'Should cap pageSize at MAX_PAGE_SIZE (200) + 1');
    }

    @isTest
    static void test_archive_getFilterOptions_returnsAllOptions() {
        // Act
        Test.startTest();
        UoWAuditArchiveController.FilterOptions options =
            UoWAuditArchiveController.getFilterOptions();
        Test.stopTest();

        // Assert
        Assert.isNotNull(options, 'Should return filter options');
        Assert.isNotNull(options.workTypes, 'Should include work types');
        Assert.isNotNull(options.statuses, 'Should include statuses');
        Assert.isNotNull(options.riskLevels, 'Should include risk levels');
        Assert.isFalse(options.workTypes.isEmpty(), 'Work types should not be empty');
    }

    @isTest
    static void test_archive_archiveQueryResult_constructor() {
        // Arrange
        List<UoWAuditHistory__b> records = new List<UoWAuditHistory__b>();

        // Act
        UoWAuditArchiveController.ArchiveQueryResult result =
            new UoWAuditArchiveController.ArchiveQueryResult(records, false, null, null);

        // Assert
        Assert.isNotNull(result.records, 'Should have records list');
        Assert.isFalse(result.hasMore, 'Should not have more');
        Assert.areEqual(0, result.totalCount, 'Should have 0 total count');
    }

    @isTest
    static void test_archive_selectOption_constructor() {
        // Act
        UoWAuditArchiveController.SelectOption option =
            new UoWAuditArchiveController.SelectOption('VALUE', 'Label Text');

        // Assert
        Assert.areEqual('VALUE', option.value, 'Should store value');
        Assert.areEqual('Label Text', option.label, 'Should store label');
    }

    // ============================================================================
    // DELETE CONTROLLER TESTS
    // ============================================================================

    @isTest
    static void test_delete_initialize_setsErrorMessage_whenNoIds() {
        // Arrange
        UoWAuditTransactionDeleteController controller = new UoWAuditTransactionDeleteController();
        controller.recordIds = new List<String>();

        // Act
        Test.startTest();
        controller.initialize();
        Test.stopTest();

        // Assert
        Assert.isTrue(controller.getHasError(), 'Should have error');
        Assert.isTrue(controller.errorMessage.contains('No records'), 'Should mention no records');
    }

    @isTest
    static void test_delete_initialize_loadsSelectedRecords() {
        // Arrange
        UoWAuditTransaction__c txn = [SELECT Id FROM UoWAuditTransaction__c LIMIT 1];
        User testUser = getAuditAdminUser();

        // Act - Run as audit admin since controller queries use WITH SECURITY_ENFORCED
        System.runAs(testUser) {
            UoWAuditTransactionDeleteController controller = new UoWAuditTransactionDeleteController();
            controller.recordIds = new List<String>{ txn.Id };

            Test.startTest();
            controller.initialize();
            Test.stopTest();

            // Assert
            Assert.isTrue(controller.getHasSelectedRecords(), 'Should have selected records');
            Assert.areEqual(1, controller.getSelectedCount(), 'Should have 1 selected');
        }
    }

    @isTest
    static void test_delete_deleteRecords_deletesTransactions() {
        // Arrange - Create a transaction to delete
        User testUser = getAuditAdminUser();

        // Act - Run as audit admin since controller queries use WITH SECURITY_ENFORCED
        System.runAs(testUser) {
            UoWAuditTransaction__c txnToDelete = new UoWAuditTransaction__c(
                TransactionId__c = 'TXN-DELETE-001',
                CorrelationId__c = 'CORR-DELETE-001',
                TransactionStatus__c = 'SUCCESS'
            );
            insert txnToDelete;

            UoWAuditTransactionDeleteController controller = new UoWAuditTransactionDeleteController();
            controller.recordIds = new List<String>{ txnToDelete.Id };
            controller.initialize();

            Test.startTest();
            controller.deleteRecords();
            Test.stopTest();

            // Assert
            Assert.isTrue(controller.deleteSuccess, 'Delete should succeed');
            Assert.areEqual(1, controller.deletedCount, 'Should delete 1 record');

            List<UoWAuditTransaction__c> remaining = [
                SELECT Id FROM UoWAuditTransaction__c WHERE Id = :txnToDelete.Id
            ];
            Assert.areEqual(0, remaining.size(), 'Record should be deleted');
        }
    }

    @isTest
    static void test_delete_cancel_returnsListViewPageReference() {
        // Arrange
        UoWAuditTransactionDeleteController controller = new UoWAuditTransactionDeleteController();

        // Act
        Test.startTest();
        PageReference pageRef = controller.cancel();
        Test.stopTest();

        // Assert
        Assert.isNotNull(pageRef, 'Should return PageReference');
        Assert.isTrue(pageRef.getUrl().contains('UoWAuditTransaction__c'), 'Should navigate to list view');
    }

    @isTest
    static void test_delete_computedProperties() {
        // Arrange
        UoWAuditTransactionDeleteController controller = new UoWAuditTransactionDeleteController();

        // Act & Assert - Default state
        Assert.isFalse(controller.getHasSelectedRecords(), 'Should not have selected records by default');
        Assert.isFalse(controller.getHasRelatedRecords(), 'Should not have related records by default');
        Assert.isFalse(controller.getHasError(), 'Should not have error by default');
        Assert.areEqual(0, controller.getSelectedCount(), 'Selected count should be 0');
        Assert.areEqual(0, controller.getRelatedCount(), 'Related count should be 0');
    }

    // ============================================================================
    // METADATA VIEWER CONTROLLER TESTS
    // ============================================================================

    @isTest
    static void test_metadata_asSysAdmin_canViewOriginMetadata_permitted() {
        // Act
        Test.startTest();
        Boolean canView = UoWMetadataViewerController.canViewOriginMetadata();
        Test.stopTest();

        // Assert - Result depends on user permissions
        Assert.isTrue(canView, 'Sys Admin user should be able to view the metadata');
    }

    @isTest
    static void test_metadata_asAuditAdmin_canViewOriginMetadata_permitted() {
        // Arrange - Create a transaction to delete
        User testUser = getAuditAdminUser();

        // Act - Run as audit admin since controller queries use WITH SECURITY_ENFORCED
        System.runAs(testUser) {
            // Act
            Test.startTest();
            Boolean canView = UoWMetadataViewerController.canViewOriginMetadata();
            Test.stopTest();

            // Assert - Result depends on user permissions
            Assert.isTrue(canView, 'Audit Admin user should be able to view the metadata');
        }
    }

    @isTest
    static void test_metadata_asStandardUser_canViewOriginMetadata_denied() {
        // Arrange - Create a transaction to delete
        User testUser = getAuditMinAccessUser();

        // Act - Run as audit admin since controller queries use WITH SECURITY_ENFORCED
        System.runAs(testUser) {
            // Act
            Test.startTest();
            Boolean canView = UoWMetadataViewerController.canViewOriginMetadata();
            Test.stopTest();

            // Assert - Result depends on user permissions
            Assert.isFalse(canView, 'Standard user should NOT be able to view the metadata');
        }
    }

    @isTest
    static void test_metadata_checkForModifications_handlesBlankInputs() {
        // Act
        Test.startTest();
        UoWMetadataViewerController.MetadataCheckResult result =
            UoWMetadataViewerController.checkForModifications('', '', null);
        Test.stopTest();

        // Assert
        Assert.isNotNull(result, 'Should return result');
        Assert.isFalse(result.hasBeenModified == true, 'Should not show modified for blank inputs');
    }

    @isTest
    static void test_metadata_checkForModifications_checksApexClass() {
        // Arrange - Use a known system class
        String className = 'UoWMetadataViewerController';
        DateTime capturedDate = DateTime.now().addDays(-1);

        // Act
        Test.startTest();
        UoWMetadataViewerController.MetadataCheckResult result =
            UoWMetadataViewerController.checkForModifications('ApexClass', className, capturedDate);
        Test.stopTest();

        // Assert
        Assert.isNotNull(result, 'Should return result');
        // The actual modification status depends on deployment state
    }

    @isTest
    static void test_metadata_checkForModifications_handlesClassNotFound() {
        // Arrange - Use a non-existent class name
        String className = 'NonExistentClassName12345';
        DateTime capturedDate = DateTime.now();

        // Act
        Test.startTest();
        UoWMetadataViewerController.MetadataCheckResult result =
            UoWMetadataViewerController.checkForModifications('ApexClass', className, capturedDate);
        Test.stopTest();

        // Assert
        Assert.isNotNull(result, 'Should return result');
        Assert.isTrue(result.classNotFound == true, 'Should indicate class not found');
    }

    @isTest
    static void test_metadata_metadataCheckResult_properties() {
        // Arrange & Act
        UoWMetadataViewerController.MetadataCheckResult result =
            new UoWMetadataViewerController.MetadataCheckResult();
        result.hasBeenModified = true;
        result.currentLastModifiedDate = '2024-01-15T10:00:00.000Z';
        result.currentApiVersion = '65.0';
        result.classNotFound = false;
        result.errorMessage = null;

        // Assert
        Assert.isTrue(result.hasBeenModified, 'Should store hasBeenModified');
        Assert.areEqual('65.0', result.currentApiVersion, 'Should store apiVersion');
    }

    // ============================================================================
    // ARCHIVE CONTROLLER TESTS - DETAIL, EXPORT, CURSOR
    // ============================================================================

    @isTest
    static void test_archive_getArchiveDetail_returnsNullForBlankCorrelation() {
        // Act
        Test.startTest();
        UoWAuditHistory__b result = UoWAuditArchiveController.getArchiveDetail('', 1, DateTime.now());
        Test.stopTest();

        // Assert
        Assert.isNull(result, 'Should return null for blank correlation ID');
    }

    @isTest
    static void test_archive_getArchiveDetail_returnsNullForNullTimestamp() {
        // Act
        Test.startTest();
        UoWAuditHistory__b result = UoWAuditArchiveController.getArchiveDetail('CORR-001', 1, null);
        Test.stopTest();

        // Assert
        Assert.isNull(result, 'Should return null for null timestamp');
    }

    @isTest
    static void test_archive_getArchiveDetail_returnsRecordForValidKeys() {
        // Arrange - Configure mock DataSelector to return a known record
        UoWAuditMocks.MockDataSelector mockSelector = UoWAuditMocks.installDataSelectorMock();

        DateTime knownTimestamp = DateTime.newInstance(2024, 6, 15, 12, 0, 0);
        String correlationId = 'CORR-DETAIL-TEST-001';
        Decimal sequence = 1;

        UoWAuditHistory__b mockRecord = new UoWAuditHistory__b(
            CorrelationId__c = correlationId,
            Sequence__c = sequence,
            CreatedTimestamp__c = knownTimestamp,
            TransactionId__c = 'TXN-DETAIL-TEST-001',
            TransactionStatus__c = 'SUCCESS',
            WorkType__c = 'DML'
        );
        mockSelector.archiveDetailResult = mockRecord;

        // Act
        Test.startTest();
        UoWAuditHistory__b result = UoWAuditArchiveController.getArchiveDetail(
            correlationId, sequence, knownTimestamp
        );
        Test.stopTest();

        // Assert - Record fields
        Assert.isNotNull(result, 'Should return archive record');
        Assert.areEqual(correlationId, result.CorrelationId__c, 'CorrelationId should match');
        Assert.areEqual(sequence, result.Sequence__c, 'Sequence should match');
        Assert.areEqual(knownTimestamp, result.CreatedTimestamp__c, 'CreatedTimestamp should match');
        Assert.areEqual('TXN-DETAIL-TEST-001', result.TransactionId__c, 'TransactionId should match');
        Assert.areEqual('SUCCESS', result.TransactionStatus__c, 'TransactionStatus should match');
        Assert.areEqual('DML', result.WorkType__c, 'WorkType should match');

        // Assert - Parameters passed to selector
        Assert.areEqual(correlationId, mockSelector.capturedCorrelationId, 'Should pass correlationId to selector');
        Assert.areEqual(sequence, mockSelector.capturedSequence, 'Should pass sequence to selector');
        Assert.areEqual(knownTimestamp, mockSelector.capturedCreatedTimestamp, 'Should pass timestamp to selector');
    }

    @isTest
    static void test_archive_exportArchiveRecords_overridesPageSize() {
        // Arrange - Mock selector to avoid Big Object query issues
        UoWAuditMocks.MockDataSelector mockSelector = UoWAuditMocks.installDataSelectorMock();
        mockSelector.archiveQueryResults = new List<UoWAuditHistory__b>{
            new UoWAuditHistory__b(CorrelationId__c = 'CORR-EXPORT-001', Sequence__c = 1)
        };

        UoWAuditArchiveController.ArchiveQueryParams params = new UoWAuditArchiveController.ArchiveQueryParams();
        params.pageSize = 10;
        params.startDate = Date.today().addDays(-30);
        params.endDate = Date.today();

        // Act - Export overrides page size to MAX_PAGE_SIZE (200)
        Test.startTest();
        String jsonResult = UoWAuditArchiveController.exportArchiveRecords(params);
        Test.stopTest();

        // Assert
        Assert.isNotNull(jsonResult, 'Should return JSON string');
        // Export overrides pageSize to 200, so queryLimit = 201
        Assert.areEqual(201, mockSelector.capturedQueryLimit, 'Should override pageSize to MAX_PAGE_SIZE');
    }

    @isTest
    static void test_archive_getArchiveRecords_withCorrelationIdFilter() {
        // Arrange - Mock selector to avoid Big Object query issues
        UoWAuditMocks.MockDataSelector mockSelector = UoWAuditMocks.installDataSelectorMock();

        UoWAuditArchiveController.ArchiveQueryParams params = new UoWAuditArchiveController.ArchiveQueryParams();
        params.correlationId = 'CORR-ARCHIVE-001';

        // Act
        Test.startTest();
        UoWAuditArchiveController.ArchiveQueryResult result =
            UoWAuditArchiveController.getArchiveRecords(params);
        Test.stopTest();

        // Assert
        Assert.isNotNull(result, 'Should return result');
        Assert.areEqual('CORR-ARCHIVE-001', mockSelector.capturedCorrelationId, 'Should pass correlationId to selector');
    }

    @isTest
    static void test_archive_getArchiveRecords_withCursorPagination() {
        // Arrange - Mock selector returns more records than pageSize to test hasMore
        UoWAuditMocks.MockDataSelector mockSelector = UoWAuditMocks.installDataSelectorMock();

        List<UoWAuditHistory__b> mockRecords = new List<UoWAuditHistory__b>();
        for (Integer i = 0; i < 4; i++) {
            mockRecords.add(new UoWAuditHistory__b(
                CorrelationId__c = 'CORR-PAGE-' + i,
                Sequence__c = i,
                CreatedTimestamp__c = DateTime.now().addHours(-i)
            ));
        }
        mockSelector.archiveQueryResults = mockRecords;

        Long epochMs = DateTime.now().addDays(-1).getTime();
        String cursor = EncodingUtil.base64Encode(Blob.valueOf(String.valueOf(epochMs)));

        UoWAuditArchiveController.ArchiveQueryParams params = new UoWAuditArchiveController.ArchiveQueryParams();
        params.cursor = cursor;
        params.pageSize = 3;
        params.startDate = Date.today().addDays(-30);
        params.endDate = Date.today();

        // Act
        Test.startTest();
        UoWAuditArchiveController.ArchiveQueryResult result =
            UoWAuditArchiveController.getArchiveRecords(params);
        Test.stopTest();

        // Assert - result structure
        Assert.isNotNull(result, 'Should return result with cursor pagination');
        Assert.isNotNull(result.records, 'Should have records list');
        Assert.areEqual(cursor, result.previousCursor, 'Should pass cursor as previousCursor');

        // Assert - pagination: mock returned 4 records for pageSize 3, so hasMore = true
        // and the 4th record is trimmed, leaving 3
        Assert.areEqual(3, result.records.size(), 'Should trim to pageSize');
        Assert.areEqual(3, result.totalCount, 'totalCount should match trimmed records');
        Assert.isTrue(result.hasMore, 'Should indicate more records available');
        Assert.isNotNull(result.nextCursor, 'Should provide next cursor');

        // Assert - selector received pageSize + 1 as queryLimit
        Assert.areEqual(4, mockSelector.capturedQueryLimit, 'Should query pageSize + 1');
    }

    @isTest
    static void test_archive_getArchiveRecords_withInvalidCursor_throws() {
        // Arrange - Invalid base64 cursor
        UoWAuditArchiveController.ArchiveQueryParams params = new UoWAuditArchiveController.ArchiveQueryParams();
        params.cursor = 'not-valid-base64!!!';

        // Act & Assert
        Test.startTest();
        try {
            UoWAuditArchiveController.getArchiveRecords(params);
            Assert.fail('Should throw for invalid cursor');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage(), 'Should have error message');
        }
        Test.stopTest();
    }

    // ============================================================================
    // TIMELINE CONTROLLER TESTS - HYDRATION, EVENTS, EVENT NODE
    // ============================================================================

    @isTest
    static void test_timeline_getTimelineData_hydratesWorkItems() {
        // Arrange - Create timeline with work item IDs referencing existing work item
        UoWAuditTransaction__c txn = [SELECT Id FROM UoWAuditTransaction__c WHERE TransactionId__c = 'TXN-CTRL-001' LIMIT 1];
        UoWAuditWorkItem__c workItem = [SELECT Id, Name FROM UoWAuditWorkItem__c WHERE Name = 'WORK-CTRL-001' LIMIT 1];

        // Update timeline to reference the work item by Name
        String timelineWithWorkItem = '{"td":150,"sc":2,"sp":[' +
            '{"id":1,"n":"Root Span","s":1704067200000,"e":1704067200150,"d":150,"l":1,"p":"TRANSACTION","c":"FRAMEWORK","st":"OK"},' +
            '{"id":2,"pid":1,"n":"DML Phase","s":1704067200010,"e":1704067200100,"d":90,"l":2,"p":"DML_EXECUTION","c":"DML","st":"OK","wk":["' + workItem.Name + '"]}' +
            ']}';
        txn.Timeline__c = timelineWithWorkItem;
        update txn;

        User testUser = getAuditAdminUser();

        // Act
        System.runAs(testUser) {
            Test.startTest();
            UoWAuditTimelineController.TimelineData data = UoWAuditTimelineController.getTimelineData(txn.Id);
            Test.stopTest();

            // Assert
            Assert.isNotNull(data, 'Should return timeline data');
            Assert.isTrue(data.totalPhases >= 2, 'Should have at least 2 spans');

            // Find span with hydrated work items
            Boolean foundHydratedWorkItem = false;
            for (UoWAuditTimelineController.SpanNode span : data.phases) {
                if (span.hasWorkItems == true && span.workItems != null && !span.workItems.isEmpty()) {
                    foundHydratedWorkItem = true;
                }
                if (span.children != null) {
                    for (UoWAuditTimelineController.SpanNode child : span.children) {
                        if (child.hasWorkItems == true && child.workItems != null && !child.workItems.isEmpty()) {
                            foundHydratedWorkItem = true;
                        }
                    }
                }
            }
            Assert.isTrue(foundHydratedWorkItem, 'Should hydrate work items from database');
        }
    }

    @isTest
    static void test_timeline_eventNode_expandsAllEventTypes() {
        // Arrange & Act - Test each event type code expansion
        Map<String, String> typeCodeToExpected = new Map<String, String>{
            'S' => 'STATE',
            'D' => 'DECISION',
            'R' => 'RISK',
            'E' => 'ERROR',
            'W' => 'WARNING'
        };

        for (String typeCode : typeCodeToExpected.keySet()) {
            UoWCompactTimeline.CompactEvent ev = new UoWCompactTimeline.CompactEvent();
            ev.n = 'Test event';
            ev.t = 1704067200000L;
            ev.ty = typeCode;
            ev.seq = 1;

            UoWAuditTimelineController.EventNode node = new UoWAuditTimelineController.EventNode(ev);

            Assert.areEqual(
                typeCodeToExpected.get(typeCode),
                node.eventType,
                'Type code ' + typeCode + ' should expand to ' + typeCodeToExpected.get(typeCode)
            );
        }

        // Test default/unknown case - should default to INFO
        UoWCompactTimeline.CompactEvent unknownEv = new UoWCompactTimeline.CompactEvent();
        unknownEv.n = 'Unknown event';
        unknownEv.t = 1704067200000L;
        unknownEv.ty = 'X';
        unknownEv.seq = 1;
        UoWAuditTimelineController.EventNode unknownNode = new UoWAuditTimelineController.EventNode(unknownEv);
        Assert.areEqual('INFO', unknownNode.eventType, 'Unknown type code should default to INFO');
    }

    @isTest
    static void test_timeline_eventNode_convertsTimestamp() {
        // Arrange
        UoWCompactTimeline.CompactEvent ev = new UoWCompactTimeline.CompactEvent();
        ev.n = 'Timed event';
        ev.t = 1704067200000L;
        ev.ty = 'S';
        ev.seq = 1;

        // Act
        UoWAuditTimelineController.EventNode node = new UoWAuditTimelineController.EventNode(ev);

        // Assert
        Assert.isNotNull(node.timestamp, 'Should convert epoch ms to DateTime');
        Assert.areEqual(1704067200000L, node.timestampMs, 'Should preserve timestampMs');
        Assert.areEqual(1, node.sequence, 'Should preserve sequence');
        Assert.areEqual('Timed event', node.name, 'Should preserve name');
    }

    @isTest
    static void test_timeline_eventNode_handlesNullTimestamp() {
        // Arrange
        UoWCompactTimeline.CompactEvent ev = new UoWCompactTimeline.CompactEvent();
        ev.n = 'No timestamp';
        ev.t = null;
        ev.ty = 'D';
        ev.seq = 1;

        // Act
        UoWAuditTimelineController.EventNode node = new UoWAuditTimelineController.EventNode(ev);

        // Assert
        Assert.isNull(node.timestamp, 'Timestamp should be null when not provided');
        Assert.isNull(node.timestampMs, 'TimestampMs should be null');
    }

    @isTest
    static void test_timeline_spanNode_withEventsAndWorkItemIds() {
        // Arrange - Span with events and work item IDs
        UoWCompactTimeline.CompactSpan span = new UoWCompactTimeline.CompactSpan();
        span.id = 1;
        span.n = 'DML Phase';
        span.s = 1000L;
        span.e = 2000L;
        span.d = 1000L;
        span.l = 1;
        span.st = 'OK';
        span.p = 'DML_EXECUTION';
        span.c = 'DML';

        UoWCompactTimeline.CompactEvent event = new UoWCompactTimeline.CompactEvent();
        event.n = 'Records processed';
        event.t = 1500L;
        event.ty = 'S';
        event.seq = 1;
        span.ev = new List<UoWCompactTimeline.CompactEvent>{ event };
        span.wk = new List<String>{ 'WORK-001', 'WORK-002' };

        // Act
        UoWAuditTimelineController.SpanNode node = new UoWAuditTimelineController.SpanNode(span);

        // Assert
        Assert.isNotNull(node.events, 'Should have events list');
        Assert.areEqual(1, node.events.size(), 'Should have 1 event');
        Assert.areEqual('STATE', node.events[0].eventType, 'Event type should be expanded');
        Assert.isTrue(node.hasWorkItems, 'Should indicate work items present');
        Assert.areEqual(2, node.workItemIds.size(), 'Should have 2 work item IDs');
        Assert.areEqual('DML_EXECUTION', node.phase, 'Phase should be mapped');
        Assert.areEqual('DML', node.category, 'Category should be mapped');
    }

    // ============================================================================
    // DELETE EXTENSION TESTS - CONSTRUCTOR COVERAGE
    // ============================================================================

    @isTest
    static void test_deleteExtension_standardSetController_extractsIds() {
        // Arrange - Create transactions
        UoWAuditTransaction__c txn1 = new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-DEL-EXT-001',
            CorrelationId__c = 'CORR-DEL-EXT-001',
            TransactionStatus__c = 'SUCCESS'
        );
        UoWAuditTransaction__c txn2 = new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-DEL-EXT-002',
            CorrelationId__c = 'CORR-DEL-EXT-002',
            TransactionStatus__c = 'SUCCESS'
        );
        insert new List<UoWAuditTransaction__c>{ txn1, txn2 };

        // Create StandardSetController with selected records
        ApexPages.StandardSetController setCtrl = new ApexPages.StandardSetController(
            new List<UoWAuditTransaction__c>{ txn1, txn2 }
        );
        setCtrl.setSelected(new List<UoWAuditTransaction__c>{ txn1, txn2 });

        // Act
        Test.startTest();
        UoWAuditTransactionDeleteExtension ext = new UoWAuditTransactionDeleteExtension(setCtrl);
        Test.stopTest();

        // Assert
        Assert.areEqual(2, ext.selectedIdList.size(), 'Should have 2 selected IDs');
        Assert.isTrue(ext.selectedIds.contains(String.valueOf(txn1.Id)), 'Should contain first ID');
        Assert.isTrue(ext.selectedIds.contains(String.valueOf(txn2.Id)), 'Should contain second ID');
    }

    @isTest
    static void test_deleteExtension_standardController_extractsSingleId() {
        // Arrange
        UoWAuditTransaction__c txn = new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-DEL-SINGLE-001',
            CorrelationId__c = 'CORR-DEL-SINGLE-001',
            TransactionStatus__c = 'SUCCESS'
        );
        insert txn;

        ApexPages.StandardController stdCtrl = new ApexPages.StandardController(txn);

        // Act
        Test.startTest();
        UoWAuditTransactionDeleteExtension ext = new UoWAuditTransactionDeleteExtension(stdCtrl);
        Test.stopTest();

        // Assert
        Assert.areEqual(1, ext.selectedIdList.size(), 'Should have 1 selected ID');
        Assert.areEqual(String.valueOf(txn.Id), ext.selectedIdList[0], 'Should contain the record ID');
        Assert.areEqual(String.valueOf(txn.Id), ext.selectedIds, 'selectedIds should be the record ID');
    }

    @isTest
    static void test_deleteExtension_standardController_handlesNoId() {
        // Arrange - Create controller with a record that has no ID (not inserted)
        UoWAuditTransaction__c txn = new UoWAuditTransaction__c();
        ApexPages.StandardController stdCtrl = new ApexPages.StandardController(txn);

        // Act
        Test.startTest();
        UoWAuditTransactionDeleteExtension ext = new UoWAuditTransactionDeleteExtension(stdCtrl);
        Test.stopTest();

        // Assert
        Assert.isTrue(ext.selectedIdList.isEmpty(), 'Should have empty selected ID list');
        Assert.areEqual('', ext.selectedIds, 'selectedIds should be empty string');
    }

    // ============================================================================
    // METADATA VIEWER CONTROLLER TESTS - TRIGGER & NULL DATE
    // ============================================================================

    @isTest
    static void test_metadata_checkForModifications_checksApexTrigger() {
        // Arrange - Use a trigger name (non-existent)
        String triggerName = 'NonExistentTestTrigger12345';
        DateTime capturedDate = DateTime.now().addDays(-1);

        // Act
        Test.startTest();
        UoWMetadataViewerController.MetadataCheckResult result =
            UoWMetadataViewerController.checkForModifications('ApexTrigger', triggerName, capturedDate);
        Test.stopTest();

        // Assert - Trigger doesn't exist, should mark as not found
        Assert.isNotNull(result, 'Should return result');
        Assert.isTrue(result.classNotFound == true, 'Should indicate trigger not found');
    }

    @isTest
    static void test_metadata_checkForModifications_handlesNullCapturedDate() {
        // Arrange - Known class with null captured date
        String className = 'UoWMetadataViewerController';

        // Act
        Test.startTest();
        UoWMetadataViewerController.MetadataCheckResult result =
            UoWMetadataViewerController.checkForModifications('ApexClass', className, null);
        Test.stopTest();

        // Assert - Can't compare with null captured date
        Assert.isNotNull(result, 'Should return result');
        Assert.isNull(result.hasBeenModified, 'Should be null when captured date is null');
    }

    // ============================================================================
    // WRAPPER CLASS INSTANTIATION TESTS
    // ============================================================================

    @isTest
    static void test_timelineData_wrapper() {
        // Arrange
        UoWAuditTransaction__c txn = new UoWAuditTransaction__c(TransactionId__c = 'TXN-WRAPPER');
        List<UoWAuditTimelineController.SpanNode> spans = new List<UoWAuditTimelineController.SpanNode>();

        // Act
        UoWAuditTimelineController.TimelineData data =
            new UoWAuditTimelineController.TimelineData(txn, spans, 5);

        // Assert
        Assert.areEqual(txn, data.txnRecord, 'Should store transaction');
        Assert.areEqual(spans, data.phases, 'Should store phases');
        Assert.areEqual(5, data.totalPhases, 'Should store total');
    }

    @isTest
    static void test_configurationData_wrapper() {
        // Act
        UoWAuditConfigurationController.ConfigurationData data =
            new UoWAuditConfigurationController.ConfigurationData('TXN-001', '{"key":"value"}', 'ConfigName');

        // Assert
        Assert.areEqual('TXN-001', data.transactionId, 'Should store transaction ID');
        Assert.areEqual('{"key":"value"}', data.settingsJson, 'Should store JSON');
        Assert.areEqual('ConfigName', data.configurationName, 'Should store config name');
    }

    @isTest
    static void test_messagesData_wrapper() {
        // Arrange
        List<UoWAuditMessagesController.MessageDTO> messages = new List<UoWAuditMessagesController.MessageDTO>();
        DateTime startTime = DateTime.now();

        // Act
        UoWAuditMessagesController.MessagesData data =
            new UoWAuditMessagesController.MessagesData(messages, startTime);

        // Assert
        Assert.areEqual(messages, data.messages, 'Should store messages');
        Assert.areEqual(startTime, data.transactionStartTime, 'Should store start time');
    }

    @isTest
    static void test_transactionNode_wrapper() {
        // Act
        UoWTransactionHierarchyController.TransactionNode node =
            new UoWTransactionHierarchyController.TransactionNode();
        node.id = UoWTestHelpers.generateFakeId(UoWAuditTransaction__c.SObjectType);
        node.transactionId = 'TXN-NODE-001';
        node.description = 'Test description';
        node.status = 'SUCCESS';
        node.hasChildren = true;
        node.totalWorkCount = 5;
        node.children = new List<UoWTransactionHierarchyController.TransactionNode>();

        // Assert
        Assert.isNotNull(node.id, 'Should store ID');
        Assert.areEqual('TXN-NODE-001', node.transactionId, 'Should store transaction ID');
        Assert.areEqual('SUCCESS', node.status, 'Should store status');
    }

    @isTest
    static void test_rootTransactionInfo_wrapper() {
        // Act
        UoWTransactionHierarchyController.RootTransactionInfo info =
            new UoWTransactionHierarchyController.RootTransactionInfo();
        info.id = UoWTestHelpers.generateFakeId(UoWAuditTransaction__c.SObjectType);
        info.name = 'AUD-000001';
        info.transactionId = 'TXN-ROOT-001';
        info.correlationId = 'CORR-ROOT-001';
        info.status = 'SUCCESS';
        info.commitMode = 'SYNC';
        info.startTime = DateTime.now();
        info.executionTimeMs = 150;
        info.workItemCount = 5;
        info.childCount = 2;

        // Assert
        Assert.areEqual('AUD-000001', info.name, 'Should store name');
        Assert.areEqual(5, info.workItemCount, 'Should store work item count');
        Assert.areEqual(2, info.childCount, 'Should store child count');
    }
}
