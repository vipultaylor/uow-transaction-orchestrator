//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * @description Reusable empty state component for displaying placeholder content
 *              when no data is available. Configurable icon, heading, and body text.
 *
 * @example
 * <c-uow-empty-state
 *     icon-name="utility:success"
 *     icon-variant="success"
 *     heading="No Errors"
 *     body="No errors were recorded.">
 * </c-uow-empty-state>
 */
import { LightningElement, api } from 'lwc';

export default class UowEmptyState extends LightningElement {
    /**
     * Lightning icon name (e.g., "utility:success", "utility:warning")
     * @type {string}
     */
    @api iconName = 'utility:info';

    /**
     * Main heading text
     * @type {string}
     */
    @api heading = '';

    /**
     * Body/description text
     * @type {string}
     */
    @api body = '';

    /**
     * Icon size (xx-small, x-small, small, medium, large)
     * @type {string}
     */
    @api iconSize = 'large';

    /**
     * Icon variant (bare, default, brand, inverse, error, success, warning)
     * Uses lightning-icon's native variant property
     * @type {string}
     */
    @api iconVariant = '';

    /**
     * Whether to show the heading
     */
    get hasHeading() {
        return Boolean(this.heading);
    }

    /**
     * Whether to show the body
     */
    get hasBody() {
        return Boolean(this.body);
    }
}