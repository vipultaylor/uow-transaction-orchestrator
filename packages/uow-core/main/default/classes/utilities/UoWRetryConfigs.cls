//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Factory class providing common retry configuration presets.
 * Use these presets for standard retry scenarios or as starting points for custom configs.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Core
 * @see UoWRetryConfig
 */
public inherited sharing class UoWRetryConfigs {

    // ============================================================================
    // PRESET CONFIGURATIONS
    // ============================================================================

    /**
     * No retry configuration (single attempt only).
     * Use when retries are not desired.
     *
     * @return Retry config with maxRetries=0
     */
    public static UoWRetryConfig none() {
        return UoWRetryConfig.builder()
            .withMaxRetries(0)
            .build();
    }

    /**
     * Quick retry for transient failures.
     * 3 retries, 500ms base delay, 2x backoff.
     * Good for APIs with occasional hiccups.
     *
     * @return Quick retry configuration
     */
    public static UoWRetryConfig quick() {
        return UoWRetryConfig.builder()
            .withMaxRetries(3)
            .withBaseDelay(500)
            .withMaxDelay(5000)
            .withBackoffMultiplier(2.0)
            .withJitter(true)
            .build();
    }

    /**
     * Standard retry configuration.
     * 3 retries, 1s base delay, 2x backoff, up to 30s.
     * Default balanced configuration for most APIs.
     *
     * @return Standard retry configuration
     */
    public static UoWRetryConfig standard() {
        return UoWRetryConfig.builder()
            .withMaxRetries(3)
            .withBaseDelay(1000)
            .withMaxDelay(30000)
            .withBackoffMultiplier(2.0)
            .withJitter(true)
            .build();
    }

    /**
     * Aggressive retry for critical operations.
     * 5 retries, 2s base delay, 2x backoff, up to 60s.
     * Use for critical operations that must succeed.
     *
     * @return Aggressive retry configuration
     */
    public static UoWRetryConfig aggressive() {
        return UoWRetryConfig.builder()
            .withMaxRetries(5)
            .withBaseDelay(2000)
            .withMaxDelay(60000)
            .withBackoffMultiplier(2.0)
            .withJitter(true)
            .build();
    }

    /**
     * Rate limit handling configuration.
     * 5 retries, 5s base delay, 2x backoff, up to 120s.
     * Specifically tuned for APIs with rate limiting (429 responses).
     *
     * @return Rate limit retry configuration
     */
    public static UoWRetryConfig rateLimited() {
        return UoWRetryConfig.builder()
            .withMaxRetries(5)
            .withBaseDelay(5000)
            .withMaxDelay(120000)
            .withBackoffMultiplier(2.0)
            .withRetryableStatusCodes(new Set<Integer>{ 429 })
            .withJitter(true)
            .build();
    }
}