# SocioWatch Salesforce

Salesforce managed-package source for SocioWatch. SocioWatch collects online
brand mentions in AWS and imports customer-visible, actionable mentions into
Salesforce for monitoring, follow-up, and intelligence chat.

## Architecture

- Salesforce stores the company configuration and imported actionable mentions.
- AWS stores the complete mention history and runs the source collectors.
- Salesforce calls AWS only through the `SocioWatch_API` Named Credential.
- No AWS credentials, API tokens, or session identifiers are stored in Apex,
  LWC, custom-object records, or source control.
- Salesforce and AWS run separate schedules. AWS collects source data according
  to each connector's EventBridge schedule. Salesforce imports currently
  available mentions once per hour.

SocioWatch AWS resources used by this project are in `us-east-2`.

## First-time setup

1. Deploy or install the package, then populate the secret token on the
   source-controlled `SocioWatch_API_Authentication` External Credential as described in
   [`docs/named-credential-setup.md`](docs/named-credential-setup.md).
2. Assign `SocioWatch Admin` to administrators. Assign `SocioWatch User` to
   users who need the dashboard and chat experience.
3. Open SocioWatch Settings and enter the company name, website, primary
   business city, state or province, country, and monitoring keywords. Leave
   **Include Google Reviews** and monitoring enabled, then save.
4. The settings request creates or updates the company in AWS. For a newly
   created company, AWS starts the initial onboarding collection and dispatches
   source discovery, RSS, GDELT, X, YouTube, Webz, and Google Reviews
   collection. The business location is resolved to its Google Business
   Profile before review collection. These jobs are asynchronous, so all
   results might not be available immediately.
5. When monitoring is enabled, saving Settings automatically creates the
   hourly Salesforce job named **SocioWatch Mentions Job**. This setup is
   idempotent, so later saves reuse the existing job. No Execute Anonymous
   script or manual scheduling step is required. An administrator can confirm
   the job under **Setup > Scheduled Jobs**.

## How synchronization works

### Initial company onboarding

Saving settings sends `POST /v1/settings` to AWS. When AWS creates a new
company and monitoring is enabled, it invokes the company reader with
`triggerSource=initial-onboarding`. Source discovery runs first so RSS can use
the discovered official feeds. RSS, GDELT, X, YouTube, and Webz are then
dispatched asynchronously. When Google Reviews is enabled, the saved business
location is resolved and its reviews are collected into the same AWS mentions
table. AWS EventBridge schedules are responsible for later recurring collection
runs.

### Hourly Salesforce import

**SocioWatch Mentions Job** runs `SocioWatchSyncScheduler` at the top of every
hour. If exactly one enabled configuration exists and it has an AWS company ID,
it enqueues
`SocioWatchImportQueueable`. The queueable:

1. Calls `GET /v1/mentions?companyId=...` through the Named Credential.
2. Keeps customer-visible actionable mentions returned by AWS.
3. Upserts them by external mention ID so repeated imports do not create
   duplicates.
4. Updates the last-successful-sync timestamp and status in Salesforce.

Google Reviews require no separate Salesforce import. They are returned by the
same mentions endpoint and upserted into `SocioWatch_Mention__c` with source
**Google Reviews**, alongside all other mention sources. Review rating is shown
in the generated title and review text is stored in the standard mention text
field. The **Review Mentions** list view includes both Webz and Google reviews.

The hourly Salesforce job imports mentions already available in AWS; it does
not trigger every AWS collector. Collector frequency is controlled by the AWS
EventBridge schedules for each source.

### Sync Now

The **Sync Now** button enqueues `SocioWatchSyncQueueable`. It first sends
`POST /v1/sync` to request an on-demand AWS collection, then immediately imports
mentions that AWS already has. Because collection is asynchronous, mentions
created by that request can arrive later and are picked up by the next hourly
Salesforce import. Sync Now is therefore a collection request plus an immediate
best-effort import, not a wait for every connector to finish.

Turning off monitoring prevents manual and scheduled Salesforce sync. AWS must
also honor the stored `SyncEnabled` value when its connector schedules run.

## Development and verification

- Salesforce DX source format
- Second-generation managed packaging
- Scratch-org-based development and testing
- GitHub as the source of truth
- Salesforce Code Analyzer security and AppExchange rule scans
- Apex tests and check-only deployment validation before deployment
- LWC ESLint and Jest tooling

Run the local checks with:

```bash
npm install
npm run lint
npm run test:unit -- -- --runInBand --passWithNoTests
sf code-analyzer run --workspace . --target force-app --rule-selector Security --severity-threshold 3
sf code-analyzer run --workspace . --target force-app --rule-selector AppExchange --severity-threshold 3
```

The current security-review record, documented scanner false positives, and
remaining submission work are in
[`docs/security-review.md`](docs/security-review.md).

## Security principles

- Explicit sharing declarations
- User-mode SOQL and DML for subscriber data access
- CRUD and field-level security enforcement
- Named Credentials and External Credentials
- No browser-to-AWS credential exposure
- Input validation and endpoint allowlisting
- Tenant and company mapping integrity
- Sanitized exception handling
- Salesforce Code Analyzer validation
