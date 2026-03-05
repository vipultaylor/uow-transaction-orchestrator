//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Utility class for capturing and parsing stack traces to extract origin location information.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Services
 *
 * @example
 * // Capture current stack trace
 * UoWStackTraceParser.StackTraceInfo info = UoWStackTraceParser.parse();
 * System.debug('Origin: ' + info.originLocation);
 * System.debug('Type: ' + info.originType);
 * System.debug('Full trace: ' + info.fullStackTrace);
 */
@SuppressWarnings('PMD.CognitiveComplexity')
public inherited sharing class UoWStackTraceParser {

    // Framework classes to skip when finding request origin
    private static final Set<String> FRAMEWORK_CLASSES = new Set<String>{
        'UnitOfWork',
        'UoWWorkItem',
        'UoWDmlWorkItem',
        'UoWEventWorkItem',
        'UoWEmailWorkItem',
        'UoWNotificationWorkItem',
        'UoWFlowWorkItem',
        'UoWCalloutWorkItem',
        'UoWStackTraceParser'
    };

    // Stack trace patterns for different execution contexts
    private static final String APEX_CLASS_PATTERN = 'Class\\.([a-zA-Z0-9_]+)\\.([a-zA-Z0-9_<>]+): line (\\d+), column (\\d+)';
    private static final String TRIGGER_PATTERN = 'Trigger\\.([a-zA-Z0-9_]+): line (\\d+), column (\\d+)';
    private static final String ANONYMOUS_PATTERN = 'AnonymousBlock: line (\\d+), column (\\d+)';

    /**
     * Captures and parses the current stack trace, excluding framework internal calls.
     *
     * @return StackTraceInfo containing parsed information
     */
    public static StackTraceInfo parse() {
        return parse(captureStackTrace(), null);
    }

    /**
     * Parses a provided stack trace string.
     *
     * @param stackTrace The stack trace string to parse
     * @return StackTraceInfo containing parsed information
     */
    public static StackTraceInfo parse(String stackTrace) {
        return parse(stackTrace, null);
    }

    /**
     * Parses a provided stack trace and extracts origin location.
     *
     * @param stackTrace The stack trace string to parse (if null/blank, captures current stack trace)
     * @param skipNamespace Optional namespace to skip when finding origin (e.g., framework namespace)
     * @return StackTraceInfo containing parsed information
     */
    public static StackTraceInfo parse(String stackTrace, String skipNamespace) {
        StackTraceInfo info = new StackTraceInfo();

        // Capture stack trace if not provided
        if (String.isBlank(stackTrace)) {
            stackTrace = captureStackTrace();
        }

        // Still blank after capture attempt - return empty info
        if (String.isBlank(stackTrace)) {
            return info;
        }

        info.fullStackTrace = stackTrace;

        // Split stack trace into lines
        List<String> lines = stackTrace.split('\n');

        // Find the first meaningful line (skip framework internal classes)
        for (String line : lines) {
            line = line.trim();

            // Skip empty lines
            if (String.isBlank(line)) {
                continue;
            }

            // Check if this line should be skipped (framework internal class)
            if (shouldSkipLine(line, skipNamespace)) {
                continue;
            }

            // Try to parse as Apex class
            if (line.contains('Class.')) {
                if (parseApexClass(line, info)) {
                    info.originType = determineOriginType(info.className);
                    return info;
                }
            }

            // Try to parse as Trigger
            if (line.contains('Trigger.')) {
                if (parseTrigger(line, info)) {
                    info.originType = 'Trigger';
                    return info;
                }
            }

            // Try to parse as Anonymous Apex
            if (line.contains('AnonymousBlock')) {
                if (parseAnonymousApex(line, info)) {
                    info.originType = 'Anonymous Apex';
                    return info;
                }
            }
        }

        // If we couldn't parse anything specific, return what we have
        return info;
    }

    /**
     * Captures the current stack trace using exception mechanism.
     *
     * @return String containing the full stack trace
     */
    public static String captureStackTrace() {
        try {
            // Intentionally throw exception to capture stack trace
            throw new StackTraceException();
        } catch (Exception ex) {
            return ex.getStackTraceString();
        }
    }

    /**
     * Parses an exception and extracts stack trace information.
     *
     * @param ex The exception to parse
     * @return StackTraceInfo containing exception stack trace details
     */
    public static StackTraceInfo parseException(Exception ex) {
        StackTraceInfo info = parse(ex.getStackTraceString());

        // Also capture exception-specific details
        // (Could be used to populate ExceptionMessage__c, ExceptionType__c fields)

        return info;
    }

    // ============================================================
    // PRIVATE HELPER METHODS
    // ============================================================

    // Determines if a stack trace line should be skipped (framework internal class)
    private static Boolean shouldSkipLine(String line, String skipClassesCsv) {
        if (String.isBlank(line) || !line.startsWith('Class.')) {
            return false;
        }

        // Build set of classes to skip
        Set<String> skipClasses = new Set<String>(FRAMEWORK_CLASSES);
        if (String.isNotBlank(skipClassesCsv)) {
            for (String cls : skipClassesCsv.split(',')) {
                skipClasses.add(cls.trim());
            }
        }

        // Extract class name: "Class.ClassName.method: line X" -> "ClassName"
        String remainder = line.substring(6); // After "Class."
        Integer dotIndex = remainder.indexOf('.');
        if (dotIndex == -1) {
            return false;
        }

        String className = remainder.substring(0, dotIndex);
        return skipClasses.contains(className);
    }

    // Parses an Apex class stack trace line using Nebula Logger pattern
    // Uses namespace prefix to disambiguate namespace vs inner class
    private static Boolean parseApexClass(String line, StackTraceInfo info) {
        // Extract the location and line number from stack trace line
        // Format: Class.Something.Something.method: line 123, column 45
        if (!line.contains('.') || !line.contains(':')) {
            return false;
        }

        Integer lineIndex = line.indexOf(': line ');
        if (lineIndex == -1) {
            return false;
        }

        String location = line.substring(0, lineIndex);
        location = location.replace('Class.', '');

        String lineInfo = line.substring(lineIndex + 7); // Skip ": line "
        String lineNumStr = lineInfo.split(',')[0].trim();

        try {
            info.lineNumber = Integer.valueOf(lineNumStr);
        } catch (Exception ex) {
            return false;
        }

        // Parse the location using Nebula pattern
        // Formats:
        //   ClassName.method -> apexClassName = ClassName
        //   OuterClass.InnerClass.method -> apexClassName = OuterClass, innerClassName = InnerClass
        //   Namespace.ClassName.method -> apexClassName = ClassName (if Namespace matches)
        //   Namespace.OuterClass.InnerClass.method -> apexClassName = OuterClass, innerClassName = InnerClass
        List<String> parts = location.split('\\.');
        if (parts.size() < 2) {
            return false;
        }

        // Method name is always the last part
        info.methodName = parts[parts.size() - 1];

        // Determine if first part is the namespace
        String currentNamespace = getNamespacePrefix();
        Integer classNameIndex = 0;
        if (String.isNotBlank(currentNamespace) && parts.size() > 2 &&
            parts[0].equalsIgnoreCase(currentNamespace)) {
            classNameIndex = 1;
        }

        // className is the first non-namespace part (outer class when inner exists)
        if (classNameIndex < parts.size() - 1) {
            info.className = parts[classNameIndex];

            // Build classPath (everything except method)
            List<String> classPathParts = new List<String>();
            for (Integer i = classNameIndex; i < parts.size() - 1; i++) {
                classPathParts.add(parts[i]);
            }
            info.classPath = String.join(classPathParts, '.');

            // Inner class is anything between outer class and method
            if (classNameIndex + 2 < parts.size()) {
                info.innerClassName = parts[classNameIndex + 1];
            }
        }

        info.originLocation = location + ':' + info.lineNumber;
        return true;
    }

    // Parses a Trigger stack trace line
    private static Boolean parseTrigger(String line, StackTraceInfo info) {
        // Pattern: Trigger.TriggerName: line 123, column 45

        Pattern p = Pattern.compile(TRIGGER_PATTERN);
        Matcher m = p.matcher(line);

        if (m.find()) {
            info.className = m.group(1);
            info.lineNumber = Integer.valueOf(m.group(2));
            info.originLocation = 'Trigger.' + info.className + ':' + info.lineNumber;
            return true;
        }

        return false;
    }

    // Parses an Anonymous Apex stack trace line
    private static Boolean parseAnonymousApex(String line, StackTraceInfo info) {
        // Pattern: AnonymousBlock: line 123, column 45

        Pattern p = Pattern.compile(ANONYMOUS_PATTERN);
        Matcher m = p.matcher(line);

        if (m.find()) {
            info.lineNumber = Integer.valueOf(m.group(1));
            info.originLocation = 'AnonymousBlock:' + info.lineNumber;
            info.className = 'AnonymousBlock';
            return true;
        }

        return false;
    }

    // Determines the origin type based on class name patterns.
    // Note: This is only called for Apex classes (after parseApexClass succeeds).
    // Actual triggers are handled by parseTrigger() which sets originType = 'Trigger' directly.
    private static String determineOriginType(String className) {
        if (String.isBlank(className)) {
            return 'Unknown';
        }

        // Check for common patterns
        if (className.endsWith('Test')) {
            return 'Test';
        }

        if (className.equals('AnonymousBlock')) {
            return 'Anonymous Apex';
        }

        // Default to Apex (includes trigger handler classes like *TriggerHandler)
        return 'Apex';
    }

    /**
     * Gets the current namespace prefix, or null if unmanaged.
     * Cached for performance.
     */
    private static String namespacePrefix;
    private static Boolean namespacePrefixLoaded = false;

    private static String getNamespacePrefix() {
        if (!namespacePrefixLoaded) {
            namespacePrefixLoaded = true;
            // Query a known framework class to get namespace prefix
            List<ApexClass> classes = [
                SELECT NamespacePrefix FROM ApexClass WHERE Name = 'UoWStackTraceParser' LIMIT 1
            ];
            namespacePrefix = classes.isEmpty() ? null : classes[0].NamespacePrefix;
        }
        return namespacePrefix;
    }

    // ============================================================
    // INNER CLASSES
    // ============================================================

    /**
     * Container for parsed stack trace information.
     */
    public class StackTraceInfo {
        public String fullStackTrace;           // Complete stack trace
        public String originLocation;           // Parsed location (Class.Method:Line)
        public String originType;               // Type of execution context
        public String className;                // The actual ApexClass/ApexTrigger name (outer class when inner exists)
        public String innerClassName;           // Inner class name if present (null otherwise)
        public String classPath;                // Full class path (e.g., "OuterClass.InnerClass")
        public String methodName;               // Extracted method name
        public Integer lineNumber;              // Extracted line number

        public StackTraceInfo() {
            this.fullStackTrace = '';
            this.originLocation = '';
            this.originType = 'Unknown';
        }
    }

    // ============================================================
    // EXCEPTIONS
    // ============================================================

    /**
     * Custom exception for stack trace capture.
     */
    private class StackTraceException extends Exception {}
}