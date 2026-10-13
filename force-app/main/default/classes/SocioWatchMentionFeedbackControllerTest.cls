@IsTest
private class SocioWatchMentionFeedbackControllerTest {
  @IsTest
  static void marksMentionNotRelevantInAwsAndSalesforce() {
    SocioWatch_Configuration__c configuration = new SocioWatch_Configuration__c(
      Company_Name__c = 'Acme',
      AWS_Company_Id__c = 'sw_acme123',
      Keywords__c = 'Acme; roofing',
      Sync_Enabled__c = true
    );
    insert configuration;

    SocioWatch_Mention__c mention = new SocioWatch_Mention__c(
      Configuration__c = configuration.Id,
      External_Mention_Id__c = 'MENTION-123',
      Title__c = 'Acme mention',
      Mention_Date__c = System.now(),
      Synced_At__c = System.now(),
      Is_Relevant__c = true
    );
    insert mention;

    Test.setMock(
      HttpCalloutMock.class,
      new SocioWatchHttpMock(
          200,
          '{"message":"Mention marked as not relevant."}'
        )
        .expectRequest(
          'POST',
          'callout:SocioWatch_API/v1/mentions/relevance',
          null
        )
    );

    Test.startTest();
    SocioWatchMentionFeedbackController.markNotRelevant(mention.Id);
    Test.stopTest();

    SocioWatch_Mention__c updatedMention = [
      SELECT Is_Relevant__c
      FROM SocioWatch_Mention__c
      WHERE Id = :mention.Id
    ];
    System.assertEquals(false, updatedMention.Is_Relevant__c);
  }

  @IsTest
  static void rejectsMentionWithoutAwsIdentifiers() {
    SocioWatch_Configuration__c configuration = new SocioWatch_Configuration__c(
      Company_Name__c = 'Acme',
      Keywords__c = 'Acme; roofing',
      Sync_Enabled__c = true
    );
    insert configuration;

    SocioWatch_Mention__c mention = new SocioWatch_Mention__c(
      Configuration__c = configuration.Id,
      External_Mention_Id__c = 'MENTION-456',
      Title__c = 'Unlinked mention',
      Mention_Date__c = System.now(),
      Synced_At__c = System.now(),
      Is_Relevant__c = true
    );
    insert mention;

    try {
      SocioWatchMentionFeedbackController.markNotRelevant(mention.Id);
      System.assert(false, 'Expected an exception.');
    } catch (AuraHandledException error) {
      System.assertNotEquals(null, error);
    }
  }

  @IsTest
  static void rejectsMissingMentionId() {
    try {
      SocioWatchMentionFeedbackController.markNotRelevant(null);
      System.assert(false, 'Expected an exception.');
    } catch (AuraHandledException error) {
      System.assertNotEquals(null, error);
    }
  }
}
