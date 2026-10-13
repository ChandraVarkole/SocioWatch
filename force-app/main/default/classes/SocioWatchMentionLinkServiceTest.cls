@IsTest
private class SocioWatchMentionLinkServiceTest {
  @TestSetup
  static void setupUser() {
    User testUser = new User(
      Alias = 'swlink',
      Email = 'sociowatch-link@example.test',
      EmailEncodingKey = 'UTF-8',
      LastName = 'SocioWatch Link',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = UserInfo.getProfileId(),
      TimeZoneSidKey = 'America/New_York',
      Username = 'sociowatch-link-' +
        System.currentTimeMillis() +
        '@example.test'
    );
    insert testUser;

    PermissionSet adminPermissionSet = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'SocioWatch_Admin' AND IsOwnedByProfile = FALSE
      LIMIT 1
    ];
    insert new PermissionSetAssignment(
      AssigneeId = testUser.Id,
      PermissionSetId = adminPermissionSet.Id
    );
  }

  @IsTest
  static void linksUniqueAccountMatch() {
    User testUser = [SELECT Id FROM User WHERE Alias = 'swlink' LIMIT 1];

    System.runAs(testUser) {
      Account matchedAccount = new Account(Name = 'Sample Customer');
      insert matchedAccount;
      SocioWatch_Configuration__c configuration = createConfiguration();

      SocioWatch_Mention__c mention = createMention(
        configuration.Id,
        'MENTION-LINK-1',
        'sample customer'
      );
      insert mention;

      mention = [
        SELECT
          Author_Match_Status__c,
          Linked_Account__c,
          Linked_Object_API_Name__c,
          Linked_Record_Id__c,
          Linked_Record_Name__c
        FROM SocioWatch_Mention__c
        WHERE Id = :mention.Id
      ];

      System.assertEquals(
        matchedAccount.Id,
        mention.Linked_Account__c,
        'The unique Account should be linked.'
      );
      System.assertEquals(
        'Matched',
        mention.Author_Match_Status__c,
        'A unique match should be recorded as matched.'
      );
      System.assertEquals(
        'Account',
        mention.Linked_Object_API_Name__c,
        'The linked object API name should be saved.'
      );
      System.assertEquals(
        String.valueOf(matchedAccount.Id),
        mention.Linked_Record_Id__c,
        'The generic linked record ID should be saved.'
      );
      System.assertEquals(
        'sample customer',
        mention.Linked_Record_Name__c,
        'The matched author name should be saved.'
      );
    }
  }

  @IsTest
  static void leavesAmbiguousMatchUnlinked() {
    User testUser = [SELECT Id FROM User WHERE Alias = 'swlink' LIMIT 1];

    System.runAs(testUser) {
      insert new List<Account>{
        new Account(Name = 'Duplicate Author'),
        new Account(Name = 'Duplicate Author')
      };
      SocioWatch_Configuration__c configuration = createConfiguration();
      SocioWatch_Mention__c mention = createMention(
        configuration.Id,
        'MENTION-LINK-2',
        'Duplicate Author'
      );
      insert mention;

      mention = [
        SELECT Author_Match_Status__c, Linked_Account__c, Linked_Record_Id__c
        FROM SocioWatch_Mention__c
        WHERE Id = :mention.Id
      ];

      System.assertEquals(
        null,
        mention.Linked_Account__c,
        'An ambiguous Account match must remain unlinked.'
      );
      System.assertEquals(
        null,
        mention.Linked_Record_Id__c,
        'An ambiguous generic match must remain unlinked.'
      );
      System.assertEquals(
        'No match found',
        mention.Author_Match_Status__c,
        'An ambiguous match should be recorded as not found.'
      );
    }
  }

  @IsTest
  static void recordsWhenNoMatchIsFound() {
    User testUser = [SELECT Id FROM User WHERE Alias = 'swlink' LIMIT 1];

    System.runAs(testUser) {
      SocioWatch_Configuration__c configuration = createConfiguration();
      SocioWatch_Mention__c mention = createMention(
        configuration.Id,
        'MENTION-LINK-3',
        'Missing Customer'
      );
      insert mention;

      mention = [
        SELECT Author_Match_Status__c, Linked_Account__c, Linked_Record_Id__c
        FROM SocioWatch_Mention__c
        WHERE Id = :mention.Id
      ];

      System.assertEquals(
        'No match found',
        mention.Author_Match_Status__c,
        'A missing match should be recorded on the mention.'
      );
      System.assertEquals(
        null,
        mention.Linked_Account__c,
        'A missing Account match must remain unlinked.'
      );
      System.assertEquals(
        null,
        mention.Linked_Record_Id__c,
        'A missing generic match must remain unlinked.'
      );
    }
  }

  @IsTest
  static void rejectsInvalidTargetConfiguration() {
    User testUser = [SELECT Id FROM User WHERE Alias = 'swlink' LIMIT 1];

    System.runAs(testUser) {
      try {
        SocioWatchSettingsRequest request = new SocioWatchSettingsRequest();
        request.autoLinkMentions = true;
        request.authorMatchObjectApiName = 'Not_An_Object';
        request.authorMatchFieldApiName = 'Name';
        SocioWatchMentionLinkService.validateConfiguration(request);
        System.assert(false, 'Expected invalid object configuration to fail.');
      } catch (SocioWatchValidationException error) {
        System.assertEquals(
          'The author match object does not exist or cannot be queried.',
          error.getMessage(),
          'The invalid object should return a safe validation message.'
        );
      }
    }
  }

  private static SocioWatch_Configuration__c createConfiguration() {
    SocioWatch_Configuration__c configuration = new SocioWatch_Configuration__c(
      Company_Name__c = 'Test Company',
      Keywords__c = 'Test Company',
      Auto_Link_Mentions__c = true,
      Author_Match_Object__c = 'Account',
      Author_Match_Field__c = 'Name'
    );
    insert configuration;
    return configuration;
  }

  private static SocioWatch_Mention__c createMention(
    Id configurationId,
    String externalId,
    String authorName
  ) {
    return new SocioWatch_Mention__c(
      Configuration__c = configurationId,
      External_Mention_Id__c = externalId,
      Author_Name__c = authorName,
      Mention_Date__c = System.now(),
      Synced_At__c = System.now()
    );
  }
}
