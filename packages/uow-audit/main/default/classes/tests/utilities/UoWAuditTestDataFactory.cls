//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Test data factory for UoW Audit package testing.
 * Creates test UoWAuditEvent__e, UoWAuditTransaction__c, and UoWAuditWorkItem__c
 * records for comprehensive integration testing.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Audit Test Utilities
 */
@isTest
@SuppressWarnings('PMD.ExcessivePublicCount')
public class UoWAuditTestDataFactory {

    private static final String PERMISSION_SET_AUDIT_ADMIN = 'UoWAuditAdmin';
    public static final String ADMIN_USER_ALIAS = 'audadmin';
    public static final String STANDARD_USER_ALIAS = 'audstand';
    public static final String MIN_ACCESS_USER_ALIAS = 'audmin';

    // ============================================================================
    // PLATFORM EVENT FACTORY - TRANSACTION EVENTS
    // ============================================================================

    /**
     * Create a mock transaction audit event for testing.
     *
     * @param transactionId External transaction ID (e.g., 'TXN-001')
     * @param storageMode Storage mode string (CUSTOM_OBJECT, BIG_OBJECT, etc.)
     * @return Mock UoWAuditEvent__e
     */
    public static UoWAuditEvent__e createTransactionEvent(String transactionId, String storageMode) {
        return new UoWAuditEvent__e(
            EventType__c = UoWAuditParameter.EVENT_TYPE_TRANSACTION,
            TransactionId__c = transactionId,
            CorrelationId__c = 'CORR-' + transactionId,
            StorageMode__c = storageMode,
            TransactionStatus__c = 'SUCCESS',
            ConfigurationName__c = 'TestConfig',
            Timestamp__c = System.now()
        );
    }

    /**
     * Create a mock transaction audit event with full details.
     *
     * @param transactionId External transaction ID
     * @param correlationId Correlation ID for transaction chain
     * @param storageMode Storage mode string
     * @param status Transaction status
     * @return Mock UoWAuditEvent__e
     */
    public static UoWAuditEvent__e createTransactionEvent(
        String transactionId,
        String correlationId,
        String storageMode,
        String status
    ) {
        return new UoWAuditEvent__e(
            EventType__c = UoWAuditParameter.EVENT_TYPE_TRANSACTION,
            TransactionId__c = transactionId,
            CorrelationId__c = correlationId,
            StorageMode__c = storageMode,
            TransactionStatus__c = status,
            ConfigurationName__c = 'TestConfig',
            Timestamp__c = System.now()
        );
    }

    // ============================================================================
    // PLATFORM EVENT FACTORY - WORK ITEM EVENTS
    // ============================================================================

    /**
     * Create a mock work item audit event for testing.
     *
     * @param transactionId External transaction ID
     * @param workItemId External work item ID (e.g., 'WORK-001')
     * @param storageMode Storage mode string
     * @return Mock UoWAuditEvent__e
     */
    public static UoWAuditEvent__e createWorkItemEvent(
        String transactionId,
        String workItemId,
        String storageMode
    ) {
        return new UoWAuditEvent__e(
            EventType__c = UoWAuditParameter.EVENT_TYPE_WORK_ITEM,
            TransactionId__c = transactionId,
            CorrelationId__c = 'CORR-' + transactionId,
            WorkId__c = workItemId,
            StorageMode__c = storageMode,
            WorkType__c = 'DML',
            DmlOperation__c = 'INSERT_OP',
            Timestamp__c = System.now()
        );
    }

    /**
     * Create a mock work item audit event with full details.
     *
     * @param transactionId External transaction ID
     * @param correlationId Correlation ID
     * @param workItemId External work item ID
     * @param storageMode Storage mode string
     * @param workType Work type (DML, EVENT, EMAIL, etc.)
     * @return Mock UoWAuditEvent__e
     */
    public static UoWAuditEvent__e createWorkItemEvent(
        String transactionId,
        String correlationId,
        String workItemId,
        String storageMode,
        String workType
    ) {
        return new UoWAuditEvent__e(
            EventType__c = UoWAuditParameter.EVENT_TYPE_WORK_ITEM,
            TransactionId__c = transactionId,
            CorrelationId__c = correlationId,
            WorkId__c = workItemId,
            StorageMode__c = storageMode,
            WorkType__c = workType,
            Timestamp__c = System.now()
        );
    }

    // ============================================================================
    // TRANSACTION RECORD FACTORY
    // ============================================================================

    /**
     * Create a basic mock transaction record.
     *
     * @return Mock UoWAuditTransaction__c with default values
     */
    public static UoWAuditTransaction__c createTransaction() {
        return new UoWAuditTransaction__c(
            TransactionId__c = 'TXN-' + System.now().getTime(),
            CorrelationId__c = 'CORR-' + System.now().getTime(),
            TransactionStatus__c = 'SUCCESS',
            StartTime__c = System.now().addMinutes(-1),
            EndTime__c = System.now(),
            ExecutionTimeMs__c = 150
        );
    }

