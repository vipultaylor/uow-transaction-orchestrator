//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Tests for extensibility patterns in UoW framework.
 * Covers all extension points: policies (multi-instance), plugins (multi-instance),
 * DML strategies (per-key), channel resolvers (3-tier resolution), risk assessor,
 * base classes, critical behavior, and policy evaluation summary.
 *
 * Channel Resolvers Tested:
 * - Event, Flow, Email, Notification, Callout (3-tier: runtime → config → default)
 * - Masking, Approval, Async Error Sink, Event Publish Failure Handler (2-tier: runtime → config, optional)
 * - Risk Assessor (2-tier: runtime → config)
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Tests
 * @see UoWPolicyRegistry
 * @see UoWPluginRegistry
 * @see UoWDmlStrategyRegistry
 */
@isTest
@SuppressWarnings('PMD.MethodNamingConventions')
private class UoWCoreExtensibilityTests {

    // ============================================================================
    // TEST SETUP
    // ============================================================================

    @TestSetup
    static void setupTestData() {
        // Load test configurations
        UoWTestHelpers.loadTestConfigurations();
    }

    // Reset registries before each test for isolation
    private static void resetRegistries() {
        // Disable auto-initialization to prevent metadata loading
        UoWPluginRegistry.disableAutoInit = true;
        UoWPolicyRegistry.disableAutoInit = true;

        UoWPluginRegistry.getInstance().clearAll();
        UoWPolicyRegistry.getInstance().clearAll();
        UoWChaosEngine.reset();
    }

    // ============================================================================
    // DML STRATEGY REGISTRY TESTS
    // ============================================================================

    @isTest
    static void test_dmlStrategyRegistry_runtimeOverride_success() {
        // Arrange
        UoWTestMocks.MockDmlStrategy mockStrategy = new UoWTestMocks.MockDmlStrategy('RuntimeMockDmlStrategy');

        // Arrange - Create unit of work with no risk assessor configured
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigMinimal')
            .withDmlStrategy(Account.SObjectType, mockStrategy);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IDmlStrategy resolved = UoWDmlStrategyRegistry.getInstance().resolveForSObjectType(Account.SObjectType, uow.getContext(), result);
        Test.stopTest();

        // Assert - Runtime override takes priority
        Assert.isNotNull(resolved, 'Should return a non-null strategy instance');
        Assert.areEqual('RuntimeMockDmlStrategy', resolved.getName(), 'Should resolve to runtime override strategy');
    }

    @isTest
    static void test_dmlStrategyRegistry_multipleStrategies_perObjectType() {
        // Arrange - Different strategies for different objects
        UoWTestMocks.MockDmlStrategy accountStrategy = new UoWTestMocks.MockDmlStrategy('AccountDmlStrategy');
        UoWTestMocks.MockDmlStrategy contactStrategy = new UoWTestMocks.MockDmlStrategy('ContactDmlStrategy');

        //Generate Uow for Dml Inserts only - Accounts & Contacts
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigMinimal')
            .withDmlStrategy(Account.SObjectType, accountStrategy)
            .withDmlStrategy(Contact.SObjectType, contactStrategy);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IDmlStrategy resolvedAccountStrategy = UoWDmlStrategyRegistry.getInstance().resolveForSObjectType(Account.SObjectType, uow.getContext(), result);
        UoWInterfaces.IDmlStrategy resolvedContactStrategy = UoWDmlStrategyRegistry.getInstance().resolveForSObjectType(Contact.SObjectType, uow.getContext(), result);
        Test.stopTest();

        // Assert - Each strategy used for its object type (verified via statistics)
        UoWTestHelpers.assertSuccess(result);
        Integer dmlCount = UoWTestHelpers.DEFAULT_DML_COUNT * 2; // Accounts & Contacts
        Assert.areEqual(dmlCount, result.statistics.dmlStats.inserts.records.successes, 'Should have ' + dmlCount + ' successful inserts');

        Assert.areEqual('AccountDmlStrategy', resolvedAccountStrategy.getName(), 'Should resolve to correct runtime override strategy for Account SObjectType');
        Assert.areEqual('ContactDmlStrategy', resolvedContactStrategy.getName(), 'Should resolve to correct runtime override strategy for Contact SObjectType');
    }

