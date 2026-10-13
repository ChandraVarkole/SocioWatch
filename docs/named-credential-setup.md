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

SocioWatch uses AWS Signature Version 4 with temporary credentials obtained
through AWS STS. Each Salesforce customer org uses a Named Principal that
assumes a customer-specific IAM role.

The Salesforce configuration uses these fixed values:

```text
External Credential label: SocioWatch API Authentication
External Credential name:  SocioWatch_API_Authentication
Authentication protocol:   AWS Signature 4
AWS service:                execute-api
Principal parameter name:   SocioWatchToken
Named Credential label:     SocioWatch API
Named Credential name:      SocioWatch_API
```

The AWS-provided values listed below are intentionally not stored in this
repository.

## Values required from AWS

Obtain these values before starting:

- The API Gateway base URL, including its stage or custom-domain base mapping.
  Do not include `/v1/settings` and do not end the URL with `/`.
- The AWS region containing API Gateway: `us-east-2`.
- The 12-digit AWS account ID.
- A customer-specific IAM role ARN for the Salesforce org.
- An STS bootstrap access-key ID and secret whose only purpose is assuming that
  customer-specific role.
- A unique STS External ID for the customer, using a value such as
  `salesforceIntegration-<unguessable-customer-value>`.

The route used by this test must be:

```text
POST /v1/settings
```

## Salesforce Setup: AWS Signature Version 4 with STS

Complete this configuration after AWS supplies the values above. The names in
this procedure are intentional and must be entered exactly as shown.

### 1. Create the External Credential

1. In Setup, enter `Named Credentials` in Quick Find and open **Named
   Credentials**.
2. Select **External Credentials**, then click **New**.
3. Enter:
   - Label: `SocioWatch API Authentication`
   - Name: `SocioWatch_API_Authentication`
   - Authentication Protocol: `AWS Signature 4`
   - Service: `execute-api`
   - Region: the region supplied from AWS
   - AWS Account ID: the 12-digit account ID supplied from AWS
   - Obtain Temporary IAM Credentials via STS: enabled
   - Credential Type: `IAM User Identified by Access Key`
   - STS Access Key: the customer-specific bootstrap access-key ID
   - STS Access Secret: the customer-specific bootstrap secret
   - STS External ID: the unique value supplied for this customer
   - STS Duration: `3600`
4. Leave **Additional Status Codes for Token Refresh** empty. API Gateway must
   return `400` or `401` for expired credentials; do not use `403` for an
   expired token.
5. Save. Salesforce stores the access-key values as credential data; never copy
   them into Apex, LWC, metadata, Custom Labels, or this repository.

### 2. Create the customer Named Principal

1. Open the `SocioWatch API Authentication` external credential.
2. In **Principals**, click **New**.
3. Enter:
   - Parameter Name: `SocioWatchToken`
   - Sequence Number: `1`
   - Identity Type: `Named Principal`
   - IAM Role ARN: the customer-specific role ARN supplied from AWS
4. Save.
5. Confirm the External Credential shows an authentication status of
   **Configured**. This status confirms that required Salesforce fields are
   populated; it does not prove AWS connectivity.

### 3. Create the Named Credential

1. Return to Setup **Named Credentials**, select **Named Credentials**, and
   click **New**.
2. Enter:
   - Label: `SocioWatch API`
   - Name: `SocioWatch_API`
   - URL: the AWS API Gateway base URL without `/v1/settings` and without a
     trailing slash
   - External Credential: `SocioWatch API Authentication`
3. Enable **Enabled for Callouts**.
4. Enable **Generate Authorization Header** so Salesforce signs the request
   using AWS Signature Version 4.
5. Leave custom authentication headers empty. Apex already supplies
   `Accept`, `Content-Type`, and `X-Correlation-Id`.
6. Save.

The Apex endpoint will resolve to:

```text
<AWS base URL>/v1/settings
```

## Salesforce Setup: principal and application permission

1. In Setup, enter `Permission Sets` in Quick Find and open **Permission Sets**.
2. Open **SocioWatch Admin**.
3. Open **External Credential Principal Access**, then click **Edit**.
4. Move `SocioWatch_API_Authentication - SocioWatchToken` from Available to
   Enabled and save. The packaged SocioWatch permission sets reference this
   exact principal name.
5. Confirm **SocioWatch Admin** is assigned to the user performing the test.
6. If the callout reports that the user cannot access the credential, grant the
   permission set the Salesforce-recommended access to **User External
   Credentials**, then retry. Do not grant users permission to view or edit
   stored AWS credential values.

No Remote Site Setting is required for an endpoint reached through a Named
Credential.

## AWS requirements for this Salesforce configuration

AWS must configure the API Gateway method authorization as `AWS_IAM`. The STS
bootstrap identity must be allowed to assume only the customer-specific role,
using the matching External ID. That role must grant least-privilege
`execute-api:Invoke` access to the required SocioWatch API stage and routes.

The AWS application must map the authenticated IAM principal or role session to
the SocioWatch tenant. Request fields such as `companyId`, `tenantId`, and
`externalAccountId` are application data and must not be treated as proof of
identity.

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
