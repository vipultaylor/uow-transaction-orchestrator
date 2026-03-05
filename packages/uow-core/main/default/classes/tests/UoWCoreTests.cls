//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Tests for core UnitOfWork functionality.
 * Covers DML operations (INSERT, UPSERT, UPDATE, DELETE, UNDELETE), relationships,
 * all work types (Platform Events, Flows, Emails, Custom Notifications, Callouts),
 * and basic transaction lifecycle.
 *
 * Tests for asynchronous execution in UoW framework.
 * Covers async commit (ASYNC mode), async child execution (Queueable)
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Tests
 * @see UnitOfWork
 * @see UoWResult
 * @see UoWQueueable
 */
@isTest
@SuppressWarnings('PMD.MethodNamingConventions')
private class UoWCoreTests {
    // ============================================================================
    // TEST SETUP
    // ============================================================================

    @TestSetup
    static void setupTestData() {
        // Load test configurations
        UoWTestHelpers.loadTestConfigurations();
    }

    // ============================================================================
    // DML INSERTS
    // ============================================================================

    @isTest
    static void test_dmlInsert_succeeds() {
        // Arrange - Use mock DML strategy for org-independent testing
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        Account acc = UoWCoreTestDataFactory.createAccount('Test Account Insert');
        List<Contact> contacts = UoWCoreTestDataFactory.createContacts(5, null);

        uow.registerInsert(acc);
        uow.registerInsert(contacts);
        uow.relate(contacts, Contact.AccountId, acc);

        UoWPlan plan = uow.getPlan();
        Assert.isTrue(plan.hasDmlWork(), 'DML work should have been registered to the plan');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Framework correctly processed the mock results
        UoWTestHelpers.assertSuccess(result);

        // 1 work item for Account Inserts (as DML work item support consolidation by type and operation)
        UoWTestHelpers.assertExecutedDmlWorkItemCount(result, Account.SObjectType, UoWEnums.DmlOperation.INSERT_OP, 1);
        // 1 work item for Contact Inserts (as event work items support consolidation by type and operation)
        UoWTestHelpers.assertExecutedDmlWorkItemCount(result, Contact.SObjectType, UoWEnums.DmlOperation.INSERT_OP, 1);

        //Inserts
        Integer totalInsertDmlCount = 6; // Inserts - 1 Account & 5 Contacts
        Assert.areEqual(totalInsertDmlCount, result.statistics.dmlStats.inserts.records.processed, 'Should process ' + totalInsertDmlCount + ' DML inserts');
        Assert.areEqual(totalInsertDmlCount, result.statistics.dmlStats.inserts.records.successes, 'Should have ' + totalInsertDmlCount + ' DML insert successes');
        Assert.areEqual(1, result.statistics.dmlStats.inserts.byType.get('Account').successes, 'Should have 1 DML inserts for Account');
        Assert.areEqual(5, result.statistics.dmlStats.inserts.byType.get('Contact').successes, 'Should have 5 DML inserts for Contact');

        //Total DML
        Assert.areEqual(totalInsertDmlCount, result.statistics.dmlStats.records.processed, 'Should process ' + totalInsertDmlCount + ' DML records');
        Assert.areEqual(totalInsertDmlCount, result.statistics.dmlStats.records.successes, 'Should have ' + totalInsertDmlCount + ' DML successes');

        // Assert total statistics via convenience methods
        Assert.areEqual(totalInsertDmlCount, result.statistics.getTotalProcessed(), 'Should have ' + totalInsertDmlCount + ' processed items');
        Assert.areEqual(totalInsertDmlCount, result.statistics.getTotalSucceeded(), 'Should have ' + totalInsertDmlCount + ' success items');
        Assert.areEqual(0, result.statistics.getTotalFailed(), 'Should have no failures');

        //Assert Relationship is resolved
        for(Contact con : contacts) {
            UoWTestHelpers.assertRelationshipResolved(con, Contact.AccountId, acc.Id);
        }

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.SUCCESS, workItem.status, 'DML work item should have SUCCESS status');
        }
    }

    @isTest
    static void test_dmlInsert_multiLevelRelationship_succeeds() {
        // Arrange - Use mock DML strategy for org-independent testing
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        Account acc = UoWCoreTestDataFactory.createAccount('Grandparent Account');
        Contact con = UoWCoreTestDataFactory.createContact('Parent Contact', null);
        Case supportCase = UoWCoreTestDataFactory.createCase('Support Case', null);

        uow.registerInsert(acc);
        uow.registerInsert(con);
        uow.relate(con, Contact.AccountId, acc);
        uow.registerInsert(supportCase);
        uow.relate(supportCase, Case.ContactId, con);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertSuccess(result);

        // Assert aggregate statistics
        Assert.areEqual(3, result.statistics.dmlStats.records.processed, 'Should process 3 total records');
        Assert.areEqual(3, result.statistics.dmlStats.records.successes, 'Should have 3 total successes');
        Assert.areEqual(0, result.statistics.dmlStats.records.errors, 'Should have 0 total errors');

        // Assert byType statistics
        Assert.isTrue(result.statistics.dmlStats.inserts.byType.containsKey('Account'), 'Should have Account stats');
        Assert.isTrue(result.statistics.dmlStats.inserts.byType.containsKey('Contact'), 'Should have Contact stats');
        Assert.isTrue(result.statistics.dmlStats.inserts.byType.containsKey('Case'), 'Should have Case stats');

        UoWTestHelpers.assertRelationshipResolved(con, Contact.AccountId, acc.Id);
        UoWTestHelpers.assertRelationshipResolved(supportCase, Case.ContactId, con.Id);

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.SUCCESS, workItem.status, 'DML work item should have SUCCESS status');
        }
    }

    // ============================================================================
    // DML UPSERTS
    // ============================================================================

    @isTest
    static void test_dmlUpsert_succeeds() {
        // Arrange - Use mock DML strategy for org-independent testing
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> existingAccounts = UoWCoreTestDataFactory.createExistingAccounts(1);
        existingAccounts[0].Name = 'Updated via Upsert';

        // Create new accounts
        Account newAccount = UoWCoreTestDataFactory.createAccount('Inserted via Upsert');

        List<Account> accountsToUpsert = new List<Account>();
        accountsToUpsert.addAll(existingAccounts);
        accountsToUpsert.add(newAccount);

        //Since we do not have an external id on Account, we will just use Id field for upsert
        for(Account acc : accountsToUpsert) {
            uow.registerUpsert(acc, Account.Id);
        }

        UoWPlan plan = uow.getPlan();
        Assert.isTrue(plan.hasDmlWork(), 'DML work should have been registered to the plan');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Framework correctly processed the mock results
        UoWTestHelpers.assertSuccess(result);

        // 1 work item for Account Upserts (as DML work items support consolidation by type and operation)
        UoWTestHelpers.assertExecutedDmlWorkItemCount(result, Account.SObjectType, UoWEnums.DmlOperation.UPSERT_OP, 1);

        // Upserts - 1 insert and 1 update
        Integer totalUpsertDmlCount = 2;
        Assert.areEqual(totalUpsertDmlCount, result.statistics.dmlStats.upserts.records.processed, 'Should process ' + totalUpsertDmlCount + ' DML upserts');
        Assert.areEqual(totalUpsertDmlCount, result.statistics.dmlStats.upserts.records.successes, 'Should have ' + totalUpsertDmlCount + ' DML upsert successes');
        Assert.areEqual(1, result.statistics.dmlStats.upserts.records.inserts, 'Should have 1 inserts in upsert operation');
        Assert.areEqual(1, result.statistics.dmlStats.upserts.records.updates, 'Should have 1 updates in upsert operation');
        Assert.areEqual(totalUpsertDmlCount, result.statistics.dmlStats.upserts.byType.get('Account').successes, 'Should have ' + totalUpsertDmlCount + ' DML upserts for Account');

        // Total DML
        Assert.areEqual(totalUpsertDmlCount, result.statistics.dmlStats.records.processed, 'Should process ' + totalUpsertDmlCount + ' DML records');
        Assert.areEqual(totalUpsertDmlCount, result.statistics.dmlStats.records.successes, 'Should have ' + totalUpsertDmlCount + ' DML successes');

        // Assert total statistics via convenience methods
        Assert.areEqual(totalUpsertDmlCount, result.statistics.getTotalProcessed(), 'Should have ' + totalUpsertDmlCount + ' processed items');
        Assert.areEqual(totalUpsertDmlCount, result.statistics.getTotalSucceeded(), 'Should have ' + totalUpsertDmlCount + ' success items');
        Assert.areEqual(0, result.statistics.getTotalFailed(), 'Should have no failures');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.SUCCESS, workItem.status, 'DML work item should have SUCCESS status');
        }
    }

    // ============================================================================
    // DML UPDATES
    // ============================================================================

    @isTest
    static void test_dmlUpdate_succeeds() {
        // Arrange - Use mock DML strategy for org-independent testing
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');
        List<Account> existingAccounts = UoWCoreTestDataFactory.createExistingAccounts(1);
        existingAccounts[0].Name = 'Updated via Update';
        uow.registerUpdate(existingAccounts);

        UoWPlan plan = uow.getPlan();
        Assert.isTrue(plan.hasDmlWork(), 'DML work should have been registered to the plan');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Framework correctly processed the mock results
        UoWTestHelpers.assertSuccess(result);

        // 1 work item for Account Updates (as DML work items support consolidation by type and operation)
        UoWTestHelpers.assertExecutedDmlWorkItemCount(result, Account.SObjectType, UoWEnums.DmlOperation.UPDATE_OP, 1);

        // Updates
        Assert.areEqual(1, result.statistics.dmlStats.updates.records.processed, 'Should process 1 DML updates');
        Assert.areEqual(1, result.statistics.dmlStats.updates.records.successes, 'Should have 1 DML update successes');
        Assert.areEqual(1, result.statistics.dmlStats.updates.byType.get('Account').successes, 'Should have 1 DML updates for Account');

        // Total DML
        Assert.areEqual(1, result.statistics.dmlStats.records.processed, 'Should process 1 DML records');
        Assert.areEqual(1, result.statistics.dmlStats.records.successes, 'Should have 1 DML successes');

        // Assert total statistics via convenience methods
        Assert.areEqual(1, result.statistics.getTotalProcessed(), 'Should have 1 processed items');
        Assert.areEqual(1, result.statistics.getTotalSucceeded(), 'Should have 1 success items');
        Assert.areEqual(0, result.statistics.getTotalFailed(), 'Should have no failures');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.SUCCESS, workItem.status, 'DML work item should have SUCCESS status');
        }
    }

    // ============================================================================
    // DML DELETES
    // ============================================================================

    @isTest
    static void test_dmlDelete_succeeds() {
        // Arrange - Use mock DML strategy for org-independent testing
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');
        List<Account> existingAccounts = UoWCoreTestDataFactory.createExistingAccounts(1);
        uow.registerDelete(existingAccounts);

        UoWPlan plan = uow.getPlan();
        Assert.isTrue(plan.hasDmlWork(), 'DML work should have been registered to the plan');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Framework correctly processed the mock results
        UoWTestHelpers.assertSuccess(result);

        // 1 work item for Account Deletes (as DML work items support consolidation by type and operation)
        UoWTestHelpers.assertExecutedDmlWorkItemCount(result, Account.SObjectType, UoWEnums.DmlOperation.DELETE_OP, 1);

        // Deletes
        Assert.areEqual(1, result.statistics.dmlStats.deletes.records.processed, 'Should process 1 DML deletes');
        Assert.areEqual(1, result.statistics.dmlStats.deletes.records.successes, 'Should have 1 DML delete successes');
        Assert.areEqual(1, result.statistics.dmlStats.deletes.byType.get('Account').successes, 'Should have 1 DML deletes for Account');

        // Total DML
        Assert.areEqual(1, result.statistics.dmlStats.records.processed, 'Should process 1 DML records');
        Assert.areEqual(1, result.statistics.dmlStats.records.successes, 'Should have 1 DML successes');

        // Assert total statistics via convenience methods
        Assert.areEqual(1, result.statistics.getTotalProcessed(), 'Should have 1 processed items');
        Assert.areEqual(1, result.statistics.getTotalSucceeded(), 'Should have 1 success items');
        Assert.areEqual(0, result.statistics.getTotalFailed(), 'Should have no failures');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.SUCCESS, workItem.status, 'DML work item should have SUCCESS status');
        }
    }

    // ============================================================================
    // DML UNDELETES
    // ============================================================================

    @isTest
    static void test_dmlUndelete_succeeds() {
        // Arrange - Use mock DML strategy for org-independent testing
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');
        List<Account> existingAccounts = UoWCoreTestDataFactory.createExistingAccounts(1);
        uow.registerUndelete(existingAccounts);

        UoWPlan plan = uow.getPlan();
        Assert.isTrue(plan.hasDmlWork(), 'DML work should have been registered to the plan');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Framework correctly processed the mock results
        UoWTestHelpers.assertSuccess(result);

        // 1 work item for Account Undeletes (as DML work items support consolidation by type and operation)
        UoWTestHelpers.assertExecutedDmlWorkItemCount(result, Account.SObjectType, UoWEnums.DmlOperation.UNDELETE_OP, 1);

        // Undeletes
        Assert.areEqual(1, result.statistics.dmlStats.undeletes.records.processed, 'Should process 1 DML undeletes');
        Assert.areEqual(1, result.statistics.dmlStats.undeletes.records.successes, 'Should have 1 DML undelete successes');
        Assert.areEqual(1, result.statistics.dmlStats.undeletes.byType.get('Account').successes, 'Should have 1 DML undeletes for Account');

        // Total DML
        Assert.areEqual(1, result.statistics.dmlStats.records.processed, 'Should process 1 DML records');
        Assert.areEqual(1, result.statistics.dmlStats.records.successes, 'Should have 1 DML successes');

        // Assert total statistics via convenience methods
        Assert.areEqual(1, result.statistics.getTotalProcessed(), 'Should have 1 processed items');
        Assert.areEqual(1, result.statistics.getTotalSucceeded(), 'Should have 1 success items');
        Assert.areEqual(0, result.statistics.getTotalFailed(), 'Should have no failures');

        // Verify work item statuses
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.SUCCESS, workItem.status, 'DML work item should have SUCCESS status');
        }
    }

    // ============================================================================
    // PLATFORM EVENTS
    // ============================================================================

    @isTest
    static void test_platformEvent_succeeds() {
        // Arrange - Use mock event channel for org-independent testing
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');
        SObject testEvent = new Account(Name = 'Test Event');
        uow.registerPlatformEvent(testEvent);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Framework correctly processed the mock results
        UoWTestHelpers.assertSuccess(result);

        // 1 work item for Platform Events (as event work items support consolidation by phase)
        UoWTestHelpers.assertExecutedEventWorkItemCount(result, UoWEnums.WorkPhase.POST_DML, 1);

        // Events
        Assert.areEqual(1, result.statistics.eventStats.events.processed, 'Should process 1 event');
        Assert.areEqual(1, result.statistics.eventStats.events.published, 'Should publish 1 event');

        // Assert total statistics via convenience methods
        Assert.areEqual(1, result.statistics.getTotalProcessed(), 'Should have 1 processed items');
        Assert.areEqual(1, result.statistics.getTotalSucceeded(), 'Should have 1 success items');
        Assert.areEqual(0, result.statistics.getTotalFailed(), 'Should have no failures');

        // Verify work item statuses
        for (UoWEventWorkItem workItem : result.getAllEventWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.SUCCESS, workItem.status, 'Event work item should have SUCCESS status');
        }
    }

    @isTest
    static void test_platformEvent_consolidationByPhase_succeeds() {
        // Arrange - Use mock event channel for org-independent testing
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Account> events1 = new List<Account>{
            new Account(Name = 'Event 1'),
            new Account(Name = 'Event 2'),
            new Account(Name = 'Event 3')
        };

        List<Account> events2 = new List<Account>{
            new Account(Name = 'Event 4'),
            new Account(Name = 'Event 5')
        };

        List<Account> events3 = new List<Account>{
            new Account(Name = 'Event 6'),
            new Account(Name = 'Event 7')
        };

        List<Account> events4 = new List<Account>{
            new Account(Name = 'Event 8'),
            new Account(Name = 'Event 9')
        };

        uow.registerPlatformEvent(events1);  // Default: POST_DML
        uow.registerPlatformEvent(events2);  // Add a different set to make sure it gets consolidated with POST_DML
        for(SObject evt : events3) {
            uow.registerPlatformEvent(evt, UoWEnums.WorkPhase.ON_SUCCESS); // Register individually to test consolidation
        }
        for(SObject evt : events4) {
            uow.registerPlatformEvent(evt, UoWEnums.WorkPhase.ON_FAILURE); // Register individually to test consolidation
        }

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Framework correctly processed the mock results
        UoWTestHelpers.assertSuccess(result);

        // 1 work item for Platform Events (as event work items support consolidation by phase)
        UoWTestHelpers.assertExecutedEventWorkItemCount(result, UoWEnums.WorkPhase.POST_DML, 1);
        UoWTestHelpers.assertExecutedEventWorkItemCount(result, UoWEnums.WorkPhase.ON_SUCCESS, 1);
        // ON_FAILURE events registered but not executed (transaction succeeded)
        UoWTestHelpers.assertExecutedEventWorkItemCount(result, UoWEnums.WorkPhase.ON_FAILURE, 0);

        // Only 7 events execute (POST_DML + ON_SUCCESS), ON_FAILURE doesn't execute in successful transaction
        Assert.areEqual(7, result.statistics.eventStats.events.published, 'Should have 7 events published');

        // Verify event counts in each phase - each phase work items should still be included in the result
        for (UoWEventWorkItem workItem : result.getAllEventWork()) {
            if (workItem.executionPhase == UoWEnums.WorkPhase.POST_DML) {
                UoWTestHelpers.assertEventWorkItemEventCount(workItem, 5);
                Assert.areEqual(UoWEnums.WorkStatus.SUCCESS, workItem.status, 'POST_DML work item should be successful');
            } else if (workItem.executionPhase == UoWEnums.WorkPhase.ON_SUCCESS) {
                UoWTestHelpers.assertEventWorkItemEventCount(workItem, 2);
                Assert.areEqual(UoWEnums.WorkStatus.SUCCESS, workItem.status, 'ON_SUCCESS work item should be successful');
            } else if (workItem.executionPhase == UoWEnums.WorkPhase.ON_FAILURE) {
                UoWTestHelpers.assertEventWorkItemEventCount(workItem, 2);
                Assert.areEqual(UoWEnums.WorkStatus.SKIPPED, workItem.status, 'ON_FAILURE work item should be skipped in successful transaction');
            }
        }
    }

    // ============================================================================
    // FLOWS
    // ============================================================================

    @isTest
    static void test_flowExecution_succeeds() {
        // Arrange - Use mock flow channel for org-independent testing
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');
        uow.registerFlowExecution('UoWTest_SimpleAutolaunchedFlow')
            .withInput('InputMessage', 'Flow Simulation');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Framework correctly processed the mock results
        UoWTestHelpers.assertSuccess(result);

        // Multiple work items for Flows (as Flows don't support consolidation)
        UoWTestHelpers.assertExecutedFlowWorkItemCount(result, UoWEnums.WorkPhase.POST_DML, 1);

        // Flows
        Assert.areEqual(1, result.statistics.flowStats.flows.processed, 'Should process 1 flow');
        Assert.areEqual(1, result.statistics.flowStats.flows.executed, 'Should execute 1 flow');

        // Assert total statistics via convenience methods
        Assert.areEqual(1, result.statistics.getTotalProcessed(), 'Should have 1 processed items');
        Assert.areEqual(1, result.statistics.getTotalSucceeded(), 'Should have 1 success items');
        Assert.areEqual(0, result.statistics.getTotalFailed(), 'Should have no failures');

        // Verify work item statuses
        for (UoWFlowWorkItem workItem : result.getAllFlowWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.SUCCESS, workItem.status, 'Flow work item should have SUCCESS status');
        }
    }

    // ============================================================================
    // EMAILS
    // ============================================================================

    @isTest
    static void test_emailSend_succeeds() {
        // Arrange - Use mock email channel for org-independent testing
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{'test@example.com'});
        email.setSubject('Test Subject');
        uow.registerEmail(email);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Framework correctly processed the mock results
        UoWTestHelpers.assertSuccess(result);

        // 1 work item for Emails (as the work item supports consolidation by phase)
        UoWTestHelpers.assertExecutedEmailWorkItemCount(result, UoWEnums.WorkPhase.ON_SUCCESS, 1);

        // Emails
        Assert.areEqual(1, result.statistics.emailStats.emails.processed, 'Should process 1 email');
        Assert.areEqual(1, result.statistics.emailStats.emails.sent, 'Should send 1 email');

        // Assert total statistics via convenience methods
        Assert.areEqual(1, result.statistics.getTotalProcessed(), 'Should have 1 processed items');
        Assert.areEqual(1, result.statistics.getTotalSucceeded(), 'Should have 1 success items');
        Assert.areEqual(0, result.statistics.getTotalFailed(), 'Should have no failures');

        // Verify work item statuses
        for (UoWEmailWorkItem workItem : result.getAllEmailWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.SUCCESS, workItem.status, 'Email work item should have SUCCESS status');
        }
    }

    @isTest
    static void test_emailSend_consolidationByPhase_succeeds() {
        // Arrange - Use mock event channel for org-independent testing
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        List<Messaging.SingleEmailMessage> emails1 = new List<Messaging.SingleEmailMessage>();
        for (Integer i = 0; i < 3; i++) {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{'test' + i + '@example.com'});
            email.setSubject('Test ' + i);
            emails1.add(email);
        }

        List<Messaging.SingleEmailMessage> emails2 = new List<Messaging.SingleEmailMessage>();
        for (Integer i = 0; i < 2; i++) {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{'test' + i + '@example.com'});
            email.setSubject('Test ' + i);
            emails2.add(email);
        }

        List<Messaging.SingleEmailMessage> emails3 = new List<Messaging.SingleEmailMessage>();
        for (Integer i = 0; i < 2; i++) {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{'test' + i + '@example.com'});
            email.setSubject('Test ' + i);
            emails3.add(email);
        }

        List<Messaging.SingleEmailMessage> emails4 = new List<Messaging.SingleEmailMessage>();
        for (Integer i = 0; i < 2; i++) {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{'test' + i + '@example.com'});
            email.setSubject('Test ' + i);
            emails4.add(email);
        }

        uow.registerEmail(emails1);  // Default: ON_SUCCESS
        uow.registerEmail(emails2);  // Add a different set to make sure it gets consolidated with ON_SUCCESS
        for(Messaging.SingleEmailMessage email : emails3) {
            uow.registerEmail(email, UoWEnums.WorkPhase.POST_DML); // Register individually to test consolidation
        }
        for(Messaging.SingleEmailMessage email : emails4) {
            uow.registerEmail(email, UoWEnums.WorkPhase.ON_FAILURE); // Register individually to test consolidation
        }

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Framework correctly processed the mock results
        UoWTestHelpers.assertSuccess(result);

        // 1 work item for Platform Events (as event work items support consolidation by phase)
        UoWTestHelpers.assertExecutedEmailWorkItemCount(result, UoWEnums.WorkPhase.ON_SUCCESS, 1);
        UoWTestHelpers.assertExecutedEmailWorkItemCount(result, UoWEnums.WorkPhase.POST_DML, 1);
        // ON_FAILURE events registered but not executed (transaction succeeded)
        UoWTestHelpers.assertExecutedEmailWorkItemCount(result, UoWEnums.WorkPhase.ON_FAILURE, 0);

        // Only 7 emails execute (POST_DML + ON_SUCCESS), ON_FAILURE doesn't execute in successful transaction
        Assert.areEqual(7, result.statistics.emailStats.emails.sent, 'Should have 7 emails sent');

        // Verify email counts in each phase - each phase work items should still be included in the result
        for (UoWEmailWorkItem workItem : result.getAllEmailWork()) {
            if (workItem.executionPhase == UoWEnums.WorkPhase.ON_SUCCESS) {
                UoWTestHelpers.assertEmailWorkItemEmailCount(workItem, 5);
                Assert.areEqual(UoWEnums.WorkStatus.SUCCESS, workItem.status, 'ON_SUCCESS work item should be successful');
            } else if (workItem.executionPhase == UoWEnums.WorkPhase.POST_DML) {
                UoWTestHelpers.assertEmailWorkItemEmailCount(workItem, 2);
                Assert.areEqual(UoWEnums.WorkStatus.SUCCESS, workItem.status, 'POST_DML work item should be successful');
            } else if (workItem.executionPhase == UoWEnums.WorkPhase.ON_FAILURE) {
                UoWTestHelpers.assertEmailWorkItemEmailCount(workItem, 2);
                Assert.areEqual(UoWEnums.WorkStatus.SKIPPED, workItem.status, 'ON_FAILURE work item should be skipped in successful transaction');
            }
        }
    }

    // ============================================================================
    // CUSTOM NOTIFICATIONS
    // ============================================================================

    @isTest
    static void test_notificationSend_succeeds() {
        // Arrange - Use mock notification channel for org-independent testing
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');
        uow.registerNotification()
            .withNotificationType(UoWTestHelpers.generateFakeId(CustomNotificationType.SObjectType), 'TestNotification')
            .withTitle('Notification Test')
            .withBody('Testing Notification sending via UoW')
            .withRecipients(new Set<String> { UserInfo.getUserId() });

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Framework correctly processed the mock results
        UoWTestHelpers.assertSuccess(result);

        // Multiple work items for Notifications (as Notifications don't support consolidation)
        UoWTestHelpers.assertExecutedNotificationWorkItemCount(result, UoWEnums.WorkPhase.ON_SUCCESS, 1);

        // Notifications
        Assert.areEqual(1, result.statistics.notificationStats.notifications.processed, 'Should process 1 notification');
        Assert.areEqual(1, result.statistics.notificationStats.notifications.sent, 'Should send 1 notification');

        // Assert total statistics via convenience methods
        Assert.areEqual(1, result.statistics.getTotalProcessed(), 'Should have 1 processed items');
        Assert.areEqual(1, result.statistics.getTotalSucceeded(), 'Should have 1 success items');
        Assert.areEqual(0, result.statistics.getTotalFailed(), 'Should have no failures');

        // Verify work item statuses
        for (UoWNotificationWorkItem workItem : result.getAllNotificationWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.SUCCESS, workItem.status, 'Notification work item should have SUCCESS status');
        }
    }

    // ============================================================================
    // CALLOUTS
    // ============================================================================

    @isTest
    static void test_calloutExecution_succeeds() {
        // Arrange - Use mock callout strategy for org-independent testing
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');
        Map<String, Object> requestData = new Map<String, Object>{
            'name' => 'Test Record',
            'type' => 'Account'
        };
        uow.registerCallout('callout:TestEndpoint/api/records', 'POST')
            .withHeader('Content-Type', 'application/json')
            .withHeader('Authorization', 'Bearer test-token-12345')
            .withBody(JSON.serialize(requestData));

        UoWPlan plan = uow.getPlan();
        Assert.isTrue(plan.hasCallouts(), 'Callout work should have been registered to the plan');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Framework correctly processed the mock results
        UoWTestHelpers.assertSuccess(result);

        // Multiple work items for Callouts (as Callouts don't support consolidation)
        UoWTestHelpers.assertExecutedCalloutWorkItemCount(result, UoWEnums.WorkPhase.PRE_DML, 1);

        // Callouts
        Assert.areEqual(1, result.statistics.calloutStats.callouts.processed, 'Should process 1 callout');
        Assert.areEqual(1, result.statistics.calloutStats.callouts.executed, 'Should execute 1 callout');
        // Assert total statistics via convenience methods
        Assert.areEqual(1, result.statistics.getTotalProcessed(), 'Should have 1 processed items');
        Assert.areEqual(1, result.statistics.getTotalSucceeded(), 'Should have 1 success items');
        Assert.areEqual(0, result.statistics.getTotalFailed(), 'Should have no failures');

        // Verify work item statuses
        for (UoWCalloutWorkItem workItem : result.getAllCalloutWork()) {
            Assert.areEqual(UoWEnums.WorkStatus.SUCCESS, workItem.status, 'Callout work item should have SUCCESS status');
        }
    }

    // ============================================================================
    // ALL WORK TYPES
    // ============================================================================

    @isTest
    static void test_allWorkTypes_singleTransaction_succeeds() {
        // Arrange - Use mock DML strategy for org-independent testing
        UnitOfWork uow = UoWTestHelpers.generateUoW_AllWorkItems('TestConfigAllMocks');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Framework correctly processed the results
        Assert.isFalse(result.isDryRun, 'Should not be a dry run');
        UoWTestHelpers.assertSuccess(result);
        UoWTestHelpers.assertAllWorkItemSuccessfulExecution(result);
    }

    // ============================================================================
    // ASYNC TRANSACTION TESTS
    // ============================================================================

    @isTest
    static void test_asyncCommit_allWorkItems_enqueuesSuccessfully() {
        // Arrange - Use mock DML strategy for org-independent testing
        UnitOfWork uow = UoWTestHelpers.generateUoW_AllWorkItems('TestConfigAllMocks');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork(UoWEnums.CommitMode.ASYNC);
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertSuccess(result);
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.ENQUEUED);

        // Assert - All statistics should be zero
        Assert.areEqual(0, result.statistics.dmlStats.records.processed, 'Should have 0 DML records');
        Assert.areEqual(0, result.statistics.eventStats.events.processed, 'Should have 0 events');
        Assert.areEqual(0, result.statistics.emailStats.emails.processed, 'Should have 0 emails');
        Assert.areEqual(0, result.statistics.notificationStats.notifications.processed, 'Should have 0 notifications');
        Assert.areEqual(0, result.statistics.flowStats.flows.processed, 'Should have 0 flows');
        Assert.areEqual(0, result.statistics.calloutStats.callouts.processed, 'Should have 0 callouts');

        // Assert - Async child execution completed
        // UoWQueueable sets finalizerState in its finally block, accessible after Test.stopTest()
        UoWQueueable.FinalizerState asyncState = UoWQueueable.getFinalizerState();
        Assert.isNotNull(asyncState, 'Async execution should set finalizer state');
        Assert.isNotNull(asyncState.context, 'Async execution should have context');

        //Assert the Async transaction boundary
        UoWContext originalContext = uow.getContext();
        UoWContext asyncContext = asyncState.context;
        Assert.isTrue(asyncContext.isAsyncChild(), 'The aync context should be an async child');
        Assert.areEqual(originalContext.transactionId, asyncContext.parentTransactionId, 'The original context transaction id should have been set as the parent transaction id on the async context');
        Assert.areEqual(originalContext.correlationId, asyncContext.correlationId, 'The correlationId should have survived the async boundary');
        Assert.areEqual(1, asyncContext.asyncDepth, 'The async context depth should be set at 1');

    }

    // ============================================================================
    // ASYNC CHILD EXECUTION TESTS (Simulated Queueable)
    // ============================================================================

    /**
     * Verifies async commit executes all work items successfully.
     *
     * TEST PATTERN NOTE:
     * This test accesses UoWQueueable.getFinalizerState() directly after Test.stopTest()
     * because the platform forces Queueable completion synchronously in test context.
     *
     * In production, the Queueable runs in a separate async transaction, so the static
     * finalizerState is NOT accessible from the original transaction. Production code
     * should use ITransactionFinalizer implementations to handle post-execution logic -
     * the finalizer's execute() method can access UoWQueueable.getFinalizerState() within
     * its own execution context.
     */
    @isTest
    static void test_asyncCommit_allWorkItems_executeSuccessfully() {
        // Arrange
        UnitOfWork uow = UoWTestHelpers.generateUoW_AllWorkItems('TestConfigAllMocks');

        // Act - Request async execution
        Test.startTest();
        UoWResult originalResult = uow.commitWork(UoWEnums.CommitMode.ASYNC);
        Test.stopTest();

        // Assert - Parent transaction returns early with ENQUEUED status
        UoWTestHelpers.assertSuccess(originalResult);
        UoWTestHelpers.assertAsyncEnqueued(originalResult);
        Assert.areEqual(0, originalResult.statistics.dmlStats.records.processed, 'Parent should process 0 records (DML happens in async child)');

        // Assert - Async child execution completed
        // UoWQueueable sets finalizerState in its finally block, accessible after Test.stopTest()
        UoWQueueable.FinalizerState asyncState = UoWQueueable.getFinalizerState();
        Assert.isNotNull(asyncState, 'Async execution should set finalizer state');
        Assert.isNotNull(asyncState.result, 'Async execution should produce a result');
        Assert.isNotNull(asyncState.context, 'Async execution should have context');

        // Verify async child processed the work
        UoWResult asyncResult = asyncState.result;
        UoWTestHelpers.assertSuccess(asyncResult);
        UoWTestHelpers.assertAllWorkItemSuccessfulExecution(asyncResult);
    }

    // ============================================================================
    // DRY RUN TRANSACTION
    // ============================================================================

    @isTest
    static void test_allWorkTypes_dryRunTransaction_succeeds() {
        // Arrange - Use mock DML strategy for org-independent testing
        UnitOfWork uow = UoWTestHelpers.generateUoW_AllWorkItems('TestConfigAllMocks')
                            .asDryRun();

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertSuccess(result);
        Assert.isTrue(result.isDryRun, 'Should be a dry run');
    }

    @isTest
    static void test_asyncCommit_dryRunMode_stillEnqueues() {
        // Arrange - Use mock DML strategy for org-independent testing
        UnitOfWork uow = UoWTestHelpers.generateUoW_AllWorkItems('TestConfigAllMocks')
                            .asDryRun();

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork(UoWEnums.CommitMode.ASYNC);
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertSuccess(result);
        Assert.isTrue(result.isDryRun, 'Should be a dry run');
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.ENQUEUED);

        // Assert - Async child execution completed
        // UoWQueueable sets finalizerState in its finally block, accessible after Test.stopTest()
        UoWQueueable.FinalizerState asyncState = UoWQueueable.getFinalizerState();
        Assert.isNotNull(asyncState, 'Async execution should set finalizer state');
        Assert.isNotNull(asyncState.result, 'Async execution should produce a result');
        Assert.isNotNull(asyncState.context, 'Async execution should have context');

        UoWTestHelpers.assertSuccess(asyncState.result);
        Assert.isTrue(asyncState.result.isDryRun, 'Should be a dry run');
    }

    // ============================================================================
    // EMPTY PLAN TESTS
    // ============================================================================

    @isTest
    static void test_emptyPlan_skipped() {
        // Arrange - Use mock DML strategy for org-independent testing
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Empty plan should be SKIPPED (considered successful, but nothing executed)
        UoWTestHelpers.assertSuccess(result);
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.SKIPPED);

        // Assert - Should have info message about skipped transaction
        UoWTestHelpers.assertResultHasMessage(result, System.LoggingLevel.INFO, 'No work items in plan');

        // Assert - All statistics should be zero
        Assert.areEqual(0, result.statistics.dmlStats.records.processed, 'Should have 0 DML records');
        Assert.areEqual(0, result.statistics.eventStats.events.processed, 'Should have 0 events');
        Assert.areEqual(0, result.statistics.emailStats.emails.processed, 'Should have 0 emails');
        Assert.areEqual(0, result.statistics.notificationStats.notifications.processed, 'Should have 0 notifications');
        Assert.areEqual(0, result.statistics.flowStats.flows.processed, 'Should have 0 flows');
        Assert.areEqual(0, result.statistics.calloutStats.callouts.processed, 'Should have 0 callouts');
    }

    @isTest
    static void test_asyncCommit_emptyPlan_skipped() {
        // Arrange - No work items registered
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigAllMocks');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork(UoWEnums.CommitMode.ASYNC);
        Test.stopTest();

        // Assert - Empty plan should be SKIPPED (nothing to enqueue)
        // Empty plan check happens BEFORE async enqueue, so status is SKIPPED not ENQUEUED
        UoWTestHelpers.assertSuccess(result);
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.SKIPPED);
        Assert.areEqual(0, result.statistics.dmlStats.records.processed, 'Empty plan should have 0 records processed');
    }

}