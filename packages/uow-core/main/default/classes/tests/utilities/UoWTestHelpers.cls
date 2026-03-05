//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Test helper utilities for UoW framework tests. Provides assertion helpers,
 * test data generation methods, and debugging utilities for comprehensive testing.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Test Utilities
 * @see UoWTestMocks
 * @see UoWCoreTestDataFactory
 * @see UoWMockResultBuilder
 */
@isTest
public with sharing class UoWTestHelpers {

    public final static Integer DEFAULT_DML_COUNT = 5;
    public final static Integer DEFAULT_EVENT_COUNT = 5;
    public final static Integer DEFAULT_FLOW_COUNT = 5;
    public final static Integer DEFAULT_EMAIL_COUNT = 5;
    public final static Integer DEFAULT_NOTIFICATION_COUNT = 5;
    public final static Integer DEFAULT_CALLOUT_COUNT = 5;

    // ============================================================================
    // ID GENERATOR METHODS
    // ============================================================================

    /**
     * Generate fake Salesforce ID for testing. Format: 15-character ID with proper prefix.
     *
     * @param sObjectType The SObject type to generate an ID for
     * @return Fake 15-character Salesforce ID
     */
    public static String generateFakeId(Schema.SObjectType sObjectType) {
        return generateFakeId(sObjectType, 1);
    }

    /**
     * Generate fake Salesforce ID for testing with counter suffix. Format: 15-character ID with proper prefix.
     *
     * @param sObjectType The SObject type to generate an ID for
     * @param counter Counter value for unique ID generation
     * @return Fake 15-character Salesforce ID
     */
    public static String generateFakeId(Schema.SObjectType sObjectType, Integer counter) {
        String keyPrefix = UoWCacheService.getDescribe(sObjectType).getKeyPrefix();
        if (String.isBlank(keyPrefix)) {
            keyPrefix = '000';
        }

        String counterPadded = String.valueOf(counter).leftPad(12, '0');
        return keyPrefix + counterPadded;
    }

    // ============================================================================
    // CONFIGURATIONS
    // ============================================================================

    /**
     * Load test configurations from CSV static resources into custom metadata objects.
     * Resets singleton instances and loads all related metadata (configurations, plugins, policies, objects, masking rules).
     */
    public static void loadTestConfigurations() {
        // Reset singleton to ensure fresh state before loading test data
        UoWConfigurationLoader.resetInstance();

        // Load test configurations (parent records first)
        Test.loadData(
            UoWConfiguration__mdt.SObjectType,
            'UoWTestConfigurations'
        );

        // Load plugin settings
        Test.loadData(
            UoWPluginSetting__mdt.SObjectType,
            'UoWTestPluginSettings'
        );

        // Load policy settings
        Test.loadData(
            UoWPolicySetting__mdt.SObjectType,
            'UoWTestPolicySettings'
        );

        // Load object settings
        Test.loadData(
            UoWObjectSetting__mdt.SObjectType,
            'UoWTestObjectSettings'
        );

        // Load data masking rules
        Test.loadData(
            UoWDataMaskRule__mdt.SObjectType,
            'UoWTestDataMaskRules'
        );

        // Clear masking service cache to pick up new test rules
        UoWMaskingService.clearCache();

        // Force fresh load of configuration data after all test data is loaded
        // This ensures the singleton loads data AFTER Test.loadData() completes
        UoWConfigurationLoader.getInstance();
    }

    // ============================================================================
    // UOW CONFIGURATION
    // ============================================================================

    public static UnitOfWork generateUoW_AllWorkItems(String configurationName) {
        return generateUoW(configurationName, new TestUoWOptions(true));
    }

    public static UnitOfWork generateUoW_NoWorkItems(String configurationName) {
        return generateUoW(configurationName, new TestUoWOptions(false));
    }

    public static UnitOfWork generateUoW_DmlInsertsOnly(String configurationName) {
        TestUoWOptions options = new TestUoWOptions(false);
        options.registerInserts = true;

        return generateUoW(configurationName, options);
    }

    /**
     * Generate UnitOfWork with all work types registered using continueOnError mode for partial success testing.
     *
     * @param configurationName Configuration name to use
     * @param options Test options for configuring work item registration and behavior
     * @return UnitOfWork with work types configured for continueOnError mode
     */
    public static UnitOfWork generateUoW(String configurationName, TestUoWOptions options) {
        // Arrange - Setup all mocks (channels + DML strategy)
        UnitOfWork uow = new UnitOfWork(configurationName)
                            .setScenario('Test Scenario')
                            .setDescription('UoW with all work types for testing');

        // 1a. DML Inserts - Account and Contact with relationship
        if(options.registerInserts){
            registerInserts(uow, options, DEFAULT_DML_COUNT);
        }

        // 1b. DML Upserts - Account (default count * 2 - half existing, half new)
        if(options.registerUpserts){
            registerUpserts(uow, options, DEFAULT_DML_COUNT);
        }

        // 1c. DML Updates - Account (existing records)
        if(options.registerUpdates){
            registerUpdates(uow, options, DEFAULT_DML_COUNT);
        }

        // 1d. DML Deletes - Account (existing records)
        if(options.registerDeletes){
            registerDeletes(uow, options, DEFAULT_DML_COUNT);
        }

        // 1e. DML Undeletes - Account (existing records)
        if(options.registerUndeletes){
            registerUndeletes(uow, options, DEFAULT_DML_COUNT);
        }

        // 2. Platform Events
        if(options.registerEvents){
            registerEvents(uow, options, DEFAULT_EVENT_COUNT);
        }

        // 3. Flows
        if(options.registerFlows){
            registerFlows(uow, options, DEFAULT_FLOW_COUNT);
        }

        // 4. Emails
        if(options.registerEmails){
            registerEmails(uow, options, DEFAULT_EMAIL_COUNT);
        }

        // 5. Custom Notifications
        if(options.registerNotifications){
            registerNotifications(uow, options, DEFAULT_NOTIFICATION_COUNT);
        }

        // 6. Callouts
        if(options.registerCallouts){
            registerCallouts(uow, options, DEFAULT_CALLOUT_COUNT);
        }

        return uow;
    }

    // ============================================================================
    // UNIT OF WORK FACTORY (For Permissive Security Mode Testing)
    // ============================================================================

    /**
     * Create a UnitOfWork with custom configuration name and PERMISSIVE security mode.
     *
     * @param configName Configuration name to use
     * @return UnitOfWork instance with specified config and PERMISSIVE security mode
     */
    public static UnitOfWork generatePermissiveUnitOfWork(String configName) {
        UnitOfWork uow = generateUoW_AllWorkItems(configName);

        // Override security mode to PERMISSIVE for org-independent testing
        uow.getContext().getFeatureSettings().setSecurityMode(UoWEnums.SecurityMode.PERMISSIVE);

        return uow;
    }

    /**
     * Create a UnitOfWork from existing context and plan with PERMISSIVE security mode.
     *
     * @param ctx Existing UoWContext
     * @param plan Existing UoWPlan
     * @return UnitOfWork instance with PERMISSIVE security mode
     */
    public static UnitOfWork generatePermissiveUnitOfWork(UoWContext ctx, UoWPlan plan) {
        // Override security mode to PERMISSIVE for org-independent testing
        ctx.getFeatureSettings().setSecurityMode(UoWEnums.SecurityMode.PERMISSIVE);

        UnitOfWork uow = new UnitOfWork(ctx, plan);

        return uow;
    }

    // ============================================================================
    // REGISTRATIONS
    // ============================================================================

    public static void registerInserts(UnitOfWork uow, Integer insertCount) {
        TestUoWOptions options = new TestUoWOptions(false);
        registerInserts(uow, options, insertCount);
    }

    public static void registerInserts(UnitOfWork uow, TestUoWOptions options, Integer insertCount) {
        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(insertCount);
        List<Contact> contacts = UoWCoreTestDataFactory.createContacts(insertCount, null);

        for(Integer i = 0; i< insertCount; i++) {
            UoWDmlWorkItem accountWorkItem = uow.registerInsert(accounts[i]);
            UoWDmlWorkItem contactWorkItem = uow.registerInsert(contacts[i]);
            if(options.continueOnError) {
                accountWorkItem.continueOnError();
                contactWorkItem.continueOnError();
            }
            uow.relate(contacts[i], Contact.AccountId, accounts[i]);
        }
    }

    public static void registerUpserts(UnitOfWork uow, Integer upsertCount) {
        TestUoWOptions options = new TestUoWOptions(false);
        registerUpserts(uow, options, upsertCount);
    }

    public static void registerUpserts(UnitOfWork uow, TestUoWOptions options, Integer upsertCount) {
        // Create account with fake ID (simulating existing record)
        List<Account> existingAccounts = UoWCoreTestDataFactory.createExistingAccounts(upsertCount);
        for(Integer i=0; i<existingAccounts.size(); i++) {
            existingAccounts[i].Name = 'Updated ' + i + ' via Upsert';
        }

        // Create new accounts
        List<Account> accounts = UoWCoreTestDataFactory.createAccounts(upsertCount);

        List<Account> accountsToUpsert = new List<Account>();
        accountsToUpsert.addAll(existingAccounts);
        accountsToUpsert.addAll(accounts);

        //Since we do not have an external id on Account, we will just use Id field for upsert
        for(Account acc : accountsToUpsert) {
            UoWDmlWorkItem accountWorkItem = uow.registerUpsert(acc, Account.Id);
            if(options.continueOnError) {
                accountWorkItem.continueOnError();
            }
        }
    }

    public static void registerUpdates(UnitOfWork uow, Integer updateCount) {
        TestUoWOptions options = new TestUoWOptions(false);
        registerUpdates(uow, options, updateCount);
    }

    public static void registerUpdates(UnitOfWork uow, TestUoWOptions options, Integer updateCount) {
        // Create account with fake ID (simulating existing record)
        List<Account> accounts = UoWCoreTestDataFactory.createExistingAccounts(updateCount);

        for(Account acc : accounts) {
            acc.Name = 'Updated Account Name';
            UoWDmlWorkItem accountWorkItem = uow.registerUpdate(acc);
            if(options.continueOnError) {
                accountWorkItem.continueOnError();
            }
        }
    }

    public static void registerDeletes(UnitOfWork uow, Integer deleteCount) {
        TestUoWOptions options = new TestUoWOptions(false);
        registerDeletes(uow, options, deleteCount);
    }

    public static void registerDeletes(UnitOfWork uow, TestUoWOptions options, Integer deleteCount) {
        // Create account with fake ID (simulating existing record)
        List<Account> accounts = UoWCoreTestDataFactory.createExistingAccounts(deleteCount);

        for(Account acc : accounts) {
            UoWDmlWorkItem accountWorkItem = uow.registerDelete(acc);
            if(options.continueOnError) {
                accountWorkItem.continueOnError();
            }
        }
    }

    public static void registerUndeletes(UnitOfWork uow, Integer undeleteCount) {
        TestUoWOptions options = new TestUoWOptions(false);
        registerUndeletes(uow, options, undeleteCount);
    }

    public static void registerUndeletes(UnitOfWork uow, TestUoWOptions options, Integer undeleteCount) {
        // Create account with fake ID (simulating existing record)
        List<Account> accounts = UoWCoreTestDataFactory.createExistingAccounts(undeleteCount);

        for(Account acc : accounts) {
            UoWDmlWorkItem accountWorkItem = uow.registerUndelete(acc);
            if(options.continueOnError) {
                accountWorkItem.continueOnError();
            }
        }
    }

    public static void registerEvents(UnitOfWork uow, Integer eventCount) {
        TestUoWOptions options = new TestUoWOptions(false);
        registerEvents(uow, options, eventCount);
    }

    public static void registerEvents(UnitOfWork uow, TestUoWOptions options, Integer eventCount) {
        // Since we dont have any platform events in this package, and since we are mocking,
        // we are using any SObject type to mimic platform events
        for (Integer i = 0; i < eventCount; i++) {
            //Default Events
            SObject testEvent = new Account(Name = 'Test Event ' + i);
            UoWEventWorkItem eventWorkItem = uow.registerPlatformEvent(testEvent);
            if(options.continueOnError) {
                eventWorkItem.continueOnError();
            }

            //On Success Events
            SObject onSuccessEvent = new Account(Name = 'Test Success Event ' + i);
            UoWEventWorkItem successEventWorkItem = uow.registerPlatformEvent(onSuccessEvent, UoWEnums.WorkPhase.ON_SUCCESS);
            if(options.continueOnError) {
                successEventWorkItem.continueOnError();
            }

            //On Failure Events
            SObject onFailureEvent = new Account(Name = 'Test Failure Event ' + i);
            UoWEventWorkItem failureEventWorkItem = uow.registerPlatformEvent(onFailureEvent, UoWEnums.WorkPhase.ON_FAILURE);
            if(options.continueOnError) {
                failureEventWorkItem.continueOnError();
            }
        }
    }

    public static void registerFlows(UnitOfWork uow, Integer flowCount) {
        TestUoWOptions options = new TestUoWOptions(false);
        registerFlows(uow, options, flowCount);
    }

    public static void registerFlows(UnitOfWork uow, TestUoWOptions options, Integer flowCount) {
        for (Integer i = 0; i < flowCount; i++) {
            //Default Flows
            UoWFlowWorkItem flowWorkItem = uow.registerFlowExecution('UoWTest_SimpleAutolaunchedFlow' + i)
                .withInputs(new Map<String, Object>{
                    'InputMessage' => 'All work types test flow ' + i
                });
            if(options.continueOnError) {
                flowWorkItem.continueOnError();
            }

            //On Success Flows
            UoWFlowWorkItem successFlowWorkItem = uow.registerFlowExecution('UoWTest_SuccessAutolaunchedFlow' + i, UoWEnums.WorkPhase.ON_SUCCESS)
                .withInput('InputMessage', 'Success Flow ' + i);
            if(options.continueOnError) {
                successFlowWorkItem.continueOnError();
            }

            //On Failure Flows
            UoWFlowWorkItem failureFlowWorkItem = uow.registerFlowExecution('UoWTest_FailureAutolaunchedFlow' + i, UoWEnums.WorkPhase.ON_FAILURE)
                .withInput('InputMessage', 'Failure Flow ' + i);
            if(options.continueOnError) {
                failureFlowWorkItem.continueOnError();
            }
        }
    }

    public static void registerEmails(UnitOfWork uow, Integer emailCount) {
        TestUoWOptions options = new TestUoWOptions(false);
        registerEmails(uow, options, emailCount);
    }

    public static void registerEmails(UnitOfWork uow, TestUoWOptions options, Integer emailCount) {
        for (Integer i = 0; i < emailCount; i++) {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{'test' + i + '@example.com'});
            email.setSubject('Test ' + i);

            //Default
            UoWEmailWorkItem emailWorkItem = uow.registerEmail(email);
            if(options.continueOnError) {
                emailWorkItem.continueOnError();
            }

            //On Failure
            UoWEmailWorkItem failureEmailWorkItem = uow.registerEmail(email, UoWEnums.WorkPhase.ON_FAILURE);
            if(options.continueOnError) {
                failureEmailWorkItem.continueOnError();
            }
        }
    }

    public static void registerNotifications(UnitOfWork uow, Integer notificationCount) {
        TestUoWOptions options = new TestUoWOptions(false);
        registerNotifications(uow, options, notificationCount);
    }

    public static void registerNotifications(UnitOfWork uow, TestUoWOptions options, Integer notificationCount) {
        Id recipientId = UserInfo.getUserId();
        for (Integer i = 0; i < notificationCount; i++) {
            //Default
            UoWNotificationWorkItem notificationWorkItem = uow.registerNotification()
                                                            .withNotificationType(generateFakeId(CustomNotificationType.SObjectType, i), 'TestNotification')
                                                            .withTitle('All Types Test')
                                                            .withBody('Testing all work types')
                                                            .withRecipients(new Set<String> { recipientId });
            if(options.continueOnError) {
                notificationWorkItem.continueOnError();
            }

            //On Failure
            UoWNotificationWorkItem failureNotificationWorkItem = uow.registerNotification(UoWEnums.WorkPhase.ON_FAILURE)
                                                                    .withNotificationType(generateFakeId(CustomNotificationType.SObjectType, i), 'TestNotification')
                                                                    .withTitle('All Types Test')
                                                                    .withBody('Testing all work types')
                                                                    .withRecipients(new Set<String> { recipientId });
            if(options.continueOnError) {
                failureNotificationWorkItem.continueOnError();
            }
        }
    }

    public static void registerCallouts(UnitOfWork uow, Integer calloutCount) {
        TestUoWOptions options = new TestUoWOptions(false);
        registerCallouts(uow, options, calloutCount);
    }

    public static void registerCallouts(UnitOfWork uow, TestUoWOptions options, Integer calloutCount) {
        Map<String, Object> requestData = new Map<String, Object>{
            'name' => 'Test Record',
            'type' => 'Account'
        };
        for (Integer i = 0; i < calloutCount; i++) {
            // Deafult
            UoWCalloutWorkItem calloutWorkItem = uow.registerCallout('callout:TestEndpoint/api/records')
                                                    .withHeader('Content-Type', 'application/json')
                                                    .withHeader('Authorization', 'Bearer test-token-12345')
                                                    .withBody(JSON.serialize(requestData));
            if(options.continueOnError) {
                calloutWorkItem.continueOnError();
            }

            // On Failure
            UoWCalloutWorkItem failureCalloutWorkItem = uow.registerCallout('callout:TestEndpoint/api/records', 'GET', UoWEnums.WorkPhase.ON_FAILURE)
                                                            .withHeader('Content-Type', 'application/json')
                                                            .withHeader('Authorization', 'Bearer test-token-12345')
                                                            .withBody(JSON.serialize(requestData));
            if(options.continueOnError) {
                failureCalloutWorkItem.continueOnError();
            }
        }
    }

    // ============================================================================
    // MESSAGE ASSERTIONS
    // ============================================================================

    /**
     * Assert that result contains a message with specific logging level and content.
     *
     * @param result The UoWResult to check
     * @param level The logging level to filter by
     * @param messagePart Substring to search for in message content
     */
    public static void assertResultHasMessage(UoWResult result, System.LoggingLevel level, String messagePart) {
        List<UoWMessage> messages = result.getMessagesByLevel(level);
        Boolean found = false;
        for (UoWMessage msg : messages) {
            System.debug(System.LoggingLevel.FINE, 'Checking message: ' + msg.message);
            if (msg.message.containsIgnoreCase(messagePart)) {
                found = true;
                break;
            }
        }
        Assert.isTrue(found,
            'Expected ' + level + ' message containing: "' + messagePart + '". ' +
            'Found ' + messages.size() + ' ' + level + ' messages.'
        );
    }

    // ============================================================================
    // RESULT ASSERTIONS
    // ============================================================================

    /**
     * Assert that transaction succeeded.
     *
     * @param result The UoWResult to check
     */
    public static void assertSuccess(UoWResult result) {
        Assert.isTrue(result.isSuccess(),
            'Expected transaction to succeed. Status: ' + result.transactionStatus
        );
    }

    /**
     * Assert that transaction failed.
     *
     * @param result The UoWResult to check
     */
    public static void assertFailure(UoWResult result) {
        Assert.isFalse(result.isSuccess(),
            'Expected transaction to fail. Status: ' + result.transactionStatus
        );
    }

    /**
     * Assert specific transaction status.
     *
     * @param result The UoWResult to check
     * @param expectedStatus Expected transaction status
     */
    public static void assertStatus(UoWResult result, UoWEnums.TransactionStatus expectedStatus) {
        Assert.areEqual(expectedStatus, result.transactionStatus,
            'Expected status: ' + expectedStatus + ', got: ' + result.transactionStatus
        );
    }

    public static void assertAllWorkItemSuccessfulExecution(UoWResult result){
        // 1 work item for Account Inserts (as DML work item support consolidation by type and operation)
        assertExecutedDmlWorkItemCount(result, Account.SObjectType, UoWEnums.DmlOperation.INSERT_OP, 1);
        // 1 work item for Contact Inserts (as event work items support consolidation by type and operation)
        assertExecutedDmlWorkItemCount(result, Contact.SObjectType, UoWEnums.DmlOperation.INSERT_OP, 1);
        // 1 work item for Account Upserts (as event work items support consolidation by type and operation)
        assertExecutedDmlWorkItemCount(result, Account.SObjectType, UoWEnums.DmlOperation.UPSERT_OP, 1);
        // 1 work item for Account Updates (as event work items support consolidation by type and operation)
        assertExecutedDmlWorkItemCount(result, Account.SObjectType, UoWEnums.DmlOperation.UPDATE_OP, 1);
        // 1 work item for Account Deletes (as event work items support consolidation by type and operation)
        assertExecutedDmlWorkItemCount(result, Account.SObjectType, UoWEnums.DmlOperation.DELETE_OP, 1);
        // 1 work item for Account Undeletes (as event work items support consolidation by type and operation)
        assertExecutedDmlWorkItemCount(result, Account.SObjectType, UoWEnums.DmlOperation.UNDELETE_OP, 1);

        // 1 work item for Platform Events (as wmail work items support consolidation by type and phase)
        assertExecutedEventWorkItemCount(result, UoWEnums.WorkPhase.POST_DML, 1);
        assertExecutedEventWorkItemCount(result, UoWEnums.WorkPhase.ON_SUCCESS, 1);
        assertExecutedEventWorkItemCount(result, UoWEnums.WorkPhase.ON_FAILURE, 0); // On Failure will not execute
        // 1 work item for Emails (as the work item supports consolidation by phase)
        assertExecutedEmailWorkItemCount(result, UoWEnums.WorkPhase.ON_SUCCESS, 1);
        assertExecutedEmailWorkItemCount(result, UoWEnums.WorkPhase.ON_FAILURE, 0); // On Failure will not execute
        // Multiple work items for Flows (as Flows dont support consolidation)
        assertExecutedFlowWorkItemCount(result, UoWEnums.WorkPhase.POST_DML, DEFAULT_FLOW_COUNT);
        assertExecutedFlowWorkItemCount(result, UoWEnums.WorkPhase.ON_SUCCESS, DEFAULT_FLOW_COUNT);
        assertExecutedFlowWorkItemCount(result, UoWEnums.WorkPhase.ON_FAILURE, 0); // On Failure will not execute
        // Multiple work items for Notifications (as Notifications dont support consolidation)
        assertExecutedNotificationWorkItemCount(result, UoWEnums.WorkPhase.ON_SUCCESS, DEFAULT_NOTIFICATION_COUNT);
        assertExecutedNotificationWorkItemCount(result, UoWEnums.WorkPhase.ON_FAILURE, 0); // On Failure will not execute
        // Multiple work items for Callouts (as Callouts dont support consolidation)
        assertExecutedCalloutWorkItemCount(result, UoWEnums.WorkPhase.PRE_DML, DEFAULT_CALLOUT_COUNT);
        assertExecutedCalloutWorkItemCount(result, UoWEnums.WorkPhase.ON_FAILURE, 0); // On Failure will not execute

        // Assert DML statistics

        //Inserts
        Integer totalInsertDmlCount = DEFAULT_DML_COUNT * 2; // Inserts - Accounts & Contacts
        Assert.areEqual(totalInsertDmlCount, result.statistics.dmlStats.inserts.records.processed, 'Should process ' + totalInsertDmlCount + ' DML inserts');
        Assert.areEqual(totalInsertDmlCount, result.statistics.dmlStats.inserts.records.successes, 'Should have ' + totalInsertDmlCount + ' DML insert successes');
        Assert.areEqual(DEFAULT_DML_COUNT, result.statistics.dmlStats.inserts.byType.get('Account').successes, 'Should have ' + DEFAULT_DML_COUNT + ' DML inserts for Account');
        Assert.areEqual(DEFAULT_DML_COUNT, result.statistics.dmlStats.inserts.byType.get('Contact').successes, 'Should have ' + DEFAULT_DML_COUNT + ' DML inserts for Contact');

        //Upserts
        Integer totalUpsertDmlCount = DEFAULT_DML_COUNT * 2; // Upserts - Accounts - inserts and updates
        Assert.areEqual(totalUpsertDmlCount, result.statistics.dmlStats.upserts.records.processed, 'Should process ' + totalUpsertDmlCount + ' DML upserts');
        Assert.areEqual(totalUpsertDmlCount, result.statistics.dmlStats.upserts.records.successes, 'Should have ' + totalUpsertDmlCount + ' DML upsert successes');
        Assert.areEqual(DEFAULT_DML_COUNT, result.statistics.dmlStats.upserts.records.inserts, 'Should have ' + DEFAULT_DML_COUNT + ' DML insert successes in upsert operation');
        Assert.areEqual(DEFAULT_DML_COUNT, result.statistics.dmlStats.upserts.records.updates, 'Should have ' + DEFAULT_DML_COUNT + ' DML update successes in upsert operation');
        Assert.areEqual(totalUpsertDmlCount, result.statistics.dmlStats.upserts.byType.get('Account').successes, 'Should have ' + totalUpsertDmlCount + ' DML upserts for Account');

        //Updates
        Integer totalUpdateDmlCount = DEFAULT_DML_COUNT; // Updates - Accounts
        Assert.areEqual(totalUpdateDmlCount, result.statistics.dmlStats.updates.records.processed, 'Should process ' + totalUpdateDmlCount + ' DML updates');
        Assert.areEqual(totalUpdateDmlCount, result.statistics.dmlStats.updates.records.successes, 'Should have ' + totalUpdateDmlCount + ' DML update successes');
        Assert.areEqual(DEFAULT_DML_COUNT, result.statistics.dmlStats.updates.byType.get('Account').successes, 'Should have ' + DEFAULT_DML_COUNT + ' DML updates for Account');

        //Deletes
        Integer totalDeleteDmlCount = DEFAULT_DML_COUNT; // Deletes - Accounts
        Assert.areEqual(totalDeleteDmlCount, result.statistics.dmlStats.deletes.records.processed, 'Should process ' + totalDeleteDmlCount + ' DML deletes');
        Assert.areEqual(totalDeleteDmlCount, result.statistics.dmlStats.deletes.records.successes, 'Should have ' + totalDeleteDmlCount + ' DML delete successes');
        Assert.areEqual(DEFAULT_DML_COUNT, result.statistics.dmlStats.deletes.byType.get('Account').successes, 'Should have ' + DEFAULT_DML_COUNT + ' DML deletes for Account');

        //Undeletes
        Integer totalUndeleteDmlCount = DEFAULT_DML_COUNT; // Undeletes - Accounts
        Assert.areEqual(totalUndeleteDmlCount, result.statistics.dmlStats.undeletes.records.processed, 'Should process ' + totalUndeleteDmlCount + ' DML undeletes');
        Assert.areEqual(totalUndeleteDmlCount, result.statistics.dmlStats.undeletes.records.successes, 'Should have ' + totalUndeleteDmlCount + ' DML undelete successes');
        Assert.areEqual(DEFAULT_DML_COUNT, result.statistics.dmlStats.undeletes.byType.get('Account').successes, 'Should have ' + DEFAULT_DML_COUNT + ' DML undeletes for Account');

        //Total DML
        Integer totalDmlCount = totalInsertDmlCount
                               + totalUpsertDmlCount
                               + totalUpdateDmlCount
                               + totalDeleteDmlCount
                               + totalUndeleteDmlCount;
        Assert.areEqual(totalDmlCount, result.statistics.dmlStats.records.processed, 'Should process ' + totalDmlCount + ' DML records');
        Assert.areEqual(totalDmlCount, result.statistics.dmlStats.records.successes, 'Should have ' + totalDmlCount + ' DML successes');

        // Assert event statistics
        Integer totalEventCount = DEFAULT_EVENT_COUNT * 2; // default + success
        Assert.areEqual(totalEventCount, result.statistics.eventStats.events.processed, 'Should process ' + totalEventCount + ' events');
        Assert.areEqual(totalEventCount, result.statistics.eventStats.events.published, 'Should publish ' + totalEventCount + ' events');

        // Assert flow statistics
        Integer totalFlowCount = DEFAULT_FLOW_COUNT * 2; // default + success
        Assert.areEqual(totalFlowCount, result.statistics.flowStats.flows.processed, 'Should process ' + totalFlowCount + ' flows');
        Assert.areEqual(totalFlowCount, result.statistics.flowStats.flows.executed, 'Should execute ' + totalFlowCount + ' flows');

        // Assert email statistics
        Integer totalEmailCount = DEFAULT_EMAIL_COUNT;
        Assert.areEqual(totalEmailCount, result.statistics.emailStats.emails.processed, 'Should process ' + totalEmailCount + ' emails');
        Assert.areEqual(totalEmailCount, result.statistics.emailStats.emails.sent, 'Should send ' + totalEmailCount + ' emails');

        // Assert notification statistics
        Integer totalNotificationCount = DEFAULT_NOTIFICATION_COUNT;
        Assert.areEqual(totalNotificationCount, result.statistics.notificationStats.notifications.processed, 'Should process ' + totalNotificationCount + ' notifications');
        Assert.areEqual(totalNotificationCount, result.statistics.notificationStats.notifications.sent, 'Should send ' + totalNotificationCount + ' notifications');

        // Assert callout statistics
        Integer totalCalloutCount = DEFAULT_CALLOUT_COUNT;
        Assert.areEqual(totalCalloutCount, result.statistics.calloutStats.callouts.processed, 'Should process ' + totalCalloutCount + ' callouts');
        Assert.areEqual(totalCalloutCount, result.statistics.calloutStats.callouts.executed, 'Should execute ' + totalCalloutCount + ' callouts');

        // Assert total statistics via convenience methods
        Integer totalProcessedCount = totalDmlCount // 2 records each for Accounts & Contacts
                                    + totalEventCount
                                    + totalFlowCount
                                    + totalEmailCount
                                    + totalNotificationCount
                                    + totalCalloutCount;

        Assert.areEqual(totalProcessedCount, result.statistics.getTotalProcessed(), 'Should have ' + totalProcessedCount + ' processed items');
        Assert.areEqual(totalProcessedCount, result.statistics.getTotalSucceeded(), 'Should have ' + totalProcessedCount + ' success items');
        Assert.areEqual(0, result.statistics.getTotalFailed(), 'Should have no failures');

        // Verify work item statuses
        Integer skippedWorkItemCount = 0;
        for (UoWWorkItem workItem : result.getAllWorkItems()) {
            UoWEnums.WorkPhase phase = UoWUtils.getWorkItemExecutionPhase(workItem);
            if(phase == UoWEnums.WorkPhase.ON_FAILURE){
                skippedWorkItemCount++;
                Assert.areEqual(UoWEnums.WorkStatus.SKIPPED, workItem.status, 'Work item should have been SKIPPED when registered for On_Failure in a successful transaction');
            } else {
                Assert.areEqual(UoWEnums.WorkStatus.SUCCESS, workItem.status, 'Work item should have SUCCESS status');
            }
        }
        Integer expectedOnFailureCount = 1 + DEFAULT_FLOW_COUNT + 1 + DEFAULT_NOTIFICATION_COUNT + DEFAULT_CALLOUT_COUNT; //Emails and Platform events consolidate into a single work item
        Assert.areEqual(expectedOnFailureCount, skippedWorkItemCount, 'We should have expected ' + expectedOnFailureCount + ' work items that skip execution as thy are registered for ON_FAILURE in a successful transaction');
    }

    // ============================================================================
    // ASYNC HELPERS
    // ============================================================================

    /**
     * Assert that async job was successfully enqueued.
     *
     * @param result The UoWResult to check
     */
    public static void assertAsyncEnqueued(UoWResult result) {
        Assert.areEqual(UoWEnums.CommitMode.ASYNC, result.commitMode,
            'Expected ASYNC commit mode'
        );
        Assert.areEqual(UoWEnums.TransactionStatus.ENQUEUED, result.transactionStatus,
            'Expected ENQUEUED transaction status for async enqueue'
        );
        Assert.isNotNull(result.getMetadata('asyncJobId'),
            'Expected async job ID in result'
        );
    }

    // ============================================================================
    // QUERY HELPERS
    // ============================================================================

    /**
     * Count records matching query criteria.
     *
     * @param objectName SObject API name
     * @param whereClause WHERE clause (without WHERE keyword)
     * @return Number of matching records
     */
    public static Integer countRecords(String objectName, String whereClause) {
        String query = 'SELECT COUNT() FROM ' + objectName;
        if (String.isNotBlank(whereClause)) {
            query += ' WHERE ' + whereClause;
        }
        return Database.countQuery(query);
    }

    /**
     * Assert that specific number of records exist matching criteria.
     *
     * @param objectName SObject API name
     * @param whereClause WHERE clause (without WHERE keyword)
     * @param expectedCount Expected number of records
     */
    public static void assertRecordExists(String objectName, String whereClause, Integer expectedCount) {
        Integer actualCount = countRecords(objectName, whereClause);
        Assert.areEqual(expectedCount, actualCount,
            'Expected ' + expectedCount + ' ' + objectName + ' records matching "' + whereClause + '", found ' + actualCount
        );
    }

    // ============================================================================
    // SOBJECT ASSERTIONS
    // ============================================================================

    /**
     * Assert that SObject has an ID (was inserted/updated).
     *
     * @param record The SObject to check
     */
    public static void assertHasId(SObject record) {
        Assert.isNotNull(record.Id,
            'Expected ' + record.getSObjectType() + ' to have an ID after DML'
        );
    }

    /**
     * Assert that SObject does not have an ID.
     *
     * @param record The SObject to check
     */
    public static void assertNoId(SObject record) {
        Assert.isNull(record.Id,
            'Expected ' + record.getSObjectType() + ' to NOT have an ID'
        );
    }

    /**
     * Assert that relationship was resolved and lookup field populated correctly.
     *
     * @param record The SObject to check
     * @param relationshipField The lookup field to verify
     * @param expectedId Expected parent record ID
     */
    public static void assertRelationshipResolved(SObject record, Schema.SObjectField relationshipField, Id expectedId) {
        Id actualId = (Id) record.get(relationshipField);
        Assert.areEqual(expectedId, actualId,
            'Expected ' + relationshipField + ' to be ' + expectedId + ', got ' + actualId
        );
    }

    // ============================================================================
    // DML WORK ITEM ASSERTIONS
    // ============================================================================

    /**
     * Assert executed DML work item count for specific operation.
     * Only counts work items that were actually executed (isExecuted = true).
     *
     * @param result The UoWResult to check
     * @param sobjectType The SObject type to filter by
     * @param operation The DML operation to filter by
     * @param expectedCount Expected number of executed work items
     */
    public static void assertExecutedDmlWorkItemCount(UoWResult result, Schema.SObjectType sobjectType, UoWEnums.DmlOperation operation, Integer expectedCount) {
        Integer actualCount = 0;
        for (UoWDmlWorkItem workItem : result.getAllDmlWork()) {
            if (workItem.isExecuted && workItem.sobjectType == sobjectType && workItem.operation == operation) {
                actualCount++;
            }
        }
        Assert.areEqual(expectedCount, actualCount, 'Expected ' + expectedCount + ' executed ' + operation + ' work items for ' + sobjectType + ', found ' + actualCount);
    }

    /**
     * Assert record count within a DML work item.
     * Verifies that consolidation properly combined records.
     *
     * @param workItem The DML work item to check
     * @param expectedCount Expected number of records in work item
     */
    public static void assertDmlWorkItemRecordCount(UoWDmlWorkItem workItem, Integer expectedCount) {
        Integer actualCount = workItem.getOriginalRecords()?.size() ?? 0;
        Assert.areEqual(expectedCount, actualCount, 'Expected ' + expectedCount + ' records in work item, found ' + actualCount);
    }

    // ============================================================================
    // EVENT WORK ITEM ASSERTIONS
    // ============================================================================

    /**
     * Assert executed event work item count for specific phase.
     * Only counts work items that were actually executed (isExecuted = true).
     *
     * @param result The UoWResult to check
     * @param phase The execution phase to filter by
     * @param expectedCount Expected number of executed work items
     */
    public static void assertExecutedEventWorkItemCount(UoWResult result, UoWEnums.WorkPhase phase, Integer expectedCount) {
        Integer actualCount = 0;
        for (UoWEventWorkItem workItem : result.getAllEventWork()) {
            if (workItem.isExecuted && workItem.executionPhase == phase) {
                actualCount++;
            }
        }
        Assert.areEqual(expectedCount, actualCount, 'Expected ' + expectedCount + ' executed event work items for ' + phase + ' phase, found ' + actualCount);
    }

    /**
     * Assert event count within an Event work item.
     * Verifies that consolidation properly combined events.
     *
     * @param workItem The event work item to check
     * @param expectedCount Expected number of events in work item
     */
    public static void assertEventWorkItemEventCount(UoWEventWorkItem workItem, Integer expectedCount) {
        Integer actualCount = workItem.getOriginalEvents()?.size() ?? 0;
        Assert.areEqual(expectedCount, actualCount, 'Expected ' + expectedCount + ' events in work item, found ' + actualCount);
    }

    // ============================================================================
    // EMAIL WORK ITEM ASSERTIONS
    // ============================================================================

    /**
     * Assert executed email work item count for specific phase.
     * Only counts work items that were actually executed (isExecuted = true).
     *
     * @param result The UoWResult to check
     * @param phase The execution phase to filter by
     * @param expectedCount Expected number of executed work items
     */
    public static void assertExecutedEmailWorkItemCount(UoWResult result, UoWEnums.WorkPhase phase, Integer expectedCount) {
        Integer actualCount = 0;
        for (UoWEmailWorkItem workItem : result.getAllEmailWork()) {
            if (workItem.isExecuted && workItem.executionPhase == phase) {
                actualCount++;
            }
        }
        Assert.areEqual(expectedCount, actualCount, 'Expected ' + expectedCount + ' executed email work items for ' + phase + ' phase, found ' + actualCount);
    }

    /**
     * Assert email count within an Email work item.
     * Verifies that consolidation properly combined emails.
     *
     * @param workItem The email work item to check
     * @param expectedCount Expected number of emails in work item
     */
    public static void assertEmailWorkItemEmailCount(UoWEmailWorkItem workItem, Integer expectedCount) {
        Integer actualCount = workItem.getEmails()?.size() ?? 0;
        Assert.areEqual(expectedCount, actualCount, 'Expected ' + expectedCount + ' emails in work item, found ' + actualCount);
    }

    // ============================================================================
    // FLOW WORK ITEM ASSERTIONS
    // ============================================================================

    /**
     * Assert executed flow work item count for specific phase.
     * Only counts work items that were actually executed (isExecuted = true).
     *
     * @param result The UoWResult to check
     * @param phase The execution phase to filter by
     * @param expectedCount Expected number of executed work items
     */
    public static void assertExecutedFlowWorkItemCount(UoWResult result, UoWEnums.WorkPhase phase, Integer expectedCount) {
        Integer actualCount = 0;
        for (UoWFlowWorkItem workItem : result.getAllFlowWork()) {
            if (workItem.isExecuted && workItem.executionPhase == phase) {
                actualCount++;
            }
        }
        Assert.areEqual(expectedCount, actualCount, 'Expected ' + expectedCount + ' executed flow work items for ' + phase + ' phase, found ' + actualCount);
    }

    // ============================================================================
    // NOTIFICATION WORK ITEM ASSERTIONS
    // ============================================================================

    /**
     * Assert executed notification work item count for specific phase.
     * Only counts work items that were actually executed (isExecuted = true).
     *
     * @param result The UoWResult to check
     * @param phase The execution phase to filter by
     * @param expectedCount Expected number of executed work items
     */
    public static void assertExecutedNotificationWorkItemCount(UoWResult result, UoWEnums.WorkPhase phase, Integer expectedCount) {
        Integer actualCount = 0;
        for (UoWNotificationWorkItem workItem : result.getAllNotificationWork()) {
            if (workItem.isExecuted && workItem.executionPhase == phase) {
                actualCount++;
            }
        }
        Assert.areEqual(expectedCount, actualCount, 'Expected ' + expectedCount + ' executed notification work items for ' + phase + ' phase, found ' + actualCount);
    }

    // ============================================================================
    // CALLOUT WORK ITEM ASSERTIONS
    // ============================================================================

    /**
     * Assert executed callout work item count.
     * Only counts work items that were actually executed (isExecuted = true).
     *
     * @param result The UoWResult to check
     * @param phase The execution phase to filter by
     * @param expectedCount Expected number of executed callout work items
     */
    public static void assertExecutedCalloutWorkItemCount(UoWResult result, UoWEnums.WorkPhase phase, Integer expectedCount) {
        Integer actualCount = 0;
        for (UoWCalloutWorkItem workItem : result.getAllCalloutWork()) {
            if (workItem.isExecuted && workItem.executionPhase == phase) {
                actualCount++;
            }
        }
        Assert.areEqual(expectedCount, actualCount, 'Expected ' + expectedCount + ' executed callout work items for ' + phase + ' phase, found ' + actualCount);
    }

    // ============================================================================
    // UTILITY METHODS
    // ============================================================================

    /**
     * Print comprehensive context summary with ALL properties for debugging tests.
     * Outputs all context properties including configuration, execution context, user info, and feature settings.
     *
     * @param context The UoWContext to debug
     */
    public static void debugContext(UoWContext context) {
        System.debug('=======================================================');
        System.debug('UOW CONTEXT - COMPREHENSIVE DEBUG OUTPUT');
        System.debug('=======================================================\n');

        // Core identification
        System.debug('--- CORE IDENTIFICATION --------');
        System.debug('transactionId: ' + context.transactionId);
        System.debug('correlationId: ' + context.correlationId);
        System.debug('startedAt: ' + context.startedAt);

        // Configuration
        System.debug('\n-------- CONFIGURATION --------');
        System.debug('configurationName: ' + context.configurationName);
        System.debug('isDryRun: ' + context.isDryRun);

        // Execution context
        System.debug('\n-------- EXECUTION CONTEXT --------');
        System.debug('asyncDepth: ' + context.asyncDepth);
        System.debug('parentTransactionId: ' + context.parentTransactionId);
        System.debug('isAsyncChild: ' + context.isAsyncChild());

        // Session snapshot (captured at transaction creation, persists through async)
        System.debug('\n-------- SESSION SNAPSHOT --------');
        UoWContext.SessionSnapshot snapshot = context.sessionSnapshot;
        if (snapshot != null) {
            System.debug('userId: ' + snapshot.userId);
            System.debug('username: ' + snapshot.username);
            System.debug('userType: ' + snapshot.userType);
            System.debug('profileId: ' + snapshot.profileId);
            System.debug('profileName: ' + snapshot.profileName);
            System.debug('userRoleId: ' + snapshot.userRoleId);
            System.debug('userRoleName: ' + snapshot.userRoleName);
            System.debug('quiddity: ' + snapshot.quiddity);
            System.debug('organizationId: ' + snapshot.organizationId);
            System.debug('organizationName: ' + snapshot.organizationName);
            System.debug('isSandbox: ' + snapshot.isSandbox);
            System.debug('capturedAt: ' + snapshot.capturedAt);
        }

        // Agent context
        if (context.agentContext != null) {
            System.debug('\n-------- AGENT CONTEXT --------');
            System.debug('agentId: ' + context.agentContext.agentId);
            System.debug('agentName: ' + context.agentContext.agentName);
            System.debug('modelId: ' + context.agentContext.modelId);
            System.debug('promptHash: ' + context.agentContext.promptHash);
            System.debug('confidenceScore: ' + context.agentContext.confidenceScore);
            System.debug('intent: ' + context.agentContext.intent);
            System.debug('invokedAt: ' + context.agentContext.invokedAt);
            System.debug('isAgentTransaction: ' + context.isAgentTransaction());
            System.debug('agentConfidence: ' + context.getAgentConfidence());
        }

        // Feature Settings
        if (context.getFeatureSettings() != null) {
            UoWFeatureSettings settings = context.getFeatureSettings();

            System.debug('\n-------- FEATURE SETTINGS: SCALAR VALUES --------');
            System.debug('dmlSecurityMode: ' + settings.getDmlSecurityMode());
            System.debug('enableTracing: ' + settings.getEnableTracing());
            System.debug('enableMasking: ' + settings.getEnableMasking());
            System.debug('minimumLoggingLevel: ' + settings.getMinimumLoggingLevel());
            System.debug('maxAsyncDepth: ' + settings.getMaxAsyncDepth());
            System.debug('confidenceThreshold: ' + settings.getConfidenceThreshold());

            System.debug('\n-------- FEATURE SETTINGS: RISK THRESHOLDS --------');
            System.debug('riskLowThreshold: ' + settings.getRiskLowThreshold());
            System.debug('riskMediumThreshold: ' + settings.getRiskMediumThreshold());
            System.debug('riskHighThreshold: ' + settings.getRiskHighThreshold());
            System.debug('riskCriticalThreshold: ' + settings.getRiskCriticalThreshold());
            System.debug('riskApprovalThreshold: ' + settings.getRiskApprovalThreshold());
            System.debug('riskBlockThreshold: ' + settings.getRiskBlockThreshold());

            System.debug('\n-------- FEATURE SETTINGS: CLASS NAMES (Extensibility) --------');
            System.debug('dmlStrategyClassName: ' + settings.dmlStrategyClassName);
            System.debug('eventChannelClassName: ' + settings.eventChannelClassName);
            System.debug('emailChannelClassName: ' + settings.emailChannelClassName);
            System.debug('notificationChannelClassName: ' + settings.notificationChannelClassName);
            System.debug('flowChannelClassName: ' + settings.flowChannelClassName);
            System.debug('calloutStrategyClassName: ' + settings.calloutStrategyClassName);
            System.debug('riskAssessorClassName: ' + settings.riskAssessorClassName);
            System.debug('approvalChannelClassName: ' + settings.approvalChannelClassName);
            System.debug('transactionFinalizerClassName: ' + settings.transactionFinalizerClassName);

            System.debug('\n-------- FEATURE SETTINGS: RESOLVED INSTANCES --------');
            System.debug('resolvedEventChannel: ' + settings.resolvedEventChannel?.getName());
            System.debug('resolvedEmailChannel: ' + settings.resolvedEmailChannel?.getName());
            System.debug('resolvedNotificationChannel: ' + settings.resolvedNotificationChannel?.getName());
            System.debug('resolvedFlowChannel: ' + settings.resolvedFlowChannel?.getName());
            System.debug('resolvedCalloutStrategy: ' + settings.resolvedCalloutStrategy?.getName());
            System.debug('resolvedRiskAssessor: ' + settings.resolvedRiskAssessor?.getName());
            System.debug('resolvedApprovalChannel: ' + settings.resolvedApprovalChannel?.getName());
            System.debug('resolvedDmlStrategies count: ' + String.valueOf(settings.resolvedDmlStrategies?.size() ?? 0));
            System.debug('resolvedPlugins count: ' + String.valueOf(settings.resolvedPlugins?.size() ?? 0));
            System.debug('resolvedPolicies count: ' + String.valueOf(settings.resolvedPolicies?.size() ?? 0));
        }

        // Messages
        System.debug('\n-------- MESSAGES --------');
        System.debug('messages count: ' + context.getMessages().size());
        for (UoWMessage msg : context.getMessages()) {
            System.debug('  [' + msg.loggingLevel + '] ' + msg.source + ': ' + msg.message);
        }

        System.debug('\n=======================================================');
    }

    /**
     * Print comprehensive result summary with ALL properties for debugging tests.
     * Outputs transaction status, statistics, errors, messages, work items, and tracing details.
     *
     * @param result The UoWResult to debug
     */
    public static void debugResult(UoWResult result) {
        System.debug('=======================================================');
        System.debug('UOW RESULT - COMPREHENSIVE DEBUG OUTPUT');
        System.debug('=======================================================\n');

        // Core identification
        System.debug('-------- CORE IDENTIFICATION --------');
        System.debug('transactionId: ' + result.transactionId);
        System.debug('correlationId: ' + result.correlationId);

        // Transaction status
        System.debug('\n-------- TRANSACTION STATUS --------');
        System.debug('transactionStatus: ' + result.transactionStatus);
        System.debug('isSuccess(): ' + result.isSuccess());
        System.debug('isDryRun: ' + result.isDryRun);
        System.debug('commitMode: ' + result.commitMode);
        System.debug('completedAt: ' + result.completedAt);

        // Statistics
        System.debug('\n-------- STATISTICS --------');
        System.debug('statistics.dmlStats.records.processed: ' + result.statistics.dmlStats.records.processed);
        System.debug('statistics.dmlStats.inserts: ' + result.statistics.dmlStats.inserts);
        System.debug('statistics.dmlStats.upserts: ' + result.statistics.dmlStats.upserts);
        System.debug('statistics.dmlStats.updates: ' + result.statistics.dmlStats.updates);
        System.debug('statistics.dmlStats.deletes: ' + result.statistics.dmlStats.deletes);
        System.debug('statistics.dmlStats.undeletes: ' + result.statistics.dmlStats.undeletes);
        System.debug('statistics.eventStats: ' + result.statistics.eventStats);
        System.debug('statistics.emailStats: : ' + result.statistics.emailStats);
        System.debug('statistics.notificationStats: ' + result.statistics.notificationStats);
        System.debug('statistics.flowStats: ' + result.statistics.flowStats);
        System.debug('statistics.calloutStats: ' + result.statistics.calloutStats);
        System.debug('statistics.executionTimeMs: ' + result.statistics.executionTimeMs);

        // Errors
        System.debug('\n-------- ERRORS --------');
        System.debug('hasErrors(): ' + result.hasErrors());
        System.debug('getErrors().size(): ' + result.getErrors().size());
        for (Integer i = 0; i < result.getErrors().size(); i++) {
            UoWExceptionService.ErrorInfo err = result.getErrors()[i];
            System.debug('  error[' + i + '].errorType: ' + err.errorType);
            System.debug('  error[' + i + '].errorMessage: ' + err.errorMessage);
        }

        // Messages
        System.debug('\n-------- MESSAGES --------');
        System.debug('getMessages().size(): ' + result.getMessages().size());
        System.debug('hasWarnings(): ' + result.hasWarnings());
        if (!result.getMessages().isEmpty()) {
            System.debug('  ERROR messages: ' + result.getMessagesByLevel(System.LoggingLevel.ERROR).size());
            System.debug('  WARNING messages: ' + result.getMessagesByLevel(System.LoggingLevel.WARN).size());
            System.debug('  INFO messages: ' + result.getMessagesByLevel(System.LoggingLevel.INFO).size());
            System.debug('  DEBUG messages: ' + result.getMessagesByLevel(System.LoggingLevel.DEBUG).size());

            for(UoWMessage msg : result.getMessages()) {
                System.debug('  message[' + msg.loggingLevel + ']: ' + msg.message);
            }
        }

        // Approval
        System.debug('\n-------- APPROVAL --------');
        System.debug('requiresApproval: ' + result.requiresApproval);

        // Risk assessment
        System.debug('\n-------- RISK ASSESSMENT --------');
        if (result.riskAssessment != null) {
            System.debug('  riskAssessment.riskScore: ' + result.riskAssessment.riskScore);
            System.debug('  riskAssessment.riskLevel: ' + result.riskAssessment.riskLevel);
            System.debug('  riskAssessment.requiresApproval: ' + result.riskAssessment.requiresApproval);
        }

        // Policy evaluation
        System.debug('\n-------- POLICY EVALUATION --------');
        UoWPolicyEvaluation.Summary policySummary = result.policyEvalSummary;
        if (policySummary != null) {
            System.debug('  policyEvalSummary.isDenied: ' + policySummary.isDenied);
            System.debug('  policyEvalSummary.requiresApproval: ' + policySummary.requiresApproval);
            System.debug('  policyEvalSummary.strictestPolicyAction: ' + policySummary.strictestPolicyAction);
            System.debug('  policyEvalSummary.totalPolicies: ' + policySummary.totalPolicies);
            System.debug('  policyEvalSummary.totalEvaluations: ' + policySummary.totalEvaluations);
            if (!policySummary.denialReasons.isEmpty()) {
                System.debug('  Denial reasons: ' + String.join(policySummary.denialReasons, '; '));
            }
            if (!policySummary.errorMessages.isEmpty()) {
                System.debug('  Error messages: ' + String.join(policySummary.errorMessages, '; '));
            }
        }

        // Work item results
        System.debug('\n-------- WORK ITEMS --------');
        System.debug('getAllDmlWork().size(): ' + result.getAllDmlWork().size());
        for(UoWDmlWorkItem dmlWorkItem : result.getAllDmlWork()){
            System.debug('\n--- ' + dmlWorkItem.operation + ' ---');
            System.debug('dmlWorkItem.status: ' + dmlWorkItem.status);

            // GRANULAR: SaveResults details (for INSERT/UPDATE)
            if (dmlWorkItem.saveResults != null && !dmlWorkItem.saveResults.isEmpty()) {
                System.debug('  saveResults.size(): ' + dmlWorkItem.saveResults.size());
                for (Integer i = 0; i < dmlWorkItem.saveResults.size(); i++) {
                    Database.SaveResult sr = dmlWorkItem.saveResults[i];
                    System.debug('  saveResults[' + i + '].isSuccess(): ' + sr.isSuccess());
                    System.debug('  saveResults[' + i + '].getId(): ' + sr.getId());
                    System.debug('  saveResults[' + i + '].getErrors().size(): ' + String.valueOf(sr.getErrors()?.size() ?? 0));

                    if (!sr.isSuccess() && sr.getErrors() != null) {
                        for (Integer j = 0; j < sr.getErrors().size(); j++) {
                            Database.Error err = sr.getErrors()[j];
                            System.debug('    error[' + j + '].getMessage(): ' + err.getMessage());
                            System.debug('    error[' + j + '].getStatusCode(): ' + err.getStatusCode());
                            System.debug('    error[' + j + '].getFields(): ' + err.getFields());
                        }
                    }
                }
            }

            // GRANULAR: UpsertResults details
            if (dmlWorkItem.upsertResults != null && !dmlWorkItem.upsertResults.isEmpty()) {
                System.debug('  upsertResults.size(): ' + dmlWorkItem.upsertResults.size());
                for (Integer i = 0; i < dmlWorkItem.upsertResults.size(); i++) {
                    Database.UpsertResult ur = dmlWorkItem.upsertResults[i];
                    System.debug('  upsertResults[' + i + '].isSuccess(): ' + ur.isSuccess());
                    System.debug('  upsertResults[' + i + '].isCreated(): ' + ur.isCreated());
                    System.debug('  upsertResults[' + i + '].getErrors().size(): ' + String.valueOf(ur.getErrors()?.size() ?? 0));

                    if (!ur.isSuccess() && ur.getErrors() != null) {
                        for (Integer j = 0; j < ur.getErrors().size(); j++) {
                            Database.Error err = ur.getErrors()[j];
                            System.debug('    error[' + j + '].getMessage(): ' + err.getMessage());
                            System.debug('    error[' + j + '].getStatusCode(): ' + err.getStatusCode());
                            System.debug('    error[' + j + '].getFields(): ' + err.getFields());
                        }
                    }
                }
            }

            // GRANULAR: DeleteResults details
            if (dmlWorkItem.deleteResults != null && !dmlWorkItem.deleteResults.isEmpty()) {
                System.debug('  deleteResults.size(): ' + dmlWorkItem.deleteResults.size());
                for (Integer i = 0; i < dmlWorkItem.deleteResults.size(); i++) {
                    Database.DeleteResult dr = dmlWorkItem.deleteResults[i];
                    System.debug('  deleteResults[' + i + '].isSuccess(): ' + dr.isSuccess());
                    System.debug('  deleteResults[' + i + '].getErrors().size(): ' + String.valueOf(dr.getErrors()?.size() ?? 0));

                    if (!dr.isSuccess() && dr.getErrors() != null) {
                        for (Integer j = 0; j < dr.getErrors().size(); j++) {
                            Database.Error err = dr.getErrors()[j];
                            System.debug('    error[' + j + '].getMessage(): ' + err.getMessage());
                            System.debug('    error[' + j + '].getStatusCode(): ' + err.getStatusCode());
                            System.debug('    error[' + j + '].getFields(): ' + err.getFields());
                        }
                    }
                }
            }

            // GRANULAR: UndeleteResults details
            if (dmlWorkItem.undeleteResults != null && !dmlWorkItem.undeleteResults.isEmpty()) {
                System.debug('  undeleteResults.size(): ' + dmlWorkItem.undeleteResults.size());
                for (Integer i = 0; i < dmlWorkItem.undeleteResults.size(); i++) {
                    Database.UndeleteResult udr = dmlWorkItem.undeleteResults[i];
                    System.debug('  undeleteResults[' + i + '].isSuccess(): ' + udr.isSuccess());
                    System.debug('  undeleteResults[' + i + '].getErrors().size(): ' + String.valueOf(udr.getErrors()?.size() ?? 0));

                    if (!udr.isSuccess() && udr.getErrors() != null) {
                        for (Integer j = 0; j < udr.getErrors().size(); j++) {
                            Database.Error err = udr.getErrors()[j];
                            System.debug('    error[' + j + '].getMessage(): ' + err.getMessage());
                            System.debug('    error[' + j + '].getStatusCode(): ' + err.getStatusCode());
                            System.debug('    error[' + j + '].getFields(): ' + err.getFields());
                        }
                    }
                }
            }
        }

        System.debug('\n-------- PLATFORM EVENTS --------');
        System.debug('getAllEventWork().size(): ' + result.getAllEventWork().size());
        for(UoWEventWorkItem eventWorkItem : result.getAllEventWork()){
            System.debug('eventWorkItem.executionPhase: ' + eventWorkItem.executionPhase);
            System.debug('eventWorkItem.status: ' + eventWorkItem.status);

            // GRANULAR: SaveResults details (for Event Publish)
            System.debug('  publishResults: ' + eventWorkItem.publishResults);
            if (eventWorkItem.publishResults != null && !eventWorkItem.publishResults.isEmpty()) {
                System.debug('  publishResults.size(): ' + eventWorkItem.publishResults.size());
                for (Integer i = 0; i < eventWorkItem.publishResults.size(); i++) {
                    Database.SaveResult sr = eventWorkItem.publishResults[i];
                    System.debug('  publishResults[' + i + '].isSuccess(): ' + sr.isSuccess());
                    System.debug('  publishResults[' + i + '].getId(): ' + sr.getId());
                    System.debug('  publishResults[' + i + '].getErrors().size(): ' + String.valueOf(sr.getErrors()?.size() ?? 0));

                    if (!sr.isSuccess() && sr.getErrors() != null) {
                        for (Integer j = 0; j < sr.getErrors().size(); j++) {
                            Database.Error err = sr.getErrors()[j];
                            System.debug('    error[' + j + '].getMessage(): ' + err.getMessage());
                            System.debug('    error[' + j + '].getStatusCode(): ' + err.getStatusCode());
                            System.debug('    error[' + j + '].getFields(): ' + err.getFields());
                        }
                    }
                }
            }
        }

        System.debug('\n-------- EMAILS --------');
        System.debug('getAllEmailWork().size(): ' + result.getAllEmailWork().size());
        for(UoWEmailWorkItem emailWorkItem : result.getAllEmailWork()){
            System.debug('emailWorkItem.executionPhase: ' + emailWorkItem.executionPhase);
            System.debug('emailWorkItem.status: ' + emailWorkItem.status);

            // GRANULAR: SendResults details
            System.debug('  sendResults: ' + emailWorkItem.sendResults);
            if (emailWorkItem.sendResults != null && !emailWorkItem.sendResults.isEmpty()) {
                System.debug('  sendResults.size(): ' + emailWorkItem.sendResults.size());
                for (Integer i = 0; i < emailWorkItem.sendResults.size(); i++) {
                    Messaging.SendEmailResult sr = emailWorkItem.sendResults[i];
                    System.debug('  sendResults[' + i + '].isSuccess(): ' + sr.isSuccess());
                    System.debug('  sendResults[' + i + '].getErrors(): ' + sr.getErrors());
                    System.debug('  sendResults[' + i + '].getErrors().size(): ' + String.valueOf(sr.getErrors()?.size() ?? 0));

                    // If there are errors, show details
                    if (sr.getErrors() != null && !sr.getErrors().isEmpty()) {
                        for (Integer j = 0; j < sr.getErrors().size(); j++) {
                            Messaging.SendEmailError err = sr.getErrors()[j];
                            System.debug('    error[' + j + '].getMessage(): ' + err.getMessage());
                            System.debug('    error[' + j + '].getStatusCode(): ' + err.getStatusCode());
                            System.debug('    error[' + j + '].getFields(): ' + err.getFields());
                            System.debug('    error[' + j + '].getTargetObjectId(): ' + err.getTargetObjectId());
                        }
                    }
                }
            }
        }

        System.debug('\n-------- NOTIFICATIONS --------');
        System.debug('getAllNotificationWork().size(): ' + result.getAllNotificationWork().size());
        for(UoWNotificationWorkItem notificationWorkItem : result.getAllNotificationWork()){
            System.debug('notificationWorkItem.executionPhase: ' + notificationWorkItem.executionPhase);
            System.debug('notificationWorkItem.status: ' + notificationWorkItem.status);
        }

        System.debug('\n-------- FLOWS --------');
        System.debug('getAllFlowWork().size(): ' + result.getAllFlowWork().size());
        for(UoWFlowWorkItem flowWorkItem : result.getAllFlowWork()){
            System.debug('flowWorkItem.executionPhase: ' + flowWorkItem.executionPhase);
            System.debug('flowWorkItem.status: ' + flowWorkItem.status);
        }

        System.debug('\n-------- CALLOUTS --------');
        System.debug('getAllCalloutWork().size(): ' + result.getAllCalloutWork().size());
        for(UoWCalloutWorkItem calloutWorkItem : result.getAllCalloutWork()){
            System.debug('calloutWorkItem.executionPhase: ' + calloutWorkItem.executionPhase);
            System.debug('calloutWorkItem.endpoint: ' + calloutWorkItem.endpoint);
            System.debug('calloutWorkItem.httpMethod: ' + calloutWorkItem.httpMethod);
            System.debug('calloutWorkItem.status: ' + calloutWorkItem.status);
            System.debug('calloutWorkItem.isExecuted: ' + calloutWorkItem.isExecuted);
            if (calloutWorkItem.response != null) {
                System.debug('calloutWorkItem.response.statusCode: ' + calloutWorkItem.response.getStatusCode());
            }
        }

        // Metadata
        System.debug('\n-------- METADATA --------');
        Map<String, Object> metadata = result.getMetadata();
        System.debug('metadata.size(): ' + metadata.size());
        for (String key : metadata.keySet()) {
            System.debug(key + ': ' + metadata.get(key));
        }

        // Tracing
        System.debug('\n-------- TRACING --------');
        if (result.tracer != null) {
            UoWTracer.TraceSummary traceSummary = result.getTraceSummary();
            if (traceSummary != null) {
                System.debug('Profiling enabled: true');
                System.debug('getSpansJson(): ' + result.getSpansJson());
                System.debug('getEventsJson(): ' + result.getEventsJson());
            }
        } else {
            System.debug('Tracing enabled: false');
        }

        // Context reference
        System.debug('\n-------- CONTEXT --------');
        UoWContext ctx = result.getContext();
        if (ctx != null) {
            System.debug('getContext().transactionId: ' + ctx.transactionId);
            System.debug('getContext().isDryRun: ' + ctx.isDryRun);

            UoWSessionContext session = ctx.getSessionContext();
            if (session != null) {
                System.debug('getSessionContext().quiddity: ' + session.quiddity);
                System.debug('getSessionContext().userId: ' + session.userId);
            }
        }

        System.debug('=======================================================');
        System.debug('END OF RESULT DEBUG OUTPUT');
        System.debug('=======================================================');
    }

    // ============================================================================
    // INNER CLASSES
    // ============================================================================

    public class TestUoWOptions {
        public boolean registerInserts = false;
        public boolean registerUpserts = false;
        public boolean registerUpdates = false;
        public boolean registerDeletes = false;
        public boolean registerUndeletes = false;
        public Boolean registerEvents = false;
        public Boolean registerFlows = false;
        public Boolean registerEmails = false;
        public Boolean registerNotifications = false;
        public Boolean registerCallouts = false;

        public Boolean continueOnError = false;

        public TestUoWOptions(Boolean includeAll) {
            if (includeAll) {
                this.registerInserts = true;
                this.registerUpserts = true;
                this.registerUpdates = true;
                this.registerDeletes = true;
                this.registerUndeletes = true;
                this.registerEvents = true;
                this.registerFlows = true;
                this.registerEmails = true;
                this.registerNotifications = true;
                this.registerCallouts = true;
            }

            this.continueOnError = false;
        }

        public TestUoWOptions(Boolean includeAll, Boolean continueOnError) {
            this(includeAll);
            this.continueOnError = continueOnError;
        }
    }
}