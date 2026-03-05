//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Service for applying field-level data masking to work items.
 * Uses UoWDataMaskRule__mdt metadata to determine WHAT to mask and HOW.
 *
 * Architecture:
 * - EnableMasking__c (boolean) controls whether masking is active
 * - UoWDataMaskRule__mdt defines masking rules per object/field
 * - Service loads rules and applies masking directly (no strategy pattern)
 *
 * Match Types:
 * - EXACT_FIELD: Mask specific field by API name (requires SObjectType + FieldApiName)
 * - REGEX_PATTERN: Mask any field whose value matches regex (requires MatchPattern, SObjectType optional)
 *
 * Masking Modes:
 * - FULL: Replace entire value with '***'
 * - PARTIAL: Show last N characters (configurable)
 * - EMAIL: Mask email preserving structure (j***@***.com)
 * - HASH: SHA-256 hash (truncated to 16 chars)
 * - REDACT: Return null (complete removal)
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Services
 */
public inherited sharing class UoWMaskingService {

    // ============================================================================
    // PRIVATE STATIC - RULE CACHING
    // ============================================================================

    private static List<UoWDataMaskRule__mdt> maskingRules;
    private static Boolean rulesLoaded = false;

    // PERFORMANCE: Cache compiled regex patterns to avoid recompilation on every call
    private static Map<String, Pattern> compiledPatternCache = new Map<String, Pattern>();

    // ============================================================================
    // ENUMS - MATCH TYPE
    // ============================================================================

    public enum MatchType {
        EXACT_FIELD,    // 1. Exact Field Name Match
        REGEX_PATTERN   // 2. RegEx pattern
    }

    // ============================================================================
    // PUBLIC API - Work Item Masking
    // ============================================================================

    /**
     * Apply masking to all work items based on UoWDataMaskRule__mdt metadata.
     *
     * @param plan Execution plan
     * @param result Execution result instance
     * @return Masking result with details of masked fields
     */
    public static MaskingResult applyMaskingToWorkItems(UoWPlan plan, UoWResult result) {
        MaskingResult maskResult = new MaskingResult();

        // Check if masking is enabled
        if (!result.getContext().getFeatureSettings().getEnableMasking()) {
            return maskResult;
        }

        // Process DML work items
        for (UoWDmlWorkItem workItem : plan.getPlannedDmlWork()) {
            Set<String> fieldsToMask = detectFieldsToMask(workItem.getOriginalRecords(), result);

            if (!fieldsToMask.isEmpty()) {
                applyMaskingToDmlWorkItem(workItem, fieldsToMask, result);
                maskResult.addMaskedFields(workItem.workId, fieldsToMask);
            }
        }

        // Process Platform Event work items
        for (UoWEventWorkItem workItem : plan.getPlannedEventWork()) {
            Set<String> fieldsToMask = detectFieldsToMask(workItem.getOriginalEvents(), result);

            if (!fieldsToMask.isEmpty()) {
                applyMaskingToEventWorkItem(workItem, fieldsToMask, result);
                maskResult.addMaskedFields(workItem.workId, fieldsToMask);
            }
        }

        result.setMaskingResult(maskResult);
        return maskResult;
    }

    /**
     * Detect sensitive fields in a list of records based on masking rules.
     *
     * @param records Records to analyze
     * @param result Execution result for logging
     * @return Set of field names that should be masked
     */
    public static Set<String> detectFieldsToMask(List<SObject> records, UoWResult result) {
        Set<String> fieldsToMask = new Set<String>();

        if (records == null || records.isEmpty()) {
            return fieldsToMask;
        }

        for (SObject record : records) {
            fieldsToMask.addAll(detectSensitiveFields(record));
        }

        return fieldsToMask;
    }

    /**
     * Detect sensitive fields in a single record based on masking rules.
     *
     * @param record Record to analyze
     * @return Set of field names that should be masked
     */
    public static Set<String> detectSensitiveFields(SObject record) {
        Set<String> sensitiveFields = new Set<String>();

        if (record == null) {
            return sensitiveFields;
        }

        Schema.SObjectType sType = record.getSObjectType();
        Map<String, Object> populatedFields = record.getPopulatedFieldsAsMap();

        for (String fieldName : populatedFields.keySet()) {
            Object fieldValue = populatedFields.get(fieldName);
            if (fieldValue instanceof String) {
                UoWDataMaskRule__mdt rule = findMatchingRule(sType, fieldName, (String) fieldValue);
                if (rule != null) {
                    sensitiveFields.add(fieldName);
                }
            }
        }

        return sensitiveFields;
    }

    /**
     * Mask a single field value based on its matching rule.
     *
     * @param sObjectType The SObject type containing the field
     * @param fieldName The field API name
     * @param value The value to mask
     * @return Masked value
     */
    public static String maskField(Schema.SObjectType sObjectType, String fieldName, String value) {
        if (String.isBlank(value)) {
            return value;
        }

        UoWDataMaskRule__mdt rule = findMatchingRule(sObjectType, fieldName, value);
        if (rule == null) {
            return value; // No rule matched - return original
        }

        Map<String, Object> options = parseOptions(rule.MaskingOptions__c, rule.MaskingStrategy__c);
        return applyMask(value, options);
    }

    /**
     * Mask multiple fields in a record.
     *
     * @param record Record to mask
     * @param fieldsToMask Set of field names to mask
     * @return Cloned record with masked fields
     */
    public static SObject maskRecord(SObject record, Set<String> fieldsToMask) {
        if (record == null || fieldsToMask == null || fieldsToMask.isEmpty()) {
            return record;
        }

        SObject maskedRecord = record.clone(true, true, true, true);
        Schema.SObjectType sType = record.getSObjectType();

        for (String fieldName : fieldsToMask) {
            try {
                Object fieldValue = record.get(fieldName);
                if (fieldValue instanceof String) {
                    String maskedValue = maskField(sType, fieldName, (String) fieldValue);
                    maskedRecord.put(fieldName, maskedValue);
                }
            } catch (Exception ex) { // NOPMD - Intentionally empty: Field may not exist on record (dynamically detected fields)
                // This is expected when fieldsToMask contains fields from rule patterns that don't apply to this record
                System.debug(LoggingLevel.FINEST, 'Field ' + fieldName + ' not found on record: ' + ex.getMessage());
            }
        }

        return maskedRecord;
    }

    // ============================================================================
    // PRIVATE METHODS - Apply Masking to Work Items
    // ============================================================================

    /**
     * Apply masking to DML work item - creates fullyMaskedRecords via setter.
     */
    private static void applyMaskingToDmlWorkItem(
        UoWDmlWorkItem workItem,
        Set<String> fieldsToMask,
        UoWResult result
    ) {
        List<SObject> maskedRecords = new List<SObject>();

        for (SObject record : workItem.getOriginalRecords()) {
            SObject maskedRecord = maskRecord(record, fieldsToMask);
            maskedRecords.add(maskedRecord);
        }

        workItem.setMaskedRecords(maskedRecords);
        result.debug('Masked ' + fieldsToMask.size() + ' fields in DML work item: ' + workItem.workId, 'UoWMaskingService');
    }

    /**
     * Apply masking to Event work item - creates fullyMaskedEvents via setter.
     */
    private static void applyMaskingToEventWorkItem(
        UoWEventWorkItem workItem,
        Set<String> fieldsToMask,
        UoWResult result
    ) {
        List<SObject> maskedEvents = new List<SObject>();

        for (SObject evt : workItem.getOriginalEvents()) {
            SObject maskedEvent = maskRecord(evt, fieldsToMask);
            maskedEvents.add(maskedEvent);
        }

        workItem.setMaskedEvents(maskedEvents);
        result.debug('Masked ' + fieldsToMask.size() + ' fields in Event work item: ' + workItem.workId, 'UoWMaskingService');
    }

    // ============================================================================
    // PRIVATE METHODS - Rule Loading and Matching
    // ============================================================================

    /**
     * Load masking rules from custom metadata (cached).
     */
    private static List<UoWDataMaskRule__mdt> loadMaskingRules() {
        if (!rulesLoaded) {
            maskingRules = [
                SELECT DeveloperName, IsActive__c, SortOrder__c,
                       MatchType__c, MatchPattern__c, SObjectType__c, FieldApiName__c,
                       MaskingStrategy__c, MaskingOptions__c
                FROM UoWDataMaskRule__mdt
                WHERE IsActive__c = true
                ORDER BY SortOrder__c ASC NULLS LAST, DeveloperName ASC
            ];
            rulesLoaded = true;
        }
        return maskingRules;
    }

    /**
     * Find matching rule for a field.
     */
    private static UoWDataMaskRule__mdt findMatchingRule(
        Schema.SObjectType sObjectType,
        String fieldName,
        String value
    ) {
        List<UoWDataMaskRule__mdt> rules = loadMaskingRules();
        String objectName = sObjectType != null ? UoWCacheService.getDescribe(sObjectType).getName() : null;

        for (UoWDataMaskRule__mdt rule : rules) {
            // Check object filter based on match type
            // EXACT_FIELD requires SObjectType; REGEX_PATTERN allows blank (applies to all objects)
            if (String.isNotBlank(rule.SObjectType__c) && rule.SObjectType__c != objectName) {
                continue;
            }

            // Check match type
            if (matchesRule(rule, fieldName, value)) {
                return rule; // First match wins
            }
        }

        return null;
    }

    /**
     * Check if a rule matches the field.
     */
    private static Boolean matchesRule(UoWDataMaskRule__mdt rule, String fieldName, String value) {
        MatchType mType = MatchType.valueOf(rule.MatchType__c);

        switch on mType {
            when EXACT_FIELD {
                return rule.FieldApiName__c == fieldName;
            }
            when REGEX_PATTERN {
                return matchesRegex(value, rule.MatchPattern__c);
            }
        }
        return false;
    }

    /**
     * Match value against regex pattern.
     * PERFORMANCE: Uses cached compiled patterns to avoid recompilation on every call.
     */
    private static Boolean matchesRegex(String value, String regexPattern) {
        if (String.isBlank(regexPattern) || String.isBlank(value)) {
            return false;
        }
        try {
            // PERFORMANCE: Check cache first, compile only once per pattern
            Pattern compiledPattern = compiledPatternCache.get(regexPattern);
            if (compiledPattern == null) {
                compiledPattern = Pattern.compile(regexPattern);
                compiledPatternCache.put(regexPattern, compiledPattern);
            }
            Matcher patternMatcher = compiledPattern.matcher(value);
            return patternMatcher.find();
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, '[UoWMaskingService] Invalid regex pattern: ' + regexPattern + '. Error: ' + ex.getMessage());
            return false;
        }
    }

    // ============================================================================
    // PRIVATE METHODS - Masking Implementation
    // ============================================================================

    /**
     * Parse JSON options and add mode from strategy.
     */
    private static Map<String, Object> parseOptions(String optionsJson, String maskingStrategy) {
        Map<String, Object> options = new Map<String, Object>();

        // Parse JSON if provided
        if (String.isNotBlank(optionsJson)) {
            try {
                options = (Map<String, Object>) JSON.deserializeUntyped(optionsJson);
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN, '[UoWMaskingService] Invalid JSON in MaskingOptions: ' + optionsJson + '. Error: ' + ex.getMessage());
            }
        }

        // Add mode based on strategy
        if (!options.containsKey('mode') && String.isNotBlank(maskingStrategy)) {
            options.put('mode', maskingStrategy);
        }

        return options;
    }

    /**
     * Apply masking based on options.
     */
    private static String applyMask(String value, Map<String, Object> options) {
        if (String.isBlank(value)) {
            return value;
        }

        String mode = (String) options.get('mode');
        if (String.isBlank(mode)) {
            mode = 'FULL'; // Default to full masking
        }

        switch on mode.toUpperCase() {
            when 'FULL' {
                return '***';
            }
            when 'PARTIAL' {
                return maskPartial(value, options);
            }
            when 'EMAIL' {
                return maskEmail(value);
            }
            when 'HASH' {
                return maskHash(value);
            }
            when 'REDACT' {
                return null;
            }
            when else {
                return '***'; // Fallback to full masking
            }
        }
    }

    /**
     * Partial masking - show last N characters.
     */
    private static String maskPartial(String value, Map<String, Object> options) {
        Integer visibleChars = 4; // Default to last 4 characters
        if (options.containsKey('visibleCharacters')) {
            visibleChars = (Integer) options.get('visibleCharacters');
        }

        if (value.length() <= visibleChars) {
            return '***';
        }

        String lastN = value.substring(value.length() - visibleChars);
        return '***' + lastN;
    }

    /**
     * Email masking - show first character and domain extension.
     */
    private static String maskEmail(String value) {
        if (!value.contains('@')) {
            return '***';
        }

        List<String> parts = value.split('@');
        if (parts.size() != 2 || String.isBlank(parts[0])) {
            return '***';
        }

        String local = parts[0];
        String domain = parts[1];

        return local.substring(0, 1) + '***@***.' + domain.substringAfterLast('.');
    }

    /**
     * Hash masking - SHA-256 hash (truncated).
     */
    private static String maskHash(String value) {
        Blob hash = Crypto.generateDigest('SHA-256', Blob.valueOf(value));
        return EncodingUtil.convertToHex(hash).substring(0, 16);
    }

    // ============================================================================
    // PUBLIC API - Cache Management
    // ============================================================================

    /**
     * Clear the cached masking rules and compiled patterns (for testing).
     */
    @TestVisible
    private static void clearCache() {
        maskingRules = null;
        rulesLoaded = false;
        compiledPatternCache.clear();
    }

    // ============================================================================
    // INNER CLASSES - Result Types
    // ============================================================================

    /**
     * Result of masking operation.
     */
    public class MaskingResult {
        private Map<String, Set<String>> workItemMaskedFields;

        public MaskingResult() {
            this.workItemMaskedFields = new Map<String, Set<String>>();
        }

        public void addMaskedFields(String workItemId, Set<String> fields) {
            this.workItemMaskedFields.put(workItemId, fields);
        }

        public Set<String> getMaskedFields(String workItemId) {
            return this.workItemMaskedFields.get(workItemId);
        }

        /**
         * Get masked fields as a comma-separated string for audit storage.
         *
         * @param workItemId The work item ID
         * @return Comma-separated field names, or null if no fields masked
         */
        public String getMaskedFieldsAsString(String workItemId) {
            Set<String> fields = this.workItemMaskedFields.get(workItemId);
            if (fields == null || fields.isEmpty()) {
                return null;
            }
            List<String> sortedFields = new List<String>(fields);
            sortedFields.sort();
            return String.join(sortedFields, ', ');
        }

        /**
         * Check if masking was applied to a specific work item.
         *
         * @param workItemId The work item ID
         * @return True if any fields were masked
         */
        public Boolean hasMasking(String workItemId) {
            Set<String> fields = this.workItemMaskedFields.get(workItemId);
            return fields != null && !fields.isEmpty();
        }

        public Boolean isEmpty() {
            return this.workItemMaskedFields.isEmpty();
        }

        public Integer getWorkItemCount() {
            return this.workItemMaskedFields.size();
        }
    }
}