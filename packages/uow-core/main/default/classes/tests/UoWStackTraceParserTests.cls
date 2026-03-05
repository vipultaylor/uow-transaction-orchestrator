//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Tests for UoWStackTraceParser utility class.
 * Covers stack trace parsing for Apex classes, triggers, anonymous blocks,
 * exception parsing, namespace skipping, and stack trace capture.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Tests
 * @see UoWStackTraceParser
 */
@isTest
@SuppressWarnings('PMD.MethodNamingConventions')
private class UoWStackTraceParserTests {
    // ============================================================================
    // TEST SETUP
    // ============================================================================

    @TestSetup
    static void setupTestData() {
        // Load test configurations
        UoWTestHelpers.loadTestConfigurations();
    }

    // ============================================================================
    // UoWStackTraceParser TESTS
    // ============================================================================

    @isTest
    static void test_stackTraceParser_parse_capturesCurrentLocation() {
        // Act
        Test.startTest();
        UoWStackTraceParser.StackTraceInfo info = UoWStackTraceParser.parse();
        Test.stopTest();

        // Assert
        Assert.isNotNull(info, 'StackTraceInfo should not be null');
        Assert.isNotNull(info.fullStackTrace, 'Full stack trace should be captured');
        Assert.isTrue(info.fullStackTrace.length() > 0, 'Stack trace should not be empty');
    }

    @isTest
    static void test_stackTraceParser_parseApexClass_extractsDetails() {
        // Arrange - Sample stack trace line (single line to avoid multi-line parsing issues)
        String stackTrace = 'Class.AccountService.processRecords: line 123, column 1';

        // Act
        Test.startTest();
        UoWStackTraceParser.StackTraceInfo info = UoWStackTraceParser.parse(stackTrace);
        Test.stopTest();

        // Assert
        Assert.areEqual('AccountService', info.className, 'Should extract class name');
        Assert.areEqual('processRecords', info.methodName, 'Should extract method name');
        Assert.areEqual(123, info.lineNumber, 'Should extract line number');
        Assert.isTrue(info.originLocation.contains('AccountService'),
            'Origin location should contain class name');
        Assert.areEqual('Apex', info.originType, 'Origin type should be Apex for non-test class');
    }

    @isTest
    static void test_stackTraceParser_parseTrigger_extractsDetails() {
        // Arrange - Sample trigger stack trace
        String stackTrace = 'Trigger.AccountTrigger: line 45, column 1';

        // Act
        Test.startTest();
        UoWStackTraceParser.StackTraceInfo info = UoWStackTraceParser.parse(stackTrace);
        Test.stopTest();

        // Assert
        Assert.areEqual('AccountTrigger', info.className, 'Should extract trigger name');
        Assert.areEqual(45, info.lineNumber, 'Should extract line number');
        Assert.areEqual('Trigger', info.originType, 'Origin type should be Trigger');
        Assert.isTrue(info.originLocation.contains('Trigger.AccountTrigger'),
            'Origin location should contain trigger reference');
    }

    @isTest
    static void test_stackTraceParser_parseAnonymousApex_extractsDetails() {
        // Arrange - Sample anonymous apex stack trace
        String stackTrace = 'AnonymousBlock: line 10, column 1';

        // Act
        Test.startTest();
        UoWStackTraceParser.StackTraceInfo info = UoWStackTraceParser.parse(stackTrace);
        Test.stopTest();

        // Assert
        Assert.areEqual('AnonymousBlock', info.className, 'Should identify as AnonymousBlock');
        Assert.areEqual(10, info.lineNumber, 'Should extract line number');
        Assert.areEqual('Anonymous Apex', info.originType, 'Origin type should be Anonymous Apex');
    }

    @isTest
    static void test_stackTraceParser_parseException_capturesStackTrace() {
        // Arrange - Create and catch exception
        Exception testEx;
        try {
            throw new UoWExceptionService.UoWException('Test exception');
        } catch (Exception ex) {
            testEx = ex;
        }

        // Act
        Test.startTest();
        UoWStackTraceParser.StackTraceInfo info = UoWStackTraceParser.parseException(testEx);
        Test.stopTest();

        // Assert
        Assert.isNotNull(info, 'Should parse exception stack trace');
        Assert.isNotNull(info.fullStackTrace, 'Should have full stack trace');
    }

    @isTest
    static void test_stackTraceParser_withSkipNamespace_skipsFrameworkLines() {
        // Arrange - Stack trace with framework lines to skip
        String stackTrace = 'Class.UoWCore.UoWTransactionStateService.execute: line 100, column 1\n' +
            'Class.MyClass.myMethod: line 50, column 1';

        // Act - Skip UoWCore namespace
        Test.startTest();
        UoWStackTraceParser.StackTraceInfo info = UoWStackTraceParser.parse(stackTrace, 'UoWCore');
        Test.stopTest();

        // Assert - Should parse the non-framework line
        Assert.isNotNull(info.originLocation, 'Should have origin location');
    }

    @isTest
    static void test_stackTraceParser_captureStackTrace_returnsString() {
        // Act
        Test.startTest();
        String stackTrace = UoWStackTraceParser.captureStackTrace();
        Test.stopTest();

        // Assert
        Assert.isNotNull(stackTrace, 'Should capture stack trace');
        Assert.isTrue(stackTrace.length() > 0, 'Stack trace should not be empty');
        Assert.isTrue(stackTrace.contains('UoWStackTraceParserTests'),
            'Stack trace should contain this test class');
    }
}