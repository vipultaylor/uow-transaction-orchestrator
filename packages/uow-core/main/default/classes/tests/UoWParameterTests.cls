//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Tests for UoWCoreParameter and UoWParameterUtil classes.
 * Covers parameter default fallbacks, mocked values, type-safe getters,
 * cache clearing, and prefix matching.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Tests
 * @see UoWCoreParameter
 * @see UoWParameterUtil
 */
@isTest
@SuppressWarnings('PMD.MethodNamingConventions')
private class UoWParameterTests {
    // ============================================================================
    // TEST SETUP
    // ============================================================================

    @TestSetup
    static void setupTestData() {
        // Load test configurations
        UoWTestHelpers.loadTestConfigurations();
    }

    // ============================================================================
    // UoWCoreParameter - DEFAULT FALLBACK TESTS
    // ============================================================================

    @isTest
    static void test_coreParameter_riskThresholds_returnDefaults() {
        // Arrange - Clear cache to ensure fresh read with no metadata
        UoWCoreParameter.clearCache();

        // Act
        Test.startTest();
        Decimal lowThreshold = UoWCoreParameter.DEFAULT_RISK_LOW_THRESHOLD;
        Decimal mediumThreshold = UoWCoreParameter.DEFAULT_RISK_MEDIUM_THRESHOLD;
        Decimal highThreshold = UoWCoreParameter.DEFAULT_RISK_HIGH_THRESHOLD;
        Decimal criticalThreshold = UoWCoreParameter.DEFAULT_RISK_CRITICAL_THRESHOLD;
        Decimal approvalThreshold = UoWCoreParameter.DEFAULT_RISK_APPROVAL_THRESHOLD;
        Decimal blockThreshold = UoWCoreParameter.DEFAULT_RISK_BLOCK_THRESHOLD;
        Test.stopTest();

        // Assert - Should return hardcoded defaults when no metadata exists
        Assert.areEqual(25.0, lowThreshold, 'DEFAULT_RISK_LOW_THRESHOLD should default to 25.0');
        Assert.areEqual(50.0, mediumThreshold, 'DEFAULT_RISK_MEDIUM_THRESHOLD should default to 50.0');
        Assert.areEqual(75.0, highThreshold, 'DEFAULT_RISK_HIGH_THRESHOLD should default to 75.0');
        Assert.areEqual(90.0, criticalThreshold, 'DEFAULT_RISK_CRITICAL_THRESHOLD should default to 90.0');
        Assert.areEqual(75.0, approvalThreshold, 'DEFAULT_RISK_APPROVAL_THRESHOLD should default to 75.0');
        Assert.areEqual(95.0, blockThreshold, 'DEFAULT_RISK_BLOCK_THRESHOLD should default to 95.0');
    }

    @isTest
    static void test_coreParameter_batchSizes_returnDefaults() {
        // Arrange - Clear cache to ensure fresh read with no metadata
        UoWCoreParameter.clearCache();

        // Act
        Test.startTest();
        Integer dmlBatchSize = UoWCoreParameter.DEFAULT_DML_BATCH_SIZE;
        Integer maxDmlBatchSize = UoWCoreParameter.DEFAULT_MAX_DML_BATCH_SIZE;
        Integer eventBatchSize = UoWCoreParameter.DEFAULT_EVENT_BATCH_SIZE;
        Integer maxAsyncDepth = UoWCoreParameter.DEFAULT_MAX_ASYNC_DEPTH;
        Test.stopTest();

        // Assert - Should return hardcoded defaults when no metadata exists
        Assert.areEqual(200, dmlBatchSize, 'DEFAULT_DML_BATCH_SIZE should default to 200');
        Assert.areEqual(10000, maxDmlBatchSize, 'DEFAULT_MAX_DML_BATCH_SIZE should default to 10000');
        Assert.areEqual(100, eventBatchSize, 'DEFAULT_EVENT_BATCH_SIZE should default to 100');
        Assert.areEqual(1, maxAsyncDepth, 'DEFAULT_MAX_ASYNC_DEPTH should default to 1');
    }

