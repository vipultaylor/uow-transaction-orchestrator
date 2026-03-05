//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Builder for creating mock Database and Messaging result objects via JSON deserialization.
 * Provides clean, reusable methods for test mocks to simulate success/failure scenarios.
 * Uses JSON.deserialize() to create non-instantiable result objects.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Test Utilities
 * @see UoWTestMocks
 * @see UoWChaosEngine
 */
@isTest
public class UoWMockResultBuilder {

    // ============================================================================
    // DATABASE.SAVERESULT (DML INSERT/UPDATE)
    // ============================================================================

    /**
     * Create successful SaveResult objects with fake IDs for DML insert/update operations.
     *
     * @param records Records to generate results for (IDs will be assigned)
     * @return List of successful SaveResult objects
     */
    public static List<Database.SaveResult> createSuccessfulSaveResults(List<SObject> records) {
        List<Database.SaveResult> results = new List<Database.SaveResult>();
        Integer counter = 0;

        for (SObject record : records) {
            String fakeId = UoWTestHelpers.generateFakeId(record.getSObjectType(), counter);
            record.put('Id', fakeId);

            MockSaveResult mock = new MockSaveResult();
            mock.success = true;
            mock.id = fakeId;

            String jsonString = JSON.serialize(mock);
            Database.SaveResult sr = (Database.SaveResult) JSON.deserialize(jsonString, Database.SaveResult.class);
            results.add(sr);
            counter++;
        }

        return results;
    }

    /**
     * Create failed SaveResult objects.
     *
     * @param count Number of failed results to create
     * @param errorMessage Error message for failures
     * @param statusCode Status code for failures
     * @return List of failed SaveResult objects
     */
    public static List<Database.SaveResult> createFailedSaveResults(
        Integer count,
        String errorMessage,
        String statusCode
    ) {
        List<Database.SaveResult> results = new List<Database.SaveResult>();

        for (Integer i = 0; i < count; i++) {
            MockSaveResult mock = new MockSaveResult();
            mock.success = false;
            mock.errors = new List<MockDatabaseError>();

            MockDatabaseError error = new MockDatabaseError();
            error.message = errorMessage;
            error.statusCode = statusCode;
            mock.errors.add(error);

            String jsonString = JSON.serialize(mock);
            Database.SaveResult sr = (Database.SaveResult) JSON.deserialize(jsonString, Database.SaveResult.class);
            results.add(sr);
        }

        return results;
    }

    /**
     * Create partial SaveResult objects (some succeed, some fail).
     * Used for continueOnError=true (partial success) testing.
     *
     * @param records Records to generate results for
     * @param failureIndexes Indexes of records that should fail
     * @param errorMessage Error message for failed records
     * @param statusCode Status code for failed records
     * @return List of partial SaveResult objects
     */
    public static List<Database.SaveResult> createPartialSaveResults(
        List<SObject> records,
        List<Integer> failureIndexes,
        String errorMessage,
        System.StatusCode statusCode
    ) {
        List<Database.SaveResult> results = new List<Database.SaveResult>();
        Integer counter = 0;

        for (Integer i = 0; i < records.size(); i++) {
            SObject record = records[i];

            if (failureIndexes.contains(i)) {
                // This record fails
                MockSaveResult mock = new MockSaveResult();
                mock.success = false;
                mock.errors = new List<MockDatabaseError>();

                MockDatabaseError error = new MockDatabaseError();
                error.message = errorMessage;
                error.statusCode = statusCode.name();  // Convert enum to string for JSON serialization
                error.fields = new List<String>();  // Empty fields list
                mock.errors.add(error);

                String jsonString = JSON.serialize(mock);
                Database.SaveResult sr = (Database.SaveResult) JSON.deserialize(jsonString, Database.SaveResult.class);
                results.add(sr);
            } else {
                // This record succeeds
                String fakeId = UoWTestHelpers.generateFakeId(record.getSObjectType(), counter);
                record.put('Id', fakeId);

                MockSaveResult mock = new MockSaveResult();
                mock.success = true;
                mock.id = fakeId;

                String jsonString = JSON.serialize(mock);
                Database.SaveResult sr = (Database.SaveResult) JSON.deserialize(jsonString, Database.SaveResult.class);
                results.add(sr);
                counter++;
            }
        }

        return results;
    }