    /**
     * Create a mock transaction record with specified ID.
     *
     * @param fakeId Fake Salesforce record ID
     * @return Mock UoWAuditTransaction__c
     */
    public static UoWAuditTransaction__c createTransaction(Id fakeId) {
        UoWAuditTransaction__c txn = createTransaction();
        txn.Id = fakeId;
        return txn;
    }

    /**
     * Create a mock transaction record with specified external ID.
     *
     * @param transactionId External transaction ID
     * @return Mock UoWAuditTransaction__c
     */
    public static UoWAuditTransaction__c createTransaction(String transactionId) {
        UoWAuditTransaction__c txn = createTransaction();
        txn.TransactionId__c = transactionId;
        txn.CorrelationId__c = 'CORR-' + transactionId;
        return txn;
    }

    /**
     * Create a mock transaction record with timeline data.
     *
     * @return Mock UoWAuditTransaction__c with compact timeline JSON
     */
    public static UoWAuditTransaction__c createTransactionWithTimeline() {
        UoWAuditTransaction__c txn = createTransaction();
        txn.Timeline__c = getCompactTimelineJson();
        return txn;
    }

    /**
     * Create a mock transaction record with configuration snapshot.
     *
     * @return Mock UoWAuditTransaction__c with configuration data
     */
    public static UoWAuditTransaction__c createTransactionWithConfiguration() {
        UoWAuditTransaction__c txn = createTransaction();
        txn.ConfigurationName__c = 'TestConfig';
        txn.ConfigurationSnapshot__c = '{"enableTracing":true,"securityMode":"ENFORCED"}';
        return txn;
    }

    /**
     * Create a mock transaction record with messages.
     *
     * @return Mock UoWAuditTransaction__c with messages JSON
     */
    public static UoWAuditTransaction__c createTransactionWithMessages() {
        UoWAuditTransaction__c txn = createTransaction();
        txn.Messages__c = getMessagesJson();
        return txn;
    }

    /**
     * Create a mock transaction record with error details.
     *
     * @return Mock UoWAuditTransaction__c with error data
     */
    public static UoWAuditTransaction__c createTransactionWithErrors() {
        UoWAuditTransaction__c txn = createTransaction();
        txn.TransactionStatus__c = 'FAILURE';
        txn.HasErrors__c = true;
        txn.ErrorCount__c = 1;
        txn.ErrorDetails__c = getErrorDetailsJson();
        return txn;
    }

    /**
     * Create a mock transaction record for hierarchy testing.
     *
     * @param transactionId External transaction ID
     * @param correlationId Correlation ID
     * @param parentTransactionId Parent transaction lookup ID (can be null for root)
     * @param asyncDepth Depth in async chain (0 for root)
     * @return Mock UoWAuditTransaction__c
     */
    public static UoWAuditTransaction__c createTransactionForHierarchy(
        String transactionId,
        String correlationId,
        Id parentTransactionId,
        Integer asyncDepth
    ) {
        UoWAuditTransaction__c txn = createTransaction(transactionId);
        txn.CorrelationId__c = correlationId;
        txn.ParentTransaction__c = parentTransactionId;
        txn.AsyncDepth__c = asyncDepth;
        txn.HasChildTransactions__c = false;
        return txn;
    }

    // ============================================================================
    // WORK ITEM RECORD FACTORY
    // ============================================================================

    /**
     * Create a basic mock work item record.
     *
     * @return Mock UoWAuditWorkItem__c with default values
     */
    public static UoWAuditWorkItem__c createWorkItem() {
        return new UoWAuditWorkItem__c(
            Name = 'WORK-' + System.now().getTime(),
            WorkType__c = 'DML',
            WorkItemStatus__c = 'SUCCESS',
            SObjectType__c = 'Account',
            DmlOperation__c = 'INSERT_OP',
            PlannedCount__c = 5,
            ProcessedCount__c = 5,
            SuccessCount__c = 5,
            FailureCount__c = 0,
            ExecutionTimeMs__c = 50
        );
    }

    /**
     * Create a mock work item record with specified ID.
     *
     * @param fakeId Fake Salesforce record ID
     * @return Mock UoWAuditWorkItem__c
     */
    public static UoWAuditWorkItem__c createWorkItem(Id fakeId) {
        UoWAuditWorkItem__c wi = createWorkItem();
        wi.Id = fakeId;
        return wi;
    }

