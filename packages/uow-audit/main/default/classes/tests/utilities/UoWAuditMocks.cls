//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Shared test mocks for UoW Audit package testing.
 * Centralizes reusable StubProviders and mock installation helpers
 * to avoid duplication across test classes.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Audit Test Utilities
 * @see UoWAuditBigObjectDmlService
 * @see UoWAuditDataSelector
 */
@isTest
public class UoWAuditMocks {

    // ============================================================================
    // BIG OBJECT DML MOCK
    // ============================================================================

    /**
     * StubProvider for mocking UoWAuditBigObjectDmlService.
     * Captures archived records for verification and returns configurable results.
     */
    public class BigObjectDmlMockProvider implements System.StubProvider {
        public List<UoWAuditHistory__b> capturedRecords = new List<UoWAuditHistory__b>();
        public Boolean shouldSucceed = true;

        public Object handleMethodCall(
            Object stubbedObject,
            String stubbedMethodName,
            Type returnType,
            List<Type> listOfParamTypes,
            List<String> listOfParamNames,
            List<Object> listOfArgs
        ) {
            if (stubbedMethodName == 'insertRecords') {
                List<UoWAuditHistory__b> records = (List<UoWAuditHistory__b>) listOfArgs[0];
                capturedRecords.addAll(records);
                return shouldSucceed;
            }
            return null;
        }
    }

    /**
     * Install the Big Object DML mock via Stub API.
     * Returns the mock provider so tests can inspect captured records.
     *
     * @return BigObjectDmlMockProvider instance for assertion access
     */
    public static BigObjectDmlMockProvider installBigObjectMock() {
        BigObjectDmlMockProvider mockProvider = new BigObjectDmlMockProvider();
        UoWAuditBigObjectDmlService mockService = (UoWAuditBigObjectDmlService) Test.createStub(
            UoWAuditBigObjectDmlService.class, mockProvider
        );
        UoWAuditBigObjectDmlService.setMock(mockService);
        return mockProvider;
    }

    // ============================================================================
    // DATA SELECTOR MOCK - BIG OBJECT QUERIES
    // ============================================================================

    /**
     * Mock DataSelector that overrides Big Object query methods with
     * configurable return values. Custom object methods (UoWAuditTransaction__c,
     * UoWAuditWorkItem__c) are NOT overridden — those use real DML per the
     * extension package testing strategy.
     */
    public class MockDataSelector extends UoWAuditDataSelector {

        /** Configurable return value for getArchiveByKey */
        public UoWAuditHistory__b archiveDetailResult;

        /** Configurable return value for queryArchiveRecords */
        public List<UoWAuditHistory__b> archiveQueryResults = new List<UoWAuditHistory__b>();

        /** Captured parameters for assertion */
        public String capturedCorrelationId;
        public Decimal capturedSequence;
        public DateTime capturedCreatedTimestamp;
        public Integer capturedQueryLimit;

        public override UoWAuditHistory__b getArchiveByKey(
            String correlationId,
            Decimal sequence,
            DateTime createdTimestamp
        ) {
            this.capturedCorrelationId = correlationId;
            this.capturedSequence = sequence;
            this.capturedCreatedTimestamp = createdTimestamp;

            if (String.isBlank(correlationId) || createdTimestamp == null) {
                return null;
            }
            return archiveDetailResult;
        }

        public override List<UoWAuditHistory__b> queryArchiveRecords(
            String correlationId,
            Date startDate,
            Date endDate,
            DateTime cursorTimestamp,
            Integer queryLimit
        ) {
            this.capturedCorrelationId = correlationId;
            this.capturedQueryLimit = queryLimit;
            return archiveQueryResults;
        }
    }

    /**
     * Install the MockDataSelector via setInstance().
     * Returns the mock so tests can configure return values and inspect captures.
     *
     * @return MockDataSelector instance for configuration and assertion access
     */
    public static MockDataSelector installDataSelectorMock() {
        MockDataSelector mockSelector = new MockDataSelector();
        UoWAuditDataSelector.setInstance(mockSelector);
        return mockSelector;
    }
}
