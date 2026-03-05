//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Service for Big Object DML operations.
 * Virtual methods enable mocking via System.StubProvider in tests.
 *
 * Big Object DML (Database.insertAsync/insertImmediate) is treated as a callout
 * by the Apex runtime, which means:
 * - Cannot be executed with pending (uncommitted) DML in the same transaction
 * - Cannot be automatically rolled back in tests (real data is manipulated)
 * - Must be mocked via Stub API in test context to avoid callout errors
 *
 * Uses async-first strategy: Database.insertAsync() for throughput,
 * with Database.insertImmediate() as synchronous fallback on failure.
 *
 * @author Vipul Taylor
 * @group UoW Audit
 * @see UoWAuditArchivalService
 * @see UoWAuditBigObjectWriter
 */
public virtual class UoWAuditBigObjectDmlService {

    // ============================================================================
    // SINGLETON
    // ============================================================================

    private static UoWAuditBigObjectDmlService instance = new UoWAuditBigObjectDmlService();

    /**
     * Get the singleton instance. In test context, this can be replaced
     * with a stub via setMock().
     *
     * @return The current service instance (real or stubbed)
     */
    public static UoWAuditBigObjectDmlService getInstance() {
        return instance;
    }

    /**
     * Replace the singleton instance with a mock for testing.
     * Use with Test.createStub() and System.StubProvider.
     *
     * @param mockInstance The stubbed instance to use
     *
     * @example
     * UoWAuditBigObjectDmlService mockService = (UoWAuditBigObjectDmlService) Test.createStub(
     *     UoWAuditBigObjectDmlService.class, new MyStubProvider()
     * );
     * UoWAuditBigObjectDmlService.setMock(mockService);
     */
    @TestVisible
    private static void setMock(UoWAuditBigObjectDmlService mockInstance) {
        instance = mockInstance;
    }

    // ============================================================================
    // PUBLIC API
    // ============================================================================

    /**
     * Insert records to Big Object storage.
     * Uses Database.insertAsync() with Database.insertImmediate() as fallback.
     *
     * @param records Big Object records to insert
     * @return true if insert succeeded, false otherwise
     */
    public virtual Boolean insertRecords(List<UoWAuditHistory__b> records) {
        try {
            Database.insertAsync(records);
            System.debug(LoggingLevel.INFO,
                'Successfully archived ' + records.size() + ' records to Big Object');
            return true;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'Big Object async insert failed, trying synchronous: ' + e.getMessage());
            try {
                Database.insertImmediate(records);
                return true;
            } catch (Exception syncEx) {
                System.debug(LoggingLevel.ERROR,
                    'Big Object synchronous insert also failed: ' + syncEx.getMessage());
                return false;
            }
        }
    }
}
