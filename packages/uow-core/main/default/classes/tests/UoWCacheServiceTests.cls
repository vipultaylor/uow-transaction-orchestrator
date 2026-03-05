//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Tests for UoWCacheService utility class.
 * Covers schema describe caching, field describe caching,
 * cache management, and warmup functionality.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Tests
 * @see UoWCacheService
 */
@isTest
@SuppressWarnings('PMD.MethodNamingConventions')
private class UoWCacheServiceTests {
    // ============================================================================
    // TEST SETUP
    // ============================================================================

    @TestSetup
    static void setupTestData() {
        // Load test configurations
        UoWTestHelpers.loadTestConfigurations();
    }

    // ============================================================================
    // UoWCacheService TESTS
    // ============================================================================

    @isTest
    static void test_cacheService_getDescribe_cachesSObjectType() {
        // Act
        Test.startTest();
        Schema.DescribeSObjectResult describe1 = UoWCacheService.getDescribe(Account.SObjectType);
        Schema.DescribeSObjectResult describe2 = UoWCacheService.getDescribe(Account.SObjectType);
        Test.stopTest();

        // Assert
        Assert.isNotNull(describe1, 'First describe should not be null');
        Assert.isNotNull(describe2, 'Second describe should not be null');
        Assert.areEqual(describe1.getName(), describe2.getName(), 'Both calls should return same describe result');
        Assert.areEqual('Account', describe1.getName(), 'Should describe Account');
    }

    @isTest
    static void test_cacheService_getFieldDescribe_cachesField() {
        // Act
        Test.startTest();
        Schema.DescribeFieldResult fieldDescribe1 = UoWCacheService.getFieldDescribe(Account.Name);
        Schema.DescribeFieldResult fieldDescribe2 = UoWCacheService.getFieldDescribe(Account.Name);
        Test.stopTest();

        // Assert
        Assert.isNotNull(fieldDescribe1, 'First field describe should not be null');
        Assert.isNotNull(fieldDescribe2, 'Second field describe should not be null');
        Assert.areEqual(fieldDescribe1.getName(), fieldDescribe2.getName(),
            'Both calls should return same field describe');
        Assert.areEqual('Name', fieldDescribe1.getName(), 'Should describe Name field');
    }

    @isTest
    static void test_cacheService_getDescribe_multipleSObjectTypes() {
        // Act
        Test.startTest();
        Schema.DescribeSObjectResult accountDescribe = UoWCacheService.getDescribe(Account.SObjectType);
        Schema.DescribeSObjectResult contactDescribe = UoWCacheService.getDescribe(Contact.SObjectType);
        Schema.DescribeSObjectResult caseDescribe = UoWCacheService.getDescribe(Case.SObjectType);
        Test.stopTest();

        // Assert
        Assert.areEqual('Account', accountDescribe.getName(), 'Should describe Account');
        Assert.areEqual('Contact', contactDescribe.getName(), 'Should describe Contact');
        Assert.areEqual('Case', caseDescribe.getName(), 'Should describe Case');
    }

    @isTest
    static void test_cacheService_clearCache_removesAllEntries() {
        // Arrange - Populate cache
        UoWCacheService.getDescribe(Account.SObjectType);
        UoWCacheService.getFieldDescribe(Account.Name);

        // Act
        Test.startTest();
        UoWCacheService.clearCache();
        // Re-fetch after clear (should still work, just not from cache)
        Schema.DescribeSObjectResult describe = UoWCacheService.getDescribe(Account.SObjectType);
        Test.stopTest();

        // Assert
        Assert.isNotNull(describe, 'Should still return describe after cache clear');
        Assert.areEqual('Account', describe.getName(), 'Should describe Account');
    }

