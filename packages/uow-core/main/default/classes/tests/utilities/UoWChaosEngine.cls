//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Chaos Engineering utility for controlled exception injection during tests.
 * Enables deterministic failure injection at specific execution points within the UoW framework,
 * allowing comprehensive error handling testing including complete failures and partial failures.
 *
 * @example Configure failure sequence
 * UoWChaosEngine.addFailure(UoWChaosEngine.Point.DML_INSERT,
 *      new UoWChaosEngine.ChaosDmlException('Simulated validation error'));
 *
 * // Execute test - first insert will fail
 * UnitOfWork uow = new UnitOfWork();
 * uow.registerInsert(acc);
 * UoWResult result = uow.commitWork();
 *
 * // Verify error handling
 * Assert.isTrue(result.hasErrors());
  *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Test Utilities
 * @see UoWTestMocks
 * @see UoWMockResultBuilder
 */
@IsTest
public class UoWChaosEngine {

    private static DmlException cachedInsertDmlException;
    private static EmailException cachedEmailException;

    // Injection points where chaos can be introduced
    public enum Point {
        DML_INSERT,
        DML_UPDATE,
        DML_UPSERT,
        DML_DELETE,
        DML_UNDELETE,
        PLATFORM_EVENT_PUBLISH,
        CUSTOM_NOTIFICATION_SEND,
        EMAIL_SEND,
        CALLOUT,
        FLOW_INVOKE
    }

    // Deterministic failure model: per point, a sequence of exceptions to throw (complete failures)
    private static Boolean enabled = false;
    private static Map<Point, List<Exception>> failuresByPoint = new Map<Point, List<Exception>>();
    private static Map<Point, Integer> indexByPoint = new Map<Point, Integer>();

    // Partial failure model: per point, configuration for mixed success/failure results
    private static Map<Point, PartialFailureConfig> partialFailuresByPoint = new Map<Point, PartialFailureConfig>();

    /**
     * Reset chaos engine to initial state, clearing all configured failures.
     */
    public static void reset() {
        enabled = false;
        failuresByPoint.clear();
        indexByPoint.clear();
        partialFailuresByPoint.clear();
    }

    /**
     * Enable chaos injection. Only functions in test context for safety.
     */
    public static void enable() {
        if (!Test.isRunningTest()) { return; }
        enabled = true;
    }

    /**
     * Disable chaos injection and reset state.
     */
    public static void disable() {
        reset();
    }

    /**
     * Add a failure to the sequence for a specific injection point.
     *
     * @param injectionPoint The injection point
     * @param exceptionToThrow The exception to throw when this point is hit
     */
    public static void addFailure(Point injectionPoint, Exception exceptionToThrow) {
        if (!Test.isRunningTest()) { return; }

        if (!failuresByPoint.containsKey(injectionPoint)) {
            failuresByPoint.put(injectionPoint, new List<Exception>());
            indexByPoint.put(injectionPoint, 0);
        }
        failuresByPoint.get(injectionPoint).add(exceptionToThrow);
    }

    /**
     * Configure a point to always fail with the same exception.
     *
     * @param injectionPoint The injection point
     * @param exceptionToThrow The exception to throw on every hit
     */
    public static void alwaysFail(Point injectionPoint, Exception exceptionToThrow) {
        if (!Test.isRunningTest()) { return; }
        failuresByPoint.put(injectionPoint, new List<Exception>{ exceptionToThrow });
        indexByPoint.put(injectionPoint, 0);
    }

    /**
     * Hit an injection point - throws exception if one is configured.
     *
     * @param injectionPoint The injection point being hit
     * @throws Exception Configured exception for this point in the sequence
     */
    public static void hit(Point injectionPoint) {
        if (!enabled || !Test.isRunningTest()) { return; }
        if (!failuresByPoint.containsKey(injectionPoint)) { return; }

        Integer currentIndex = indexByPoint.get(injectionPoint);
        List<Exception> failureSequence = failuresByPoint.get(injectionPoint);

        if (currentIndex >= failureSequence.size()) {
            return; // no more failures configured for this point
        }

        Exception exceptionToThrow = failureSequence[currentIndex];
        indexByPoint.put(injectionPoint, currentIndex + 1);
        throw exceptionToThrow;
    }

