# UoW Transaction Orchestrator

**Enterprise-grade transaction orchestration framework for Salesforce**

[![Salesforce API](https://img.shields.io/badge/Salesforce%20API-v65.0-blue.svg)]()
[![License](https://img.shields.io/badge/License-MIT-green.svg)]()

---

## What is UoW Transaction Orchestrator?

The Unit of Work (UoW) Transaction Orchestrator is a comprehensive Apex framework that provides transactional integrity, policy-based governance, and complete observability for complex Salesforce operations.

### Key Features

- **Transactional Integrity** - All-or-none semantics with automatic rollback
- **Relationship Management** - Automatic parent-child dependency resolution
- **Complete Work Item Tracking** - All operations ALWAYS tracked with status (SUCCESS, FAILED, SKIPPED, NOT_EXECUTED)
- **Policy-Based Governance** - Pluggable policy infrastructure for custom governance rules
- **Risk Assessment** - Dynamic risk scoring with approval triggers
- **Comprehensive Audit** - Full transaction timeline with phase execution metrics
- **Record Audit Activity** - Jump straight from any business record to the transactions that touched it
- **Extensive Extensibility** - Plugins, policies, DML strategies, channels, and more (10+ extension points)
- **Data Masking** - Configuration-driven PII masking
- **Asynchronous Execution** - Queueable-based async with serialization
- **Flow Integration** - Execute UoW transactions from flows

---

## Quick Start

```apex
// Create a Unit of Work
UnitOfWork uow = new UnitOfWork('Default');

// Register parent and child with relationship
Account acc = new Account(Name = 'Acme Corp');
Contact con = new Contact(FirstName = 'Jane', LastName = 'Doe');

uow.registerInsert(acc);
uow.registerInsert(con);
uow.relate(con, Contact.AccountId, acc);

// Commit with transactional integrity
UoWResult result = uow.commitWork();

if (result.isSuccess()) {
    System.debug('Transaction succeeded: ' + result.correlationId);
    System.debug('Account ID: ' + acc.Id);
    System.debug('Contact ID: ' + con.Id);
    System.debug('Contact.AccountId: ' + con.AccountId); // Automatically populated!
} else {
    System.debug('Transaction failed: ' + result.getErrorSummary());
}
```

---

## Installation

There are two installation options available:

| Installation Option | Description |
| ------------------- | ----------- |
| [Unlocked Package](#option-1-unlocked-package) | Recommended for most users. Install via URL or CLI with easy upgrades. |
| [Unmanaged Source](#option-2-unmanaged-source-from-github) | Deploy directly from GitHub. Best for customization or development. |

### Option 1: Unlocked Package

The unlocked package is the recommended installation method. Install packages **in order** (dependencies require sequential installation).

#### Package 1: UoW Core (Required)

<a href="https://login.salesforce.com/packaging/installPackage.apexp?p0=04tJ5000000HHprIAG">
  <img alt="Install in Production" src="https://img.shields.io/badge/Install%20in-Production-0d6efd?style=for-the-badge">
</a>

<a href="https://test.salesforce.com/packaging/installPackage.apexp?p0=04tJ5000000HHprIAG">
  <img alt="Install in Sandbox" src="https://img.shields.io/badge/Install%20in-Sandbox-198754?style=for-the-badge">
</a>

```bash
sf package install --package 04tJ5000000HHprIAG --target-org <your-org-alias> --wait 10
```

#### Package 2: UoW Audit (Optional)

<a href="https://login.salesforce.com/packaging/installPackage.apexp?p0=04tJ5000000HHpwIAG">
  <img alt="Install in Production" src="https://img.shields.io/badge/Install%20in-Production-0d6efd?style=for-the-badge">
</a>

<a href="https://test.salesforce.com/packaging/installPackage.apexp?p0=04tJ5000000HHpwIAG">
  <img alt="Install in Sandbox" src="https://img.shields.io/badge/Install%20in-Sandbox-198754?style=for-the-badge">
</a>

```bash
sf package install --package 04tJ5000000HHpwIAG --target-org <your-org-alias> --wait 10
```

#### Post-Installation: Assign Permission Sets

```bash
sf org assign permset --name UoW_Core_User --target-org <your-org-alias>
sf org assign permset --name UoW_Audit_User --target-org <your-org-alias>  # If audit installed
```

---

### Option 2: Unmanaged Source from GitHub

Deploy the source code directly from GitHub. This option is useful if you need to customize the framework or contribute to development.

<a href="https://githubsfdeploy.herokuapp.com/app/githubdeploy/vipultaylor/uow-transaction-orchestrator">
  <img alt="Deploy to Production" src="https://img.shields.io/badge/Deploy%20to-Production-0d6efd?style=for-the-badge">
</a>

<a href="https://githubsfdeploy-sandbox.herokuapp.com/app/githubdeploy/vipultaylor/uow-transaction-orchestrator">
  <img alt="Deploy to Sandbox" src="https://img.shields.io/badge/Deploy%20to-Sandbox-198754?style=for-the-badge">
</a>

> **Note:** Always test in a sandbox before deploying to production.

See [Installation Guide](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Installation) for detailed instructions and troubleshooting.

---

## Documentation

### Getting Started
- [Home](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki) - Framework overview and features
- [Getting Started](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Getting-Started) - Quick start guide
- [Installation](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Installation) - Package deployment
- [Your First Transaction](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Your-First-Transaction) - Step-by-step tutorial

### Core Documentation
- [Architecture Overview](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Architecture) - Component relationships and execution flow
- [API Reference](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/API-Reference) - Complete API documentation
- [Configuration Guide](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Configuration-Guide) - Metadata setup and feature flags

### Feature Guides
- [DML Operations](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/DML-Operations) - Database operations and relationships
- [Policy System](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Policy-System) - Governance and risk assessment
- [Approval Workflows](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Approval-Workflows) - Multi-channel approval orchestration
- [Data Masking](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Data-Masking) - PII protection and masking strategies
- [Security & CRUD/FLS](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Security) - Security enforcement modes
- [Asynchronous Execution](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Async-Execution) - Background processing
- [Performance Profiling](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Performance-Profiling) - Governor limit tracking

### Extension Guides
- [Extending the Framework](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Extending-Framework) - Custom implementations
- [Custom Policies](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Custom-Policies) - Build governance rules
- [Custom Plugins](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Custom-Plugins) - Lifecycle hooks
- [Custom DML Strategies](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Custom-DML-Strategies) - Custom DML logic

### Operations & Support
- [Best Practices](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Best-Practices) - Design patterns and recommendations
- [Troubleshooting](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Troubleshooting) - Common issues and solutions
- [FAQ](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/FAQ) - Frequently asked questions
- [Known Limitations](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Known-Limitations) - Current limitations

---

## Architecture

### Package Structure

```
uow-core              Foundation framework (DML, policies, plugins)
  └── uow-audit       Observability (audit trails, timeline visualization)
```

> **Note:** Additional extension packages (e.g., approval workflows) may be released separately in the future.

### Component Diagram

![UoW Architecture Overview](https://raw.githubusercontent.com/wiki/vipultaylor/uow-transaction-orchestrator/images/uow-architecture-overview.svg)

See [Architecture Overview](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Architecture) for detailed diagrams.

---

## Examples

### Multi-Level Hierarchy

```apex
UnitOfWork uow = new UnitOfWork('Default');

// Level 1: Grandparent
Account grandparent = new Account(Name = 'Acme Corp');
uow.registerInsert(grandparent);

// Level 2: Parent
Account parent = new Account(Name = 'Acme Division');
uow.registerInsert(parent);
uow.relate(parent, Account.ParentId, grandparent);

// Level 3: Contact
Contact con = new Contact(FirstName = 'Jane', LastName = 'Doe');
uow.registerInsert(con);
uow.relate(con, Contact.AccountId, parent);

// Framework resolves relationships automatically
UoWResult result = uow.commitWork();
```

### Policy-Based Governance

```apex
UnitOfWork uow = new UnitOfWork('Default');
uow.registerInsert(new Contact(
    LastName = 'Doe',
    Email = 'john.doe@example.com',
    Phone = '555-1234'
));

UoWResult result = uow.commitWork();

// Policies evaluate automatically (if registered)
UoWPolicyEvaluation.Summary summary = result.policyEvalSummary;
for (UoWPolicyEvaluation.Evaluation eval : summary.getEvaluations()) {
    System.debug(eval.policyName + ': ' + eval.action + ' - ' + eval.reason);
}
```

### Asynchronous Execution

```apex
UnitOfWork uow = new UnitOfWork('Default');
// ... register large volume of operations ...

// Execute in background with Queueable
UoWResult result = uow.commitWork(UoWEnums.CommitMode.ASYNC);
System.debug('Async job queued: ' + result.correlationId);
```

### Approval Workflows

```apex
UnitOfWork uow = new UnitOfWork('Default');
// ... register high-risk operations ...

// Policies evaluate risk and trigger approval if needed
UoWResult result = uow.commitWork();

if (result.transactionStatus == UoWEnums.TransactionStatus.PENDING_APPROVAL) {
    System.debug('Approval requested by policy: ' + result.correlationId);
    // Approval request sent to configured channel (Salesforce, Slack, custom)
    // Transaction resumes automatically after approval
}
```

More examples in [Getting Started](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Getting-Started) and [Common Patterns](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Common-Patterns).

---

## Features

### Transactional Operations

| Feature | Description |
|---------|-------------|
| **DML Operations** | INSERT, UPDATE, DELETE, UPSERT, UNDELETE |
| **Relationships** | Automatic parent-child dependency resolution |
| **Platform Events** | Event publishing with phase control |
| **Emails** | Single and mass email with templates |
| **Custom Notifications** | Bell notifications with recipient targeting |
| **Flows** | Synchronous flow invocation |
| **Callouts** | HTTP requests with timeout management |
| **Complete Work Item Tracking** | All work items tracked with status (SUCCESS, FAILED, SKIPPED, NOT_EXECUTED) |

### Governance

| Feature | Description |
|---------|-------------|
| **Policy System** | Pluggable governance with ALLOW/DENY/APPROVE/MASK actions |
| **Risk Assessment** | Dynamic risk scoring with threshold triggers |
| **CRUD/FLS Enforcement** | Security validation with ENFORCED/PERMISSIVE modes |
| **Governor Limit Policies** | Threshold-based limit enforcement |
| **PII Detection** | Automatic sensitive data identification |
| **Data Masking** | Configuration-driven field masking |

### Observability & Audit

| Feature | Description |
|---------|-------------|
| **[Timeline Visualization](#audit-features)** | OpenTelemetry-based hierarchical execution timeline with phase tracking |
| **[Governor Limits Tracking](#audit-features)** | Per-operation limit consumption with before/after snapshots |
| **[Configuration Snapshot](#audit-features)** | Historical capture of settings in effect at execution time |
| **[Work Item Snapshots](#audit-features)** | Record-level data capture for DML, events, and emails |
| **[Record Audit Activity](#audit-features)** | Record-page component linking a business record to the transactions/work items that touched it |
| **[Origin Source Metadata](#audit-features)** | Track which code registered each operation with line numbers |
| **[Error Tracking](#audit-features)** | Detailed errors with stack traces, suggestions, and retry info |
| **[Messages Console](#audit-features)** | Developer console-style log viewer with severity filtering |
| **User & Org Context** | Execution context, user tracking, and scenario tagging |

### Extensibility

The framework provides **10+ extension points** for customizing every aspect of transaction processing:

| Extension Point | Purpose | Cardinality |
|-----------------|---------|-------------|
| **IPolicy** | Custom governance rules (ALLOW/DENY/APPROVE/MASK) | Multi-instance |
| **IPlugin** | Lifecycle hooks (before/after/error/finally) | Multi-instance |
| **IDmlStrategy** | Custom DML execution logic per SObject | Per-SObject |
| **IMaskingStrategy** | Custom data masking algorithms | Per-field |
| **IRiskAssessor** | Custom risk scoring logic | Single-instance |
| **IEventChannel** | Custom platform event publishing | Single-instance |
| **IEmailChannel** | Custom email sending | Single-instance |
| **INotificationChannel** | Custom notification delivery | Single-instance |
| **IFlowChannel** | Custom flow invocation | Single-instance |
| **ICalloutStrategy** | Custom HTTP callout handling | Single-instance |
| **IApprovalChannel** | Custom approval systems (Slack, Teams, custom) | Single-instance |

See [Extending Framework](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Extending-Framework) for implementation guides.

---

## Audit Features

The UoW Audit Package provides enterprise-grade observability with rich visualization components.

> **Full documentation:** [Audit System](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Audit-System)

### Transaction Overview

Browse and search all audited transactions with status, scenario tags, execution context, and timing.

> ![Audit Transactions List View](https://raw.githubusercontent.com/wiki/vipultaylor/uow-transaction-orchestrator/images/screenshots/audit-transactions-list-view.png)

### Timeline Visualization

OpenTelemetry-based hierarchical view of transaction execution with phase-level timing and status indicators.

> ![Timeline - Successful Transaction](https://raw.githubusercontent.com/wiki/vipultaylor/uow-transaction-orchestrator/images/screenshots/timeline-success.png)

### Work Item Tracking

ALL registered work items are captured with their final status — SUCCESS, FAILED, SKIPPED, or NOT_EXECUTED — along with record snapshots and origin source metadata.

> ![Work Items](https://raw.githubusercontent.com/wiki/vipultaylor/uow-transaction-orchestrator/images/screenshots/work-items-success.png)

### Governor Limits Tracking

Per-operation limit consumption with before/after snapshots across DML, SOQL, CPU, heap, callouts, and more.

> ![Governor Limits](https://raw.githubusercontent.com/wiki/vipultaylor/uow-transaction-orchestrator/images/screenshots/governor-limits-transaction.png)

### Messages Console & Error Tracking

Developer console-style log viewer with severity filtering, detailed error capture with stack traces, and contextual suggestions.

> ![Messages Console](https://raw.githubusercontent.com/wiki/vipultaylor/uow-transaction-orchestrator/images/screenshots/logs-tab.png)

### Record Audit Activity

Drop the **UoW: Record Audit Activity** component onto any object's Lightning record page to see the UoW transactions and work items that touched that record — grouped by transaction, most-recent-first, with direct links to the audit records. Powered by an indexed reverse lookup (`UoWAuditRecordIndex__c`) written per sampled record; disable per object via `AuditSampleStrategy = NONE`.

See [Audit System Documentation](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Audit-System) for architecture, storage modes, configuration, and all feature details.

---

## Package Contents

### uow-core (~100 Apex classes)
- UnitOfWork API and execution engine
- Work item types (DML, Event, Email, Notification, Flow, Callout)
- Relationship management and dependency resolution
- Policy, plugin, and DML strategy registries and resolvers
- Flow integration (15 invocable actions)
- Services (caching, masking, serialization, tracing, configuration)
- Base classes and default channel implementations
- Test utilities (mocks, chaos engine, helpers)
- 8 custom metadata types for configuration

### uow-audit (~30 Apex classes + Objects + Visualization)
- Audit plugin with platform event-based capture
- Custom objects (transactions, work items, record index, scenarios, publish failures)
- Big Object for long-term audit history storage
- ~16 Lightning Web Components (timeline, record audit activity, messages console, error details, snapshots, and more)

---

## Configuration

All framework behavior is controlled via custom metadata:

| Metadata Type | Purpose |
|---------------|---------|
| `UoWConfiguration__mdt` | Global feature flags, security mode, thresholds |
| `UoWObjectSetting__mdt` | Per-object security and DML strategy overrides |
| `UoWPluginSetting__mdt` | Plugin registration and execution order |
| `UoWPolicySetting__mdt` | Policy registration and evaluation order |
| `UoWDataMaskRule__mdt` | Data masking rules for sensitive fields |

See [Configuration Guide](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Configuration-Guide) for detailed setup.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Support

- **Documentation:** [Wiki](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki)
- **Issues:** [GitHub Issues](https://github.com/vipultaylor/uow-transaction-orchestrator/issues)
- **Discussions:** [GitHub Discussions](https://github.com/vipultaylor/uow-transaction-orchestrator/discussions)

---

## Credits

Built with enterprise Salesforce best practices. Implements the Unit of Work pattern with modern transaction orchestration capabilities.

---

**Ready to get started?** See [Getting Started Guide](https://github.com/vipultaylor/uow-transaction-orchestrator/wiki/Getting-Started) for your first transaction in under 10 minutes.
