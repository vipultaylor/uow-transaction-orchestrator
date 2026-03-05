//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * @description Expandable span item component for OTel-aligned timeline visualization.
 *              Renders a single span as an accordion item with detailed information,
 *              duration metrics, work items, and recursive child spans.
 *
 *              OTel Alignment:
 *              - Uses "span" instead of "phase"
 *              - Uses "name" for span description (OTel standard)
 *              - Uses "phase" for UoW phase (from attributes['uow.phase'])
 *              - Uses "category" for UoW category (from attributes['uow.category'])
 *              - Uses "statusCode" for OTel status (OK, ERROR, UNSET)
 *
 * @see UowSpanTree
 * @see UowSpanEvent
 * @see UowWorkItemEvent
 */
import { LightningElement, api } from 'lwc';
import { CATEGORY_TOKENS, STATUS_TOKENS, getToken } from 'c/uowSharedDesignTokens';

export default class UowSpanItem extends LightningElement {
    _span;
    @api totalDurationMs = 0;
    isExpanded = false;

    @api
    get span() {
        return this._span;
    }

    set span(value) {
        this._span = value;
    }

    // ============================================================================
    // COMPUTED PROPERTIES - CHILDREN AND EVENTS
    // ============================================================================

    get hasChildren() {
        return this.span?.hasChildren && this.span?.children?.length > 0;
    }

    get children() {
        return this.span?.children || [];
    }

    get hasEvents() {
        return this.span?.events?.length > 0;
    }

    get events() {
        return this.span?.events || [];
    }

    get hasWorkItems() {
        return this.span?.hasWorkItems && this.span?.workItems?.length > 0;
    }

    get workItems() {
        return this.span?.workItems || [];
    }

    get isExpandable() {
        return this.hasChildren || this.hasEvents || this.hasWorkItems;
    }

    // ============================================================================
    // COMPUTED PROPERTIES - DISPLAY (OTel-aligned naming)
    // ============================================================================

    /**
     * OTel span name - the descriptive title of the span.
     * e.g., "Executing DML operations (completed in 245ms)"
     */
    get name() {
        return this.span?.name || '';
    }

    /**
     * UoW phase - extracted from attributes['uow.phase'].
     * e.g., "DML_EXECUTION", "POLICY_EVALUATION"
     */
    get phase() {
        return this.span?.phase || '';
    }

    /**
     * Formatted phase name for display (Title Case).
     * e.g., "Dml Execution", "Policy Evaluation"
     */
    get phaseDisplay() {
        return this.formatName(this.span?.phase);
    }

    /**
     * UoW category - extracted from attributes['uow.category'].
     * e.g., "DML", "POLICY", "CALLOUT"
     */
    get category() {
        return this.span?.category || '';
    }

    /**
     * OTel status code - OK, ERROR, or UNSET.
     */
    get statusCode() {
        return this.span?.statusCode || 'UNSET';
    }

    get startTime() {
        return this.span?.startTime;
    }

    get endTime() {
        return this.span?.endTimeMs ? new Date(this.span.endTimeMs) : null;
    }

    get timeOffset() {
        // Calculate offset from transaction start if available
        // This would need to be passed from parent or calculated
        return null; // TODO: Implement time offset calculation
    }

    get duration() {
        const ms = this.span?.durationMs;
        if (ms == null) return 'In Progress';
        return `${ms}ms`;
    }

    get durationPercentage() {
        if (!this.totalDurationMs || this.totalDurationMs === 0) {
            return null;
        }
        const ms = this.span?.durationMs;
        if (ms == null || ms === 0) {
            return null;
        }

        const percentage = ((ms / this.totalDurationMs) * 100).toFixed(1);
        return percentage;
    }

    get durationBadgeClass() {
        let classes = 'slds-badge slds-m-left_x-small';

        const percentage = parseFloat(this.durationPercentage);

        // Only apply color if percentage is a valid number
        if (!isNaN(percentage)) {
            if (percentage > 50) {
                classes += ' slds-theme_error slds-badge_inverse'; // Red for >50%
            } else if (percentage >= 25) {
                classes += ' slds-theme_warning slds-badge_inverse'; // Orange for 25-50%
            }
        }
        // No color for <25% or invalid percentage

        return classes;
    }

    get showStatusBadge() {
        // Show ERROR badge only for complete failures (✗), not partial (⚠)
        return this.isError;
    }

    /**
     * Whether to show the partial error (warning) badge.
     */
    get showPartialErrorBadge() {
        return this.isPartialError;
    }