    /**
     * Create a mock work item record with specified work type.
     *
     * @param workType Work type (DML, EVENT, EMAIL, NOTIFICATION, FLOW, CALLOUT)
     * @return Mock UoWAuditWorkItem__c
     */
    public static UoWAuditWorkItem__c createWorkItem(String workType) {
        UoWAuditWorkItem__c wi = createWorkItem();
        wi.WorkType__c = workType;
        return wi;
    }

    /**
     * Create a mock work item record linked to a transaction.
     *
     * @param transactionId Parent transaction record ID
     * @return Mock UoWAuditWorkItem__c
     */
    public static UoWAuditWorkItem__c createWorkItemForTransaction(Id transactionId) {
        UoWAuditWorkItem__c wi = createWorkItem();
        wi.AuditTransaction__c = transactionId;
        return wi;
    }

    /**
     * Create a mock work item record with error details.
     *
     * @return Mock UoWAuditWorkItem__c with error data
     */
    public static UoWAuditWorkItem__c createWorkItemWithErrors() {
        UoWAuditWorkItem__c wi = createWorkItem();
        wi.WorkItemStatus__c = 'PARTIAL_SUCCESS';
        wi.SuccessCount__c = 3;
        wi.FailureCount__c = 2;
        wi.HasErrors__c = true;
        wi.ErrorCount__c = 2;
        wi.ErrorDetails__c = getWorkItemErrorDetailsJson();
        return wi;
    }

    /**
     * Create a mock work item record with snapshot data.
     *
     * @return Mock UoWAuditWorkItem__c with snapshot JSON
     */
    public static UoWAuditWorkItem__c createWorkItemWithSnapshot() {
        UoWAuditWorkItem__c wi = createWorkItem();
        wi.Snapshot__c = getSnapshotJson();
        return wi;
    }

    // ============================================================================
    // JSON DATA HELPERS
    // ============================================================================

    /**
     * Get sample compact timeline JSON for testing.
     *
     * @return Compact timeline JSON string
     */
    public static String getCompactTimelineJson() {
        return '{"td":150,"sc":3,"sp":[' +
            '{"id":1,"n":"Root Span","s":1704067200000,"e":1704067200150,"d":150,"l":1,"p":"TRANSACTION","c":"FRAMEWORK","st":"OK"},' +
            '{"id":2,"pid":1,"n":"DML Phase","s":1704067200010,"e":1704067200100,"d":90,"l":2,"p":"DML_EXECUTION","c":"DML","st":"OK"}' +
            ']}';
    }

    /**
     * Get sample messages JSON for testing.
     *
     * @return Messages JSON string
     */
    public static String getMessagesJson() {
        return '[' +
            '{"timestamp":"' + System.now().format('yyyy-MM-dd\'T\'HH:mm:ss.SSSZ') + '",' +
            '"loggingLevel":"INFO","message":"Transaction started","source":"UnitOfWork"},' +
            '{"timestamp":"' + System.now().format('yyyy-MM-dd\'T\'HH:mm:ss.SSSZ') + '",' +
            '"loggingLevel":"DEBUG","message":"Processing 5 records","source":"UoWDmlWorkItem"}' +
            ']';
    }

    /**
     * Get sample error details JSON for transaction testing.
     *
     * @return Error details JSON string
     */
    public static String getErrorDetailsJson() {
        return '[{' +
            '"errorId":"ERR-001",' +
            '"workItemId":"WORK-001",' +
            '"errorType":"DML_EXCEPTION",' +
            '"errorMessage":"Required field missing: Name",' +
            '"statusCode":"REQUIRED_FIELD_MISSING"' +
            '}]';
    }

    /**
     * Get sample error details JSON for work item testing.
     *
     * @return Work item error details JSON string
     */
    public static String getWorkItemErrorDetailsJson() {
        return '[{' +
            '"errorId":"ERR-WI-001",' +
            '"recordIndex":2,' +
            '"errorType":"VALIDATION_ERROR",' +
            '"errorMessage":"Validation rule failed",' +
            '"statusCode":"FIELD_CUSTOM_VALIDATION_EXCEPTION"' +
            '}]';
    }

    /**
     * Get sample snapshot JSON for work item testing.
     *
     * @return Snapshot JSON string
     */
    public static String getSnapshotJson() {
        return '[{' +
            '"recordType":"Account",' +
            '"recordIndex":0,' +
            '"fields":{"Name":"Test Account","Industry":"Technology"}' +
            '}]';
    }

    // ============================================================================
    // HIERARCHY DATA FACTORY
    // ============================================================================

