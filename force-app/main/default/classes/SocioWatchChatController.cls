/**
 * Secure LWC entry point for SocioWatch intelligence chat.
 */
public with sharing class SocioWatchChatController {
  private static final Integer MAX_QUESTION_LENGTH = 2000;
  private static final Integer MAX_HISTORY_MESSAGES = 10;
  private static final Integer MAX_HISTORY_MESSAGE_LENGTH = 4000;

  private SocioWatchChatController() {
  }

  @AuraEnabled
  public static String askQuestion(String question, String historyJson) {
    try {
      SocioWatchPermissionService.requireUseChat();

      String normalizedQuestion = validateQuestion(question);

      List<Object> normalizedHistory = normalizeHistory(historyJson);

      SocioWatch_Configuration__c configuration = getConfiguration();

      String requestBody = JSON.serialize(
        new Map<String, Object>{
          'companyId' => configuration.AWS_Company_Id__c,
          'question' => normalizedQuestion,
          'history' => normalizedHistory
        }
      );

      SocioWatchApiResponse response = SocioWatchApiClient.post(
        SocioWatchConstants.CHAT_ENDPOINT,
        requestBody
      );

      return parseAnswer(response.responseBody);
    } catch (SocioWatchAccessException error) {
      throw handledException(error.getMessage());
    } catch (SocioWatchValidationException error) {
      throw handledException(error.getMessage());
    } catch (SocioWatchApiException error) {
      throw handledException(error.getMessage());
    } catch (Exception error) {
      throw handledException(Label.SocioWatch_Unexpected_Error);
    }
  }

  private static List<Object> normalizeHistory(String historyJson) {
    if (String.isBlank(historyJson)) {
      return new List<Object>();
    }

    List<Object> submittedHistory;

    try {
      submittedHistory = (List<Object>) JSON.deserializeUntyped(historyJson);
    } catch (Exception error) {
      throw new SocioWatchValidationException(
        'The conversation history is invalid.'
      );
    }

    List<Object> validHistory = new List<Object>();

    for (Object historyValue : submittedHistory) {
      Map<String, Object> historyItem;

      try {
        historyItem = (Map<String, Object>) historyValue;
      } catch (Exception error) {
        continue;
      }

      String role = historyItem.get('role') == null
        ? ''
        : String.valueOf(historyItem.get('role')).trim().toLowerCase();

      String text = historyItem.get('text') == null
        ? ''
        : String.valueOf(historyItem.get('text')).trim();

      if (role != 'user' && role != 'assistant') {
        continue;
      }

      if (String.isBlank(text)) {
        continue;
      }

      if (text.length() > MAX_HISTORY_MESSAGE_LENGTH) {
        text = text.substring(0, MAX_HISTORY_MESSAGE_LENGTH);
      }

      validHistory.add(
        new Map<String, Object>{ 'role' => role, 'text' => text }
      );
    }

    Integer startIndex = 0;

    if (validHistory.size() > MAX_HISTORY_MESSAGES) {
      startIndex = validHistory.size() - MAX_HISTORY_MESSAGES;
    }

    List<Object> limitedHistory = new List<Object>();

    for (Integer index = startIndex; index < validHistory.size(); index++) {
      limitedHistory.add(validHistory[index]);
    }

    return limitedHistory;
  }

  private static SocioWatch_Configuration__c getConfiguration() {
    List<SocioWatch_Configuration__c> configurations = [
      SELECT Id, AWS_Company_Id__c
      FROM SocioWatch_Configuration__c
      WITH USER_MODE
      ORDER BY CreatedDate ASC
      LIMIT 2
    ];

    if (configurations.isEmpty()) {
      throw new SocioWatchValidationException(
        'Save the SocioWatch settings before using chat.'
      );
    }

    if (configurations.size() > 1) {
      throw new SocioWatchValidationException(
        'Multiple SocioWatch configurations were found.'
      );
    }

    if (String.isBlank(configurations[0].AWS_Company_Id__c)) {
      throw new SocioWatchValidationException(
        'Save the SocioWatch settings before using chat.'
      );
    }

    return configurations[0];
  }

  private static String validateQuestion(String question) {
    if (String.isBlank(question)) {
      throw new SocioWatchValidationException('Enter a question.');
    }

    String normalized = question.trim();

    if (normalized.length() > MAX_QUESTION_LENGTH) {
      throw new SocioWatchValidationException(
        'The question cannot exceed 2,000 characters.'
      );
    }

    return normalized;
  }

  private static String parseAnswer(String responseBody) {
    if (String.isBlank(responseBody)) {
      throw new SocioWatchApiException(
        'SocioWatch returned an empty chat response.'
      );
    }

    Map<String, Object> response;

    try {
      response = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
    } catch (Exception error) {
      throw new SocioWatchApiException(
        'SocioWatch returned an invalid chat response.'
      );
    }

    Object answerValue = response.get('answer');

    if (answerValue == null || String.isBlank(String.valueOf(answerValue))) {
      throw new SocioWatchApiException('SocioWatch did not return an answer.');
    }

    return String.valueOf(answerValue);
  }

  private static AuraHandledException handledException(String message) {
    String safeMessage = SocioWatchValidationService.truncateSafeError(message);

    AuraHandledException error = new AuraHandledException(safeMessage);

    error.setMessage(safeMessage);

    return error;
  }
}