    @isTest
    static void test_coreParameter_approvalSettings_returnDefaults() {
        // Arrange - Clear cache to ensure fresh read with no metadata
        UoWCoreParameter.clearCache();

        // Act
        Test.startTest();
        Decimal confidenceThreshold = UoWCoreParameter.DEFAULT_CONFIDENCE_THRESHOLD;
        Integer approvalTimeout = UoWCoreParameter.DEFAULT_APPROVAL_TIMEOUT_MINUTES;
        Test.stopTest();

        // Assert - Should return hardcoded defaults when no metadata exists
        Assert.areEqual(0.70, confidenceThreshold, 'DEFAULT_CONFIDENCE_THRESHOLD should default to 0.70');
        Assert.areEqual(30, approvalTimeout, 'DEFAULT_APPROVAL_TIMEOUT_MINUTES should default to 30');
    }

    @isTest
    static void test_coreParameter_retryableStatusCodes_returnDefaults() {
        // Arrange - Clear cache to ensure fresh read with no metadata
        UoWCoreParameter.clearCache();

        // Act
        Test.startTest();
        List<Integer> statusCodes = UoWCoreParameter.RETRYABLE_STATUS_CODES;
        Test.stopTest();

        // Assert - Should return default list of retryable HTTP status codes
        Assert.isNotNull(statusCodes, 'RETRYABLE_STATUS_CODES should not be null');
        Assert.isTrue(statusCodes.contains(429), 'Should include 429 (Too Many Requests)');
        Assert.isTrue(statusCodes.contains(500), 'Should include 500 (Internal Server Error)');
        Assert.isTrue(statusCodes.contains(502), 'Should include 502 (Bad Gateway)');
        Assert.isTrue(statusCodes.contains(503), 'Should include 503 (Service Unavailable)');
        Assert.isTrue(statusCodes.contains(504), 'Should include 504 (Gateway Timeout)');
    }

    // ============================================================================
    // UoWCoreParameter - MOCK VALUE TESTS
    // ============================================================================

    @isTest
    static void test_coreParameter_riskThresholds_useMockedValues() {
        // Arrange - Clear cache and set mock values
        UoWCoreParameter.clearCache();
        UoWParameterUtil.setMock('DefaultRiskLowThreshold', '10.0');
        UoWParameterUtil.setMock('DefaultRiskMediumThreshold', '30.0');
        UoWParameterUtil.setMock('DefaultRiskHighThreshold', '60.0');
        UoWParameterUtil.setMock('DefaultRiskCriticalThreshold', '85.0');

        // Act
        Test.startTest();
        Decimal lowThreshold = UoWCoreParameter.DEFAULT_RISK_LOW_THRESHOLD;
        Decimal mediumThreshold = UoWCoreParameter.DEFAULT_RISK_MEDIUM_THRESHOLD;
        Decimal highThreshold = UoWCoreParameter.DEFAULT_RISK_HIGH_THRESHOLD;
        Decimal criticalThreshold = UoWCoreParameter.DEFAULT_RISK_CRITICAL_THRESHOLD;
        Test.stopTest();

        // Assert - Should return mocked values
        Assert.areEqual(10.0, lowThreshold, 'Should use mocked low threshold');
        Assert.areEqual(30.0, mediumThreshold, 'Should use mocked medium threshold');
        Assert.areEqual(60.0, highThreshold, 'Should use mocked high threshold');
        Assert.areEqual(85.0, criticalThreshold, 'Should use mocked critical threshold');
    }

