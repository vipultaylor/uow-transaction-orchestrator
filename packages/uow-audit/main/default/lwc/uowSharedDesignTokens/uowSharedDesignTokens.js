//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * @description Centralized design tokens for UoW Audit LWC components.
 *              This module exports JavaScript constants that complement the CSS
 *              custom properties defined in uowSharedStylesModule.css.
 *
 *              Use these tokens for icon names and CSS class suffixes.
 *
 * @example
 * import { WORK_TYPE_TOKENS, getToken } from 'c/uowSharedDesignTokens';
 * const config = getToken(WORK_TYPE_TOKENS, workType);
 * // config.icon -> 'utility:edit'
 * // config.suffix -> 'dml'
 *
 * @group UoW Audit
 */

// =============================================================================
// WORK TYPE TOKENS (Canonical Order: DML → EVENT → FLOW → EMAIL → NOTIFICATION → CALLOUT)
// =============================================================================

/**
 * Work type configuration for user-registered operations.
 * Used by uowWorkItemEvent to render work item icons and styles.
 */
const WORK_TYPE_TOKENS = {
    DML:          { icon: 'utility:edit',         suffix: 'dml' },
    EVENT:        { icon: 'utility:announcement', suffix: 'event' },
    FLOW:         { icon: 'utility:flow',         suffix: 'flow' },
    EMAIL:        { icon: 'utility:email',        suffix: 'email' },
    NOTIFICATION: { icon: 'utility:notification', suffix: 'notification' },
    CALLOUT:      { icon: 'utility:share_post',   suffix: 'callout' }
};

// =============================================================================
// CATEGORY TOKENS (Span categories for timeline visualization)
// =============================================================================

/**
 * Category configuration for OTel-aligned span visualization.
 * Used by uowSpanItem to render span icons and connector line colors.
 * Maps to CSS variables: --uow-category-{suffix}
 */
const CATEGORY_TOKENS = {
    // Framework categories
    FRAMEWORK:    { icon: 'utility:layers',           suffix: 'framework' },
    TRANSACT:     { icon: 'utility:database',         suffix: 'transaction' },

    // Work type categories
    DML:          { icon: 'utility:record_update',    suffix: 'dml' },
    EVENT:        { icon: 'utility:broadcast',        suffix: 'event' },
    FLOW:         { icon: 'utility:flow',             suffix: 'flow' },
    EMAIL:        { icon: 'utility:email',            suffix: 'email' },
    NOTIFICATION: { icon: 'utility:notification',     suffix: 'notification' },
    CALLOUT:      { icon: 'utility:link',             suffix: 'callout' },

    // Extensibility patterns
    POLICY:       { icon: 'utility:shield',           suffix: 'policy' },
    PLUGIN:       { icon: 'utility:connected_apps',   suffix: 'plugin' },
    RISK:         { icon: 'utility:warning',          suffix: 'risk' },
    APPROVAL:     { icon: 'utility:approval',         suffix: 'approval' },

    // Other framework categories
    VALIDATION:   { icon: 'utility:check',            suffix: 'validation' },
    SECURITY:     { icon: 'utility:lock',             suffix: 'security' },
    DEPENDENCY:   { icon: 'utility:hierarchy',        suffix: 'dependency' },
    WORK_PHASE:   { icon: 'utility:stage_collection', suffix: 'work_phase' },
    FINALIZATION: { icon: 'utility:lock',             suffix: 'finalization' }
};

// =============================================================================
// STATUS TOKENS (Transaction/work item result states)
// =============================================================================

/**
 * Status configuration for transaction and work item results.
 * Maps to CSS variables: --uow-status-{suffix}
 */
const STATUS_TOKENS = {
    SUCCESS: { icon: 'utility:success', suffix: 'success' },
    WARNING: { icon: 'utility:warning', suffix: 'warning' },
    ERROR:   { icon: 'utility:error',   suffix: 'error' }
};

// =============================================================================
// EVENT TYPE TOKENS (Span events - point-in-time occurrences)
// =============================================================================

/**
 * Event type configuration for OTel span events.
 * Used by uowSpanEvent to render event icons and styles.
 */
const EVENT_TYPE_TOKENS = {
    STATE:    { icon: 'utility:record',  suffix: 'state' },
    DECISION: { icon: 'utility:choice',  suffix: 'decision' },
    RISK:     { icon: 'utility:warning', suffix: 'risk' },
    ERROR:    { icon: 'utility:error',   suffix: 'error' },
    WARNING:  { icon: 'utility:warning', suffix: 'warning' },
    INFO:     { icon: 'utility:info',    suffix: 'info' }
};

// =============================================================================
// DEFAULT TOKEN (Fallback for unknown keys)
// =============================================================================

/**
 * Default token used when a key is not found in any token map.
 */
const DEFAULT_TOKEN = { icon: 'utility:forward', suffix: 'default' };

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

/**
 * Safely retrieves a token from a token map with fallback to DEFAULT_TOKEN.
 *
 * @param {Object} tokenMap - The token map to search (e.g., WORK_TYPE_TOKENS)
 * @param {string} key - The key to look up
 * @returns {Object} Token object with icon and suffix properties
 *
 * @example
 * const config = getToken(WORK_TYPE_TOKENS, 'DML');
 * // Returns: { icon: 'utility:edit', suffix: 'dml' }
 *
 * const unknown = getToken(WORK_TYPE_TOKENS, 'UNKNOWN');
 * // Returns: { icon: 'utility:forward', suffix: 'default' }
 */
function getToken(tokenMap, key) {
    return tokenMap[key] || DEFAULT_TOKEN;
}

export {
    WORK_TYPE_TOKENS,
    CATEGORY_TOKENS,
    STATUS_TOKENS,
    EVENT_TYPE_TOKENS,
    DEFAULT_TOKEN,
    getToken
};