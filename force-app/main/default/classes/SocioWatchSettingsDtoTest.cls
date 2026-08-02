@IsTest
private class SocioWatchSettingsDtoTest {

    @IsTest
    static void requestProducesExpectedApiJson() {
        SocioWatchSettingsRequest request =
            new SocioWatchSettingsRequest();

        request.companyName =
            '  Tesla   Motors  ';

        request.alertId =
            ' alert_12345 ';

        request.keywords =
            new List<String>{
                'Tesla',
                ' tesla ',
                'Tesla Motors'
            };

        request.syncEnabled = true;

        String requestJson =
            request.toApiJson(
                '00D000000000001AAA'
            );

        Map<String, Object> payload =
            (Map<String, Object>)
                JSON.deserializeUntyped(
                    requestJson
                );

        System.assertEquals(
            'Tesla Motors',
            payload.get('companyName')
        );

        System.assertEquals(
            'salesforce',
            payload.get('externalPlatform')
        );

        System.assertEquals(
            '00D000000000001AAA',
            payload.get('externalAccountId')
        );

        System.assertEquals(
            'alert_12345',
            payload.get('alertId')
        );

        System.assertEquals(
            true,
            payload.get('syncEnabled')
        );

        List<Object> keywords =
            (List<Object>) payload.get('keywords');

        System.assertEquals(
            2,
            keywords.size()
        );

        System.assertEquals(
            'Tesla',
            keywords[0]
        );

        System.assertEquals(
            'Tesla Motors',
            keywords[1]
        );
    }

    @IsTest
    static void nullSyncEnabledDefaultsToTrue() {
        SocioWatchSettingsRequest request =
            new SocioWatchSettingsRequest();

        request.companyName = 'Tesla';
        request.alertId = 'alert_12345';

        request.keywords =
            new List<String>{
                'Tesla'
            };

        request.syncEnabled = null;

        SocioWatchSettingsRequest normalized =
            request.normalizedCopy();

        System.assertEquals(
            true,
            normalized.syncEnabled
        );
    }

    @IsTest
    static void originalRequestIsNotModified() {
        SocioWatchSettingsRequest request =
            new SocioWatchSettingsRequest();

        request.companyName =
            '  Tesla   Motors  ';

        request.alertId =
            ' alert_12345 ';

        request.keywords =
            new List<String>{
                ' Tesla '
            };

        SocioWatchSettingsRequest normalized =
            request.normalizedCopy();

        System.assertEquals(
            '  Tesla   Motors  ',
            request.companyName
        );

        System.assertEquals(
            'Tesla Motors',
            normalized.companyName
        );

        System.assertEquals(
            ' Tesla ',
            request.keywords[0]
        );

        System.assertEquals(
            'Tesla',
            normalized.keywords[0]
        );
    }

    @IsTest
    static void parsesValidAwsSettingsResponse() {
        String responseBody = JSON.serialize(
            new Map<String, Object>{
                'message' =>
                    'Company configuration updated successfully.',
                'created' => false,
                'tenantId' => 'TENANT-000001',
                'companyId' => 'COMP-000001',
                'companyName' => 'Tesla',
                'externalPlatform' => 'salesforce',
                'externalAccountId' =>
                    '00D000000000001AAA',
                'status' => 'Active'
            }
        );

        SocioWatchSettingsResponse.AwsSettingsResult result =
            SocioWatchSettingsResponse.parseAwsResponse(
                responseBody
            );

        System.assertEquals(
            'COMP-000001',
            result.companyId
        );

        System.assertEquals(
            'TENANT-000001',
            result.tenantId
        );

        System.assertEquals(
            false,
            result.created
        );

        System.assertEquals(
            'Company configuration updated successfully.',
            result.message
        );
    }

    @IsTest
    static void rejectsEmptyAwsSettingsResponse() {
        assertApiResponseError(
            null,
            'SocioWatch returned an empty settings response.'
        );
    }

    @IsTest
    static void rejectsMalformedAwsSettingsResponse() {
        assertApiResponseError(
            '{"companyId":',
            'SocioWatch returned an invalid settings response.'
        );
    }

    @IsTest
    static void rejectsAwsResponseWithoutCompanyId() {
        String responseBody = JSON.serialize(
            new Map<String, Object>{
                'tenantId' => 'TENANT-000001'
            }
        );

        assertApiResponseError(
            responseBody,
            'SocioWatch did not return the required company information.'
        );
    }

    @IsTest
    static void rejectsAwsResponseWithoutTenantId() {
        String responseBody = JSON.serialize(
            new Map<String, Object>{
                'companyId' => 'COMP-000001'
            }
        );

        assertApiResponseError(
            responseBody,
            'SocioWatch did not return the required company information.'
        );
    }

    @IsTest
    static void rejectsUnsafeAwsCompanyId() {
        String responseBody = JSON.serialize(
            new Map<String, Object>{
                'companyId' => '../COMP-000001',
                'tenantId' => 'TENANT-000001'
            }
        );

        try {
            SocioWatchSettingsResponse.parseAwsResponse(
                responseBody
            );

            System.assert(
                false,
                'Expected a validation exception.'
            );
        } catch (SocioWatchValidationException error) {
            System.assertEquals(
                'The SocioWatch company identifier is invalid.',
                error.getMessage()
            );
        }
    }

    @IsTest
    static void createsEmptyUiResponse() {
        SocioWatchSettingsResponse response =
            SocioWatchSettingsResponse.fromConfiguration(null);

        System.assertEquals(
            true,
            response.syncEnabled
        );

        System.assertEquals(
            SocioWatchConstants.SYNC_STATUS_NOT_STARTED,
            response.lastSyncStatus
        );

        System.assertEquals(
            0,
            response.keywords.size()
        );
    }

    @IsTest
    static void convertsConfigurationToUiResponse() {
        SocioWatch_Configuration__c configuration =
            new SocioWatch_Configuration__c(
                Company_Name__c = 'Tesla',
                Keywords__c =
                    'Tesla\nTesla Motors',
                Alert_Id__c = 'alert_12345',
                Sync_Enabled__c = true,
                AWS_Company_Id__c = 'COMP-000001',
                Tenant_Id__c = 'TENANT-000001',
                Salesforce_Org_Id__c =
                    '00D000000000001AAA',
                Last_Sync_Status__c =
                    SocioWatchConstants.SYNC_STATUS_NOT_STARTED
            );

        SocioWatchSettingsResponse response =
            SocioWatchSettingsResponse.fromConfiguration(configuration);

        System.assertEquals(
            'Tesla',
            response.companyName
        );

        System.assertEquals(
            'alert_12345',
            response.alertId
        );

        System.assertEquals(
            true,
            response.syncEnabled
        );

        System.assertEquals(
            2,
            response.keywords.size()
        );

        System.assertEquals(
            'COMP-000001',
            response.companyId
        );

        System.assertEquals(
            'TENANT-000001',
            response.tenantId
        );
    }

    private static void assertApiResponseError(
        String responseBody,
        String expectedMessage
    ) {
        try {
            SocioWatchSettingsResponse.parseAwsResponse(responseBody);

            System.assert(
                false,
                'Expected an API exception.'
            );
        } catch (SocioWatchApiException error) {
            System.assertEquals(
                expectedMessage,
                error.getMessage()
            );
        }
    }
}