    @isTest
    static void test_coreParameter_batchSizes_useMockedValues() {
        // Arrange - Clear cache and set mock values
        UoWCoreParameter.clearCache();
        UoWParameterUtil.setMock('DefaultDmlBatchSize', '500');
        UoWParameterUtil.setMock('DefaultMaxDmlBatchSize', '5000');
        UoWParameterUtil.setMock('DefaultEventBatchSize', '50');
        UoWParameterUtil.setMock('DefaultMaxAsyncDepth', '3');

        // Act
        Test.startTest();
        Integer dmlBatchSize = UoWCoreParameter.DEFAULT_DML_BATCH_SIZE;
        Integer maxDmlBatchSize = UoWCoreParameter.DEFAULT_MAX_DML_BATCH_SIZE;
        Integer eventBatchSize = UoWCoreParameter.DEFAULT_EVENT_BATCH_SIZE;
        Integer maxAsyncDepth = UoWCoreParameter.DEFAULT_MAX_ASYNC_DEPTH;
        Test.stopTest();

        // Assert - Should return mocked values
        Assert.areEqual(500, dmlBatchSize, 'Should use mocked DML batch size');
        Assert.areEqual(5000, maxDmlBatchSize, 'Should use mocked max DML batch size');
        Assert.areEqual(50, eventBatchSize, 'Should use mocked event batch size');
        Assert.areEqual(3, maxAsyncDepth, 'Should use mocked max async depth');
    }

    @isTest
    static void test_coreParameter_clearCache_resetsAllValues() {
        // Arrange - Set mock values and read them to cache
        UoWCoreParameter.clearCache();
        UoWParameterUtil.setMock('DefaultDmlBatchSize', '999');
        Integer cachedValue = UoWCoreParameter.DEFAULT_DML_BATCH_SIZE;
        Assert.areEqual(999, cachedValue, 'Should have cached mocked value');

        // Act - Clear cache and parameter util
        Test.startTest();
        UoWCoreParameter.clearCache();
        Test.stopTest();

        // Assert - After clearCache, reading again should get fresh value (default)
        Integer freshValue = UoWCoreParameter.DEFAULT_DML_BATCH_SIZE;
        Assert.areEqual(200, freshValue, 'After clearCache should return default value');
    }

    // ============================================================================
    // UoWParameterUtil - TYPE CONVERSION TESTS
    // ============================================================================

    @isTest
    static void test_parameterUtil_getBoolean_returnsCorrectValue() {
        // Arrange
        UoWParameterUtil.clearCache();
        UoWParameterUtil.setMock('TestBooleanTrue', 'true');
        UoWParameterUtil.setMock('TestBooleanFalse', 'false');

        // Act
        Test.startTest();
        Boolean trueValue = UoWParameterUtil.getBoolean('TestBooleanTrue', false);
        Boolean falseValue = UoWParameterUtil.getBoolean('TestBooleanFalse', true);
        Boolean defaultValue = UoWParameterUtil.getBoolean('NonExistent', true);
        Test.stopTest();

        // Assert
        Assert.isTrue(trueValue, 'Should return true for "true" string');
        Assert.isFalse(falseValue, 'Should return false for "false" string');
        Assert.isTrue(defaultValue, 'Should return default when parameter not found');
    }

    @isTest
    static void test_parameterUtil_getInteger_returnsCorrectValue() {
        // Arrange
        UoWParameterUtil.clearCache();
        UoWParameterUtil.setMock('TestInteger', '42');

        // Act
        Test.startTest();
        Integer value = UoWParameterUtil.getInteger('TestInteger', 0);
        Integer defaultValue = UoWParameterUtil.getInteger('NonExistent', 99);
        Test.stopTest();

        // Assert
        Assert.areEqual(42, value, 'Should return parsed integer value');
        Assert.areEqual(99, defaultValue, 'Should return default when parameter not found');
    }

    @isTest
    static void test_parameterUtil_getDecimal_returnsCorrectValue() {
        // Arrange
        UoWParameterUtil.clearCache();
        UoWParameterUtil.setMock('TestDecimal', '3.14159');

        // Act
        Test.startTest();
        Decimal value = UoWParameterUtil.getDecimal('TestDecimal', 0.0);
        Decimal defaultValue = UoWParameterUtil.getDecimal('NonExistent', 2.71828);
        Test.stopTest();

        // Assert
        Assert.areEqual(3.14159, value, 'Should return parsed decimal value');
        Assert.areEqual(2.71828, defaultValue, 'Should return default when parameter not found');
    }