    // ============================================================================
    // DATABASE.UPSERTRESULT
    // ============================================================================

    /**
     * Create successful UpsertResult objects.
     *
     * @param records Records to generate results for
     * @return List of successful UpsertResult objects
     */
    public static List<Database.UpsertResult> createSuccessfulUpsertResults(List<SObject> records) {
        List<Database.UpsertResult> results = new List<Database.UpsertResult>();
        Integer counter = 0;

        for (SObject record : records) {
            Boolean isInsert = record.Id == null;
            String fakeId = null;

            if (isInsert) {
                fakeId = UoWTestHelpers.generateFakeId(record.getSObjectType(), counter);
                record.put('Id', fakeId);
            } else {
                fakeId = record.Id;
            }

            MockUpsertResult mock = new MockUpsertResult();
            mock.success = true;
            mock.created = isInsert;
            mock.id = fakeId;

            String jsonString = JSON.serialize(mock);
            Database.UpsertResult ur = (Database.UpsertResult) JSON.deserialize(jsonString, Database.UpsertResult.class);
            results.add(ur);
            counter++;
        }

        return results;
    }

    /**
     * Create failed UpsertResult objects.
     *
     * @param count Number of failed results to create
     * @param errorMessage Error message for failures
     * @param statusCode Status code for failures
     * @return List of failed UpsertResult objects
     */
    public static List<Database.UpsertResult> createFailedUpsertResults(
        Integer count,
        String errorMessage,
        String statusCode
    ) {
        List<Database.UpsertResult> results = new List<Database.UpsertResult>();

        for (Integer i = 0; i < count; i++) {
            MockUpsertResult mock = new MockUpsertResult();
            mock.success = false;
            mock.created = false;
            mock.errors = new List<MockDatabaseError>();

            MockDatabaseError error = new MockDatabaseError();
            error.message = errorMessage;
            error.statusCode = statusCode;
            mock.errors.add(error);

            String jsonString = JSON.serialize(mock);
            Database.UpsertResult ur = (Database.UpsertResult) JSON.deserialize(jsonString, Database.UpsertResult.class);
            results.add(ur);
        }

        return results;
    }

    /**
     * Create partial UpsertResult objects (some succeed, some fail).
     * Used for continueOnError=true (partial success) testing.
     *
     * @param records Records to generate results for
     * @param failureIndexes Indexes of records that should fail
     * @param errorMessage Error message for failed records
     * @param statusCode Status code for failed records
     * @return List of partial UpsertResult objects
     */
    public static List<Database.UpsertResult> createPartialUpsertResults(
        List<SObject> records,
        List<Integer> failureIndexes,
        String errorMessage,
        System.StatusCode statusCode
    ) {
        List<Database.UpsertResult> results = new List<Database.UpsertResult>();
        Integer counter = 0;

        for (Integer i = 0; i < records.size(); i++) {
            SObject record = records[i];

            if (failureIndexes.contains(i)) {
                // This record fails
                MockUpsertResult mock = new MockUpsertResult();
                mock.success = false;
                mock.created = false;
                mock.errors = new List<MockDatabaseError>();

                MockDatabaseError error = new MockDatabaseError();
                error.message = errorMessage;
                error.statusCode = statusCode.name();  // Convert enum to string for JSON serialization
                error.fields = new List<String>();  // Empty fields list
                mock.errors.add(error);

                String jsonString = JSON.serialize(mock);
                Database.UpsertResult ur = (Database.UpsertResult) JSON.deserialize(jsonString, Database.UpsertResult.class);
                results.add(ur);
            } else {
                // This record succeeds
                Boolean isInsert = record.Id == null;
                String fakeId = null;

                if (isInsert) {
                    fakeId = UoWTestHelpers.generateFakeId(record.getSObjectType(), counter);
                    record.put('Id', fakeId);
                } else {
                    fakeId = record.Id;
                }

                MockUpsertResult mock = new MockUpsertResult();
                mock.success = true;
                mock.created = isInsert;
                mock.id = fakeId;

                String jsonString = JSON.serialize(mock);
                Database.UpsertResult ur = (Database.UpsertResult) JSON.deserialize(jsonString, Database.UpsertResult.class);
                results.add(ur);
                counter++;
            }
        }

        return results;
    }

