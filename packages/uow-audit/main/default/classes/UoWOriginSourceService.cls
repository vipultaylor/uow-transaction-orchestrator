//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Service for capturing origin source metadata during audit publishing.
 * Only called when enableOriginSourceMetadata is true.
 *
 * Queries ApexClass/ApexTrigger metadata to capture:
 * - Source code snippet around the origin line
 * - API version and modification dates
 * - Class/trigger name and method name
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Audit
 */
public inherited sharing class UoWOriginSourceService {

    // Number of lines to show before and after the origin line
    private static final Integer CONTEXT_LINES = 10;

    // Cache to avoid repeated SOQL during batch publishing (same class may appear multiple times)
    private static Map<String, ApexClassInfo> classCache = new Map<String, ApexClassInfo>();
    private static Map<String, ApexTriggerInfo> triggerCache = new Map<String, ApexTriggerInfo>();

    // ============================================================================
    // PUBLIC API
    // ============================================================================

    /**
     * Capture origin source metadata for a work item.
     * Called during audit event publishing when enableOriginSourceMetadata is true.
     *
     * @param className The actual ApexClass/ApexTrigger name (pre-parsed from stack trace)
     * @param originLocation The origin location string (format: ClassName.methodName:lineNumber)
     * @param originType The origin type ('Apex', 'Trigger', 'Test', 'Flow', 'Anonymous Apex')
     * @return CaptureResult with all metadata fields and source snippet, or null if not found/applicable
     */
    public static CaptureResult captureOriginMetadata(String className, String originLocation, String originType) {
        if (String.isBlank(className) || String.isBlank(originLocation)) {
            return null;
        }

        // Anonymous Apex cannot be queried
        if (originType == 'Anonymous Apex' || className == 'AnonymousBlock') {
            return null;
        }

        try {
            // Handle Flow origin type - Flows are not queryable metadata in the same way as Apex
            // We return a minimal CaptureResult with the Flow name and metadata type
            if (originType == 'Flow') {
                return captureFlowMetadata(className);
            }

            // Parse origin location for line number and method name
            OriginInfo origin = parseOriginLocation(originLocation);
            if (origin == null) {
                return null;
            }

            // Use pre-parsed className (outer class for inner classes)
            origin.className = className;

            // Handle triggers differently
            if (originType == 'Trigger' || originLocation.startsWith('Trigger.')) {
                origin.isTrigger = true;
                return captureTriggerMetadata(origin);
            }

            // Handle Apex classes
            return captureClassMetadata(origin);

        } catch (Exception ex) {
            // Silently fail - metadata capture should not break audit publishing
            System.debug(LoggingLevel.WARN, 'Failed to capture origin metadata: ' + ex.getMessage());
            return null;
        }
    }

    /**
     * Clear the cache. Useful for testing or memory management.
     */
    public static void clearCache() {
        classCache.clear();
        triggerCache.clear();
    }

    // ============================================================================
    // PRIVATE METHODS - APEX CLASS
    // ============================================================================

    private static CaptureResult captureClassMetadata(OriginInfo origin) {
        // Check cache first
        if (classCache.containsKey(origin.className)) {
            ApexClassInfo info = classCache.get(origin.className);
            return buildCaptureResult(info, origin);
        }

        // Query ApexClass metadata - className is always the actual ApexClass (outer class)
        List<ApexClass> classes = [
            SELECT Id, Name, Body, ApiVersion, CreatedDate, LastModifiedDate, NamespacePrefix
            FROM ApexClass
            WHERE Name = :origin.className
            LIMIT 1
        ];

        if (classes.isEmpty()) {
            return null;
        }

        ApexClass cls = classes[0];
        ApexClassInfo info = new ApexClassInfo();
        info.className = cls.Name;
        info.body = cls.Body;
        info.apiVersion = String.valueOf(cls.ApiVersion);
        info.createdDate = cls.CreatedDate;
        info.lastModifiedDate = cls.LastModifiedDate;
        info.namespacePrefix = cls.NamespacePrefix;
        info.metadataType = 'ApexClass';

        // Cache for reuse
        classCache.put(origin.className, info);

        return buildCaptureResult(info, origin);
    }

    // ============================================================================
    // PRIVATE METHODS - APEX TRIGGER
    // ============================================================================

    private static CaptureResult captureTriggerMetadata(OriginInfo origin) {
        // Check cache first
        if (triggerCache.containsKey(origin.className)) {
            ApexTriggerInfo info = triggerCache.get(origin.className);
            return buildTriggerCaptureResult(info, origin);
        }

        // Query ApexTrigger metadata
        List<ApexTrigger> triggers = [
            SELECT Id, Name, Body, ApiVersion, CreatedDate, LastModifiedDate, NamespacePrefix
            FROM ApexTrigger
            WHERE Name = :origin.className
            LIMIT 1
        ];

        if (triggers.isEmpty()) {
            return null;
        }

        ApexTrigger trg = triggers[0];
        ApexTriggerInfo info = new ApexTriggerInfo();
        info.triggerName = trg.Name;
        info.body = trg.Body;
        info.apiVersion = String.valueOf(trg.ApiVersion);
        info.createdDate = trg.CreatedDate;
        info.lastModifiedDate = trg.LastModifiedDate;
        info.namespacePrefix = trg.NamespacePrefix;
        info.metadataType = 'ApexTrigger';

        // Cache for reuse
        triggerCache.put(origin.className, info);

        return buildTriggerCaptureResult(info, origin);
    }

    // ============================================================================
    // PRIVATE METHODS - FLOW
    // ============================================================================

    /**
     * Capture metadata for Flow origin type.
     * Flows are not queryable in the same way as Apex classes/triggers.
     * We return a minimal CaptureResult with the Flow API name and metadata type.
     *
     * @param flowApiName The Flow's API name
     * @return CaptureResult with Flow metadata
     */
    private static CaptureResult captureFlowMetadata(String flowApiName) {
        CaptureResult result = new CaptureResult();
        result.metadataType = 'Flow';
        result.className = flowApiName;
        // Flows don't have queryable source code, API version, or modification dates
        // in the same way Apex classes do - these fields remain null
        return result;
    }

    // ============================================================================
    // PRIVATE METHODS - RESULT BUILDING
    // ============================================================================

    private static CaptureResult buildCaptureResult(ApexClassInfo info, OriginInfo origin) {
        CaptureResult result = new CaptureResult();
        result.metadataType = info.metadataType;
        result.apiVersion = info.apiVersion;
        result.className = info.className;
        result.methodName = origin.methodName;
        result.lineNumber = origin.lineNumber;
        result.lastModifiedDate = info.lastModifiedDate;

        // Extract source snippet around the origin line
        extractSourceSnippet(info.body, origin.lineNumber, result);

        return result;
    }

    private static CaptureResult buildTriggerCaptureResult(ApexTriggerInfo info, OriginInfo origin) {
        CaptureResult result = new CaptureResult();
        result.metadataType = info.metadataType;
        result.apiVersion = info.apiVersion;
        result.className = info.triggerName;
        result.lineNumber = origin.lineNumber;
        result.lastModifiedDate = info.lastModifiedDate;

        // Extract source snippet around the origin line
        extractSourceSnippet(info.body, origin.lineNumber, result);

        return result;
    }

    private static void extractSourceSnippet(String body, Integer lineNumber, CaptureResult result) {
        if (String.isBlank(body) || lineNumber == null || lineNumber < 1) {
            return;
        }

        // Normalize line endings - handle both \r\n (Windows) and \n (Unix)
        // ApexClass.Body from Salesforce typically uses \n but be safe
        String normalizedBody = body.replace('\r\n', '\n').replace('\r', '\n');
        List<String> lines = normalizedBody.split('\n');
        Integer totalLines = lines.size();

        // Validate line number is within bounds
        if (lineNumber > totalLines) {
            // Line number exceeds file - capture last few lines
            lineNumber = totalLines;
        }

        // Calculate start and end line (1-indexed)
        Integer startLine = Math.max(1, lineNumber - CONTEXT_LINES);
        Integer endLine = Math.min(totalLines, lineNumber + CONTEXT_LINES);

        // Build snippet
        List<String> snippetLines = new List<String>();
        for (Integer i = startLine - 1; i < endLine; i++) {
            if (i >= 0 && i < totalLines) {
                snippetLines.add(lines[i]);
            }
        }

        result.sourceSnippet = String.join(snippetLines, '\n');
        result.snippetStartLine = startLine;
    }

    // ============================================================================
    // PRIVATE METHODS - PARSING
    // ============================================================================

    /**
     * Parse origin location string into components.
     *
     * Formats:
     * - ClassName.methodName:lineNumber
     * - Trigger.TriggerName:lineNumber
     *
     * @param originLocation The origin location string
     * @return Parsed OriginInfo or null
     */
    private static OriginInfo parseOriginLocation(String originLocation) {
        if (String.isBlank(originLocation)) {
            return null;
        }

        OriginInfo info = new OriginInfo();

        // Split by colon to get line number
        List<String> parts = originLocation.split(':');
        if (parts.size() < 2) {
            return null;
        }

        try {
            info.lineNumber = Integer.valueOf(parts[parts.size() - 1].trim());
        } catch (Exception ex) {
            return null;
        }

        // Parse the class/method part
        String classMethodPart = parts[0].trim();

        // Handle trigger format: Trigger.TriggerName
        if (classMethodPart.startsWith('Trigger.')) {
            info.className = classMethodPart.substring(8); // Remove 'Trigger.'
            info.isTrigger = true;
            return info;
        }

        // Extract method name (last dot-separated part)
        // className is now passed in directly from UoWWorkItem.requestClassName
        List<String> locationPieces = classMethodPart.split('\\.');
        if (locationPieces.isEmpty()) {
            return null;
        }

        // Method name is always the last piece
        info.methodName = locationPieces[locationPieces.size() - 1];

        // className will be set by the caller from the pre-parsed value
        if (locationPieces.size() >= 2) {
            info.className = locationPieces[0];
        }

        return info;
    }

    // ============================================================================
    // INNER CLASSES
    // ============================================================================

    /**
     * Parsed origin location information.
     */
    private class OriginInfo {
        public String className;       // The actual ApexClass name (outer class)
        public String innerClassName;  // Inner class name if present
        public String methodName;
        public Integer lineNumber;
        public String namespace;
        public Boolean isTrigger = false;
    }

    /**
     * Cached ApexClass information.
     */
    private class ApexClassInfo {
        public String className;
        public String body;
        public String apiVersion;
        public DateTime createdDate;
        public DateTime lastModifiedDate;
        public String namespacePrefix;
        public String metadataType;
    }

    /**
     * Cached ApexTrigger information.
     */
    private class ApexTriggerInfo {
        public String triggerName;
        public String body;
        public String apiVersion;
        public DateTime createdDate;
        public DateTime lastModifiedDate;
        public String namespacePrefix;
        public String metadataType;
    }

    /**
     * Result of origin source metadata capture.
     * Contains all metadata fields to be stored in dedicated columns,
     * plus the source snippet for OriginSourceMetadata__c.
     */
    public class CaptureResult {
        public String metadataType;          // 'ApexClass', 'ApexTrigger', or 'Flow'
        public String apiVersion;            // e.g., '65.0'
        public String className;             // The actual ApexClass/ApexTrigger name (used for querying)
        public String methodName;            // Method name (null for triggers)
        public Integer lineNumber;           // Origin line number
        public DateTime lastModifiedDate;    // For modification detection
        public String sourceSnippet;         // Code snippet around origin line
        public Integer snippetStartLine;     // First line number in snippet
    }
}