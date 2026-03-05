//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Trigger on UoWScenario__c for extensible scenario lifecycle processing.
 * Gated by UoWAuditParameter.ENABLE_SCENARIO_TRIGGER (disabled by default).
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Audit
 */
trigger UoWScenarioTrigger on UoWScenario__c (before insert, before update) {
    if (!UoWAuditParameter.ENABLE_SCENARIO_TRIGGER) {
        return;
    }
}
