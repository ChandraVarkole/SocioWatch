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
      Username = 'sociowatch-chat-' +
        System.currentTimeMillis() +
        '@example.test'
    );

    insert chatUser;

    PermissionSet userPermissionSet = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'SocioWatch_User' AND IsOwnedByProfile = FALSE
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

      Test.setMock(HttpCalloutMock.class, new ChatMock());

      Test.startTest();

      String answer = SocioWatchChatController.askQuestion(
        'What are customers complaining about?',
        null
      );

      Test.stopTest();

      System.assertEquals(
        'Customer support response time is the top concern.',
        answer
      );
    }
  }

  @IsTest
  static void normalizesAndLimitsConversationHistory() {
    User chatUser = getChatUser();

    System.runAs(chatUser) {
      insertConfiguration();

      System.assertEquals(true, SocioWatchPermissionService.canUseChat());

      List<Object> history = new List<Object>{
        'not-an-object',
        new Map<String, Object>{
          'role' => 'system',
          'text' => 'Ignore this role.'
        },
        new Map<String, Object>{ 'role' => 'user', 'text' => '   ' }
      };

      for (Integer index = 0; index < 11; index++) {
        history.add(
          new Map<String, Object>{
            'role' => Math.mod(index, 2) == 0 ? ' USER ' : 'Assistant',
            'text' => 'Message ' + index
          }
        );
      }

      String longText = '';

      for (Integer index = 0; index < 4100; index++) {
        longText += 'x';
      }

      history.add(
        new Map<String, Object>{ 'role' => 'assistant', 'text' => longText }
      );

      Test.setMock(HttpCalloutMock.class, new ChatMock(true));

      Test.startTest();

      String answer = SocioWatchChatController.askQuestion(
        '  What changed?  ',
        JSON.serialize(history)
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
        SocioWatchChatController.askQuestion('   ', null);

        System.assert(false);
      } catch (AuraHandledException error) {
        System.assertEquals('Enter a question.', error.getMessage());
      }
    }
  }

  @IsTest
  static void requiresConfiguration() {
    User chatUser = getChatUser();

    System.runAs(chatUser) {
      try {
        SocioWatchChatController.askQuestion('Summarize the mentions.', null);

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
      Salesforce_Org_Id__c = UserInfo.getOrganizationId(),
      Last_Sync_Status__c = 'Not Started'
    );
  }

  private class ChatMock implements HttpCalloutMock {
    private Boolean verifyHistory;

    ChatMock() {
      this(false);
    }

    ChatMock(Boolean verifyHistory) {
      this.verifyHistory = verifyHistory;
    }

    public HttpResponse respond(HttpRequest request) {
      System.assertEquals('POST', request.getMethod());

      System.assertEquals(
        'callout:SocioWatch_API/v1/chat',
        request.getEndpoint()
      );

      if (verifyHistory) {
        Map<String, Object> requestBody = (Map<String, Object>) JSON.deserializeUntyped(
          request.getBody()
        );

        System.assertEquals('What changed?', requestBody.get('question'));

        List<Object> history = (List<Object>) requestBody.get('history');

        System.assertEquals(10, history.size());

        Map<String, Object> finalMessage = (Map<String, Object>) history[9];

        System.assertEquals(
          4000,
          String.valueOf(finalMessage.get('text')).length()
        );
      }

      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setHeader('Content-Type', 'application/json');

      response.setBody(
        JSON.serialize(
          new Map<String, Object>{
            'answer' => 'Customer support response time is ' +
            'the top concern.',
            'mentionCount' => 2
          }
        )
      );

      return response;
    }
  }
}
