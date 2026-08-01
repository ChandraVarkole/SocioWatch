@IsTest
private class SocioWatchChatControllerTest {

    @TestSetup
    static void setupUser() {
        User chatUser = new User(
            Alias = 'swchat',
            Email = 'sociowatch-chat@example.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'SocioWatch Chat',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'America/New_York',
            Username =
                'sociowatch-chat-' +
                System.currentTimeMillis() +
                '@example.test'
        );

        insert chatUser;

        PermissionSet userPermissionSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'SocioWatch_User'
            AND IsOwnedByProfile = false
            LIMIT 1
        ];

        insert new PermissionSetAssignment(
            AssigneeId = chatUser.Id,
            PermissionSetId = userPermissionSet.Id
        );
    }

    @IsTest
    static void returnsChatAnswer() {
        User chatUser = getChatUser();

        System.runAs(chatUser) {
            insertConfiguration();

            Test.setMock(
                HttpCalloutMock.class,
                new ChatMock()
            );

            Test.startTest();

            String answer =
                SocioWatchChatController.askQuestion(
                    'What are customers complaining about?'
                );

            Test.stopTest();

            System.assertEquals(
                'Customer support response time is the top concern.',
                answer
            );
        }
    }

    @IsTest
    static void rejectsBlankQuestion() {
        User chatUser = getChatUser();

        System.runAs(chatUser) {
            insertConfiguration();

            try {
                SocioWatchChatController.askQuestion('   ');

                System.assert(false);
            } catch (AuraHandledException error) {
                System.assertEquals(
                    'Enter a question.',
                    error.getMessage()
                );
            }
        }
    }

    @IsTest
    static void requiresConfiguration() {
        User chatUser = getChatUser();

        System.runAs(chatUser) {
            try {
                SocioWatchChatController.askQuestion(
                    'Summarize the mentions.'
                );

                System.assert(false);
            } catch (AuraHandledException error) {
                System.assertEquals(
                    'Save the SocioWatch settings before using chat.',
                    error.getMessage()
                );
            }
        }
    }

    private static User getChatUser() {
        return [
            SELECT Id
            FROM User
            WHERE Alias = 'swchat'
            LIMIT 1
        ];
    }

    private static void insertConfiguration() {
        insert new SocioWatch_Configuration__c(
            Company_Name__c = 'Tesla',
            Keywords__c = 'Tesla',
            Alert_Id__c = 'alert_12345',
            Sync_Enabled__c = true,
            AWS_Company_Id__c = 'COMP-000001',
            Tenant_Id__c = 'TENANT-000001',
            Salesforce_Org_Id__c =
                UserInfo.getOrganizationId(),
            Last_Sync_Status__c = 'Not Started'
        );
    }

    private class ChatMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {
            System.assertEquals(
                'POST',
                request.getMethod()
            );

            System.assertEquals(
                'callout:SocioWatch_API/v1/chat',
                request.getEndpoint()
            );

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader(
                'Content-Type',
                'application/json'
            );

            response.setBody(
                JSON.serialize(
                    new Map<String, Object>{
                        'answer' =>
                            'Customer support response time is ' +
                            'the top concern.',
                        'mentionCount' => 2
                    }
                )
            );

            return response;
        }
    }
}