    /**
     * Configure partial failure for an injection point (some records succeed, some fail).
     * Use this for testing continueOnError=true (partial success) scenarios.
     *
     * @param injectionPoint The injection point
     * @param config Configuration for which records fail
     */
    public static void configurePartialFailure(Point injectionPoint, PartialFailureConfig config) {
        if (!Test.isRunningTest()) { return; }
        partialFailuresByPoint.put(injectionPoint, config);
    }

    /**
     * Get partial failure configuration if one exists (doesn't throw exception).
     *
     * @param injectionPoint The injection point to check
     * @return PartialFailureConfig or null if not configured
     */
    public static PartialFailureConfig getPartialFailureConfig(Point injectionPoint) {
        if (!enabled || !Test.isRunningTest()) { return null; }
        return partialFailuresByPoint.get(injectionPoint);
    }

    // purposely induced actual exception types for classification in the framework:

    /**
     * Generate a genuine DmlException for realistic testing by attempting invalid DML.
     *
     * @return DmlException A real DmlException from a failed DML Insert operation
     */
    public static DmlException sampleInsertDmlException() {
        if (cachedInsertDmlException == null){
            try {
                insert new Account(); // will fail on required Name
                return null;
            } catch (DmlException dmlEx) {
                cachedInsertDmlException = dmlEx;
            }
        }

        return cachedInsertDmlException;
    }

    /**
     * Generate a genuine EmailException for realistic testing by attempting invalid email send.
     *
     * @return EmailException A real EmailException from a failed email send operation
     */
    public static EmailException sampleEmailException() {
        if (cachedEmailException == null){
            try {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email }); // will fail on required field
                return null;
            } catch (EmailException emailEx) {
                cachedEmailException = emailEx;
            }
        }

        return cachedEmailException;
    }

    // Chaos-specific exception families for classification in the framework

    // DML-related chaos exception
    public class ChaosDmlException extends Exception {}

    // Channel-related chaos exception (events, emails, notifications)
    public class ChaosChannelException extends Exception {}

    // Callout-related chaos exception
    public class ChaosCalloutException extends Exception {}

    // Flow-related chaos exception
    public class ChaosFlowException extends Exception {}

    // Generic chaos exception
    public class ChaosGenericException extends Exception {}

    /**
     * Configuration for partial failure scenarios (mixed success/failure).
     * Used to test continueOnError=true behavior where some records succeed and others fail.
     */
    public class PartialFailureConfig {
        // Which record indexes fail (0-based)
        public List<Integer> failureIndexes;
        // Error message for failed records
        public String failureMessage;
        // Type-safe StatusCode enum (nullable for email/notification errors)
        public System.StatusCode statusCode;

        /**
         * Create partial failure configuration for DML operations.
         *
         * @param failureIndexes List of 0-based indexes that should fail
         * @param failureMessage Error message for failed records
         * @param statusCode StatusCode enum for failed records
         */
        public PartialFailureConfig(List<Integer> failureIndexes, String failureMessage, System.StatusCode statusCode) {
            this.failureIndexes = failureIndexes ?? new List<Integer>();
            this.failureMessage = failureMessage;
            this.statusCode = statusCode;
        }

        /**
         * Create partial failure configuration for Email/Notification operations (no StatusCode).
         *
         * @param failureIndexes List of 0-based indexes that should fail
         * @param failureMessage Error message for failed records
         */
        public PartialFailureConfig(List<Integer> failureIndexes, String failureMessage) {
            this(failureIndexes, failureMessage, null);
        }
    }
}