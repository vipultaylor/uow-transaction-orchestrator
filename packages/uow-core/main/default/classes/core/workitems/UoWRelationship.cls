//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Represents a relationship between two SObject records.
 * Uses direct object references for efficient resolution.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Work Items
 * @see UoWDmlWorkItem
 * @see UoWPlan
 */
public inherited sharing class UoWRelationship {

    // ============================================================================
    // STATIC COUNTER FOR KEY GENERATION (performance optimization)
    // ============================================================================

    // Static counter for unique key generation - avoids expensive Crypto.getRandomInteger()
    private static Integer keyCounter = 0;

    // ============================================================================
    // PUBLIC PROPERTIES
    // ============================================================================

    public SObject childRecord;              // Child record instance
    public transient Schema.SObjectField childField;   // Lookup/Master-Detail field on child (transient)
    public SObject parentRecord;             // Parent record instance
    public String relationshipKey;           // Unique key for deduplication
    private Boolean resolved;                 // Track if relationship was already resolved

    // ============================================================================
    // SERIALIZATION SUPPORT - String representation for Schema.SObjectField
    // ============================================================================

    // Field API name (serializable) - used to restore childField after deserialization
    public String childFieldName;

    // Child SObject type name - used with childFieldName to restore childField
    public String childSObjectTypeName;

    // Parent SObject type name - cached to avoid repeated describe calls
    public String parentSObjectTypeName;

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    /**
     * No-arg constructor for bulk creation optimization.
     * Use initBulk() to initialize after construction.
     */
    public UoWRelationship() {
        this.resolved = false;
    }

    /**
     * Constructor using direct object references.
     * Optimized to minimize describe calls - extracts field/type names once
     * and reuses them for key generation.
     *
     * @param child Child record instance
     * @param field Relationship field on child pointing to parent
     * @param parent Parent record instance
     */
    public UoWRelationship(SObject child, Schema.SObjectField field, SObject parent) {
        this.childRecord = child;
        this.childField = field;
        this.parentRecord = parent;
        this.resolved = false;

        // Capture serializable names ONCE - reuse for key generation
        // This eliminates duplicate getFieldDescribe()/getDescribe() calls
        if (field != null) {
            this.childFieldName = UoWCacheService.getFieldDescribe(field).getName();
        }
        if (child != null) {
            this.childSObjectTypeName = UoWCacheService.getDescribe(child.getSObjectType()).getName();
        }
        if (parent != null) {
            this.parentSObjectTypeName = UoWCacheService.getDescribe(parent.getSObjectType()).getName();
        }

        // Generate key using already-extracted field name (no duplicate describe call)
        this.relationshipKey = generateKey();
    }

    /**
     * Initialize relationship with pre-computed metadata for bulk operations.
     * PERFORMANCE: Avoids describe calls by reusing pre-computed field/type names.
     *
     * @param child Child record instance
     * @param field Relationship field on child pointing to parent
     * @param parent Parent record instance
     * @param precomputedFieldName Pre-computed field API name
     * @param precomputedChildTypeName Pre-computed child SObject type name
     * @param precomputedParentTypeName Pre-computed parent SObject type name
     */
    public void initBulk(SObject child, Schema.SObjectField field, SObject parent,
                         String precomputedFieldName, String precomputedChildTypeName,
                         String precomputedParentTypeName) {
        this.childRecord = child;
        this.childField = field;
        this.parentRecord = parent;
        this.childFieldName = precomputedFieldName;
        this.childSObjectTypeName = precomputedChildTypeName;
        this.parentSObjectTypeName = precomputedParentTypeName;
        this.relationshipKey = generateKey();
    }

    // ============================================================================
    // PUBLIC METHODS
    // ============================================================================

    /**
     * Resolve relationship by copying parent ID to child lookup field.
     * After parent DML, Salesforce populates parent.Id in memory.
     * This method reads the parent ID and sets it on the child.
     * Only resolves once - subsequent calls are no-ops to prevent
     * attempting to modify Master-Detail fields after child insert.
     */
    public void resolve() {
        // Skip if already resolved (prevents modifying Master-Detail after insert)
        if (this.resolved) {
            return;
        }

        if (parentRecord == null || childRecord == null || childField == null) {
            return;
        }

        // Parent record should have ID populated after DML
        if (parentRecord.Id != null) {
            childRecord.put(childField, parentRecord.Id);
            this.resolved = true;
        }
    }

    /**
     * Check if this is a same-object relationship (self-referencing).
     *
     * @return True if parent and child are same SObjectType
     */
    public Boolean isSameObjectRelationship() {
        Schema.SObjectType parentType = getParentType();
        Schema.SObjectType childType = getChildType();
        return parentType != null && childType != null && parentType == childType;
    }

    /**
     * Get parent SObject type.
     *
     * @return Parent SObjectType or null
     */
    public Schema.SObjectType getParentType() {
        return parentRecord?.getSObjectType();
    }

    /**
     * Get child SObject type.
     *
     * @return Child SObjectType or null
     */
    public Schema.SObjectType getChildType() {
        return childRecord?.getSObjectType();
    }

    // Get parent type name (PERFORMANCE: uses cached parentSObjectTypeName when available)
    public String getParentTypeName() {
        if (String.isNotBlank(parentSObjectTypeName)) {
            return parentSObjectTypeName;
        }
        return parentRecord != null ? UoWCacheService.getDescribe(parentRecord.getSObjectType()).getName() : null;
    }

    // Get child type name (PERFORMANCE: uses cached childSObjectTypeName when available)
    public String getChildTypeName() {
        if (String.isNotBlank(childSObjectTypeName)) {
            return childSObjectTypeName;
        }
        return childRecord != null ? UoWCacheService.getDescribe(childRecord.getSObjectType()).getName() : null;
    }

    /**
     * Check if relationship is resolved (parent has ID).
     *
     * @return True if parent record has been assigned an ID
     */
    public Boolean isResolved() {
        return parentRecord != null && parentRecord.Id != null;
    }

    // ============================================================================
    // PUBLIC API - SERIALIZATION LIFECYCLE
    // ============================================================================

    /**
     * Capture field name before serialization.
     * Called by UoWSerializationService.prepareRelationships().
     * Note: Field name is already captured in constructor, but this ensures
     * it's up-to-date if called explicitly.
     */
    public void captureFieldName() {
        if (this.childField != null && String.isBlank(this.childFieldName)) {
            this.childFieldName = UoWCacheService.getFieldDescribe(this.childField).getName();
        }
        if (this.childRecord != null && String.isBlank(this.childSObjectTypeName)) {
            this.childSObjectTypeName = UoWCacheService.getDescribe(this.childRecord.getSObjectType()).getName();
        }
    }

    /**
     * Restore Schema.SObjectField from field name after deserialization.
     * Called by UoWSerializationService.hydrateRelationships().
     */
    public void hydrateField() {
        // Restore childField from childFieldName and childSObjectTypeName
        // PERFORMANCE: Use UoWCacheService.getSobjectTypeFromGlobalDescribe() instead of direct Schema.getGlobalDescribe()
        if (this.childField == null && String.isNotBlank(this.childFieldName) && String.isNotBlank(this.childSObjectTypeName)) {
            Schema.SObjectType childType = UoWCacheService.getSobjectTypeFromGlobalDescribe(this.childSObjectTypeName);
            if (childType != null) {
                Map<String, Schema.SObjectField> fieldMap = UoWCacheService.getDescribe(childType).fields.getMap();
                this.childField = fieldMap.get(this.childFieldName);
            }
        }
    }

    // ============================================================================
    // PRIVATE METHODS
    // ============================================================================

    // Generate unique key for relationship deduplication.
    // PERFORMANCE: Uses simple counter-only key - no string concatenation.
    // Counter is sufficient since relationships are only compared within a single
    // UoW transaction, and the counter resets between transactions.
    private String generateKey() {
        return String.valueOf(++keyCounter);
    }
}