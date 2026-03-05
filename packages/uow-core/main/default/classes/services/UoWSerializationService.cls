//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Unified serialization service for UoW transactions.
 * Provides high-level facades for:
 * - Async execution (Queueable prepare/hydrate)
 * - Audit snapshots (masking + sampling + serialization)
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Services
 * @see UoWQueueable
 * @see UoWPlan
 */
public inherited sharing class UoWSerializationService {

    // ============================================================================
    // HIGH-LEVEL FACADES - ASYNC EXECUTION
    // ============================================================================

    /**
     * Prepare context and plan for async serialization.
     * Call this before enqueueing a Queueable job.
     *
     * @param ctx The UoWContext to prepare
     * @param plan The UoWPlan to prepare
     */
    public static void prepareForAsync(UoWContext ctx, UoWPlan plan) {
        prepareContextForSerialization(ctx);
        preparePlanForSerialization(plan);
    }

    /**
     * Hydrate context and plan after async deserialization.
     * Call this at the start of Queueable.execute().
     *
     * @param ctx The UoWContext to hydrate
     * @param plan The UoWPlan to hydrate
     */
    public static void hydrateFromAsync(UoWContext ctx, UoWPlan plan) {
        hydrateContext(ctx);
        hydratePlan(plan);
    }

    // ============================================================================
    // CONTEXT SERIALIZATION
    // ============================================================================

    /**
     * Prepare context for serialization.
     * Captures any non-serializable data as serializable fields.
     *
     * @param ctx The UoWContext to prepare
     */
    public static void prepareContextForSerialization(UoWContext ctx) {
        if (ctx?.getFeatureSettings() != null) {
            ctx.getFeatureSettings().prepareForSerialization();
        }
    }

    /**
     * Hydrate context after deserialization.
     * Restores transient fields from serialized data.
     *
     * @param ctx The UoWContext to hydrate
     */
    public static void hydrateContext(UoWContext ctx) {
        if (ctx?.getFeatureSettings() != null) {
            ctx.getFeatureSettings().hydrate();
        }
    }

    // ============================================================================
    // PLAN SERIALIZATION
    // ============================================================================

    /**
     * Prepare plan for serialization.
     * Prepares all work items and relationships.
     *
     * @param plan The UoWPlan to prepare
     */
    public static void preparePlanForSerialization(UoWPlan plan) {
        if (plan == null) {
            return;
        }
        // Cast to base type for polymorphic processing
        prepareWorkItems((List<UoWWorkItem>) plan.getPlannedDmlWork());
        prepareWorkItems((List<UoWWorkItem>) plan.getPlannedEventWork());
        prepareWorkItems((List<UoWWorkItem>) plan.getPlannedEmailWork());
        prepareRelationships(plan.getRelationships());
    }

    /**
     * Hydrate plan after deserialization.
     * Restores all work items and relationships.
     *
     * @param plan The UoWPlan to hydrate
     */
    public static void hydratePlan(UoWPlan plan) {
        if (plan == null) {
            return;
        }
        // Cast to base type for polymorphic processing
        hydrateWorkItems((List<UoWWorkItem>) plan.getPlannedDmlWork());
        hydrateWorkItems((List<UoWWorkItem>) plan.getPlannedEventWork());
        hydrateWorkItems((List<UoWWorkItem>) plan.getPlannedEmailWork());
        hydrateRelationships(plan.getRelationships());
    }

    // ============================================================================
    // WORK ITEM SERIALIZATION (Polymorphic)
    // ============================================================================

    /**
     * Prepare work items for async serialization.
     * Uses polymorphic dispatch - each work item type handles its own serialization,
     * including preparing its errors for serialization.
     *
     * @param items The work items to prepare (accepts any List of UoWWorkItem subclasses)
     */
    public static void prepareWorkItems(List<UoWWorkItem> items) {
        if (items == null) {
            return;
        }
        for (UoWWorkItem item : items) {
            item.prepareForSerialization();
        }
    }

    /**
     * Hydrate work items after deserialization.
     * Uses polymorphic dispatch - each work item type handles its own hydration,
     * including hydrating its errors.
     *
     * @param items The work items to hydrate (accepts any List of UoWWorkItem subclasses)
     */
    public static void hydrateWorkItems(List<UoWWorkItem> items) {
        if (items == null) {
            return;
        }
        for (UoWWorkItem item : items) {
            item.hydrate();
        }
    }

    // ============================================================================
    // RELATIONSHIP SERIALIZATION
    // ============================================================================

    /**
     * Prepare relationships for serialization.
     * Captures Schema.SObjectField as field API name string.
     *
     * @param relationships The relationships to prepare
     */
    public static void prepareRelationships(List<UoWRelationship> relationships) {
        if (relationships == null) {
            return;
        }
        for (UoWRelationship rel : relationships) {
            rel.captureFieldName();
        }
    }

    /**
     * Hydrate relationships after deserialization.
     * Restores Schema.SObjectField from field API name string.
     *
     * @param relationships The relationships to hydrate
     */
    public static void hydrateRelationships(List<UoWRelationship> relationships) {
        if (relationships == null) {
            return;
        }
        for (UoWRelationship rel : relationships) {
            rel.hydrateField();
        }
    }

    // ============================================================================
    // AUDIT SUPPORT
    // ============================================================================

    /**
     * Prepare a single work item for audit snapshot.
     * Applies masking and sampling based on serialization config.
     *
     * @param item The work item to prepare
     * @param config Serialization configuration controlling masking/sampling behavior
     */
    public static void prepareWorkItemForAuditSnapshot(UoWWorkItem item, UoWSerializationConfig config) {
        item?.prepareForSerialization(config);
    }

    /**
     * Prepare work items for audit snapshot.
     * Applies masking and sampling based on serialization config.
     *
     * @param items The work items to prepare
     * @param config Serialization configuration controlling masking/sampling behavior
     */
    public static void prepareWorkItemsForAuditSnapshot(List<UoWWorkItem> items, UoWSerializationConfig config) {
        if (items == null) {
            return;
        }

        for (UoWWorkItem item : items) {
            prepareWorkItemForAuditSnapshot(item, config);
        }
    }

    /**
     * Serialize a single work item for audit purposes.
     *
     * @param item The work item to serialize
     * @param config Serialization configuration controlling masking/sampling behavior
     * @return JSON string representation
     */
    public static String serializeWorkItemForAudit(UoWWorkItem item, UoWSerializationConfig config) {
        if (item == null) {
            return null;
        }
        item.prepareForSerialization(config);
        return JSON.serialize(item);
    }

    // ============================================================================
    // INNER CLASSES
    // ============================================================================

    /**
     * Serializable snapshot of relationship state.
     * Used for audit and approval storage.
     */
    public class RelationshipSnapshot {
        public String childWorkId;
        public Integer childRecordIndex;
        public String relationshipFieldName;
        public String parentWorkId;
        public Integer parentRecordIndex;
    }
}