    // ============================================================================
    // DATABASE.DELETERESULT
    // ============================================================================

    /**
     * Create successful DeleteResult objects.
     *
     * @param records Records to generate results for
     * @return List of successful DeleteResult objects
     */
    public static List<Database.DeleteResult> createSuccessfulDeleteResults(List<SObject> records) {
        List<Database.DeleteResult> results = new List<Database.DeleteResult>();

        for (SObject record : records) {
            String recordId = record.Id ?? '';

            MockDeleteResult mock = new MockDeleteResult();
            mock.success = true;
            mock.id = recordId;

            String jsonString = JSON.serialize(mock);
            Database.DeleteResult dr = (Database.DeleteResult) JSON.deserialize(jsonString, Database.DeleteResult.class);
            results.add(dr);
        }

        return results;
    }

    /**
     * Create failed DeleteResult objects.
     *
     * @param count Number of failed results to create
     * @param errorMessage Error message for failures
     * @param statusCode Status code for failures
     * @return List of failed DeleteResult objects
     */
    public static List<Database.DeleteResult> createFailedDeleteResults(
        Integer count,
        String errorMessage,
        String statusCode
    ) {
        List<Database.DeleteResult> results = new List<Database.DeleteResult>();

        for (Integer i = 0; i < count; i++) {
            MockDeleteResult mock = new MockDeleteResult();
            mock.success = false;
            mock.errors = new List<MockDatabaseError>();

            MockDatabaseError error = new MockDatabaseError();
            error.message = errorMessage;
            error.statusCode = statusCode;
            mock.errors.add(error);

            String jsonString = JSON.serialize(mock);
            Database.DeleteResult dr = (Database.DeleteResult) JSON.deserialize(jsonString, Database.DeleteResult.class);
            results.add(dr);
        }

        return results;
    }

    /**
     * Create partial DeleteResult objects (some succeed, some fail).
     * Used for continueOnError=true (partial success) testing.
     *
     * @param records Records to generate results for
     * @param failureIndexes Indexes of records that should fail
     * @param errorMessage Error message for failed records
     * @param statusCode Status code for failed records
     * @return List of partial DeleteResult objects
     */
    public static List<Database.DeleteResult> createPartialDeleteResults(
        List<SObject> records,
        List<Integer> failureIndexes,
        String errorMessage,
        System.StatusCode statusCode
    ) {
        List<Database.DeleteResult> results = new List<Database.DeleteResult>();

        for (Integer i = 0; i < records.size(); i++) {
            SObject record = records[i];

            if (failureIndexes.contains(i)) {
                // This record fails
                MockDeleteResult mock = new MockDeleteResult();
                mock.success = false;
                mock.errors = new List<MockDatabaseError>();

                MockDatabaseError error = new MockDatabaseError();
                error.message = errorMessage;
                error.statusCode = statusCode.name();  // Convert enum to string for JSON serialization
                error.fields = new List<String>();  // Empty fields list
                mock.errors.add(error);

                String jsonString = JSON.serialize(mock);
                Database.DeleteResult dr = (Database.DeleteResult) JSON.deserialize(jsonString, Database.DeleteResult.class);
                results.add(dr);
            } else {
                // This record succeeds
                MockDeleteResult mock = new MockDeleteResult();
                mock.success = true;
                mock.id = record.Id;

                String jsonString = JSON.serialize(mock);
                Database.DeleteResult dr = (Database.DeleteResult) JSON.deserialize(jsonString, Database.DeleteResult.class);
                results.add(dr);
            }
        }

        return results;
    }

