//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Retry configuration for work items (callouts, etc.).
 * Value object that defines retry behavior - immutable after creation.
 * Core package stores this configuration; extensions package implements actual retry logic.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Core
 * @see UoWRetryConfigs
 * @see UoWCalloutWorkItem
 */
public inherited sharing class UoWRetryConfig {

    // ============================================================================
    // PUBLIC PROPERTIES - RETRY LIMITS
    // ============================================================================

    // Maximum number of retry attempts (excludes initial attempt)
    public Integer maxRetries { get; private set; }

    // ============================================================================
    // PUBLIC PROPERTIES - DELAY CONFIGURATION
    // ============================================================================

    // Base delay between retries in milliseconds
    public Integer baseDelayMs { get; private set; }

    // Maximum delay cap in milliseconds (prevents excessive waits)
    public Integer maxDelayMs { get; private set; }

    // Multiplier for exponential backoff (e.g., 2.0 doubles delay each retry)
    public Decimal backoffMultiplier { get; private set; }

    // ============================================================================
    // PUBLIC PROPERTIES - RETRYABLE CONDITIONS
    // ============================================================================

    // HTTP status codes that should trigger retry (e.g., 429, 500, 502, 503, 504)
    public Set<Integer> retryableStatusCodes { get; private set; }

    // ============================================================================
    // PUBLIC PROPERTIES - JITTER CONFIGURATION
    // ============================================================================

    // Whether to add jitter to delay (prevents thundering herd)
    public Boolean enableJitter { get; private set; }

    // Maximum jitter percentage (0.0 to 1.0)
    public Decimal jitterPercent { get; private set; }

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    // Private constructor - use builder or factory methods
    private UoWRetryConfig() {
        this.maxRetries = 3;
        this.baseDelayMs = 1000;
        this.maxDelayMs = 30000;
        this.backoffMultiplier = 2.0;
        this.retryableStatusCodes = new Set<Integer>(UoWCoreParameter.RETRYABLE_STATUS_CODES);
        this.enableJitter = true;
        this.jitterPercent = 0.25;
    }

    // ============================================================================
    // PUBLIC API - BUILDER PATTERN
    // ============================================================================

    /**
     * Create a new builder for fluent configuration.
     *
     * @return Builder instance
     */
    public static Builder builder() {
        return new Builder();
    }

    // ============================================================================
    // PUBLIC API - DELAY CALCULATION
    // ============================================================================

    /**
     * Calculate delay for a specific retry attempt.
     *
     * @param attemptNumber Attempt number (1-based: 1st retry, 2nd retry, etc.)
     * @return Delay in milliseconds
     */
    public Integer calculateDelay(Integer attemptNumber) {
        Double multiplierPow = Math.pow(this.backoffMultiplier.doubleValue(), attemptNumber - 1);
        Decimal delay = this.baseDelayMs * multiplierPow;

        delay = Math.min(delay, this.maxDelayMs);

        if (this.enableJitter && this.jitterPercent > 0) {
            Decimal jitter = (Math.random() * 2 - 1) * this.jitterPercent;
            delay = delay * (1 + jitter);
        }

        return Integer.valueOf(Math.round(delay));
    }

    // ============================================================================
    // PUBLIC API - RETRYABILITY CHECKS
    // ============================================================================

    /**
     * Check if a status code is retryable.
     *
     * @param statusCode HTTP status code
     * @return True if should retry
     */
    public Boolean isRetryableStatusCode(Integer statusCode) {
        return this.retryableStatusCodes != null && this.retryableStatusCodes.contains(statusCode);
    }

    /**
     * Check if an exception type is retryable (timeout, connection refused, etc.).
     *
     * @param ex The exception to check
     * @return True if should retry
     */
    public Boolean isRetryableException(Exception ex) {
        if (ex == null) {
            return false;
        }

        if (ex instanceof CalloutException) {
            String message = ex.getMessage().toLowerCase();
            return message.contains('timeout') ||
                   message.contains('connection') ||
                   message.contains('timed out') ||
                   message.contains('unable to connect');
        }

        return false;
    }

    // ============================================================================
    // PUBLIC API - DEBUG
    // ============================================================================

    /**
     * Get string representation for debugging.
     *
     * @return String representation
     */
    public override String toString() {
        return String.format(
            'UoWRetryConfig[maxRetries={0}, baseDelayMs={1}, maxDelayMs={2}, backoffMultiplier={3}, jitter={4}]',
            new String[]{
                String.valueOf(this.maxRetries),
                String.valueOf(this.baseDelayMs),
                String.valueOf(this.maxDelayMs),
                String.valueOf(this.backoffMultiplier),
                String.valueOf(this.enableJitter)
            }
        );
    }

    // ============================================================================
    // INNER CLASSES - BUILDER
    // ============================================================================

    /**
     * Builder class for fluent retry configuration.
     */
    public class Builder {

        // ============================================================================
        // PRIVATE PROPERTIES
        // ============================================================================

        private UoWRetryConfig config;

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        // Initialize builder with default config
        public Builder() {
            this.config = new UoWRetryConfig();
        }

        // ============================================================================
        // PUBLIC API - RETRY LIMITS
        // ============================================================================

        /**
         * Set maximum retry attempts.
         *
         * @param maxRetries Maximum retries (excludes initial attempt)
         * @return This builder for chaining
         */
        public Builder withMaxRetries(Integer maxRetries) {
            this.config.maxRetries = maxRetries;
            return this;
        }

        // ============================================================================
        // PUBLIC API - DELAY CONFIGURATION
        // ============================================================================

        /**
         * Set base delay between retries.
         *
         * @param delayMs Delay in milliseconds
         * @return This builder for chaining
         */
        public Builder withBaseDelay(Integer delayMs) {
            this.config.baseDelayMs = delayMs;
            return this;
        }

        /**
         * Set maximum delay cap.
         *
         * @param delayMs Maximum delay in milliseconds
         * @return This builder for chaining
         */
        public Builder withMaxDelay(Integer delayMs) {
            this.config.maxDelayMs = delayMs;
            return this;
        }

        /**
         * Set backoff multiplier for exponential backoff.
         *
         * @param multiplier Multiplier (e.g., 2.0 doubles delay each retry)
         * @return This builder for chaining
         */
        public Builder withBackoffMultiplier(Decimal multiplier) {
            this.config.backoffMultiplier = multiplier;
            return this;
        }

        // ============================================================================
        // PUBLIC API - RETRYABLE CONDITIONS
        // ============================================================================

        /**
         * Set HTTP status codes that trigger retry.
         *
         * @param statusCodes Set of retryable status codes
         * @return This builder for chaining
         */
        public Builder withRetryableStatusCodes(Set<Integer> statusCodes) {
            this.config.retryableStatusCodes = statusCodes;
            return this;
        }

        /**
         * Add additional retryable status codes.
         *
         * @param statusCodes Additional status codes to add
         * @return This builder for chaining
         */
        public Builder addRetryableStatusCodes(Set<Integer> statusCodes) {
            this.config.retryableStatusCodes.addAll(statusCodes);
            return this;
        }

        // ============================================================================
        // PUBLIC API - JITTER CONFIGURATION
        // ============================================================================

        /**
         * Enable or disable jitter.
         *
         * @param enable True to enable jitter
         * @return This builder for chaining
         */
        public Builder withJitter(Boolean enable) {
            this.config.enableJitter = enable;
            return this;
        }

        /**
         * Set jitter percentage.
         *
         * @param percent Jitter percentage (0.0 to 1.0)
         * @return This builder for chaining
         */
        public Builder withJitterPercent(Decimal percent) {
            this.config.jitterPercent = percent;
            return this;
        }

        // ============================================================================
        // PUBLIC API - BUILD
        // ============================================================================

        /**
         * Build the retry configuration.
         *
         * @return Immutable UoWRetryConfig instance
         */
        public UoWRetryConfig build() {
            UoWExceptionService.require(this.config.maxRetries >= 0, 'maxRetries must be >= 0');
            UoWExceptionService.require(this.config.baseDelayMs >= 0, 'baseDelayMs must be >= 0');
            UoWExceptionService.require(this.config.maxDelayMs >= this.config.baseDelayMs, 'maxDelayMs must be >= baseDelayMs');
            UoWExceptionService.require(this.config.backoffMultiplier >= 1.0, 'backoffMultiplier must be >= 1.0');
            UoWExceptionService.require(this.config.jitterPercent >= 0 && this.config.jitterPercent <= 1.0, 'jitterPercent must be between 0.0 and 1.0');

            return this.config;
        }
    }
}