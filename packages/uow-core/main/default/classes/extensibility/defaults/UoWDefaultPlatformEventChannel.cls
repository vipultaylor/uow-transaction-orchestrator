//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Default channel for publishing platform events via EventBus.
 * Optionally includes async delivery failure detection via
 * EventBus.EventPublishFailureCallback when a failure handler is configured.
 *
 * When EventPublishFailureHandlerClassName__c is set, events are published
 * with a UoWDefaultPublishFailureCallback. If events fail to deliver after
 * commit (PublishAfterCommit), the callback fires in a separate transaction,
 * delegates to the configured IEventPublishFailureHandler, and logs the failure.
 *
 * When no handler is configured, events are published without a callback.
 * This avoids uncatchable System.UnexpectedException in orgs that do not
 * support EventPublishFailureCallback (e.g., scratch orgs, some editions).
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWInterfaces.IEventChannel
 * @see UoWDefaultPublishFailureCallback
 * @see UoWInterfaces.IEventPublishFailureHandler
 */
public inherited sharing class UoWDefaultPlatformEventChannel implements UoWInterfaces.IEventChannel {

    // ============================================================================
    // PUBLIC API - INTERFACE IMPLEMENTATION
    // ============================================================================

    /**
     * Get channel name.
     *
     * @return Channel name
     */
    public String getName() {
        return 'Default Platform Event Bus';
    }

    /**
     * Publish platform events via EventBus.
     *
     * When EventPublishFailureHandlerClassName__c is configured, publishes with
     * a UoWDefaultPublishFailureCallback for async delivery failure tracking.
     * Otherwise, publishes without callback to avoid uncatchable
     * System.UnexpectedException in unsupported orgs.
     *
     * @param workItem The event work item to execute
     * @param ctx The execution context
     */
    public void publishEvents(UoWEventWorkItem workItem, UoWContext ctx) {
        List<SObject> eventsToPublish = workItem.getOriginalEvents();
        String failureHandlerClassName = ctx.getFeatureSettings().eventPublishFailureHandlerClassName;

        if (String.isNotBlank(failureHandlerClassName)) {
            // Handler configured - publish with async failure callback
            UoWDefaultPublishFailureCallback callback = new UoWDefaultPublishFailureCallback(
                ctx, workItem, failureHandlerClassName
            );
            workItem.publishResults = EventBus.publish(eventsToPublish, callback);
        } else {
            // No handler configured - publish without callback
            workItem.publishResults = EventBus.publish(eventsToPublish);
        }
    }
}