    // ============================================================================
    // DATABASE.UNDELETERESULT
    // ============================================================================

    /**
     * Create successful UndeleteResult objects.
     *
     * @param records Records to generate results for
     * @return List of successful UndeleteResult objects
     */
    public static List<Database.UndeleteResult> createSuccessfulUndeleteResults(List<SObject> records) {
        List<Database.UndeleteResult> results = new List<Database.UndeleteResult>();

        for (SObject record : records) {
            String recordId = record.Id ?? '';

            MockUndeleteResult mock = new MockUndeleteResult();
            mock.success = true;
            mock.id = recordId;

            String jsonString = JSON.serialize(mock);
            Database.UndeleteResult udr = (Database.UndeleteResult) JSON.deserialize(jsonString, Database.UndeleteResult.class);
            results.add(udr);
        }

        return results;
    }

    /**
     * Create failed UndeleteResult objects.
     *
     * @param count Number of failed results to create
     * @param errorMessage Error message for failures
     * @param statusCode Status code for failures
     * @return List of failed UndeleteResult objects
     */
    public static List<Database.UndeleteResult> createFailedUndeleteResults(
        Integer count,
        String errorMessage,
        String statusCode
    ) {
        List<Database.UndeleteResult> results = new List<Database.UndeleteResult>();

        for (Integer i = 0; i < count; i++) {
            MockUndeleteResult mock = new MockUndeleteResult();
            mock.success = false;
            mock.errors = new List<MockDatabaseError>();

            MockDatabaseError error = new MockDatabaseError();
            error.message = errorMessage;
            error.statusCode = statusCode;
            mock.errors.add(error);

            String jsonString = JSON.serialize(mock);
            Database.UndeleteResult udr = (Database.UndeleteResult) JSON.deserialize(jsonString, Database.UndeleteResult.class);
            results.add(udr);
        }

        return results;
    }

    /**
     * Create partial UndeleteResult objects (some succeed, some fail).
     * Used for continueOnError=true (partial success) testing.
     *
     * @param records Records to generate results for
     * @param failureIndexes Indexes of records that should fail
     * @param errorMessage Error message for failed records
     * @param statusCode Status code for failed records
     * @return List of partial UndeleteResult objects
     */
    public static List<Database.UndeleteResult> createPartialUndeleteResults(
        List<SObject> records,
        List<Integer> failureIndexes,
        String errorMessage,
        System.StatusCode statusCode
    ) {
        List<Database.UndeleteResult> results = new List<Database.UndeleteResult>();

        for (Integer i = 0; i < records.size(); i++) {
            SObject record = records[i];

            if (failureIndexes.contains(i)) {
                // This record fails
                MockUndeleteResult mock = new MockUndeleteResult();
                mock.success = false;
                mock.errors = new List<MockDatabaseError>();

                MockDatabaseError error = new MockDatabaseError();
                error.message = errorMessage;
                error.statusCode = statusCode.name();  // Convert enum to string for JSON serialization
                error.fields = new List<String>();  // Empty fields list
                mock.errors.add(error);

                String jsonString = JSON.serialize(mock);
                Database.UndeleteResult udr = (Database.UndeleteResult) JSON.deserialize(jsonString, Database.UndeleteResult.class);
                results.add(udr);
            } else {
                // This record succeeds
                MockUndeleteResult mock = new MockUndeleteResult();
                mock.success = true;
                mock.id = record.Id;

                String jsonString = JSON.serialize(mock);
                Database.UndeleteResult udr = (Database.UndeleteResult) JSON.deserialize(jsonString, Database.UndeleteResult.class);
                results.add(udr);
            }
        }

        return results;
    }

    // ============================================================================
    // DATABASE.SAVERESULT (PLATFORM EVENTS)
    // ============================================================================

