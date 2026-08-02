/**
 * Secure LWC entry point for SocioWatch intelligence chat.
 */
public with sharing class SocioWatchChatController {

    private static final Integer MAX_QUESTION_LENGTH = 2000;

    private SocioWatchChatController() {
    }

    @AuraEnabled
    public static String askQuestion(String question) {
        try {
            SocioWatchPermissionService.requireUseChat();

            String normalizedQuestion =
                validateQuestion(question);

            SocioWatch_Configuration__c configuration =
                getConfiguration();

            String requestBody = JSON.serialize(
                new Map<String, Object>{
                    'companyId' =>
                        configuration.AWS_Company_Id__c,
                    'question' =>
                        normalizedQuestion
                }
            );

            SocioWatchApiResponse response =
                SocioWatchApiClient.post(
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
    throw handledException(
        Label.SocioWatch_Unexpected_Error
    );
}
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

        if (
            String.isBlank(
                configurations[0].AWS_Company_Id__c
            )
        ) {
            throw new SocioWatchValidationException(
                'Save the SocioWatch settings before using chat.'
            );
        }

        return configurations[0];
    }

    private static String validateQuestion(String question) {
        if (String.isBlank(question)) {
            throw new SocioWatchValidationException(
                'Enter a question.'
            );
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
            response = (Map<String, Object>)
                JSON.deserializeUntyped(responseBody);
        } catch (Exception error) {
            throw new SocioWatchApiException(
                'SocioWatch returned an invalid chat response.'
            );
        }

        Object answerValue = response.get('answer');

        if (
            answerValue == null ||
            String.isBlank(String.valueOf(answerValue))
        ) {
            throw new SocioWatchApiException(
                'SocioWatch did not return an answer.'
            );
        }

        return String.valueOf(answerValue);
    }

    private static AuraHandledException handledException(
        String message
    ) {
        String safeMessage =
            SocioWatchValidationService.truncateSafeError(
                message
            );

        AuraHandledException error =
            new AuraHandledException(safeMessage);

        error.setMessage(safeMessage);

        return error;
    }
}