    // ============================================================================
    // COMPUTED PROPERTIES - ERROR PROPAGATION
    // ============================================================================

    /**
     * Whether this span has a descendant with error status.
     * Used to show "contains error" visual indication on parent spans.
     */
    get hasDescendantError() {
        return this.span?.hasDescendantError === true;
    }

    /**
     * Whether to show the "contains error" indicator.
     * Only show for spans without direct errors that have descendant errors.
     */
    get showContainsErrorIndicator() {
        return !this.isError && !this.isPartialError && this.hasDescendantError;
    }

    /**
     * Whether this span represents a complete failure.
     */
    get isError() {
        return this.statusCode === 'ERROR';
    }

    /**
     * Whether this span represents a partial failure.
     * Check if any work items have partial success status.
     */
    get isPartialError() {
        if (!this.hasWorkItems) {
            return false;
        }
        return this.span.workItems.some(wi => wi.WorkItemStatus__c === 'PARTIAL_SUCCESS');
    }

    /**
     * Whether to show the description line.
     * Show the span name as description below the phase display.
     */
    get showDescription() {
        return this.name;
    }

    get statusBadgeClass() {
        let classes = 'slds-badge';

        if (this.statusCode === 'ERROR') {
            classes += ' slds-theme_error';
        }

        return classes;
    }

    // ============================================================================
    // COMPUTED PROPERTIES - ICONS
    // ============================================================================

    get iconName() {

        // Complete failure gets error icon
        if (this.isError) {
            return STATUS_TOKENS.ERROR.icon;
        }

        // Partial failure gets warning icon
        if (this.isPartialError) {
            return STATUS_TOKENS.WARNING.icon;
        }

        // Category-based icons from centralized tokens
        return getToken(CATEGORY_TOKENS, this.span?.category).icon;
    }

    get iconContainerClass() {
        let classes = 'slds-icon_container slds-timeline__icon uow-span-icon';

        const category = this.span?.category;
        const hasDescendantError = this.span?.hasDescendantError;

        // Apply theme colors based on error state or category
        if (this.isError) {
            classes += ' uow-span-icon-error';
        } else if (this.isPartialError) {
            classes += ' uow-span-icon-warning';
        } else if (hasDescendantError) {
            // Contains error but not directly errored - add ring indicator
            classes += ' uow-span-icon-contains-error';
            classes += ` uow-span-icon-${(category || 'default').toLowerCase()}`;
        } else {
            // Map categories to custom theme colors
            classes += ` uow-span-icon-${(category || 'default').toLowerCase()}`;
        }

        return classes;
    }

    get itemClass() {
        let classes = 'slds-timeline__item_expandable uow-span-item';

        const category = this.span?.category;
        const hasDescendantError = this.span?.hasDescendantError;

        // Add category class for connector line colors
        if (this.isError) {
            classes += ' uow-span__item_error';
        } else if (this.isPartialError) {
            classes += ' uow-span__item_warning';
        } else if (hasDescendantError) {
            // Contains error - use dashed line indicator
            classes += ' uow-span__item_contains-error';
            classes += ` uow-span__item_${(category || 'default').toLowerCase()}`;
        } else {
            classes += ` uow-span__item_${(category || 'default').toLowerCase()}`;
        }

        // Add open state if expanded
        if (this.isExpanded) {
            classes += ' slds-is-open';
        }

        return classes;
    }

    get expandIcon() {
        return this.isExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    // ============================================================================
    // EVENT HANDLERS
    // ============================================================================

    handleToggle(event) {
        event.stopPropagation();
        this.isExpanded = !this.isExpanded;
    }

    // ============================================================================
    // UTILITY METHODS
    // ============================================================================

    /**
     * Format SNAKE_CASE name to Title Case for display.
     * Preserves acronyms like DML, API, HTTP, etc.
     * @param {string} name - SNAKE_CASE name
     * @returns {string} Title Case name
     */
    formatName(name) {
        if (!name) return '';

        // Acronyms to preserve in uppercase
        const acronyms = new Set(['DML', 'API', 'HTTP', 'ID', 'URL', 'JSON', 'XML', 'SQL', 'SOQL', 'SOSL']);

        // Convert SNAKE_CASE to Title Case, preserving acronyms
        return name
            .split('_')
            .map(word => {
                const upper = word.toUpperCase();
                if (acronyms.has(upper)) {
                    return upper;
                }
                return word.charAt(0).toUpperCase() + word.slice(1).toLowerCase();
            })
            .join(' ');
    }
}