    /**
     * Create successful SaveResult objects with fake IDs for platform events.
     *
     * @param records Platform event records to generate results for
     * @return List of successful SaveResult objects
     */
    public static List<Database.SaveResult> createSuccessfulPublishResults(List<SObject> records) {
        List<Database.SaveResult> results = new List<Database.SaveResult>();
        Integer counter = 0;

        for (SObject record : records) {
            String fakeId = UoWTestHelpers.generateFakeId(record.getSObjectType(), counter);
            record.put('Id', fakeId);

            MockSaveResult mock = new MockSaveResult();
            mock.success = true;
            mock.id = fakeId;
            mock.errors = new List<MockDatabaseError>();

            String jsonString = JSON.serialize(mock);
            Database.SaveResult sr = (Database.SaveResult) JSON.deserialize(jsonString, Database.SaveResult.class);
            results.add(sr);
            counter++;
        }

        return results;
    }

    /**
     * Create partial SaveResult objects for platform events (some succeed, some fail).
     * Used for continueOnError=true (partial success) testing.
     *
     * @param records Platform event records to generate results for
     * @param failureIndexes Indexes of records that should fail
     * @param errorMessage Error message for failed records
     * @param statusCode Status code for failed records
     * @return List of partial SaveResult objects
     */
    public static List<Database.SaveResult> createPartialPublishResults(
        List<SObject> records,
        List<Integer> failureIndexes,
        String errorMessage,
        System.StatusCode statusCode
    ) {
        List<Database.SaveResult> results = new List<Database.SaveResult>();
        Integer counter = 0;

        for (Integer i = 0; i < records.size(); i++) {
            SObject record = records[i];

            if (failureIndexes.contains(i)) {
                // This record fails
                MockSaveResult mock = new MockSaveResult();
                mock.success = false;
                mock.errors = new List<MockDatabaseError>();

                MockDatabaseError error = new MockDatabaseError();
                error.message = errorMessage;
                error.statusCode = statusCode.name();  // Convert enum to string for JSON serialization
                error.fields = new List<String>();  // Empty fields list
                mock.errors.add(error);

                String jsonString = JSON.serialize(mock);
                Database.SaveResult sr = (Database.SaveResult) JSON.deserialize(jsonString, Database.SaveResult.class);
                results.add(sr);
            } else {
                // This record succeeds
                String fakeId = UoWTestHelpers.generateFakeId(record.getSObjectType(), counter);
                record.put('Id', fakeId);

                MockSaveResult mock = new MockSaveResult();
                mock.success = true;
                mock.id = fakeId;
                mock.errors = new List<MockDatabaseError>();

                String jsonString = JSON.serialize(mock);
                Database.SaveResult sr = (Database.SaveResult) JSON.deserialize(jsonString, Database.SaveResult.class);
                results.add(sr);
                counter++;
            }
        }

        return results;
    }

    // ============================================================================
    // MESSAGING.SENDEMAILRESULT
    // ============================================================================

    /**
     * Create successful SendEmailResult.
     *
     * @return Successful SendEmailResult
     */
    public static Messaging.SendEmailResult createSuccessfulEmailResult() {
        MockSendEmailResult mock = new MockSendEmailResult();
        mock.success = true;
        mock.errors = new List<MockSendEmailError>();

        String jsonString = JSON.serialize(mock);
        return (Messaging.SendEmailResult) JSON.deserialize(jsonString, Messaging.SendEmailResult.class);
    }

    /**
     * Create failed SendEmailResult.
     *
     * @param errorMessage Error message for failure
     * @return Failed SendEmailResult
     */
    public static Messaging.SendEmailResult createFailedEmailResult(String errorMessage) {
        MockSendEmailResult mock = new MockSendEmailResult();
        mock.success = false;
        mock.errors = new List<MockSendEmailError>();

        String jsonString = JSON.serialize(mock);
        Messaging.SendEmailResult result = (Messaging.SendEmailResult) JSON.deserialize(jsonString, Messaging.SendEmailResult.class);

        //Explicitly deserializing an email error
        MockSendEmailError error = new MockSendEmailError();
        error.message = errorMessage;
        error.statusCode = 'INVALID_EMAIL_ADDRESS';  // Add default status code
        Messaging.SendEmailError emailError = (Messaging.SendEmailError) JSON.deserialize(JSON.serialize(error), Messaging.SendEmailError.class);

        //Add the error to the result
        result.getErrors().add(emailError);

        return result;
    }