    @isTest
    static void test_parameterUtil_getString_returnsCorrectValue() {
        // Arrange
        UoWParameterUtil.clearCache();
        UoWParameterUtil.setMock('TestString', 'Hello World');

        // Act
        Test.startTest();
        String value = UoWParameterUtil.getString('TestString', 'default');
        String defaultValue = UoWParameterUtil.getString('NonExistent', 'fallback');
        Test.stopTest();

        // Assert
        Assert.areEqual('Hello World', value, 'Should return string value');
        Assert.areEqual('fallback', defaultValue, 'Should return default when parameter not found');
    }

    @isTest
    static void test_parameterUtil_getStringList_returnsCorrectValue() {
        // Arrange
        UoWParameterUtil.clearCache();
        UoWParameterUtil.setMock('TestStringList', '["one","two","three"]');

        // Act
        Test.startTest();
        List<String> value = UoWParameterUtil.getStringList('TestStringList', new List<String>());
        List<String> defaultValue = UoWParameterUtil.getStringList('NonExistent', new List<String>{ 'default' });
        Test.stopTest();

        // Assert
        Assert.areEqual(3, value.size(), 'Should return parsed list with 3 items');
        Assert.isTrue(value.contains('one'), 'Should contain "one"');
        Assert.isTrue(value.contains('two'), 'Should contain "two"');
        Assert.isTrue(value.contains('three'), 'Should contain "three"');
        Assert.areEqual(1, defaultValue.size(), 'Should return default list');
    }

    @isTest
    static void test_parameterUtil_getIntegerList_returnsCorrectValue() {
        // Arrange
        UoWParameterUtil.clearCache();
        UoWParameterUtil.setMock('TestIntegerList', '[100,200,300]');

        // Act
        Test.startTest();
        List<Integer> value = UoWParameterUtil.getIntegerList('TestIntegerList', new List<Integer>());
        List<Integer> defaultValue = UoWParameterUtil.getIntegerList('NonExistent', new List<Integer>{ 999 });
        Test.stopTest();

        // Assert
        Assert.areEqual(3, value.size(), 'Should return parsed list with 3 items');
        Assert.isTrue(value.contains(100), 'Should contain 100');
        Assert.isTrue(value.contains(200), 'Should contain 200');
        Assert.isTrue(value.contains(300), 'Should contain 300');
        Assert.areEqual(1, defaultValue.size(), 'Should return default list');
    }

    @isTest
    static void test_parameterUtil_getStringList_invalidJson_returnsDefault() {
        // Arrange
        UoWParameterUtil.clearCache();
        UoWParameterUtil.setMock('TestInvalidJson', 'not valid json');

        // Act
        Test.startTest();
        List<String> value = UoWParameterUtil.getStringList('TestInvalidJson', new List<String>{ 'fallback' });
        Test.stopTest();

        // Assert - Invalid JSON should return default
        Assert.areEqual(1, value.size(), 'Should return default list for invalid JSON');
        Assert.areEqual('fallback', value[0], 'Should contain fallback value');
    }

    @isTest
    static void test_parameterUtil_matchOnPrefix_returnsMatchingParams() {
        // Arrange
        UoWParameterUtil.clearCache();
        UoWParameterUtil.setMock('TestPrefix_One', 'value1');
        UoWParameterUtil.setMock('TestPrefix_Two', 'value2');
        UoWParameterUtil.setMock('OtherPrefix_Three', 'value3');

        // Act
        Test.startTest();
        Map<String, String> matches = UoWParameterUtil.matchOnPrefix('TestPrefix_');
        Map<String, String> noMatches = UoWParameterUtil.matchOnPrefix('NoMatch_');
        Map<String, String> emptyPrefix = UoWParameterUtil.matchOnPrefix('');
        Test.stopTest();

        // Assert
        Assert.areEqual(2, matches.size(), 'Should find 2 matching parameters');
        Assert.areEqual('value1', matches.get('TestPrefix_One'), 'Should contain TestPrefix_One');
        Assert.areEqual('value2', matches.get('TestPrefix_Two'), 'Should contain TestPrefix_Two');
        Assert.areEqual(0, noMatches.size(), 'Should return empty map for no matches');
        Assert.areEqual(0, emptyPrefix.size(), 'Should return empty map for empty prefix');
    }
}