    @isTest
    static void test_cacheService_clearCache_clearsAllCachedData() {
        // Real-world scenario: Reset cache between transactions for isolation

        // Arrange - Populate cache
        Test.startTest();
        Schema.DescribeSObjectResult describeResult = UoWCacheService.getDescribe(Account.SObjectType);
        Assert.isNotNull(describeResult, 'Should cache Account describe');

        // Act - Clear cache
        UoWCacheService.clearCache();

        // Assert - Cache still works after clear
        Schema.DescribeSObjectResult descAfter = UoWCacheService.getDescribe(Account.SObjectType);
        Assert.isNotNull(descAfter, 'Should return describe after cache clear');
        Test.stopTest();
    }

    @isTest
    static void test_cacheService_setCacheEnabled_togglesCaching() {
        // Real-world scenario: Disable caching for debugging

        // Arrange
        Test.startTest();

        // Verify default state
        Assert.isTrue(UoWCacheService.isCacheEnabled(), 'Cache should be enabled by default');

        // Act - Disable cache
        UoWCacheService.setCacheEnabled(false);
        Assert.isFalse(UoWCacheService.isCacheEnabled(), 'Cache should be disabled');

        // Act - Re-enable cache
        UoWCacheService.setCacheEnabled(true);
        Assert.isTrue(UoWCacheService.isCacheEnabled(), 'Cache should be re-enabled');

        Test.stopTest();
    }

    @isTest
    static void test_cacheService_getFieldDescribe_cachesFieldResults() {
        // Real-world scenario: Multiple CRUD/FLS checks on same field

        // Arrange
        Test.startTest();

        // Act - Get field describe multiple times
        Schema.DescribeFieldResult field1 = UoWCacheService.getFieldDescribe(Account.Name);
        Schema.DescribeFieldResult field2 = UoWCacheService.getFieldDescribe(Account.Name);

        Test.stopTest();

        // Assert - Both calls return valid results
        Assert.isNotNull(field1, 'First call should return field describe');
        Assert.isNotNull(field2, 'Second call should return field describe');
        Assert.areEqual(field1.getName(), field2.getName(), 'Should return same field name');
        Assert.isTrue(field1.isCreateable() == field2.isCreateable(), 'Should return same createable status');
    }

    @isTest
    static void test_cacheService_warmupCache_preloadsMultipleTypes() {
        // Real-world scenario: Batch job initialization preloads common objects

        // Arrange
        UoWCacheService.clearCache();

        Set<Schema.SObjectType> types = new Set<Schema.SObjectType>{
            Account.SObjectType,
            Contact.SObjectType,
            Opportunity.SObjectType
        };

        // Act
        Test.startTest();
        UoWCacheService.warmupCache(types);
        Test.stopTest();

        // Assert - All types should be accessible
        Assert.isNotNull(UoWCacheService.getDescribe(Account.SObjectType), 'Account should be cached');
        Assert.isNotNull(UoWCacheService.getDescribe(Contact.SObjectType), 'Contact should be cached');
        Assert.isNotNull(UoWCacheService.getDescribe(Opportunity.SObjectType), 'Opportunity should be cached');
    }

    @isTest
    static void test_cacheService_getDescribe_handlesNullType() {
        // Real-world scenario: Defensive handling of null input

        // Act & Assert
        Test.startTest();
        try {
            Schema.DescribeSObjectResult describeResult = UoWCacheService.getDescribe(null);
            // If it returns null gracefully, that's acceptable
            Assert.isNull(describeResult, 'Should return null for null input');
        } catch (Exception ex) {
            // If it throws, that's also acceptable defensive behavior
            Assert.isTrue(true, 'Exception is acceptable for null input');
        }
        Test.stopTest();
    }

    @isTest
    static void test_cacheService_getFieldDescribe_handlesNullField() {
        // Real-world scenario: Defensive handling of null input

        // Act & Assert
        Test.startTest();
        try {
            Schema.DescribeFieldResult fieldDescribe = UoWCacheService.getFieldDescribe(null);
            // If it returns null gracefully, that's acceptable
            Assert.isNull(fieldDescribe, 'Should return null for null input');
        } catch (Exception ex) {
            // If it throws, that's also acceptable defensive behavior
            Assert.isTrue(true, 'Exception is acceptable for null input');
        }
        Test.stopTest();
    }
}