    /**
     * Create list of successful SendEmailResults.
     *
     * @param count Number of successful results to create
     * @return List of successful SendEmailResults
     */
    public static List<Messaging.SendEmailResult> createSuccessfulEmailResults(Integer count) {
        List<Messaging.SendEmailResult> results = new List<Messaging.SendEmailResult>();
        for (Integer i = 0; i < count; i++) {
            results.add(createSuccessfulEmailResult());
        }
        return results;
    }

    /**
     * Create list of failed SendEmailResults.
     *
     * @param count Number of failed results to create
     * @param errorMessage Error message for failures
     * @return List of failed SendEmailResults
     */
    public static List<Messaging.SendEmailResult> createFailedEmailResults(Integer count, String errorMessage) {
        List<Messaging.SendEmailResult> results = new List<Messaging.SendEmailResult>();
        for (Integer i = 0; i < count; i++) {
            results.add(createFailedEmailResult(errorMessage));
        }
        return results;
    }

    /**
     * Create partial SendEmailResults (some succeed, some fail).
     * Used for allOrNone=false email testing.
     *
     * @param totalCount Total number of email results to create
     * @param failureIndexes Indexes of emails that should fail
     * @param errorMessage Error message for failed emails
     * @return List of partial SendEmailResults
     */
    public static List<Messaging.SendEmailResult> createPartialEmailResults(
        Integer totalCount,
        List<Integer> failureIndexes,
        String errorMessage
    ) {
        List<Messaging.SendEmailResult> results = new List<Messaging.SendEmailResult>();

        for (Integer i = 0; i < totalCount; i++) {
            if (failureIndexes.contains(i)) {
                // This email fails
                results.add(createFailedEmailResult(errorMessage));
            } else {
                // This email succeeds
                results.add(createSuccessfulEmailResult());
            }
        }

        return results;
    }

    // ============================================================================
    // MOCK RESULT CLASSES - Match Result Structures
    // ============================================================================

    /**
     * Mock SaveResult structure for JSON serialization.
     */
    private class MockSaveResult {
        public Boolean success;
        public String id;
        public List<MockDatabaseError> errors;
    }

    /**
     * Mock UpsertResult structure for JSON serialization.
     */
    private class MockUpsertResult {
        public Boolean success;
        public Boolean created;
        public String id;
        public List<MockDatabaseError> errors;
    }

    /**
     * Mock DeleteResult structure for JSON serialization.
     */
    private class MockDeleteResult {
        public Boolean success;
        public String id;
        public List<MockDatabaseError> errors;
    }

    /**
     * Mock UndeleteResult structure for JSON serialization.
     */
    private class MockUndeleteResult {
        public Boolean success;
        public String id;
        public List<MockDatabaseError> errors;
    }

    /**
     * Mock Database.Error structure for JSON serialization.
     */
    private class MockDatabaseError {
        public String message;
        public String statusCode;  // Salesforce StatusCode enum name as string
        public List<String> fields;

        // Note: When JSON.deserialize reconstructs Database.Error, the statusCode string
        // is automatically converted to System.StatusCode enum by Salesforce
    }

    /**
     * Mock SendEmailResult structure for JSON serialization.
     */
    private class MockSendEmailResult {
        public Boolean success;
        public List<MockSendEmailError> errors;
    }

    /**
     * Mock SendEmailError structure for JSON serialization.
     */
    private class MockSendEmailError {
        public String message;
        public String statusCode;
        public List<String> fields;
    }
}