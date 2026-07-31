@IsTest
private class SocioWatchApiClientTest {

    private static final String NAMED_CREDENTIAL_ENDPOINT =
        'callout:SocioWatch_API';

    @IsTest
    static void postReturnsSuccessfulResponse() {
        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'companyName' => 'Tesla',
                'alertId' => 'alert_12345',
                'syncEnabled' => true
            }
        );

        String responseBody = JSON.serialize(
            new Map<String, Object>{
                'message' => 'Settings saved.',
                'companyId' => 'COMP-000001',
                'tenantId' => 'TENANT-000001'
            }
        );

        SocioWatchHttpMock mock = new SocioWatchHttpMock(
            200,
            responseBody
        ).expectRequest(
            'POST',
            NAMED_CREDENTIAL_ENDPOINT + '/v1/settings',
            requestBody
        );

        Test.setMock(
            HttpCalloutMock.class,
            mock
        );

        Test.startTest();

        SocioWatchApiResponse result =
            SocioWatchApiClient.post(
                '/v1/settings',
                requestBody
            );

        Test.stopTest();

        System.assertEquals(
            200,
            result.statusCode
        );

        System.assertEquals(
            responseBody,
            result.responseBody
        );

        System.assertEquals(
            true,
            result.isSuccessful()
        );

        System.assert(
            String.isNotBlank(result.correlationId),
            'The result must include a correlation ID.'
        );
    }

    @IsTest
    static void getMentionsReturnsSuccessfulResponse() {
        String responseBody = JSON.serialize(
            new Map<String, Object>{
                'companyId' => 'COMP-000001',
                'count' => 2,
                'mentions' => new List<Object>()
            }
        );

        String path =
            '/v1/mentions?companyId=COMP-000001';

        SocioWatchHttpMock mock = new SocioWatchHttpMock(
            200,
            responseBody
        ).expectRequest(
            'GET',
            NAMED_CREDENTIAL_ENDPOINT + path,
            null
        );

        Test.setMock(
            HttpCalloutMock.class,
            mock
        );

        Test.startTest();

        SocioWatchApiResponse result =
            SocioWatchApiClient.get(path);

        Test.stopTest();

        System.assertEquals(
            200,
            result.statusCode
        );

        System.assertEquals(
            true,
            result.isSuccessful()
        );

        System.assertEquals(
            responseBody,
            result.responseBody
        );
    }

    @IsTest
    static void chatRequestReturnsSuccessfulResponse() {
        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'companyId' => 'COMP-000001',
                'question' =>
                    'What are customers complaining about?'
            }
        );

        String responseBody = JSON.serialize(
            new Map<String, Object>{
                'answer' => 'Customer support is the top concern.',
                'mentionCount' => 2
            }
        );

        SocioWatchHttpMock mock = new SocioWatchHttpMock(
            200,
            responseBody
        ).expectRequest(
            'POST',
            NAMED_CREDENTIAL_ENDPOINT + '/v1/chat',
            requestBody
        );

        Test.setMock(
            HttpCalloutMock.class,
            mock
        );

        Test.startTest();

        SocioWatchApiResponse result =
            SocioWatchApiClient.post(
                '/v1/chat',
                requestBody
            );

        Test.stopTest();

        System.assertEquals(
            true,
            result.isSuccessful()
        );
    }

    @IsTest
    static void manualSyncReturnsSuccessfulResponse() {
        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'companyId' => 'COMP-000001'
            }
        );

        String responseBody = JSON.serialize(
            new Map<String, Object>{
                'message' =>
                    'Synchronization completed successfully.',
                'companyId' => 'COMP-000001'
            }
        );

        Test.setMock(
            HttpCalloutMock.class,
            new SocioWatchHttpMock(
                200,
                responseBody
            ).expectRequest(
                'POST',
                NAMED_CREDENTIAL_ENDPOINT + '/v1/sync',
                requestBody
            )
        );

        Test.startTest();

        SocioWatchApiResponse result =
            SocioWatchApiClient.post(
                '/v1/sync',
                requestBody
            );

        Test.stopTest();

        System.assertEquals(
            200,
            result.statusCode
        );
    }

    @IsTest
    static void rejectsUnsupportedMethod() {
        try {
            SocioWatchApiClient.send(
                'DELETE',
                '/v1/settings',
                null
            );

            System.assert(
                false,
                'Expected an exception.'
            );
        } catch (SocioWatchApiException error) {
            System.assertEquals(
                'The requested HTTP method is not supported.',
                error.getMessage()
            );
        }
    }

    @IsTest
    static void rejectsBlankMethod() {
        try {
            SocioWatchApiClient.send(
                null,
                '/v1/settings',
                null
            );

            System.assert(
                false,
                'Expected an exception.'
            );
        } catch (SocioWatchApiException error) {
            System.assertEquals(
                'An HTTP method is required.',
                error.getMessage()
            );
        }
    }

    @IsTest
    static void rejectsUnsupportedPath() {
        try {
            SocioWatchApiClient.get(
                '/v1/admin'
            );

            System.assert(
                false,
                'Expected an exception.'
            );
        } catch (SocioWatchApiException error) {
            System.assertEquals(
                'The requested SocioWatch API path is not supported.',
                error.getMessage()
            );
        }
    }

    @IsTest
    static void rejectsAbsoluteUrl() {
        try {
            SocioWatchApiClient.get(
                'https://malicious.example.com'
            );

            System.assert(
                false,
                'Expected an exception.'
            );
        } catch (SocioWatchApiException error) {
            System.assertEquals(
                'The SocioWatch API path is invalid.',
                error.getMessage()
            );
        }
    }

    @IsTest
    static void rejectsDirectoryTraversal() {
        try {
            SocioWatchApiClient.get(
                '/v1/../settings'
            );

            System.assert(
                false,
                'Expected an exception.'
            );
        } catch (SocioWatchApiException error) {
            System.assertEquals(
                'The SocioWatch API path is invalid.',
                error.getMessage()
            );
        }
    }

    @IsTest
    static void rejectsQueryParametersOnSettings() {
        try {
            SocioWatchApiClient.get(
                '/v1/settings?companyId=COMP-000001'
            );

            System.assert(
                false,
                'Expected an exception.'
            );
        } catch (SocioWatchApiException error) {
            System.assertEquals(
                'Query parameters are not allowed for this endpoint.',
                error.getMessage()
            );
        }
    }

    @IsTest
    static void rejectsUnexpectedMentionQueryParameter() {
        try {
            SocioWatchApiClient.get(
                '/v1/mentions?tenantId=TENANT-000001'
            );

            System.assert(
                false,
                'Expected an exception.'
            );
        } catch (SocioWatchApiException error) {
            System.assertEquals(
                'The SocioWatch query parameter is invalid.',
                error.getMessage()
            );
        }
    }

    @IsTest
    static void rejectsInvalidCompanyIdentifier() {
        try {
            SocioWatchApiClient.get(
                '/v1/mentions?companyId=' +
                EncodingUtil.urlEncode(
                    '../COMP-000001',
                    'UTF-8'
                )
            );

            System.assert(
                false,
                'Expected an exception.'
            );
        } catch (SocioWatchApiException error) {
            System.assertEquals(
                'The SocioWatch company identifier is invalid.',
                error.getMessage()
            );
        }
    }

    @IsTest
    static void rejectsGetRequestBody() {
        try {
            SocioWatchApiClient.send(
                'GET',
                '/v1/mentions?companyId=COMP-000001',
                '{"unexpected":true}'
            );

            System.assert(
                false,
                'Expected an exception.'
            );
        } catch (SocioWatchApiException error) {
            System.assertEquals(
                'GET requests cannot contain a request body.',
                error.getMessage()
            );
        }
    }

    @IsTest
    static void rejectsMalformedJsonBody() {
        try {
            SocioWatchApiClient.post(
                '/v1/settings',
                '{"companyName":'
            );

            System.assert(
                false,
                'Expected an exception.'
            );
        } catch (SocioWatchApiException error) {
            System.assertEquals(
                'The SocioWatch request body must contain valid JSON.',
                error.getMessage()
            );
        }
    }

    @IsTest
    static void mapsBadRequestToSafeException() {
        assertStatusCodeException(
            400,
            'SocioWatch rejected the request because it was invalid.'
        );
    }

    @IsTest
    static void mapsUnauthorizedToSafeException() {
        assertStatusCodeException(
            401,
            'SocioWatch authentication or authorization failed.'
        );
    }

    @IsTest
    static void mapsForbiddenToSafeException() {
        assertStatusCodeException(
            403,
            'SocioWatch authentication or authorization failed.'
        );
    }

    @IsTest
    static void mapsNotFoundToSafeException() {
        assertStatusCodeException(
            404,
            'The requested SocioWatch resource was not found.'
        );
    }

    @IsTest
    static void mapsConflictToSafeException() {
        assertStatusCodeException(
            409,
            'The SocioWatch request conflicts with existing data.'
        );
    }

    @IsTest
    static void mapsRateLimitToSafeException() {
        assertStatusCodeException(
            429,
            'SocioWatch is temporarily rate limited. Try again later.'
        );
    }

    @IsTest
    static void mapsServerErrorToSafeException() {
        assertStatusCodeException(
            500,
            'The SocioWatch service is temporarily unavailable.'
        );
    }

    @IsTest
    static void doesNotExposeExternalErrorBody() {
        String sensitiveExternalResponse =
            '{"message":"Internal AWS failure",' +
            '"apiKey":"secret-value",' +
            '"stackTrace":"internal details"}';

        Test.setMock(
            HttpCalloutMock.class,
            new SocioWatchHttpMock(
                500,
                sensitiveExternalResponse
            )
        );

        try {
            SocioWatchApiClient.post(
                '/v1/sync',
                '{"companyId":"COMP-000001"}'
            );

            System.assert(
                false,
                'Expected an exception.'
            );
        } catch (SocioWatchApiException error) {
            System.assertEquals(
                false,
                error.getMessage().contains('secret-value'),
                'External secrets must not be exposed.'
            );

            System.assertEquals(
                false,
                error.getMessage().contains('stackTrace'),
                'External stack traces must not be exposed.'
            );

            System.assert(
                error.getMessage().contains('Reference:'),
                'The safe error must contain a correlation reference.'
            );
        }
    }

    private static void assertStatusCodeException(
        Integer statusCode,
        String expectedMessage
    ) {
        Test.setMock(
            HttpCalloutMock.class,
            new SocioWatchHttpMock(
                statusCode,
                '{"message":"External details must not be exposed."}'
            )
        );

        try {
            SocioWatchApiClient.post(
                '/v1/sync',
                '{"companyId":"COMP-000001"}'
            );

            System.assert(
                false,
                'Expected an exception for HTTP ' + statusCode
            );
        } catch (SocioWatchApiException error) {
            System.assert(
                error.getMessage().startsWith(expectedMessage),
                'Unexpected safe error message: ' +
                error.getMessage()
            );

            System.assert(
                error.getMessage().contains('Reference:'),
                'The error must contain a correlation reference.'
            );

            System.assertEquals(
                false,
                error.getMessage().contains(
                    'External details must not be exposed.'
                ),
                'The external response must not be exposed.'
            );
        }
    }
}
