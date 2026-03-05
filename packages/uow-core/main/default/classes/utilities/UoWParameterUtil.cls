//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Utility class for reading UoWParameters__mdt custom metadata values.
 * Provides type-safe access methods with caching for performance.
 *
 * This class is used by package-specific parameter classes:
 * - UoWCoreParameter (uow-core package)
 * - UoWAuditParameter (uow-audit package)
 *
 * @group UoW Core
 * @author Vipul Taylor
 */
public class UoWParameterUtil {

    // ============================================================================
    // PRIVATE STATIC FIELDS
    // ============================================================================

    private static Map<String, UoWParameters__mdt> parametersByDeveloperName;

    // ============================================================================
    // PUBLIC API - TYPE-SAFE GETTERS
    // ============================================================================

    /**
     * Get a Boolean parameter value.
     *
     * @param parameterDeveloperName The parameter's DeveloperName
     * @param defaultValue Value to return if parameter not found
     * @return The parameter value or default
     */
    public static Boolean getBoolean(String parameterDeveloperName, Boolean defaultValue) {
        String value = getValue(parameterDeveloperName);
        if (String.isBlank(value)) {
            return defaultValue;
        }
        return Boolean.valueOf(value);
    }

    /**
     * Get an Integer parameter value.
     *
     * @param parameterDeveloperName The parameter's DeveloperName
     * @param defaultValue Value to return if parameter not found
     * @return The parameter value or default
     */
    public static Integer getInteger(String parameterDeveloperName, Integer defaultValue) {
        String value = getValue(parameterDeveloperName);
        if (String.isBlank(value)) {
            return defaultValue;
        }
        return Integer.valueOf(value);
    }

    /**
     * Get a Decimal parameter value.
     *
     * @param parameterDeveloperName The parameter's DeveloperName
     * @param defaultValue Value to return if parameter not found
     * @return The parameter value or default
     */
    public static Decimal getDecimal(String parameterDeveloperName, Decimal defaultValue) {
        String value = getValue(parameterDeveloperName);
        if (String.isBlank(value)) {
            return defaultValue;
        }
        return Decimal.valueOf(value);
    }

    /**
     * Get a String parameter value.
     *
     * @param parameterDeveloperName The parameter's DeveloperName
     * @param defaultValue Value to return if parameter not found
     * @return The parameter value or default
     */
    public static String getString(String parameterDeveloperName, String defaultValue) {
        String value = getValue(parameterDeveloperName);
        if (String.isBlank(value)) {
            return defaultValue;
        }
        return value;
    }

    /**
     * Get a List of Strings parameter value (JSON array).
     *
     * @param parameterDeveloperName The parameter's DeveloperName
     * @param defaultValue Value to return if parameter not found
     * @return The parameter value or default
     */
    public static List<String> getStringList(String parameterDeveloperName, List<String> defaultValue) {
        String value = getValue(parameterDeveloperName);
        if (String.isBlank(value)) {
            return defaultValue;
        }
        try {
            return (List<String>) JSON.deserialize(value, List<String>.class);
        } catch (Exception e) {
            return defaultValue;
        }
    }

    /**
     * Get a List of Integers parameter value (JSON array).
     *
     * @param parameterDeveloperName The parameter's DeveloperName
     * @param defaultValue Value to return if parameter not found
     * @return The parameter value or default
     */
    public static List<Integer> getIntegerList(String parameterDeveloperName, List<Integer> defaultValue) {
        String value = getValue(parameterDeveloperName);
        if (String.isBlank(value)) {
            return defaultValue;
        }
        try {
            return (List<Integer>) JSON.deserialize(value, List<Integer>.class);
        } catch (Exception e) {
            return defaultValue;
        }
    }

    /**
     * Get a parameter value deserialized as a specific type.
     *
     * @param parameterDeveloperName The parameter's DeveloperName
     * @param apexType The Type to deserialize to
     * @param defaultValue Value to return if parameter not found
     * @return The deserialized value or default
     */
    public static Object getObject(String parameterDeveloperName, System.Type apexType, Object defaultValue) {
        String value = getValue(parameterDeveloperName);
        if (String.isBlank(value)) {
            return defaultValue;
        }
        try {
            return JSON.deserialize(value, apexType);
        } catch (Exception e) {
            return defaultValue;
        }
    }

    /**
     * Get all parameters matching a developer name prefix.
     *
     * @param prefix The prefix to match against DeveloperName
     * @return Map of matching parameter DeveloperNames to their values
     */
    public static Map<String, String> matchOnPrefix(String prefix) {
        loadParameters();
        Map<String, String> matches = new Map<String, String>();

        if (String.isBlank(prefix)) {
            return matches;
        }

        for (String devName : parametersByDeveloperName.keySet()) {
            if (devName.startsWith(prefix)) {
                UoWParameters__mdt param = parametersByDeveloperName.get(devName);
                matches.put(devName, param.Value__c);
            }
        }

        return matches;
    }

    // ============================================================================
    // TESTING SUPPORT
    // ============================================================================

    /**
     * Set a mock parameter value for testing.
     * Only works in test context.
     *
     * @param parameterDeveloperName The parameter's DeveloperName
     * @param value The mock value to set
     */
    @TestVisible
    public static void setMock(String parameterDeveloperName, String value) {
        loadParameters();

        UoWParameters__mdt mockParam = new UoWParameters__mdt(
            DeveloperName = parameterDeveloperName,
            Value__c = value
        );
        parametersByDeveloperName.put(parameterDeveloperName, mockParam);
    }

    /**
     * Clear the parameter cache. Useful for testing.
     * Note: Package-specific parameter classes should also clear their own caches.
     */
    @TestVisible
    public static void clearCache() {
        parametersByDeveloperName = null;
    }

    // ============================================================================
    // PRIVATE HELPER METHODS
    // ============================================================================

    private static String getValue(String parameterDeveloperName) {
        loadParameters();

        UoWParameters__mdt param = parametersByDeveloperName.get(parameterDeveloperName);
        return param?.Value__c;
    }

    private static void loadParameters() {
        if (parametersByDeveloperName != null) {
            return;
        }

        parametersByDeveloperName = new Map<String, UoWParameters__mdt>();

        for (UoWParameters__mdt param : UoWParameters__mdt.getAll().values()) {
            parametersByDeveloperName.put(param.DeveloperName, param);
        }
    }
}
