//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Shared instantiation utility for extensibility points.
 * Eliminates duplicate Type.forName() logic across resolvers and registries.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Services
 */
public inherited sharing class UoWExtensibilityInstantiator {

    // ============================================================================
    // TYPED INSTANTIATION METHODS (Public API)
    // ============================================================================

    public static UoWInterfaces.IPlugin instantiatePlugin(String className, UoWResult result, String source) {
        Object instance = instantiateTyped(className, 'Plugin', 'UoWInterfaces.IPlugin', result, source);
        if (instance == null) { return null; }
        try {
            return (UoWInterfaces.IPlugin) instance;
        } catch (System.TypeException ex) {
            result?.warn(String.format(System.Label.UoW_Error_ExtDoesNotImplement,
                new String[]{ 'Plugin', className, 'UoWInterfaces.IPlugin' }), source);
            return null;
        }
    }

    public static UoWInterfaces.IPolicy instantiatePolicy(String className, UoWResult result, String source) {
        Object instance = instantiateTyped(className, 'Policy', 'UoWInterfaces.IPolicy', result, source);
        if (instance == null) { return null; }
        try {
            return (UoWInterfaces.IPolicy) instance;
        } catch (System.TypeException ex) {
            result?.warn(String.format(System.Label.UoW_Error_ExtDoesNotImplement,
                new String[]{ 'Policy', className, 'UoWInterfaces.IPolicy' }), source);
            return null;
        }
    }

    public static UoWInterfaces.IDmlStrategy instantiateDmlStrategy(String className, UoWResult result, String source) {
        Object instance = instantiateTyped(className, 'DML Strategy', 'UoWInterfaces.IDmlStrategy', result, source);
        if (instance == null) { return null; }
        try {
            return (UoWInterfaces.IDmlStrategy) instance;
        } catch (System.TypeException ex) {
            result?.warn(String.format(System.Label.UoW_Error_ExtDoesNotImplement,
                new String[]{ 'DML Strategy', className, 'UoWInterfaces.IDmlStrategy' }), source);
            return null;
        }
    }

    public static UoWInterfaces.IRiskAssessor instantiateRiskAssessor(String className, UoWResult result, String source) {
        Object instance = instantiateTyped(className, 'Risk Assessor', 'UoWInterfaces.IRiskAssessor', result, source);
        if (instance == null) { return null; }
        try {
            return (UoWInterfaces.IRiskAssessor) instance;
        } catch (System.TypeException ex) {
            result?.warn(String.format(System.Label.UoW_Error_ExtDoesNotImplement,
                new String[]{ 'Risk Assessor', className, 'UoWInterfaces.IRiskAssessor' }), source);
            return null;
        }
    }

    public static UoWInterfaces.IEventChannel instantiateEventChannel(String className, UoWResult result, String source) {
        Object instance = instantiateTyped(className, 'Event Channel', 'UoWInterfaces.IEventChannel', result, source);
        if (instance == null) { return null; }
        try {
            return (UoWInterfaces.IEventChannel) instance;
        } catch (System.TypeException ex) {
            result?.warn(String.format(System.Label.UoW_Error_ExtDoesNotImplement,
                new String[]{ 'Event Channel', className, 'UoWInterfaces.IEventChannel' }), source);
            return null;
        }
    }

    public static UoWInterfaces.IEmailChannel instantiateEmailChannel(String className, UoWResult result, String source) {
        Object instance = instantiateTyped(className, 'Email Channel', 'UoWInterfaces.IEmailChannel', result, source);
        if (instance == null) { return null; }
        try {
            return (UoWInterfaces.IEmailChannel) instance;
        } catch (System.TypeException ex) {
            result?.warn(String.format(System.Label.UoW_Error_ExtDoesNotImplement,
                new String[]{ 'Email Channel', className, 'UoWInterfaces.IEmailChannel' }), source);
            return null;
        }
    }

    public static UoWInterfaces.INotificationChannel instantiateNotificationChannel(String className, UoWResult result, String source) {
        Object instance = instantiateTyped(className, 'Notification Channel', 'UoWInterfaces.INotificationChannel', result, source);
        if (instance == null) { return null; }
        try {
            return (UoWInterfaces.INotificationChannel) instance;
        } catch (System.TypeException ex) {
            result?.warn(String.format(System.Label.UoW_Error_ExtDoesNotImplement,
                new String[]{ 'Notification Channel', className, 'UoWInterfaces.INotificationChannel' }), source);
            return null;
        }
    }

    public static UoWInterfaces.IFlowChannel instantiateFlowChannel(String className, UoWResult result, String source) {
        Object instance = instantiateTyped(className, 'Flow Channel', 'UoWInterfaces.IFlowChannel', result, source);
        if (instance == null) { return null; }
        try {
            return (UoWInterfaces.IFlowChannel) instance;
        } catch (System.TypeException ex) {
            result?.warn(String.format(System.Label.UoW_Error_ExtDoesNotImplement,
                new String[]{ 'Flow Channel', className, 'UoWInterfaces.IFlowChannel' }), source);
            return null;
        }
    }

    public static UoWInterfaces.ICalloutStrategy instantiateCalloutStrategy(String className, UoWResult result, String source) {
        Object instance = instantiateTyped(className, 'Callout Strategy', 'UoWInterfaces.ICalloutStrategy', result, source);
        if (instance == null) { return null; }
        try {
            return (UoWInterfaces.ICalloutStrategy) instance;
        } catch (System.TypeException ex) {
            result?.warn(String.format(System.Label.UoW_Error_ExtDoesNotImplement,
                new String[]{ 'Callout Strategy', className, 'UoWInterfaces.ICalloutStrategy' }), source);
            return null;
        }
    }

    public static UoWInterfaces.IApprovalChannel instantiateApprovalChannel(String className, UoWResult result, String source) {
        Object instance = instantiateTyped(className, 'Approval Channel', 'UoWInterfaces.IApprovalChannel', result, source);
        if (instance == null) { return null; }
        try {
            return (UoWInterfaces.IApprovalChannel) instance;
        } catch (System.TypeException ex) {
            result?.warn(String.format(System.Label.UoW_Error_ExtDoesNotImplement,
                new String[]{ 'Approval Channel', className, 'UoWInterfaces.IApprovalChannel' }), source);
            return null;
        }
    }

    public static UoWInterfaces.ITransactionFinalizer instantiateTransactionFinalizer(String className, UoWResult result, String source) {
        Object instance = instantiateTyped(className, 'Transaction Finalizer', 'UoWInterfaces.ITransactionFinalizer', result, source);
        if (instance == null) { return null; }
        try {
            return (UoWInterfaces.ITransactionFinalizer) instance;
        } catch (System.TypeException ex) {
            result?.warn(String.format(System.Label.UoW_Error_ExtDoesNotImplement,
                new String[]{ 'Transaction Finalizer', className, 'UoWInterfaces.ITransactionFinalizer' }), source);
            return null;
        }
    }

    public static UoWInterfaces.IEventPublishFailureHandler instantiateEventPublishFailureHandler(String className, UoWResult result, String source) {
        Object instance = instantiateTyped(className, 'Event Publish Failure Handler', 'UoWInterfaces.IEventPublishFailureHandler', result, source);
        if (instance == null) { return null; }
        try {
            return (UoWInterfaces.IEventPublishFailureHandler) instance;
        } catch (System.TypeException ex) {
            result?.warn(String.format(System.Label.UoW_Error_ExtDoesNotImplement,
                new String[]{ 'Event Publish Failure Handler', className, 'UoWInterfaces.IEventPublishFailureHandler' }), source);
            return null;
        }
    }

    // ============================================================================
    // CORE INSTANTIATION LOGIC (Private)
    // ============================================================================

    // Dynamically instantiate an extension class by name with proper error handling
    // Returns Instance of the class, or null if instantiation fails
    @SuppressWarnings('PMD.ExcessiveParameterList')
    private static Object instantiateTyped(String className, String extensionType, String expectedInterface, UoWResult result, String source) {
        UoWExceptionService.requireNonBlank(className, 'Class Name during instantiation');

        try {
            Type classType = Type.forName(className);
            if (classType != null) {
                return classType.newInstance();
            } else {
                result?.warn(
                    String.format(System.Label.UoW_Error_ExtClassNotFound,
                        new String[]{ extensionType, className }),
                    source
                );
            }
        } catch (Exception ex) {
            result?.warn(
                String.format(System.Label.UoW_Error_ExtInstantiationFailed,
                    new String[]{ extensionType, className, ex.getMessage() }),
                source
            );
        }
        return null;
    }
}