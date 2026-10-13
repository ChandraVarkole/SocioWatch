# SocioWatch AppExchange Security Scan Record

Final scan date: 2026-09-16

Scanner: Salesforce Code Analyzer 5.16.0

Scope: `force-app`

## Results

| Check                                  | Result                                                                          |
| -------------------------------------- | ------------------------------------------------------------------------------- |
| Salesforce `Security` rules            | 0 unsuppressed violations                                                       |
| Salesforce `AppExchange` rules         | 0 unsuppressed violations                                                       |
| Salesforce Graph Engine                | 112 paths analyzed; 0 detected violations                                       |
| Project ESLint                         | Passed                                                                          |
| Code Analyzer recommended ESLint rules | 0 critical, high, or moderate findings; low SLDS styling suggestions only       |
| LWC Jest                               | Passed with no test files present                                               |
| Production npm dependencies            | 0 vulnerabilities                                                               |
| Development npm dependencies           | 4 low-severity transitive advisories; no moderate, high, or critical advisories |
| Check-only Apex validation             | Passed: 112 components, 83/83 tests, no coverage warnings                       |
| Post-deployment Apex tests             | Passed: 87/87 tests in `CV_DEV`                                                 |

Generated JSON and HTML reports are written under `reports/` and intentionally
ignored by Git.

## Security fixes made

1. Removed the unnecessary `CreatedDate` ordering from the system-mode
   singleton-ID query in `SocioWatchSettingsService`. The query now reads only
   `Id`; subscriber data is still queried separately with `WITH USER_MODE`.
2. Renamed the Named Credential callout-prefix constant in
   `SocioWatchApiClient`. The previous variable name caused a credential-rule
   false positive even though the stored value was a Salesforce
   `callout:` reference rather than a credential.
3. Corrected the LWC lint target and the single reported JavaScript lint issue.
4. Added a bounded Code Analyzer configuration for the documented metadata
   false positives below.
5. Kept path-traversal checks scoped to the URL path while URL-decoding and
   strictly validating the only allowed query parameter (`companyId`).
6. Corrected an Apex test helper that passed a null assertion message, which
   newer platform behavior rejects.
7. Made hourly scheduling idempotent. Saving enabled Settings creates
   `SocioWatch Mentions Job`; a healthy existing hourly job is reused, while a
   legacy-named or unhealthy job is safely replaced.

## Documented false positives

The PMD `ProtectSensitiveData` rule uses field-name heuristics. It identifies
these three business-data fields as potential authentication material:

- `SocioWatch_Configuration__c.Keywords__c`: public brand-monitoring terms.
- `SocioWatch_Mention__c.Assigned_To__c`: a Salesforce `User` lookup.
- `SocioWatch_Mention__c.Author_Name__c`: a public author display name.

None stores secrets, passwords, access tokens, API keys, session identifiers,
or authentication material. `code-analyzer.yml` suppresses exactly one
`pmd:ProtectSensitiveData` result per named metadata file. The maximum count
prevents the suppression from hiding future findings.

## Graph Engine limitation and manual verification

Graph Engine 5.16.0 raised an internal `UnexpectedException` while traversing
the `SocioWatchSettingsController.saveSettings` path at the boolean expression
passed to `saveConfiguration`. This is an analyzer failure, not a reported
vulnerability.

That path was manually verified:

- `SocioWatchPermissionService.requireManageSettings()` gates the operation.
- `SocioWatchSettingsRequest.normalizedCopy()` validates and normalizes input.
- The external request uses the fixed Salesforce Named Credential endpoint.
- Existing configuration data is read with `WITH USER_MODE`.
- Inserts and updates use `AccessLevel.USER_MODE`.
- The system-mode singleton query selects only `Id` and returns no field data.
- Controller errors are converted to sanitized user-facing messages.

Retain the final scanner reports and this explanation with the AppExchange
security-review evidence.

## Apex validation and deployment

The final check-only validation against `CV_DEV` succeeded with all 112
components compiled, 83 of 83 validation tests passing, and no per-class
coverage warnings. Salesforce Quick Deploy then deployed that exact validated
artifact as deployment `0AfHs00002zSCy4KAG`.

The complete SocioWatch suite was run again against the deployed source. All
87 tests passed. Coverage for the security-related controller changes was:

- `SocioWatchSettingsController`: 75%
- `SocioWatchSyncController`: 75%
- `SocioWatchPermissionService`: 90%
- `SocioWatchChatController`: 77%

The deployed scheduler setup was also invoked twice. Both invocations returned
job ID `08eHs000043rp13IAA`; the second performed zero DML, confirming that a
healthy existing job is not overwritten. `CV_DEV` has exactly one active
`SocioWatch Mentions Job` in `WAITING` state with cron expression
`0 0 * * * ?`, and no active legacy-named job.

The org-wide coverage shown by `CV_DEV` remains affected by unrelated sample
code already present in that development org; it is not the managed-package
coverage result.

## Commands

```bash
sf code-analyzer run \
  --workspace . \
  --target force-app \
  --rule-selector Security \
  --severity-threshold 3

sf code-analyzer run \
  --workspace . \
  --target force-app \
  --rule-selector AppExchange \
  --severity-threshold 3

npm run lint
npm run test:unit -- -- --runInBand --passWithNoTests
npm audit --omit=dev
```

## Remaining submission work

A clean static scan does not guarantee AppExchange approval. Before submission:

1. Install the exact managed-package version into a fresh org and repeat the
   functional and permission-set tests.
2. Complete the required dynamic scan against every external web endpoint.
3. Prepare reviewer credentials, setup instructions, architecture/data-flow
   documentation, and false-positive explanations.
4. Verify Named Credential and External Credential provisioning in a clean
   subscriber org without placing secrets in package metadata.

Salesforce Code Analyzer suppression guidance:
https://developer.salesforce.com/docs/platform/salesforce-code-analyzer/guide/suppress-violations.html
