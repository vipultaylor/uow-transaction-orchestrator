//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Generic code viewer component with Prism.js syntax highlighting.
 * Used by uowMetadataViewer, uowSnapshotViewer, and other components
 * that need to display code with syntax highlighting.
 *
 * Features:
 * - Prism.js syntax highlighting
 * - Line numbers (optional)
 * - Line highlighting (optional)
 * - Multiple language support (java/apex, json, text)
 * - Fallback to plain display if Prism fails to load
 */
import { LightningElement, api } from 'lwc';
import { loadScript, loadStyle } from 'lightning/platformResourceLoader';

import PRISM from '@salesforce/resourceUrl/UoWPrism';

export default class UowCodeViewer extends LightningElement {
    // ============================================================================
    // PUBLIC API
    // ============================================================================

    /**
     * The code/text to display
     */
    @api code = '';

    /**
     * Language for syntax highlighting.
     * Supported: 'java' (for Apex), 'json', 'javascript', 'text'
     * Default: 'java'
     */
    @api language = 'java';

    /**
     * Starting line number (1-indexed).
     * If set, line numbers will be displayed.
     */
    @api startLine;

    /**
     * Line number to highlight (absolute line number, not relative).
     * Only works when startLine is also set.
     */
    @api highlightLine;

    /**
     * Whether to show line numbers.
     * Default: true if startLine is provided
     */
    @api showLineNumbers;

    /**
     * Maximum height of the code container.
     * Default: '400px'
     */
    @api maxHeight = '400px';

    // ============================================================================
    // PRIVATE STATE
    // ============================================================================

    prismLoaded = false;
    prismLoadError = false;
    hasRendered = false;

    // ============================================================================
    // LIFECYCLE HOOKS
    // ============================================================================

    renderedCallback() {
        if (this.hasRendered) {
            // If code changed, re-highlight
            if (this.code && this.prismLoaded) {
                this.highlightCode();
            }
            return;
        }

        this.hasRendered = true;

        if (this.code) {
            this.loadPrismAndHighlight();
        }
    }

    // ============================================================================
    // PRIVATE METHODS
    // ============================================================================

    async loadPrismAndHighlight() {
        if (this.prismLoaded) {
            this.highlightCode();
            return;
        }

        try {
            await Promise.all([
                loadStyle(this, PRISM + '/prism.css'),
                loadScript(this, PRISM + '/prism.js')
            ]);

            this.prismLoaded = true;
            this.highlightCode();
        } catch (ex) {
            console.error('Error loading Prism:', ex);
            this.prismLoadError = true;
            this.displayPlainCode();
        }
    }

    highlightCode() {
        if (!this.code) {
            return;
        }

        const container = this.template.querySelector('.uow-code-viewer-container');
        if (!container) {
            return;
        }

        // Escape HTML entities in the source code to prevent XSS
        const escapedCode = this.escapeHtml(this.code);

        // Determine if we should show line numbers
        const showNumbers = this.showLineNumbers !== undefined
            ? this.showLineNumbers
            : this.startLine !== undefined;

        // Build pre element classes
        const preClasses = showNumbers ? 'line-numbers' : '';

        // Build data attributes
        // data-start: sets starting line number for line-numbers plugin
        // data-line: line(s) to highlight (absolute line numbers)
        // data-line-offset: offset for line-highlight plugin when using data-start
        const dataStart = this.startLine ? `data-start="${this.startLine}"` : '';
        const dataLine = this.highlightLine ? `data-line="${this.highlightLine}"` : '';
        // Line offset is startLine - 1 (since data-line uses 1-indexed but offset is 0-indexed adjustment)
        const dataLineOffset = (this.startLine && this.highlightLine) ? `data-line-offset="${this.startLine - 1}"` : '';

        // Get Prism language class
        const langClass = this.getPrismLanguageClass();

        // Build and inject HTML
        container.innerHTML =
            `<pre class="${preClasses}" ${dataStart} ${dataLine} ${dataLineOffset} style="max-height: ${this.maxHeight}">` +
            `<code class="${langClass}">${escapedCode}</code></pre>`;

        // Trigger Prism highlighting
        if (window.Prism) {
            window.Prism.highlightAll();
        }
    }

    displayPlainCode() {
        if (!this.code) {
            return;
        }

        const container = this.template.querySelector('.uow-code-viewer-container');
        if (!container) {
            return;
        }

        // Escape HTML entities
        const escapedCode = this.escapeHtml(this.code);

        // Display as plain preformatted text with basic styling
        container.innerHTML =
            `<pre class="uow-plain-code" style="max-height: ${this.maxHeight}">` +
            `<code>${escapedCode}</code></pre>`;
    }

    getPrismLanguageClass() {
        const langMap = {
            'java': 'language-java',      // Apex uses Java-like syntax
            'apex': 'language-java',
            'json': 'language-json',
            'javascript': 'language-javascript',
            'js': 'language-javascript',
            'text': 'language-none',
            'log': 'language-none',
            'plain': 'language-none'
        };

        return langMap[this.language?.toLowerCase()] || 'language-java';
    }

    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    // ============================================================================
    // PUBLIC METHODS
    // ============================================================================

    /**
     * Force re-render of the code.
     * Call this if the code property is updated dynamically.
     */
    @api
    refresh() {
        if (this.prismLoaded) {
            this.highlightCode();
        } else if (this.prismLoadError) {
            this.displayPlainCode();
        } else {
            this.loadPrismAndHighlight();
        }
    }
}