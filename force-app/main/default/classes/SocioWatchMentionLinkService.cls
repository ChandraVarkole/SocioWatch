/**
 * @description Links newly inserted mentions by matching Author Name against
 * the object and text field selected in SocioWatch Settings.
 */
public without sharing class SocioWatchMentionLinkService {
  private static final String MATCH_STATUS_MATCHED = 'Matched';
  private static final String MATCH_STATUS_NOT_FOUND = 'No match found';

  /**
   * @description Validates the local Salesforce matching fields before
   * Settings are saved.
   * @param request normalized Settings request to validate
   */
  public static void validateConfiguration(SocioWatchSettingsRequest request) {
    if (request != null && request.autoLinkMentions == true) {
      SocioWatchMentionLinkTarget.resolve(
        request.authorMatchObjectApiName,
        request.authorMatchFieldApiName
      );
    }
  }

  /**
   * @description Links newly inserted mentions when one accessible record
   * matches.
   * @param mentions newly inserted mentions to evaluate
   */
  public static void linkNewMentions(List<SocioWatch_Mention__c> mentions) {
    if (mentions == null || mentions.isEmpty()) {
      return;
    }

    SocioWatch_Configuration__c configuration = getLinkConfiguration();

    if (configuration == null) {
      return;
    }

    SocioWatchMentionLinkTarget target = resolveSavedTarget(configuration);

    if (target == null) {
      return;
    }

    Set<String> authorNames = collectAuthorNames(mentions);

    Map<String, SObject> uniqueMatches = new Map<String, SObject>();

    if (!authorNames.isEmpty()) {
      List<SObject> candidates = queryCandidates(target, authorNames);

      if (candidates == null) {
        return;
      }

      uniqueMatches = indexUniqueMatches(candidates, target);
    }

    List<SocioWatch_Mention__c> updates = buildMentionUpdates(
      mentions,
      uniqueMatches,
      target
    );

    if (!updates.isEmpty()) {
      Database.update(updates, false, AccessLevel.USER_MODE);
    }
  }

  private static SocioWatch_Configuration__c getLinkConfiguration() {
    List<SocioWatch_Configuration__c> configurations = [
      SELECT
        Author_Match_Field__c,
        Author_Match_Object__c,
        Auto_Link_Mentions__c
      FROM SocioWatch_Configuration__c
      WHERE Auto_Link_Mentions__c = TRUE
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    return configurations.isEmpty() ? null : configurations[0];
  }

  private static SocioWatchMentionLinkTarget resolveSavedTarget(
    SocioWatch_Configuration__c configuration
  ) {
    try {
      return SocioWatchMentionLinkTarget.resolve(
        configuration.Author_Match_Object__c,
        configuration.Author_Match_Field__c
      );
    } catch (SocioWatchValidationException ignoredError) {
      return null;
    }
  }

  private static Set<String> collectAuthorNames(
    List<SocioWatch_Mention__c> mentions
  ) {
    Set<String> authorNames = new Set<String>();

    for (SocioWatch_Mention__c mention : mentions) {
      if (String.isNotBlank(mention.Author_Name__c)) {
        authorNames.add(mention.Author_Name__c.trim());
      }
    }

    return authorNames;
  }

  private static List<SObject> queryCandidates(
    SocioWatchMentionLinkTarget target,
    Set<String> authorNames
  ) {
    String queryText =
      'SELECT Id, ' +
      target.fieldApiName +
      ' FROM ' +
      target.objectApiName +
      ' WHERE ' +
      target.fieldApiName +
      ' IN :authorNames';

    try {
      return Database.queryWithBinds(
        queryText,
        new Map<String, Object>{ 'authorNames' => authorNames },
        AccessLevel.USER_MODE
      );
    } catch (Exception ignoredError) {
      return null;
    }
  }

  private static Map<String, SObject> indexUniqueMatches(
    List<SObject> candidates,
    SocioWatchMentionLinkTarget target
  ) {
    Map<String, SObject> uniqueMatches = new Map<String, SObject>();
    Set<String> ambiguousMatches = new Set<String>();

    for (SObject candidate : candidates) {
      String matchKey = normalizeMatchKey(
        String.valueOf(candidate.get(target.fieldApiName))
      );

      if (String.isBlank(matchKey)) {
        continue;
      }

      if (uniqueMatches.containsKey(matchKey)) {
        uniqueMatches.remove(matchKey);
        ambiguousMatches.add(matchKey);
      } else if (!ambiguousMatches.contains(matchKey)) {
        uniqueMatches.put(matchKey, candidate);
      }
    }

    return uniqueMatches;
  }

  private static List<SocioWatch_Mention__c> buildMentionUpdates(
    List<SocioWatch_Mention__c> mentions,
    Map<String, SObject> uniqueMatches,
    SocioWatchMentionLinkTarget target
  ) {
    List<SocioWatch_Mention__c> updates = new List<SocioWatch_Mention__c>();

    for (SocioWatch_Mention__c mention : mentions) {
      SObject matchedRecord = uniqueMatches.get(
        normalizeMatchKey(mention.Author_Name__c)
      );

      updates.add(buildMentionUpdate(mention, matchedRecord, target));
    }

    return updates;
  }

  private static SocioWatch_Mention__c buildMentionUpdate(
    SocioWatch_Mention__c mention,
    SObject matchedRecord,
    SocioWatchMentionLinkTarget target
  ) {
    SocioWatch_Mention__c updateRecord = new SocioWatch_Mention__c(
      Id = mention.Id,
      Author_Match_Status__c = matchedRecord == null
        ? MATCH_STATUS_NOT_FOUND
        : MATCH_STATUS_MATCHED
    );

    if (matchedRecord == null) {
      return updateRecord;
    }

    updateRecord.Linked_Record_Id__c = String.valueOf(matchedRecord.get('Id'));
    updateRecord.Linked_Record_Name__c = mention.Author_Name__c.trim();
    updateRecord.Linked_Object_API_Name__c = target.objectApiName;

    if (target.objectApiName == 'Account') {
      updateRecord.Linked_Account__c = (Id) matchedRecord.get('Id');
    }

    return updateRecord;
  }

  private static String normalizeMatchKey(String value) {
    return String.isBlank(value) ? null : value.trim().toLowerCase();
  }
}
