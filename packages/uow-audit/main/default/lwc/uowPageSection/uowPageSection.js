//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Collapsible page section component for UoW components.
 * Similar to Nebula Logger's loggerPageSection.
 *
 * Features:
 * - Collapsible/expandable sections
 * - Title slot for custom header content
 * - Default slot for section body content
 * - Persists collapsed state (optional)
 * - SLDS styling
 */
import { LightningElement, api } from 'lwc';

export default class UowPageSection extends LightningElement {
    // ============================================================================
    // PUBLIC API
    // ============================================================================

    /**
     * Section title text.
     */
    @api title;

    /**
     * Whether the section is collapsed.
     * Default: false (expanded)
     */
    @api isCollapsed = false;

    /**
     * Icon name for the section header (optional).
     * Uses SLDS icon format, e.g., 'utility:chevrondown'
     */
    @api iconName;

    /**
     * Unique key for persisting collapsed state in sessionStorage (optional).
     * If not provided, state is not persisted.
     */
    @api storageKey;

    // ============================================================================
    // LIFECYCLE HOOKS
    // ============================================================================

    connectedCallback() {
        this.restoreState();
    }

    // ============================================================================
    // PRIVATE METHODS
    // ============================================================================

    restoreState() {
        if (!this.storageKey) {
            return;
        }

        try {
            const savedState = sessionStorage.getItem(this.getStorageKeyName());
            if (savedState !== null) {
                this.isCollapsed = savedState === 'true';
            }
        } catch (ex) {
            // sessionStorage may not be available
            console.warn('Could not restore section state:', ex);
        }
    }

    saveState() {
        if (!this.storageKey) {
            return;
        }

        try {
            sessionStorage.setItem(this.getStorageKeyName(), String(this.isCollapsed));
        } catch (ex) {
            console.warn('Could not save section state:', ex);
        }
    }

    getStorageKeyName() {
        return `uow-section-${this.storageKey}`;
    }

    // ============================================================================
    // EVENT HANDLERS
    // ============================================================================

    handleToggle() {
        this.isCollapsed = !this.isCollapsed;
        this.saveState();

        this.dispatchEvent(new CustomEvent('toggle', {
            detail: { isCollapsed: this.isCollapsed }
        }));
    }

    // ============================================================================
    // GETTERS
    // ============================================================================

    get sectionClass() {
        return this.isCollapsed
            ? 'slds-section'
            : 'slds-section slds-is-open';
    }

    get contentClass() {
        return this.isCollapsed
            ? 'slds-section__content slds-hide'
            : 'slds-section__content';
    }

    get toggleIconName() {
        return this.isCollapsed ? 'utility:switch' : 'utility:chevrondown';
    }
}