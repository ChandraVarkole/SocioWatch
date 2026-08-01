@IsTest
private class SocioWatchSyncTest {

    @TestSetup
    static void setupUser() {
        User testUser = new User(
            Alias = 'swadmin',
            Email = 'sociowatch-admin@example.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'SocioWatch Admin',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'America/New_York',
            Username =
                'sociowatch-admin-' +
                System.currentTimeMillis() +
                '@example.test'
        );

        insert testUser;

        PermissionSet adminPermissionSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'SocioWatch_Admin'
            AND IsOwnedByProfile = false
            LIMIT 1
        ];

        insert new PermissionSetAssignment(
            AssigneeId = testUser.Id,
            PermissionSetId = adminPermissionSet.Id
        );
    }

    @IsTest
    static void manualSyncCreatesMentionRecords() {
        User testUser = [
            SELECT Id
            FROM User
            WHERE Alias = 'swadmin'
            LIMIT 1
        ];

        System.runAs(testUser) {
            SocioWatch_Configuration__c configuration =
                new SocioWatch_Configuration__c(
                    Company_Name__c = 'Tesla',
                    Keywords__c = 'Tesla\nTesla Motors',
                    Alert_Id__c = 'alert_12345',
                    Sync_Enabled__c = true,
                    AWS_Company_Id__c = 'COMP-000001',
                    Tenant_Id__c = 'TENANT-000001',
                    Salesforce_Org_Id__c =
                        UserInfo.getOrganizationId(),
                    Last_Sync_Status__c = 'Not Started'
                );

            insert configuration;

            Test.setMock(
                HttpCalloutMock.class,
                new SyncHttpMock()
            );

            Test.startTest();

            Id jobId =
                SocioWatchSyncController.startSync();

            Test.stopTest();

            System.assertNotEquals(
                null,
                jobId
            );

            List<SocioWatch_Mention__c> mentions = [
                SELECT
                    External_Mention_Id__c,
                    Source__c,
                    Sentiment__c,
                    Status__c
                FROM SocioWatch_Mention__c
                ORDER BY External_Mention_Id__c
            ];

            System.assertEquals(
                2,
                mentions.size()
            );

            System.assertEquals(
                'MENTION-1001',
                mentions[0].External_Mention_Id__c
            );

            System.assertEquals(
                'New',
                mentions[0].Status__c
            );

            configuration = [
                SELECT
                    Last_Sync_Status__c,
                    Last_Successful_Sync__c,
                    Last_Sync_Error__c
                FROM SocioWatch_Configuration__c
                WHERE Id = :configuration.Id
            ];

            System.assertEquals(
                'Success',
                configuration.Last_Sync_Status__c
            );

            System.assertNotEquals(
                null,
                configuration.Last_Successful_Sync__c
            );

            System.assertEquals(
                null,
                configuration.Last_Sync_Error__c
            );
        }
    }

    @IsTest
    static void disabledSyncIsRejected() {
        User testUser = [
            SELECT Id
            FROM User
            WHERE Alias = 'swadmin'
            LIMIT 1
        ];

        System.runAs(testUser) {
            insert new SocioWatch_Configuration__c(
                Company_Name__c = 'Tesla',
                Keywords__c = 'Tesla',
                Alert_Id__c = 'alert_12345',
                Sync_Enabled__c = false,
                AWS_Company_Id__c = 'COMP-000001',
                Tenant_Id__c = 'TENANT-000001',
                Salesforce_Org_Id__c =
                    UserInfo.getOrganizationId(),
                Last_Sync_Status__c = 'Not Started'
            );

            try {
                SocioWatchSyncController.startSync();

                System.assert(
                    false,
                    'Expected synchronization to be rejected.'
                );
            } catch (AuraHandledException error) {
                System.assertEquals(
                    'Synchronization is disabled.',
                    error.getMessage()
                );
            }
        }
    }

    private class SyncHttpMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader(
                'Content-Type',
                'application/json'
            );

            if (
                request.getEndpoint().endsWith('/v1/sync')
            ) {
                response.setBody(
                    JSON.serialize(
                        new Map<String, Object>{
                            'message' =>
                                'Synchronization completed successfully.',
                            'companyId' => 'COMP-000001'
                        }
                    )
                );

                return response;
            }

            if (
                request.getEndpoint().contains(
                    '/v1/mentions?companyId=COMP-000001'
                )
            ) {
                response.setBody(
                    JSON.serialize(
                        new Map<String, Object>{
                            'companyId' => 'COMP-000001',
                            'count' => 2,
                            'mentions' =>
                                new List<Object>{
                                    new Map<String, Object>{
                                        'id' => 'MENTION-1001',
                                        'alertId' => 'alert_12345',
                                        'source' => 'reddit',
                                        'author' => 'sample_user_1',
                                        'title' =>
                                            'Positive experience',
                                        'content' =>
                                            'The service was excellent.',
                                        'sentiment' => 'positive',
                                        'publishedAt' =>
                                            '2026-07-30T12:30:00Z',
                                        'url' =>
                                            'https://example.com/1001',
                                        'language' => 'en'
                                    },
                                    new Map<String, Object>{
                                        'id' => 'MENTION-1002',
                                        'alertId' => 'alert_12345',
                                        'source' => 'x',
                                        'author' => 'sample_user_2',
                                        'title' =>
                                            'Waiting for support',
                                        'content' =>
                                            'I am waiting for an update.',
                                        'sentiment' => 'negative',
                                        'publishedAt' =>
                                            '2026-07-30T14:10:00Z',
                                        'url' =>
                                            'https://example.com/1002',
                                        'language' => 'en'
                                    }
                                }
                        }
                    )
                );

                return response;
            }

            response.setStatusCode(404);
            response.setBody(
                '{"message":"Route not found."}'
            );

            return response;
        }
    }
}
