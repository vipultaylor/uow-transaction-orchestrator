//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
import { LightningElement, api, track, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import { NavigationMixin } from 'lightning/navigation';
import getHierarchyByCorrelationId from '@salesforce/apex/UoWTransactionHierarchyController.getHierarchyByCorrelationId';
import getHierarchyByTransactionId from '@salesforce/apex/UoWTransactionHierarchyController.getHierarchyByTransactionId';

import TRANSACTION_OBJECT from '@salesforce/schema/UoWAuditTransaction__c';
import CORRELATION_ID_FIELD from '@salesforce/schema/UoWAuditTransaction__c.CorrelationId__c';
import STATUS_FIELD from '@salesforce/schema/UoWAuditTransaction__c.TransactionStatus__c';

/**
 * Transaction Hierarchy Viewer - displays parent-child transaction relationships
 * in a simple tabular view similar to Salesforce Account Hierarchy.
 */
export default class UowTransactionHierarchy extends NavigationMixin(LightningElement) {
    @api recordId;
    @api correlationId;
    @api title = 'Transaction Hierarchy';

    @track hierarchy;
    @track expandedNodes = new Set();
    @track isLoading = true;
    @track error;

    statusLabels = {};
    defaultRecordTypeId;

    // Get object info to retrieve default record type ID
    @wire(getObjectInfo, { objectApiName: TRANSACTION_OBJECT })
    wiredObjectInfo({ error, data }) {
        if (data) {
            this.defaultRecordTypeId = data.defaultRecordTypeId;
        } else if (error) {
            console.warn('Could not load object info:', error);
        }
    }

    // Load picklist values for status labels
    @wire(getPicklistValues, { recordTypeId: '$defaultRecordTypeId', fieldApiName: STATUS_FIELD })
    wiredPicklistValues({ error, data }) {
        if (data) {
            this.statusLabels = {};
            data.values.forEach(item => {
                this.statusLabels[item.value] = item.label;
            });
        } else if (error) {
            // Fallback - use API values as labels
            console.warn('Could not load status picklist values:', error);
        }
    }

    // Get correlation ID from record context if not provided
    @wire(getRecord, { recordId: '$recordId', fields: [CORRELATION_ID_FIELD] })
    wiredRecord({ error, data }) {
        if (data && !this.correlationId) {
            const corrId = getFieldValue(data, CORRELATION_ID_FIELD);
            if (corrId) {
                this.loadHierarchy(corrId);
            }
        } else if (error) {
            this.error = error.body?.message || 'Error loading record';
            this.isLoading = false;
        }
    }

    connectedCallback() {
        if (this.correlationId) {
            this.loadHierarchy(this.correlationId);
        } else if (this.recordId) {
            this.loadHierarchyByTransaction();
        }
    }

    async loadHierarchy(corrId) {
        this.isLoading = true;
        this.error = null;
        try {
            const result = await getHierarchyByCorrelationId({ correlationId: corrId });
            this.hierarchy = result;
            // Expand all nodes by default
            if (result?.root) {
                this.expandAllNodes(result.root);
            }
        } catch (e) {
            this.error = e.body?.message || 'Error loading hierarchy';
        } finally {
            this.isLoading = false;
        }
    }

    async loadHierarchyByTransaction() {
        this.isLoading = true;
        this.error = null;
        try {
            const result = await getHierarchyByTransactionId({ transactionRecordId: this.recordId });
            this.hierarchy = result;
            // Expand all nodes by default
            if (result?.root) {
                this.expandAllNodes(result.root);
            }
        } catch (e) {
            this.error = e.body?.message || 'Error loading hierarchy';
        } finally {
            this.isLoading = false;
        }
    }

    get hasHierarchy() {
        return this.hierarchy?.root != null;
    }

    get rootNode() {
        return this.hierarchy?.root;
    }

    /**
     * Flatten the tree into rows for table display
     */
    get flattenedRows() {
        if (!this.rootNode) return [];
        const rows = [];
        this.flattenNode(this.rootNode, 0, rows);
        return rows;
    }

    flattenNode(node, level, rows) {
        const isExpanded = this.expandedNodes.has(node.id);
        const hasChildren = node.hasChildren || (node.children && node.children.length > 0);

        rows.push({
            ...node,
            level,
            isExpanded,
            hasChildren,
            isCurrentRecord: node.id === this.recordId,
            expandIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
            indentStyle: hasChildren ? `padding-left: ${level * 1.5}rem;` : `padding-left: ${(level * 1.5) + 1.5}rem;`,
            rowClass: node.id === this.recordId ? 'current-record-row' : '',
            statusLabel: this.getStatusLabel(node.status)
        });

        // Add children if expanded
        if (isExpanded && node.children) {
            node.children.forEach(child => this.flattenNode(child, level + 1, rows));
        }
    }

    getStatusLabel(status) {
        return this.statusLabels[status] || status || '';
    }

    expandAllNodes(node) {
        if (!node) return;
        this.expandedNodes.add(node.id);
        if (node.children) {
            node.children.forEach(child => this.expandAllNodes(child));
        }
    }

    handleToggle(event) {
        const nodeId = event.currentTarget.dataset.nodeId;
        if (this.expandedNodes.has(nodeId)) {
            this.expandedNodes.delete(nodeId);
        } else {
            this.expandedNodes.add(nodeId);
        }
        // Trigger re-render
        this.expandedNodes = new Set(this.expandedNodes);
    }

    handleNavigate(event) {
        event.preventDefault();
        const recordId = event.currentTarget.dataset.recordId;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                objectApiName: 'UoWAuditTransaction__c',
                actionName: 'view'
            }
        });
    }
}