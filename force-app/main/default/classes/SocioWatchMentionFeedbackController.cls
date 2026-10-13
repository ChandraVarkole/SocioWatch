/**
 * Records explicit customer relevance feedback for imported mentions.
 */
public with sharing class SocioWatchMentionFeedbackController {
  private SocioWatchMentionFeedbackController() {
  }

  @AuraEnabled
  public static void markNotRelevant(Id mentionId) {
    if (mentionId == null) {
      throw new AuraHandledException('Select a SocioWatch mention first.');
    }

    List<SocioWatch_Mention__c> mentions = [
      SELECT
        Id,
        External_Mention_Id__c,
        Mention_Date__c,
        Is_Relevant__c,
        Configuration__r.AWS_Company_Id__c
      FROM SocioWatch_Mention__c
      WHERE Id = :mentionId
      WITH USER_MODE
      LIMIT 1
    ];

    if (mentions.isEmpty()) {
      throw new AuraHandledException(
        'The mention was not found or is not accessible.'
      );
    }

    SocioWatch_Mention__c mention = mentions[0];
    String companyId = mention.Configuration__r?.AWS_Company_Id__c;

    if (
      String.isBlank(companyId) ||
      String.isBlank(mention.External_Mention_Id__c) ||
      mention.Mention_Date__c == null
    ) {
      throw new AuraHandledException(
        'This mention is missing the AWS identifiers needed to update it.'
      );
    }

    String requestBody = JSON.serialize(
      new Map<String, Object>{
        'companyId' => companyId,
        'mentionId' => mention.External_Mention_Id__c,
        'mentionDate' => mention.Mention_Date__c.formatGmt(
          'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''
        ),
        'isRelevant' => false
      }
    );

    try {
      SocioWatchApiClient.post(
        SocioWatchConstants.MENTION_RELEVANCE_ENDPOINT,
        requestBody
      );

      mention.Is_Relevant__c = false;
      Database.update(mention, AccessLevel.USER_MODE);
    } catch (SocioWatchApiException error) {
      throw new AuraHandledException(error.getMessage());
    } catch (DmlException error) {
      throw new AuraHandledException(
        'AWS was updated, but Salesforce could not hide this mention. Refresh and try again.'
      );
    }
  }
}