    /**
     * Create a list of transactions representing a hierarchy.
     * Returns: Root -> Child1, Child2
     *
     * @param correlationId Shared correlation ID
     * @return List of mock transactions forming a hierarchy
     */
    public static List<UoWAuditTransaction__c> createTransactionHierarchy(String correlationId) {
        List<UoWAuditTransaction__c> transactions = new List<UoWAuditTransaction__c>();

        // Create root (no parent)
        Id rootId = UoWTestHelpers.generateFakeId(UoWAuditTransaction__c.SObjectType);
        UoWAuditTransaction__c root = createTransactionForHierarchy(
            'TXN-ROOT', correlationId, null, 0
        );
        root.Id = rootId;
        root.HasChildTransactions__c = true;
        transactions.add(root);

        // Create child 1
        Id child1Id = UoWTestHelpers.generateFakeId(UoWAuditTransaction__c.SObjectType, 2);
        UoWAuditTransaction__c child1 = createTransactionForHierarchy(
            'TXN-CHILD1', correlationId, rootId, 1
        );
        child1.Id = child1Id;
        transactions.add(child1);

        // Create child 2
        Id child2Id = UoWTestHelpers.generateFakeId(UoWAuditTransaction__c.SObjectType, 3);
        UoWAuditTransaction__c child2 = createTransactionForHierarchy(
            'TXN-CHILD2', correlationId, rootId, 1
        );
        child2.Id = child2Id;
        transactions.add(child2);

        return transactions;
    }

    // ============================================================================
    // EVENT LIST FACTORY
    // ============================================================================

    /**
     * Create a list of audit events for a complete transaction.
     * Returns: 1 TRANSACTION event + N WORK_ITEM events
     *
     * @param transactionId External transaction ID
     * @param storageMode Storage mode string
     * @param workItemCount Number of work item events to create
     * @return List of mock UoWAuditEvent__e records
     */
    public static List<UoWAuditEvent__e> createTransactionEvents(
        String transactionId,
        String storageMode,
        Integer workItemCount
    ) {
        List<UoWAuditEvent__e> events = new List<UoWAuditEvent__e>();

        // Add transaction event
        events.add(createTransactionEvent(transactionId, storageMode));

        // Add work item events
        for (Integer i = 0; i < workItemCount; i++) {
            events.add(createWorkItemEvent(
                transactionId,
                'WORK-' + String.valueOf(i + 1).leftPad(3, '0'),
                storageMode
            ));
        }

        return events;
    }

    // ============================================================================
    // TEST USER CREATION WITH PERMISSION SET
    // ============================================================================

    /**
     * Helper method to retrieve the test user with UoWAuditAdmin permission set.
     */
    private static User getAuditAdminUser() {
        return [SELECT Id FROM User WHERE Alias =: ADMIN_USER_ALIAS LIMIT 1];
    }

    /**
     * Helper method to retrieve the test user with UoWAuditAdmin permission set.
     */
    private static User getAuditStandardUser() {
        return [SELECT Id FROM User WHERE Alias =: STANDARD_USER_ALIAS LIMIT 1];
    }

    /**
     * Helper method to retrieve the test user with UoWAuditAdmin permission set.
     */
    private static User getAuditMinAccessUser() {
        return [SELECT Id FROM User WHERE Alias =: MIN_ACCESS_USER_ALIAS LIMIT 1];
    }

    /**
     * Create a test user with the UoWAuditAdmin permission set assigned.
     * This user has full FLS access to UoWAuditTransaction__c and UoWAuditWorkItem__c fields.
     * Required for tests that call methods using WITH USER_MODE queries.
     *
     * @return Test user with UoWAuditAdmin permission set
     */
    public static User createAuditAdminUser() {
        User testUser = createAuditUser(ADMIN_USER_ALIAS, 'Standard User');

        // Assign UoWAuditAdmin permission set
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :PERMISSION_SET_AUDIT_ADMIN LIMIT 1];
        insert new PermissionSetAssignment(
            AssigneeId = testUser.Id,
            PermissionSetId = ps.Id
        );

        return testUser;
    }

    public static User createAuditStandardUser() {
        return createAuditUser(STANDARD_USER_ALIAS, 'Standard User');
    }

    public static User createAuditMinAccessUser() {
        return createAuditUser(MIN_ACCESS_USER_ALIAS, 'Minimum Access - Salesforce');
    }

    public static User createAuditUser(String userAlias, String profileName) {
        String uniqueId = String.valueOf(Datetime.now().getTime());

        // Get Standard User profile
        Profile stdProfile = [SELECT Id FROM Profile WHERE Name =: profileName LIMIT 1];

        User testUser = new User(
            FirstName = 'Audit',
            LastName = userAlias + uniqueId,
            Email = userAlias + uniqueId + '@uow.test.com',
            Username = userAlias + uniqueId + '@uow.test.com',
            Alias = userAlias,
            ProfileId = stdProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert testUser;

        return testUser;
    }
}
