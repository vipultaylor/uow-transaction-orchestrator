//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Context object passed to IEventPublishFailureHandler.handleFailure().
 * Contains transaction identity, failure counts, and optional domain metadata.
 *
 * The correlationId, transactionId, and workId are captured at publish time
 * (stored as primitives in the callback for safe platform serialization).
 * When an async delivery failure occurs, the entire batch is considered failed.
 *
 * The metadata map allows extension packages to attach domain-specific context
 * (e.g., storageMode for audit failures) without polluting the core fields.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Core
 * @see UoWInterfaces.IEventPublishFailureHandler
 * @see EventBus.EventPublishFailureCallback
 */
public class UoWEventPublishFailureContext {

    /** Correlation ID from the publishing transaction */
    public String correlationId;

    /** Transaction ID from the publishing transaction */
    public String transactionId;

    /** Work item ID that published the events */
    public String workId;

    /** Number of events that failed to deliver */
    public Integer failedEventCount;

    /** Total number of events originally published */
    public Integer publishedEventCount;

    /** Timestamp when the failure callback executed */
    public DateTime failedAt;

    /** Optional domain-specific metadata (e.g., storageMode for audit failures) */
    public Map<String, String> metadata;
}
