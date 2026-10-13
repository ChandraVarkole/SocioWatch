# SocioWatch Named Credential Setup

## Scope

This procedure configures the Named Credential used by every Salesforce-to-AWS
request:

```text
Salesforce controllers and queueables
  -> SocioWatchApiClient
  -> callout:SocioWatch_API
     -> POST /v1/settings
     -> POST /v1/sync
     -> GET  /v1/mentions?companyId=...
     -> POST /v1/chat
```

No credential or API key belongs in Apex, LWC, Custom Labels, or source
control.

## Selected authentication model

SocioWatch uses a customer-specific Bearer token stored as an encrypted
authentication parameter on a Salesforce External Credential. The repository
contains the non-secret External Credential and Named Credential definitions so
the complete project can be deployed in one operation. Salesforce does not
deploy secret parameter values, so the token must be populated once after each
installation.

The Salesforce configuration uses these fixed values:

```text
External Credential label: SocioWatch API Authentication
External Credential name:  SocioWatch_API_Authentication
Authentication protocol:   Custom
Principal parameter name:   SocioWatchToken
Named Credential label:     SocioWatch API
Named Credential name:      SocioWatch_API
```

The AWS-provided values listed below are intentionally not stored in this
repository.

## Values required from AWS

Obtain the customer-specific SocioWatch API token from the AWS onboarding
process. Never store it in source control, Apex, LWC, Custom Labels, or custom
object records.

The route used by this test must be:

```text
POST /v1/settings
```

## Salesforce Setup: populate the deployed principal secret

1. Deploy the complete Salesforce project. This creates the External
   Credential, Named Credential, principal definition, permission sets, and app
   metadata together.
2. In Setup, enter `Named Credentials` in Quick Find and open **Named
   Credentials**.
3. Select **External Credentials**, then open **SocioWatch API
   Authentication**.
4. Under **Principals**, open `SocioWatchToken` and populate its authentication
   parameter with the customer-specific SocioWatch API token.
5. Save and confirm the External Credential shows an authentication status of
   **Configured**.

The Apex endpoint will resolve to:

```text
<AWS base URL>/v1/settings
```

## Salesforce Setup: principal and application permission

1. In Setup, enter `Permission Sets` in Quick Find and open **Permission Sets**.
2. Confirm **SocioWatch Admin** is assigned to the administrator performing the
   setup and **SocioWatch User** is assigned to each standard app user.
3. Confirm both permission sets list
   `SocioWatch_API_Authentication - SocioWatchToken` under **External
   Credential Principal Access**. This access is source controlled.
4. Confirm each permission set grants **Read** and **View All Records** on
   **User External Credentials**. The source-controlled SocioWatch permission
   sets include this access so users can perform authenticated callouts without
   gaining permission to view or edit stored AWS credential values.

No Remote Site Setting is required for an endpoint reached through a Named
Credential.

## AWS requirements for this Salesforce configuration

AWS must validate the Bearer token before invoking the SocioWatch API handlers
and map that credential to the authorized customer environment. Request fields
such as `companyId`, `tenantId`, and `externalAccountId` are application data
and must not be treated as proof of identity.

## AWS request and response contract

The Settings save sends JSON with these fields:

```json
{
  "companyName": "Connectivity Test",
  "website": "https://example.com",
  "externalPlatform": "salesforce",
  "externalAccountId": "<15-or-18-character Salesforce org ID>",
  "keywords": ["connectivity"],
  "syncEnabled": true
}
```

AWS must return an HTTP 2xx response whose body is JSON with `companyId` and
`tenantId` at the top level:

```json
{
  "companyId": "CONNECTIVITY_001",
  "tenantId": "TENANT_001",
  "created": true,
  "message": "Salesforce connected successfully."
}
```

Both identifiers must contain only letters, numbers, underscores, or hyphens
and must be no longer than 100 characters. Do not return a Lambda proxy wrapper
containing a string-valued `body`; API Gateway must deliver the JSON above as
the HTTP response body.

## First connectivity test

1. Open the **SocioWatch** Lightning application and select **SocioWatch
   Settings**.
2. Enter:
   - Company Name: `Connectivity Test`
   - Company Website: `https://example.com`
   - Keywords: `connectivity`
   - Enable Monitoring: enabled
3. Click **Save** once.
4. Verify all of the following:
   - AWS receives `POST /v1/settings`.
   - AWS logs include the Salesforce-generated `X-Correlation-Id` header.
   - The LWC shows the response message in a success toast.
   - The LWC displays `CONNECTIVITY_001` as the SocioWatch Company ID.
   - Salesforce creates or updates one `SocioWatch_Configuration__c` record
     with `AWS_Company_Id__c` and `Tenant_Id__c` populated.

Do not click **Sync Now** as part of this test.