    @isTest
    static void test_dmlStrategyRegistry_emptyClassName_fallsBackToDefault() {
        // Arrange - No runtime override
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigMinimal');

        //Assert that the class name is not set in the config
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigMinimal');
        Assert.isNull(config.DmlStrategyClassName__c, 'DML Strategy Class Name should not be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IDmlStrategy resolved = UoWDmlStrategyRegistry.getInstance().resolveForSObjectType(Account.SObjectType, uow.getContext(), result);
        Test.stopTest();

        // Assert - Should fall back to default
        Assert.isNotNull(resolved, 'Should return default strategy');
        // UoWBaseDmlStrategy is the default, its getName() returns 'Default DML Strategy'
        Assert.areEqual('Default DML Strategy', resolved.getName(), 'Default strategy should have been returned when no strategy class name is provided');
    }

    @isTest
    static void test_dmlStrategyRegistry_invalidClassName_fallsBackToDefault() {
        // Arrange - TestConfigInvalidClasses has invalid DML strategy class name
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidClasses');

        //Assert that the class name is not set in the config
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigInvalidClasses');
        Assert.areEqual('NonExistentDmlStrategy', config.DmlStrategyClassName__c, 'An invalid DML Strategy Class Name should be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IDmlStrategy resolved = UoWDmlStrategyRegistry.getInstance().resolveForSObjectType(Account.SObjectType, uow.getContext(), result);
        Test.stopTest();

        // Assert - Should fall back to default
        Assert.isNotNull(resolved, 'Should return default strategy');
        // UoWBaseDmlStrategy is the default, its getName() returns 'Default DML Strategy'
        Assert.areEqual('Default DML Strategy', resolved.getName(), 'Default strategy should have been returned when no strategy class name is provided');
    }

    @isTest
    static void test_dmlStrategyRegistry_wrongInterface_fallsBackToDefault() {
        // Arrange - TestConfigInvalidClasses has invalid DML strategy class name
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidInterfaces');

        //Assert that the class name is not set in the config
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigInvalidInterfaces');
        Assert.areEqual('UoWTestMocks.WrongInterfaceStub', config.DmlStrategyClassName__c, 'A valid class but one that does not implement the correct interface should be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IDmlStrategy resolved = UoWDmlStrategyRegistry.getInstance().resolveForSObjectType(Account.SObjectType, uow.getContext(), result);
        Test.stopTest();

        // Assert - Should fall back to default
        Assert.isNotNull(resolved, 'Should return default strategy');
        // UoWBaseDmlStrategy is the default, its getName() returns 'Default DML Strategy'
        Assert.areEqual('Default DML Strategy', resolved.getName(), 'Default strategy should have been returned when no strategy class name is provided');
    }

    // ============================================================================
    // EVENT CHANNEL RESOLVER TESTS
    // ============================================================================

    @isTest
    static void test_eventChannelResolver_runtimeOverride_success() {
        // Arrange
        UoWTestMocks.MockEventChannel mockRuntimeChannel = new UoWTestMocks.MockEventChannel('RuntimeMockEventChannel');

        // Arrange - Create unit of work with no risk assessor configured
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigMinimal')
            .withEventChannel(mockRuntimeChannel);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IEventChannel resolved = UoWEventChannelResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Runtime override takes priority
        Assert.isNotNull(resolved, 'Should return a non-null channel instance');
        Assert.areEqual('RuntimeMockEventChannel', resolved.getName(), 'Should resolve to runtime override channel');
    }

    @isTest
    static void test_eventChannelResolver_emptyClassName_fallsBackToDefault() {
        // Arrange - No runtime override
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigMinimal');

        //Assert that the class name is not set in the config
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigMinimal');
        Assert.isNull(config.EventChannelClassName__c, 'Event Channel Class Name should not be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IEventChannel resolved = UoWEventChannelResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should fall back to default
        Assert.isNotNull(resolved, 'Should return default channel');
        // UoWDefaultPlatformEventChannel is the default, its getName() returns 'Default Platform Event Bus'
        Assert.areEqual('Default Platform Event Bus', resolved.getName(), 'Default channel should have been returned when no channel class name is provided');
    }

    @isTest
    static void test_eventChannelResolver_invalidClassName_fallsBackToDefault() {
        // Arrange - TestConfigInvalidClasses has invalid DML strategy class name
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidClasses');

        //Assert that the class name is not set in the config
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigInvalidClasses');
        Assert.areEqual('NonExistentEventChannel', config.EventChannelClassName__c, 'An invalid DML Strategy Class Name should be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IEventChannel resolved = UoWEventChannelResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should fall back to default
        Assert.isNotNull(resolved, 'Should return default channel');
        // UoWDefaultPlatformEventChannel is the default, its getName() returns 'Default Platform Event Bus'
        Assert.areEqual('Default Platform Event Bus', resolved.getName(), 'Default channel should have been returned when no channel class name is provided');
    }

    @isTest
    static void test_eventChannelResolver_wrongInterface_fallsBackToDefault() {
        // Arrange - TestConfigInvalidClasses has invalid DML strategy class name
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidInterfaces');

        //Assert that the class name is not set in the config
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigInvalidInterfaces');
        Assert.areEqual('UoWTestMocks.WrongInterfaceStub', config.EventChannelClassName__c, 'A valid class but one that does not implement the correct interface should be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IEventChannel resolved = UoWEventChannelResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should fall back to default
        Assert.isNotNull(resolved, 'Should return default channel');
        // UoWDefaultPlatformEventChannel is the default, its getName() returns 'Default Platform Event Bus'
        Assert.areEqual('Default Platform Event Bus', resolved.getName(), 'Default channel should have been returned when no channel class name is provided');
    }

    // ============================================================================
    // EMAIL CHANNEL RESOLVER TESTS
    // ============================================================================

    @isTest
    static void test_emailChannelResolver_runtimeOverride_success() {
        // Arrange
        UoWTestMocks.MockEmailChannel mockRuntimeChannel = new UoWTestMocks.MockEmailChannel('RuntimeMockEmailChannel');

        // Arrange - Create unit of work with runtime override
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigMinimal')
            .withEmailChannel(mockRuntimeChannel);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IEmailChannel resolved = UoWEmailChannelResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Runtime override takes priority
        Assert.isNotNull(resolved, 'Should return a non-null channel instance');
        Assert.areEqual('RuntimeMockEmailChannel', resolved.getName(), 'Should resolve to runtime override channel');
    }

    @isTest
    static void test_emailChannelResolver_emptyClassName_fallsBackToDefault() {
        // Arrange - No runtime override
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigMinimal');

        //Assert that the class name is not set in the config
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigMinimal');
        Assert.isNull(config.EmailChannelClassName__c, 'Email Channel Class Name should not be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IEmailChannel resolved = UoWEmailChannelResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should fall back to default
        Assert.isNotNull(resolved, 'Should return default channel');
        // UoWDefaultEmailChannel is the default, its getName() returns 'Default Salesforce Email Service'
        Assert.areEqual('Default Salesforce Email Service', resolved.getName(), 'Default channel should have been returned when no channel class name is provided');
    }

    @isTest
    static void test_emailChannelResolver_invalidClassName_fallsBackToDefault() {
        // Arrange - TestConfigInvalidClasses has invalid email channel class name
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidClasses');

        //Assert that the class name is set to an invalid value
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigInvalidClasses');
        Assert.areEqual('NonExistentEmailChannel', config.EmailChannelClassName__c, 'An invalid Email Channel Class Name should be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IEmailChannel resolved = UoWEmailChannelResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should fall back to default
        Assert.isNotNull(resolved, 'Should return default channel');
        // UoWDefaultEmailChannel is the default, its getName() returns 'Default Salesforce Email Service'
        Assert.areEqual('Default Salesforce Email Service', resolved.getName(), 'Default channel should have been returned when invalid class name is provided');
    }

    @isTest
    static void test_emailChannelResolver_wrongInterface_fallsBackToDefault() {
        // Arrange - TestConfigInvalidInterfaces has valid class but wrong interface
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidInterfaces');

        //Assert that the class name is set to a valid class that doesn't implement the interface
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigInvalidInterfaces');
        Assert.areEqual('UoWTestMocks.WrongInterfaceStub', config.EmailChannelClassName__c, 'A valid class but one that does not implement the correct interface should be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IEmailChannel resolved = UoWEmailChannelResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should fall back to default
        Assert.isNotNull(resolved, 'Should return default channel');
        // UoWDefaultEmailChannel is the default, its getName() returns 'Default Salesforce Email Service'
        Assert.areEqual('Default Salesforce Email Service', resolved.getName(), 'Default channel should have been returned when class does not implement correct interface');
    }

    // ============================================================================
    // NOTIFICATION CHANNEL RESOLVER TESTS
    // ============================================================================

    @isTest
    static void test_notificationChannelResolver_runtimeOverride_success() {
        // Arrange
        UoWTestMocks.MockNotificationChannel mockRuntimeChannel = new UoWTestMocks.MockNotificationChannel('RuntimeMockNotificationChannel');

        // Arrange - Create unit of work with runtime override
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigMinimal')
            .withNotificationChannel(mockRuntimeChannel);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.INotificationChannel resolved = UoWNotificationChannelResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Runtime override takes priority
        Assert.isNotNull(resolved, 'Should return a non-null channel instance');
        Assert.areEqual('RuntimeMockNotificationChannel', resolved.getName(), 'Should resolve to runtime override channel');
    }

    @isTest
    static void test_notificationChannelResolver_emptyClassName_fallsBackToDefault() {
        // Arrange - No runtime override
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigMinimal');

        //Assert that the class name is not set in the config
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigMinimal');
        Assert.isNull(config.NotificationChannelClassName__c, 'Notification Channel Class Name should not be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.INotificationChannel resolved = UoWNotificationChannelResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should fall back to default
        Assert.isNotNull(resolved, 'Should return default channel');
        // UoWDefaultNotificationChannel is the default, its getName() returns 'Default Custom Notifications'
        Assert.areEqual('Default Custom Notifications', resolved.getName(), 'Default channel should have been returned when no channel class name is provided');
    }

    @isTest
    static void test_notificationChannelResolver_invalidClassName_fallsBackToDefault() {
        // Arrange - TestConfigInvalidClasses has invalid notification channel class name
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidClasses');

        //Assert that the class name is set to an invalid value
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigInvalidClasses');
        Assert.areEqual('NonExistentNotificationChannel', config.NotificationChannelClassName__c, 'An invalid Notification Channel Class Name should be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.INotificationChannel resolved = UoWNotificationChannelResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should fall back to default
        Assert.isNotNull(resolved, 'Should return default channel');
        // UoWDefaultNotificationChannel is the default, its getName() returns 'Default Custom Notifications'
        Assert.areEqual('Default Custom Notifications', resolved.getName(), 'Default channel should have been returned when invalid class name is provided');
    }

    @isTest
    static void test_notificationChannelResolver_wrongInterface_fallsBackToDefault() {
        // Arrange - TestConfigInvalidInterfaces has valid class but wrong interface
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidInterfaces');

        //Assert that the class name is set to a valid class that doesn't implement the interface
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigInvalidInterfaces');
        Assert.areEqual('UoWTestMocks.WrongInterfaceStub', config.NotificationChannelClassName__c, 'A valid class but one that does not implement the correct interface should be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.INotificationChannel resolved = UoWNotificationChannelResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should fall back to default
        Assert.isNotNull(resolved, 'Should return default channel');
        // UoWDefaultNotificationChannel is the default, its getName() returns 'Default Custom Notifications'
        Assert.areEqual('Default Custom Notifications', resolved.getName(), 'Default channel should have been returned when class does not implement correct interface');
    }

    // ============================================================================
    // FLOW CHANNEL RESOLVER TESTS
    // ============================================================================

    @isTest
    static void test_flowChannelResolver_runtimeOverride_success() {
        // Arrange
        UoWTestMocks.MockFlowChannel mockRuntimeChannel = new UoWTestMocks.MockFlowChannel('RuntimeMockFlowChannel');

        // Arrange - Create unit of work with runtime override
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigMinimal')
            .withFlowChannel(mockRuntimeChannel);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IFlowChannel resolved = UoWFlowChannelResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Runtime override takes priority
        Assert.isNotNull(resolved, 'Should return a non-null channel instance');
        Assert.areEqual('RuntimeMockFlowChannel', resolved.getName(), 'Should resolve to runtime override channel');
    }

    @isTest
    static void test_flowChannelResolver_emptyClassName_fallsBackToDefault() {
        // Arrange - No runtime override
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigMinimal');

        //Assert that the class name is not set in the config
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigMinimal');
        Assert.isNull(config.FlowChannelClassName__c, 'Flow Channel Class Name should not be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IFlowChannel resolved = UoWFlowChannelResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should fall back to default
        Assert.isNotNull(resolved, 'Should return default channel');
        // UoWDefaultFlowChannel is the default, its getName() returns 'Default Salesforce Flow Engine'
        Assert.areEqual('Default Salesforce Flow Engine', resolved.getName(), 'Default channel should have been returned when no channel class name is provided');
    }

    @isTest
    static void test_flowChannelResolver_invalidClassName_fallsBackToDefault() {
        // Arrange - TestConfigInvalidClasses has invalid flow channel class name
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidClasses');

        //Assert that the class name is set to an invalid value
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigInvalidClasses');
        Assert.areEqual('NonExistentFlowChannel', config.FlowChannelClassName__c, 'An invalid Flow Channel Class Name should be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IFlowChannel resolved = UoWFlowChannelResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should fall back to default
        Assert.isNotNull(resolved, 'Should return default channel');
        // UoWDefaultFlowChannel is the default, its getName() returns 'Default Salesforce Flow Engine'
        Assert.areEqual('Default Salesforce Flow Engine', resolved.getName(), 'Default channel should have been returned when invalid class name is provided');
    }

    @isTest
    static void test_flowChannelResolver_wrongInterface_fallsBackToDefault() {
        // Arrange - TestConfigInvalidInterfaces has valid class but wrong interface
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidInterfaces');

        //Assert that the class name is set to a valid class that doesn't implement the interface
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigInvalidInterfaces');
        Assert.areEqual('UoWTestMocks.WrongInterfaceStub', config.FlowChannelClassName__c, 'A valid class but one that does not implement the correct interface should be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IFlowChannel resolved = UoWFlowChannelResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should fall back to default
        Assert.isNotNull(resolved, 'Should return default channel');
        // UoWDefaultFlowChannel is the default, its getName() returns 'Default Salesforce Flow Engine'
        Assert.areEqual('Default Salesforce Flow Engine', resolved.getName(), 'Default channel should have been returned when class does not implement correct interface');
    }

    // ============================================================================
    // CALLOUT STRATEGY RESOLVER TESTS
    // ============================================================================

    @isTest
    static void test_calloutStrategyResolver_runtimeOverride_success() {
        // Arrange
        UoWTestMocks.MockCalloutStrategy mockRuntimeStrategy = new UoWTestMocks.MockCalloutStrategy('RuntimeMockCalloutStrategy');

        // Arrange - Create unit of work with no risk assessor configured
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigMinimal')
            .withCalloutStrategy(mockRuntimeStrategy);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.ICalloutStrategy resolved = UoWCalloutStrategyResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Runtime override takes priority
        Assert.isNotNull(resolved, 'Should return a non-null strategy instance');
        Assert.areEqual('RuntimeMockCalloutStrategy', resolved.getName(), 'Should resolve to runtime override strategy');
    }

    @isTest
    static void test_calloutStrategyResolver_emptyClassName_fallsBackToDefault() {
        // Arrange - No runtime override
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigMinimal');

        //Assert that the class name is not set in the config
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigMinimal');
        Assert.isNull(config.CalloutStrategyClassName__c, 'Callout Strategy Class Name should not be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.ICalloutStrategy resolved = UoWCalloutStrategyResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should fall back to default
        Assert.isNotNull(resolved, 'Should return default strategy');
        // UoWBaseCalloutStrategy is the default, its getName() returns 'Default Callout Strategy'
        Assert.areEqual('Default Callout Strategy', resolved.getName(), 'Default strategy should have been returned when no strategy class name is provided');
    }

    @isTest
    static void test_calloutStrategyResolver_invalidClassName_fallsBackToDefault() {
        // Arrange - TestConfigInvalidClasses has invalid DML strategy class name
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidClasses');

        //Assert that the class name is not set in the config
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigInvalidClasses');
        Assert.areEqual('NonExistentCalloutStrategy', config.CalloutStrategyClassName__c, 'An invalid Callout Strategy Class Name should be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.ICalloutStrategy resolved = UoWCalloutStrategyResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should fall back to default
        Assert.isNotNull(resolved, 'Should return default strategy');
        // UoWBaseCalloutStrategy is the default, its getName() returns 'Default Callout Strategy'
        Assert.areEqual('Default Callout Strategy', resolved.getName(), 'Default strategy should have been returned when no strategy class name is provided');
    }

    @isTest
    static void test_calloutStrategyResolver_wrongInterface_fallsBackToDefault() {
        // Arrange - TestConfigInvalidClasses has invalid DML strategy class name
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidInterfaces');

        //Assert that the class name is not set in the config
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigInvalidInterfaces');
        Assert.areEqual('UoWTestMocks.WrongInterfaceStub', config.CalloutStrategyClassName__c, 'A valid class but one that does not implement the correct interface should be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.ICalloutStrategy resolved = UoWCalloutStrategyResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should fall back to default
        Assert.isNotNull(resolved, 'Should return default strategy');
        // UoWBaseCalloutStrategy is the default, its getName() returns 'Default Callout Strategy'
        Assert.areEqual('Default Callout Strategy', resolved.getName(), 'Default strategy should have been returned when no strategy class name is provided');
    }

    // ============================================================================
    // PLUGIN TESTS - LIFECYCLE HOOKS
    // ============================================================================

    @isTest
    static void test_plugin_lifecycle_executes() {
        // Arrange
        resetRegistries();
        UoWTestMocks.MockPlugin mockPlugin = new UoWTestMocks.MockPlugin('TestPlugin');

        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks')
            .withPlugin(mockPlugin);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertSuccess(result);
        Integer dmlCount = UoWTestHelpers.DEFAULT_DML_COUNT * 2; // Accounts & Contacts
        Assert.areEqual(dmlCount, result.statistics.dmlStats.records.processed, 'Should process ' + dmlCount + ' total record');
        Assert.areEqual(dmlCount, result.statistics.dmlStats.records.successes, 'Should have ' + dmlCount + ' total success');

        // Crude Assert to check a plugin executed
        UoWTestHelpers.assertResultHasMessage(result, System.LoggingLevel.INFO, 'TestPlugin onBeforeCommit executed');
        UoWTestHelpers.assertResultHasMessage(result, System.LoggingLevel.INFO, 'TestPlugin onAfterCommit executed');
        UoWTestHelpers.assertResultHasMessage(result, System.LoggingLevel.INFO, 'TestPlugin onFinally executed');
    }

    @isTest
    static void test_plugin_lifecycle_onError_executesOnFailure() {
        // Arrange
        resetRegistries();
        UoWTestMocks.MockPlugin mockPlugin = new UoWTestMocks.MockPlugin('ErrorPlugin');

        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks')
            .withPlugin(mockPlugin);

        // Configure ChaosEngine to throw exception
        UoWChaosEngine.enable();
        UoWChaosEngine.alwaysFail(
            UoWChaosEngine.Point.DML_INSERT,
            UoWChaosEngine.sampleInsertDmlException()
        );

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        Integer dmlCount = UoWTestHelpers.DEFAULT_DML_COUNT * 2;
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.ROLLED_BACK);
        Assert.areEqual(0, result.statistics.dmlStats.records.successes, 'Should have no successes');
        UoWTestHelpers.assertResultHasMessage(result, System.LoggingLevel.INFO, 'ErrorPlugin onError executed');
    }

    @isTest
    static void test_plugin_withoutPlugin_disablesPlugin() {
        // Arrange
        resetRegistries();

        // Register plugin in registry
        UoWTestMocks.MockPlugin disabledPlugin = new UoWTestMocks.MockPlugin('DisabledPlugin');
        UoWTestMocks.MockPlugin enabledPlugin = new UoWTestMocks.MockPlugin('EnabledPlugin');

        // Create UoW that disables the plugin
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks')
            .withPlugin(enabledPlugin)
            .withoutPlugin('DisabledPlugin');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertSuccess(result);

        // Plugin should NOT have executed because it was disabled - check via result messages
        Boolean hasDisabledPluginMessage = false;
        Boolean hasEnabledPluginMessage = false;

        for (UoWMessage msg : result.getMessages()) {
            if (msg.message.contains('DisabledPlugin onBeforeCommit executed')) {
                hasDisabledPluginMessage = true;
            }
            if (msg.message.contains('EnabledPlugin onBeforeCommit executed')) {
                hasEnabledPluginMessage = true;
            }
        }

        Assert.isFalse(hasDisabledPluginMessage, 'Disabled plugin should not execute');
        Assert.isTrue(hasEnabledPluginMessage, 'Enabled plugin should still execute');
    }

    @isTest
    static void test_plugin_critical_failure_rollsBackTransaction() {
        // Arrange
        resetRegistries();

        UoWTestMocks.MockPlugin criticalPlugin = new UoWTestMocks.MockPlugin('CriticalPlugin');
        criticalPlugin.isCriticalPlugin = true;
        criticalPlugin.shouldFailOnBeforeCommit = true;
        criticalPlugin.failureMessage = 'Critical validation failed';

        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks')
            .withPlugin(criticalPlugin);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertFailure(result);
        // Critical plugin failures result in FAILED status (plugin execution happens before savepoint)
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.FAILED);

        // Verify error contains critical plugin failure
        UoWTestHelpers.assertResultHasMessage(result, System.LoggingLevel.ERROR, 'CRITICAL PLUGIN FAILURE');
    }

    @isTest
    static void test_plugin_nonCritical_failure_continuesTransaction() {
        // Arrange
        resetRegistries();

        UoWTestMocks.MockPlugin nonCriticalPlugin = new UoWTestMocks.MockPlugin('NonCriticalPlugin');
        nonCriticalPlugin.isCriticalPlugin = false;
        nonCriticalPlugin.shouldFailOnBeforeCommit = true;
        nonCriticalPlugin.failureMessage = 'Non-critical warning';

        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks')
            .withPlugin(nonCriticalPlugin);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertSuccess(result);
        Integer dmlCount = UoWTestHelpers.DEFAULT_DML_COUNT * 2; // Accounts & Contacts
        Assert.areEqual(dmlCount, result.statistics.dmlStats.records.processed, 'Should process ' + dmlCount + ' total record');
        Assert.areEqual(dmlCount, result.statistics.dmlStats.records.successes, 'Should have ' + dmlCount + ' total success');
        UoWTestHelpers.assertResultHasMessage(result, System.LoggingLevel.WARN, 'NonCriticalPlugin');
    }

    @isTest
    static void test_plugin_invalidClassName_skips() {
        // Arrange - TestConfigInvalidClasses has invalid DML strategy class name
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidClasses');

        //Assert that the class name is set to an invalid value
        Boolean invalidClassNameFound = false;
        for(UoWPluginSetting__mdt setting : UoWConfigurationLoader.getInstance().getPluginSettings('TestConfigInvalidClasses')) {
            if(setting.PluginClassName__c == 'NonExistentPlugin') {
                invalidClassNameFound = true;
            }
        }
        Assert.isTrue(invalidClassNameFound, 'An invalid Plugin Class Name should be set in plugin settings configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        List<UoWInterfaces.IPlugin> enabledPlugins = UoWPluginRegistry.getInstance().getEnabledPlugins(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should not have any enabled plugins
        Assert.areEqual(0, enabledPlugins.size(), 'Should return no enabled plugins as any invalid plugin classes are skipped');
    }

    @isTest
    static void test_plugin_wrongInterface_skips() {
        // Arrange - TestConfigInvalidInterfaces has invalid plugin class name
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidInterfaces');

        //Assert that the class name is set to an invalid value
        Boolean invalidInterfaceClassNameFound = false;
        for(UoWPluginSetting__mdt setting : UoWConfigurationLoader.getInstance().getPluginSettings('TestConfigInvalidInterfaces')) {
            if(setting.PluginClassName__c == 'UoWTestMocks.WrongInterfaceStub') {
                invalidInterfaceClassNameFound = true;
            }
        }
        Assert.isTrue(invalidInterfaceClassNameFound, 'An invalid Plugin Class Name should be set in plugin settings configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        List<UoWInterfaces.IPlugin> enabledPlugins = UoWPluginRegistry.getInstance().getEnabledPlugins(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should not have any enabled plugins
        Assert.areEqual(0, enabledPlugins.size(), 'Should return no enabled plugins as any invalid plugin classes are skipped');
    }

    // ============================================================================
    // POLICY TESTS - EVALUATION AND ACTIONS
    // ============================================================================

    @isTest
    static void test_policy_evaluatePlan_allow_succeeds() {
        // Arrange
        resetRegistries();
        UoWTestMocks.MockPolicy allowPolicy = new UoWTestMocks.MockPolicy('AllowPolicy');
        allowPolicy.actionToReturn = UoWEnums.PolicyAction.ALLOW;

        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks')
            .withPolicy(allowPolicy);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertSuccess(result);

        // Verify policy evaluation summary
        UoWPolicyEvaluation.Summary summary = result.policyEvalSummary;
        Assert.isNotNull(summary, 'Should have policy evaluation summary');
        Assert.areEqual(UoWEnums.PolicyAction.ALLOW, summary.strictestPolicyAction, 'Strictest action should be ALLOW');
    }

    @isTest
    static void test_policy_evaluatePlan_deny_failsTransaction() {
        // Arrange
        resetRegistries();
        UoWTestMocks.MockPolicy denyPolicy = new UoWTestMocks.MockPolicy('DenyPolicy');
        denyPolicy.actionToReturn = UoWEnums.PolicyAction.DENY;
        denyPolicy.reasonMessage = 'High risk transaction denied';

        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks')
            .withPolicy(denyPolicy);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertFailure(result);
        // Policy DENY results in DENIED_BY_POLICY status
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.DENIED_BY_POLICY);

        // Verify policy evaluation summary
        UoWPolicyEvaluation.Summary summary = result.policyEvalSummary;
        Assert.areEqual(UoWEnums.PolicyAction.DENY, summary.strictestPolicyAction, 'Strictest action should be DENY');
    }

    @isTest
    static void test_policy_evaluatePlan_requireApproval_pausesForApproval() {
        // Arrange
        resetRegistries();
        UoWTestMocks.MockPolicy approvalPolicy = new UoWTestMocks.MockPolicy('ApprovalPolicy');
        approvalPolicy.actionToReturn = UoWEnums.PolicyAction.REQUIRE_APPROVAL;
        approvalPolicy.reasonMessage = 'Transaction requires approval';

        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks')
            .withPolicy(approvalPolicy);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        Assert.isFalse(result.isSuccess(), 'Transaction should not be completed (pending approval)');
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.PENDING_APPROVAL);

        // Verify policy evaluation summary
        UoWPolicyEvaluation.Summary summary = result.policyEvalSummary;
        Assert.areEqual(UoWEnums.PolicyAction.REQUIRE_APPROVAL, summary.strictestPolicyAction, 'Strictest action should be REQUIRE_APPROVAL');

        // Verify approval was requested
        Assert.areEqual('MOCK_APPROVAL_ID', result.getMetadata('approvalRecordId'), 'Should have approval record ID in metadata');
    }

    @isTest
    static void test_policy_evaluatePlan_allowWithJustification_succeedsWithWarning() {
        // Arrange
        resetRegistries();
        UoWTestMocks.MockPolicy warningPolicy = new UoWTestMocks.MockPolicy('WarningPolicy');
        warningPolicy.actionToReturn = UoWEnums.PolicyAction.ALLOW_WITH_JUSTIFICATION;
        warningPolicy.reasonMessage = 'Exception approval granted for data migration';
        warningPolicy.evidenceData.put('recordCount', 50000);
        warningPolicy.evidenceData.put('totalValue', 100000);

        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks')
            .withPolicy(warningPolicy);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertSuccess(result);
        Integer dmlCount = UoWTestHelpers.DEFAULT_DML_COUNT * 2; // Accounts & Contacts
        Assert.areEqual(dmlCount, result.statistics.dmlStats.records.processed, 'Should process ' + dmlCount + ' total record');
        Assert.areEqual(dmlCount, result.statistics.dmlStats.records.successes, 'Should have ' + dmlCount + ' total success');

        // Verify warning message for justification requirement
        UoWTestHelpers.assertResultHasMessage(result, System.LoggingLevel.WARN, 'requires justification: Exception approval granted for data migration');

        // Verify evidence in policy evaluation
        UoWPolicyEvaluation.Summary summary = result.policyEvalSummary;
        Boolean hasEvidence = false;
        for (UoWPolicyEvaluation.Evaluation eval : summary.evaluations) {
            if (eval.evidence.containsKey('recordCount') && eval.evidence.containsKey('totalValue')) {
                hasEvidence = true;
                Assert.areEqual(50000, eval.evidence.get('recordCount'), 'Should have correct recordCount in evidence');
                Assert.areEqual(100000, eval.evidence.get('totalValue'), 'Should have correct totalValue in evidence');
                break;
            }
        }
        Assert.isTrue(hasEvidence, 'Should have evidence in policy evaluation');
    }

    @isTest
    static void test_policy_evaluatePlan_requireTracing_enablesTracing() {
        // Arrange
        resetRegistries();
        UoWTestMocks.MockPolicy tracingPolicy = new UoWTestMocks.MockPolicy('TracingPolicy');
        tracingPolicy.actionToReturn = UoWEnums.PolicyAction.REQUIRE_TRACING;
        tracingPolicy.reasonMessage = 'Tracing required for audit';

        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks')
            .withPolicy(tracingPolicy);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertSuccess(result);

        // Verify tracing was enabled
        Assert.isTrue(uow.getContext().getFeatureSettings().tracingOverride, 'Tracing should be overridden by policy');
        Assert.isTrue(uow.getContext().getFeatureSettings().getEnableTracing(), 'Tracing should be enabled');
        Assert.isNotNull(result.tracer, 'Should have tracer initialized');
    }

    @isTest
    static void test_policy_evaluatePlan_requireMasking_enablesMasking() {
        // Arrange
        resetRegistries();
        UoWTestMocks.MockPolicy maskingPolicy = new UoWTestMocks.MockPolicy('MaskingPolicy');
        maskingPolicy.actionToReturn = UoWEnums.PolicyAction.REQUIRE_MASKING;
        maskingPolicy.reasonMessage = 'PII detected - masking required';

        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks')
            .withPolicy(maskingPolicy);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertSuccess(result);
        Integer dmlCount = UoWTestHelpers.DEFAULT_DML_COUNT * 2; // Accounts & Contacts
        Assert.areEqual(dmlCount, result.statistics.dmlStats.records.processed, 'Should process ' + dmlCount + ' total record');
        Assert.areEqual(dmlCount, result.statistics.dmlStats.records.successes, 'Should have ' + dmlCount + ' total success');

        // Verify masking policy action was logged
        Assert.isTrue(uow.getContext().getFeatureSettings().maskingOverride, 'Masking should be overridden by policy');
        Assert.isTrue(uow.getContext().getFeatureSettings().getEnableMasking(), 'Masking should be enabled');
        UoWTestHelpers.assertResultHasMessage(result, LoggingLevel.INFO, 'requires masking');
    }

    @isTest
    static void test_policy_evaluatePlan_exception_failsTransaction() {
        // Arrange
        resetRegistries();
        UoWTestMocks.MockPolicy exceptionPolicy = new UoWTestMocks.MockPolicy('ExceptionPolicy');
        exceptionPolicy.shouldThrowException = true;
        exceptionPolicy.exceptionMessage = 'Policy evaluation failed';
        // Note: exceptionPolicy.mockIsCritical = true (default) - critical policy failure rolls back transaction

        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks')
            .withPolicy(exceptionPolicy);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Critical policy exception should fail transaction
        // Note: Policy evaluation happens BEFORE savepoint creation, so status is FAILED (not ROLLED_BACK)
        UoWTestHelpers.assertFailure(result);
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.FAILED);

        // Verify error message mentions CRITICAL POLICY FAILURE
        UoWTestHelpers.assertResultHasMessage(result, System.LoggingLevel.ERROR, 'CRITICAL POLICY FAILURE');
    }

    @isTest
    static void test_policy_evaluatePlan_nonCriticalException_continuesTransaction() {
        // Arrange
        resetRegistries();

        UoWTestMocks.MockPolicy nonCriticalPolicy = new UoWTestMocks.MockPolicy('NonCriticalPolicy');
        nonCriticalPolicy.shouldThrowException = true;
        nonCriticalPolicy.exceptionMessage = 'Non-critical policy failed';
        nonCriticalPolicy.mockIsCritical = false;  // Non-critical - warning logged, transaction continues

        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks')
            .withPolicy(nonCriticalPolicy);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Non-critical policy exception should NOT fail transaction
        UoWTestHelpers.assertSuccess(result);

        // Verify warning message for non-critical policy failure
        UoWTestHelpers.assertResultHasMessage(result, System.LoggingLevel.WARN, 'Non-critical policy, NonCriticalPolicy, failed during evaluation');

        // Verify framework still processed DML successfully
        Integer dmlCount = UoWTestHelpers.DEFAULT_DML_COUNT * 2; // Accounts & Contacts
        Assert.areEqual(dmlCount, result.statistics.dmlStats.inserts.records.processed, 'DML should process records despite non-critical policy failure');
    }

    @isTest
    static void test_policy_multiplePolicies_strictestActionDeterminesOutcome() {
        // Arrange
        resetRegistries();
        UoWTestMocks.MockPolicy allowPolicy = new UoWTestMocks.MockPolicy('AllowPolicy');
        allowPolicy.actionToReturn = UoWEnums.PolicyAction.ALLOW;

        UoWTestMocks.MockPolicy warningPolicy = new UoWTestMocks.MockPolicy('WarningPolicy');
        warningPolicy.actionToReturn = UoWEnums.PolicyAction.ALLOW_WITH_JUSTIFICATION;

        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks')
            .withPolicy(allowPolicy)
            .withPolicy(warningPolicy);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertSuccess(result);

        UoWPolicyEvaluation.Summary summary = result.policyEvalSummary;
        Assert.areEqual(UoWEnums.PolicyAction.ALLOW_WITH_JUSTIFICATION, summary.strictestPolicyAction, 'Strictest action should be ALLOW_WITH_JUSTIFICATION');
        Assert.areEqual(4, summary.totalEvaluations, 'Should have 4 total evaluations'); // 2 from config & 2 registered here
    }

    @isTest
    static void test_policy_multiplePolicies_denyAction_shortCircuitsEvaluation() {
        // Arrange
        resetRegistries();
        UoWTestMocks.MockPolicy denyPolicy = new UoWTestMocks.MockPolicy('DenyPolicy');
        denyPolicy.actionToReturn = UoWEnums.PolicyAction.DENY;

        UoWTestMocks.MockPolicy allowPolicy = new UoWTestMocks.MockPolicy('AllowPolicy');
        allowPolicy.actionToReturn = UoWEnums.PolicyAction.ALLOW;

        // Register DENY first to ensure short-circuit behavior
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks')
            .withPolicy(denyPolicy)
            .withPolicy(allowPolicy);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert
        UoWTestHelpers.assertFailure(result);
        UoWTestHelpers.assertStatus(result, UoWEnums.TransactionStatus.DENIED_BY_POLICY);

        // Verify DENY action was recorded
        UoWPolicyEvaluation.Summary summary = result.policyEvalSummary;
        Assert.areEqual(UoWEnums.PolicyAction.DENY, summary.strictestPolicyAction, 'Should have DENY as strictest action (short-circuits evaluation)');
        Assert.areEqual(2, summary.totalPolicies, 'Should have evaluated 2 policies');
        Assert.areEqual(1, summary.totalEvaluations, 'Should have 1 total evaluation as the DENY policy should have short-circuited further evaluation');
    }

    @isTest
    static void test_policy_invalidClassName_skips() {
        // Arrange - TestConfigInvalidClasses has invalid policy class name
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidClasses');

        // Assert that the class name is set to an invalid value
        Boolean invalidClassNameFound = false;
        for (UoWPolicySetting__mdt setting : UoWConfigurationLoader.getInstance().getPolicySettings('TestConfigInvalidClasses')) {
            if (setting.PolicyClassName__c == 'NonExistentPolicy') {
                invalidClassNameFound = true;
            }
        }
        Assert.isTrue(invalidClassNameFound, 'An invalid Policy Class Name should be set in policy settings configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        List<UoWInterfaces.IPolicy> enabledPolicies = UoWPolicyRegistry.getInstance().getEnabledPolicies(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should not have any enabled policies
        Assert.areEqual(0, enabledPolicies.size(), 'Should return no enabled policies as any invalid policy classes are skipped');
    }

    @isTest
    static void test_policy_wrongInterface_skips() {
        // Arrange - TestConfigInvalidInterfaces has invalid policy class name
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidInterfaces');

        // Assert that the class name is set to a valid class that doesn't implement the interface
        Boolean invalidInterfaceClassNameFound = false;
        for (UoWPolicySetting__mdt setting : UoWConfigurationLoader.getInstance().getPolicySettings('TestConfigInvalidInterfaces')) {
            if (setting.PolicyClassName__c == 'UoWTestMocks.WrongInterfaceStub') {
                invalidInterfaceClassNameFound = true;
            }
        }
        Assert.isTrue(invalidInterfaceClassNameFound, 'A valid class but wrong interface should be set in policy settings configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        List<UoWInterfaces.IPolicy> enabledPolicies = UoWPolicyRegistry.getInstance().getEnabledPolicies(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should not have any enabled policies
        Assert.areEqual(0, enabledPolicies.size(), 'Should return no enabled policies as any invalid policy classes are skipped');
    }

    // ============================================================================
    // RISK ASSESSOR TESTS
    // ============================================================================

    @isTest
    static void test_riskAssessor_lowRisk_succeeds() {
        // Arrange
        UoWTestMocks.MockRiskAssessor assessor = new UoWTestMocks.MockRiskAssessor();
        assessor.riskScore = 15;
        assessor.riskLevel = UoWRiskTypes.RiskLevel.LOW;

        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks')
            .withRiskAssessor(assessor);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Low risk should succeed
        UoWTestHelpers.assertSuccess(result);
        Assert.areEqual(UoWRiskTypes.RiskLevel.LOW, result.riskAssessment.riskLevel, 'Should have LOW risk level');
        Assert.areEqual(15, result.riskAssessment.riskScore, 'Should have risk score of 15');
    }

    @isTest
    static void test_riskAssessor_highRisk_requiresApproval() {
        // Arrange
        UoWTestMocks.MockRiskAssessor assessor = new UoWTestMocks.MockRiskAssessor();
        assessor.riskScore = 75;
        assessor.riskLevel = UoWRiskTypes.RiskLevel.HIGH;
        assessor.requiresApproval = true;

        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks')
            .withRiskAssessor(assessor);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - High risk should require approval
        Assert.areEqual(UoWRiskTypes.RiskLevel.HIGH, result.riskAssessment.riskLevel, 'Should have HIGH risk level');
        Assert.areEqual(75, result.riskAssessment.riskScore, 'Should have risk score of 75');
        Assert.isTrue(result.riskAssessment.requiresApproval, 'Should require approval');
        Assert.isFalse(result.riskAssessment.riskFactors.isEmpty(), 'Should have risk factors list');
    }

    @isTest
    static void test_riskAssessor_exception_failsTransaction() {
        // Arrange
        UoWTestMocks.MockRiskAssessor assessor = new UoWTestMocks.MockRiskAssessor();
        assessor.shouldThrowException = true;
        assessor.exceptionMessage = 'Risk assessment service unavailable';

        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigAllMocks')
            .withRiskAssessor(assessor);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Risk assessor exception should fail transaction
        UoWTestHelpers.assertFailure(result);

        // Verify exception message
        Boolean hasRiskAssessorError = false;
        for (UoWExceptionService.ErrorInfo error : result.getErrors()) {
            if (error.errorMessage.contains('Risk assessment service unavailable')) {
                hasRiskAssessorError = true;
                break;
            }
        }
        Assert.isTrue(hasRiskAssessorError, 'Should have risk assessor exception');
    }

    @isTest
    static void test_riskAssessor_notConfigured_skipsAssessment() {
        // Arrange - Create unit of work with no risk assessor configured
        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigMinimal');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        Test.stopTest();

        // Assert - Should succeed without risk assessment
        UoWTestHelpers.assertSuccess(result);

        // Risk assessment should be null (skipped)
        Assert.isNull(result.riskAssessment, 'Risk assessment should be null when no assessor configured');
    }

    @isTest
    static void test_riskAssessor_invalidClassName_returnsNull() {
        // Arrange - TestConfigInvalidClasses has invalid risk assessor class name
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidClasses');

        // Assert that the class name is set to an invalid value
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigInvalidClasses');
        Assert.areEqual('NonExistentRiskAssessor', config.RiskAssessorClassName__c, 'An invalid Risk Assessor Class Name should be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IRiskAssessor resolved = UoWRiskAssessorResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should return null (optional, no default fallback)
        Assert.isNull(resolved, 'Should return null when invalid class name is configured');
    }

    @isTest
    static void test_riskAssessor_wrongInterface_returnsNull() {
        // Arrange - TestConfigInvalidInterfaces has valid class but wrong interface
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidInterfaces');

        // Assert that the class name is set to a valid class that doesn't implement the interface
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigInvalidInterfaces');
        Assert.areEqual('UoWTestMocks.WrongInterfaceStub', config.RiskAssessorClassName__c, 'A valid class but one that does not implement the correct interface should be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IRiskAssessor resolved = UoWRiskAssessorResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should return null (optional, no default fallback)
        Assert.isNull(resolved, 'Should return null when class does not implement correct interface');
    }

    // ============================================================================
    // APPROVAL CHANNEL RESOLVER TESTS
    // ============================================================================

    @isTest
    static void test_approvalChannelResolver_runtimeOverride_success() {
        // Arrange
        UoWTestMocks.MockApprovalChannel mockChannel = new UoWTestMocks.MockApprovalChannel('RuntimeMockApprovalChannel');

        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigMinimal')
            .withApprovalChannel(mockChannel);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IApprovalChannel resolved = UoWApprovalChannelResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Runtime override takes priority
        Assert.isNotNull(resolved, 'Should return a non-null channel instance');
        Assert.areEqual('RuntimeMockApprovalChannel', resolved.getName(), 'Should resolve to runtime override channel');
    }

    @isTest
    static void test_approvalChannelResolver_emptyClassName_returnsNull() {
        // Arrange - No approval channel configured
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigMinimal');

        // Assert that the class name is not set in the config
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigMinimal');
        Assert.isNull(config.ApprovalChannelClassName__c, 'Approval Channel Class Name should not be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IApprovalChannel resolved = UoWApprovalChannelResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should return null (optional, no default fallback)
        Assert.isNull(resolved, 'Should return null when no approval channel is configured');
    }

    @isTest
    static void test_approvalChannelResolver_invalidClassName_returnsNull() {
        // Arrange - TestConfigInvalidClasses has invalid approval channel class name
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidClasses');

        // Assert that the class name is set to an invalid value
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigInvalidClasses');
        Assert.areEqual('NonExistentApprovalChannel', config.ApprovalChannelClassName__c, 'An invalid Approval Channel Class Name should be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IApprovalChannel resolved = UoWApprovalChannelResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should return null (optional, no default fallback)
        Assert.isNull(resolved, 'Should return null when invalid class name is configured');
    }

    @isTest
    static void test_approvalChannelResolver_wrongInterface_returnsNull() {
        // Arrange - TestConfigInvalidInterfaces has valid class but wrong interface
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidInterfaces');

        // Assert that the class name is set to a valid class that doesn't implement the interface
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigInvalidInterfaces');
        Assert.areEqual('UoWTestMocks.WrongInterfaceStub', config.ApprovalChannelClassName__c, 'A valid class but one that does not implement the correct interface should be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IApprovalChannel resolved = UoWApprovalChannelResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should return null (optional, no default fallback)
        Assert.isNull(resolved, 'Should return null when class does not implement correct interface');
    }

    // ============================================================================
    // TRANSACTION FINALIZER RESOLVER TESTS
    // ============================================================================

    @isTest
    static void test_transactionFinalizerResolver_runtimeOverride_success() {
        // Arrange
        UoWTestMocks.MockTransactionFinalizer mockFinalizer = new UoWTestMocks.MockTransactionFinalizer();
        mockFinalizer.mockName = 'RuntimeMockTransactionFinalizer';

        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigMinimal')
            .withTransactionFinalizer(mockFinalizer);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.ITransactionFinalizer resolved = UoWTransactionFinalizerResolver.getInstance().resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Runtime override takes priority
        Assert.isNotNull(resolved, 'Should return a non-null finalizer instance');
        Assert.areEqual('RuntimeMockTransactionFinalizer', resolved.getName(), 'Should resolve to runtime override finalizer');
    }

    @isTest
    static void test_transactionFinalizerResolver_emptyClassName_returnsNull() {
        // Arrange - No transaction finalizer configured
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigMinimal');

        // Assert that the class name is not set in the config
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigMinimal');
        Assert.isNull(config.TransactionFinalizerClassName__c, 'Transaction Finalizer Class Name should not be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.ITransactionFinalizer resolved = UoWTransactionFinalizerResolver.getInstance().resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should return null (optional, no default fallback)
        Assert.isNull(resolved, 'Should return null when no transaction finalizer is configured');
    }

    @isTest
    static void test_transactionFinalizerResolver_invalidClassName_returnsNull() {
        // Arrange - TestConfigInvalidClasses has invalid transaction finalizer class name
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidClasses');

        // Assert that the class name is set to an invalid value
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigInvalidClasses');
        Assert.areEqual('NonExistentTransactionFinalizer', config.TransactionFinalizerClassName__c, 'An invalid Transaction Finalizer Class Name should be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.ITransactionFinalizer resolved = UoWTransactionFinalizerResolver.getInstance().resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should return null (optional, no default fallback)
        Assert.isNull(resolved, 'Should return null when invalid class name is configured');
    }

    @isTest
    static void test_transactionFinalizerResolver_wrongInterface_returnsNull() {
        // Arrange - TestConfigInvalidInterfaces has valid class but wrong interface
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidInterfaces');

        // Assert that the class name is set to a valid class that doesn't implement the interface
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigInvalidInterfaces');
        Assert.areEqual('UoWTestMocks.WrongInterfaceStub', config.TransactionFinalizerClassName__c, 'A valid class but one that does not implement the correct interface should be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.ITransactionFinalizer resolved = UoWTransactionFinalizerResolver.getInstance().resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should return null (optional, no default fallback)
        Assert.isNull(resolved, 'Should return null when class does not implement correct interface');
    }

    // ============================================================================
    // EVENT PUBLISH FAILURE HANDLER RESOLVER TESTS
    // ============================================================================

    @isTest
    static void test_eventPublishFailureHandlerResolver_runtimeOverride_success() {
        // Arrange
        UoWTestMocks.MockEventPublishFailureHandler mockHandler = new UoWTestMocks.MockEventPublishFailureHandler();
        mockHandler.mockName = 'RuntimeMockEventPublishFailureHandler';

        UnitOfWork uow = UoWTestHelpers.generateUoW_DmlInsertsOnly('TestConfigMinimal')
            .withEventPublishFailureHandler(mockHandler);

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IEventPublishFailureHandler resolved = UoWEventPublishFailureHandlerResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Runtime override takes priority
        Assert.isNotNull(resolved, 'Should return a non-null handler instance');
        Assert.areEqual('RuntimeMockEventPublishFailureHandler', resolved.getName(), 'Should resolve to runtime override handler');
    }

    @isTest
    static void test_eventPublishFailureHandlerResolver_emptyClassName_returnsNull() {
        // Arrange - No event publish failure handler configured
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigMinimal');

        // Assert that the class name is not set in the config
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigMinimal');
        Assert.isNull(config.EventPublishFailureHandlerClassName__c, 'Event Publish Failure Handler Class Name should not be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IEventPublishFailureHandler resolved = UoWEventPublishFailureHandlerResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should return null (optional, no default fallback)
        Assert.isNull(resolved, 'Should return null when no event publish failure handler is configured');
    }

    @isTest
    static void test_eventPublishFailureHandlerResolver_invalidClassName_returnsNull() {
        // Arrange - TestConfigInvalidClasses has invalid event publish failure handler class name
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidClasses');

        // Assert that the class name is set to an invalid value
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigInvalidClasses');
        Assert.areEqual('NonExistentEventPublishFailureHandler', config.EventPublishFailureHandlerClassName__c, 'An invalid Event Publish Failure Handler Class Name should be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IEventPublishFailureHandler resolved = UoWEventPublishFailureHandlerResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should return null (optional, no default fallback)
        Assert.isNull(resolved, 'Should return null when invalid class name is configured');
    }

    @isTest
    static void test_eventPublishFailureHandlerResolver_wrongInterface_returnsNull() {
        // Arrange - TestConfigInvalidInterfaces has valid class but wrong interface
        UnitOfWork uow = UoWTestHelpers.generateUoW_NoWorkItems('TestConfigInvalidInterfaces');

        // Assert that the class name is set to a valid class that doesn't implement the interface
        UoWConfiguration__mdt config = UoWConfigurationLoader.getInstance().getConfiguration('TestConfigInvalidInterfaces');
        Assert.areEqual('UoWTestMocks.WrongInterfaceStub', config.EventPublishFailureHandlerClassName__c, 'A valid class but one that does not implement the correct interface should be set in configuration');

        // Act
        Test.startTest();
        UoWResult result = uow.commitWork();
        UoWInterfaces.IEventPublishFailureHandler resolved = UoWEventPublishFailureHandlerResolver.resolve(uow.getContext(), result);
        Test.stopTest();

        // Assert - Should return null (optional, no default fallback)
        Assert.isNull(resolved, 'Should return null when class does not implement correct interface');
    }

}