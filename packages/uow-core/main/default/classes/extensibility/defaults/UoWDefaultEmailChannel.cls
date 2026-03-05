//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Default channel for sending emails via Messaging.sendEmail API.
 * Maintains current behavior of direct Messaging.sendEmail calls.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Extensibility
 * @see UoWInterfaces.IEmailChannel
 */
public inherited sharing class UoWDefaultEmailChannel implements UoWInterfaces.IEmailChannel {

    // ============================================================================
    // PUBLIC API - INTERFACE IMPLEMENTATION
    // ============================================================================

    /**
     * Get channel name.
     *
     * @return Channel name
     */
    public String getName() {
        return 'Default Salesforce Email Service';
    }

    /**
     * Send emails via Messaging.sendEmail API.
     *
     * @param workItem The email work item to execute
     * @param ctx The execution context
     */
    public void sendEmails(UoWEmailWorkItem workItem, UoWContext ctx) {
        if (workItem.getEmails() != null && !workItem.getEmails().isEmpty()) {
            // Always capture results
            // Invert continueOnError: false (fail-fast) → allOrNone=true, true (partial success) → allOrNone=false
            workItem.sendResults = Messaging.sendEmail(workItem.getEmails(), !workItem.continueOnError);
        }
    }
}