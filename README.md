# SocioWatch Salesforce

Salesforce managed-package source for SocioWatch.

## Product

SocioWatch converts online brand mentions into actionable customer intelligence through Salesforce and AWS integrations.

## Development model

- Salesforce DX source format
- Second-generation managed packaging
- Scratch-org-based development and testing
- GitHub as the source of truth
- AWS API access through Named Credentials
- No credentials stored in Apex, LWC, metadata records, or source control

## Planned components

- SocioWatch Settings
- Actionable Mention records
- AI Chat
- Manual Sync
- Scheduled Sync
- AWS integration
- Permission sets
- Security-review test suite

## Security principles

- Explicit sharing declarations
- User-mode SOQL and DML where appropriate
- CRUD and field-level security enforcement
- Named Credentials and External Credentials
- No browser-to-AWS credential exposure
- Input validation
- Tenant isolation
- Safe exception handling
- Salesforce Code Analyzer validation