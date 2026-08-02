/**
 * Synchronizes actionable SocioWatch mentions into Salesforce.
 *
 * Complete mention history remains in AWS. Salesforce stores only
 * records returned by the customer-facing mentions endpoint.
 */
public with sharing class SocioWatchSyncService {

    private SocioWatchSyncService() {
    }

    public static void runSync(Id configurationId) {
        SocioWatch_Configuration__c configuration =
            getConfiguration(configurationId);

        if (!configuration.Sync_Enabled__c) {
            throw new SocioWatchValidationException(
                'Synchronization is disabled.'
            );
        }

        if (String.isBlank(configuration.AWS_Company_Id__c)) {
            throw new SocioWatchValidationException(
                'Save the SocioWatch settings before running a sync.'
            );
        }

        try {
            triggerAwsSync(configuration.AWS_Company_Id__c);

            List<SocioWatch_Mention__c> mentions =
                retrieveMentions(configuration);

            Integer processedCount =
                upsertMentions(mentions);

            updateSuccess(
                configuration,
                processedCount
            );
        } catch (Exception error) {
            updateFailure(
                configuration,
                getSafeErrorMessage(error)
            );

            throw error;
        }
    }

    private static SocioWatch_Configuration__c getConfiguration(
        Id configurationId
    ) {
        if (configurationId == null) {
            throw new SocioWatchValidationException(
                'SocioWatch configuration is required.'
            );
        }

        List<SocioWatch_Configuration__c> records = [
            SELECT
                Id,
                Company_Name__c,
                Alert_Id__c,
                AWS_Company_Id__c,
                Sync_Enabled__c,
                Last_Sync_Status__c,
                Last_Successful_Sync__c,
                Last_Sync_Error__c
            FROM SocioWatch_Configuration__c
            WHERE Id = :configurationId
            WITH USER_MODE
            LIMIT 1
        ];

        if (records.isEmpty()) {
            throw new SocioWatchAccessException(
                'You do not have access to the SocioWatch configuration.'
            );
        }

        return records[0];
    }

    private static void triggerAwsSync(String companyId) {
        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'companyId' => companyId
            }
        );

        SocioWatchApiClient.post(
            SocioWatchConstants.SYNC_ENDPOINT,
            requestBody
        );
    }

    private static List<SocioWatch_Mention__c> retrieveMentions(
        SocioWatch_Configuration__c configuration
    ) {
        String encodedCompanyId =
            EncodingUtil.urlEncode(
                configuration.AWS_Company_Id__c,
                'UTF-8'
            );

        SocioWatchApiResponse response =
            SocioWatchApiClient.get(
                SocioWatchConstants.MENTIONS_ENDPOINT +
                '?companyId=' +
                encodedCompanyId
            );

        Map<String, Object> payload;

        try {
            payload = (Map<String, Object>)
                JSON.deserializeUntyped(
                    response.responseBody
                );
        } catch (Exception error) {
            throw new SocioWatchApiException(
                'SocioWatch returned an invalid mentions response.'
            );
        }

        List<Object> rawMentions =
            (List<Object>) payload.get('mentions');

        List<SocioWatch_Mention__c> records =
            new List<SocioWatch_Mention__c>();

        if (rawMentions == null) {
            return records;
        }

        Datetime syncedAt = System.now();

        for (Object rawMention : rawMentions) {
            Map<String, Object> mention =
                (Map<String, Object>) rawMention;

            Boolean actionable =
                getBoolean(mention, 'actionable');

            if (
                mention.containsKey('actionable') &&
                actionable == false
            ) {
                continue;
            }

            String externalMentionId =
                firstString(
                    mention,
                    new List<String>{
                        'id',
                        'mentionId',
                        'MentionId'
                    }
                );

            if (String.isBlank(externalMentionId)) {
                continue;
            }

            SocioWatch_Mention__c record =
                new SocioWatch_Mention__c();

            record.Configuration__c =
                configuration.Id;

            record.External_Mention_Id__c =
                truncate(externalMentionId, 150);

            record.Alert_Id__c =
                truncate(
                    firstString(
                        mention,
                        new List<String>{
                            'alertId',
                            'AlertId'
                        }
                    ),
                    255
                );

            record.Source__c =
                truncate(
                    firstString(
                        mention,
                        new List<String>{
                            'source',
                            'Source'
                        }
                    ),
                    100
                );

            record.Source_URL__c =
                firstString(
                    mention,
                    new List<String>{
                        'url',
                        'sourceUrl',
                        'SourceUrl'
                    }
                );

            record.Author_Name__c =
                truncate(
                    firstString(
                        mention,
                        new List<String>{
                            'author',
                            'authorName',
                            'Author'
                        }
                    ),
                    255
                );

            record.Title__c =
                truncate(
                    firstString(
                        mention,
                        new List<String>{
                            'title',
                            'Title'
                        }
                    ),
                    255
                );

            record.Mention_Text__c =
                firstString(
                    mention,
                    new List<String>{
                        'content',
                        'text',
                        'MentionText'
                    }
                );

            record.Mention_Date__c =
                parseDatetime(
                    firstString(
                        mention,
                        new List<String>{
                            'publishedAt',
                            'mentionDate',
                            'PublishedAt'
                        }
                    )
                );

            if (record.Mention_Date__c == null) {
                record.Mention_Date__c = syncedAt;
            }

            record.Language__c =
                truncate(
                    firstString(
                        mention,
                        new List<String>{
                            'language',
                            'Language'
                        }
                    ),
                    20
                );

            record.Sentiment__c =
                normalizeSentiment(
                    firstString(
                        mention,
                        new List<String>{
                            'sentiment',
                            'Sentiment'
                        }
                    )
                );

            record.Actionable_Type__c =
                normalizeActionableType(
                    firstString(
                        mention,
                        new List<String>{
                            'actionableType',
                            'category'
                        }
                    )
                );

            record.Action_Reason__c =
                firstString(
                    mention,
                    new List<String>{
                        'actionReason',
                        'reason'
                    }
                );

            record.Recommended_Action__c =
                firstString(
                    mention,
                    new List<String>{
                        'recommendedAction'
                    }
                );

            record.Priority__c =
                normalizePriority(
                    firstString(
                        mention,
                        new List<String>{
                            'priority'
                        }
                    )
                );

            record.Status__c =
                SocioWatchConstants.MENTION_STATUS_NEW;

            record.Synced_At__c =
                syncedAt;

            record.Sync_Run_Id__c =
                truncate(
                    firstString(
                        mention,
                        new List<String>{
                            'syncRunId'
                        }
                    ),
                    100
                );

            records.add(record);
        }

        return records;
    }

    private static Integer upsertMentions(
        List<SocioWatch_Mention__c> mentions
    ) {
        if (mentions.isEmpty()) {
            return 0;
        }

        Schema.SObjectField externalIdField =
            SocioWatch_Mention__c.External_Mention_Id__c;

        Database.UpsertResult[] results =
            Database.upsert(
                mentions,
                externalIdField,
                false,
                AccessLevel.USER_MODE
            );

        Integer successCount = 0;

        for (Database.UpsertResult result : results) {
            if (result.isSuccess()) {
                successCount++;
            }
        }

        return successCount;
    }

    private static void updateSuccess(
        SocioWatch_Configuration__c configuration,
        Integer processedCount
    ) {
        configuration.Last_Sync_Status__c =
            SocioWatchConstants.SYNC_STATUS_SUCCESS;

        configuration.Last_Successful_Sync__c =
            System.now();

        configuration.Last_Sync_Error__c =
            null;

        Database.update(
            configuration,
            AccessLevel.USER_MODE
        );
    }

    private static void updateFailure(
        SocioWatch_Configuration__c configuration,
        String safeMessage
    ) {
        if (
            configuration == null ||
            configuration.Id == null
        ) {
            return;
        }

        configuration.Last_Sync_Status__c =
            SocioWatchConstants.SYNC_STATUS_FAILED;

        configuration.Last_Sync_Error__c =
            SocioWatchValidationService.truncateSafeError(
                safeMessage
            );

        try {
            Database.update(
                configuration,
                AccessLevel.USER_MODE
            );
        } catch (Exception ignoredError) {
            System.debug(
                LoggingLevel.ERROR,
                'SocioWatch failed to update the sync status.'
            );
        }
    }

    private static String getSafeErrorMessage(
        Exception error
    ) {
        if (
            error instanceof SocioWatchApiException ||
            error instanceof SocioWatchAccessException ||
            error instanceof SocioWatchValidationException
        ) {
            return error.getMessage();
        }

        return Label.SocioWatch_Unexpected_Error;
    }

    private static String firstString(
        Map<String, Object> values,
        List<String> keys
    ) {
        for (String key : keys) {
            Object value = values.get(key);

            if (value != null) {
                return String.valueOf(value);
            }
        }

        return null;
    }

    private static Boolean getBoolean(
        Map<String, Object> values,
        String key
    ) {
        Object value = values.get(key);

        if (value == null) {
            return false;
        }

        if (value instanceof Boolean) {
            return (Boolean) value;
        }

        return String.valueOf(value).toLowerCase() == 'true';
    }

    private static Datetime parseDatetime(
        String value
    ) {
        if (String.isBlank(value)) {
            return null;
        }

        try {
            return Datetime.valueOf(
                value
                    .replace('T', ' ')
                    .replace('Z', '')
            );
        } catch (Exception error) {
            return null;
        }
    }

    private static String normalizeSentiment(
        String value
    ) {
        if (String.isBlank(value)) {
            return 'Unknown';
        }

        String normalized =
            value.trim().toLowerCase();

        if (normalized == 'positive') {
            return 'Positive';
        }

        if (normalized == 'negative') {
            return 'Negative';
        }

        if (normalized == 'neutral') {
            return 'Neutral';
        }

        if (normalized == 'mixed') {
            return 'Mixed';
        }

        return 'Unknown';
    }

    private static String normalizePriority(
        String value
    ) {
        if (String.isBlank(value)) {
            return SocioWatchConstants.PRIORITY_MEDIUM;
        }

        String normalized =
            value.trim().toLowerCase();

        if (normalized == 'low') {
            return SocioWatchConstants.PRIORITY_LOW;
        }

        if (normalized == 'high') {
            return SocioWatchConstants.PRIORITY_HIGH;
        }

        if (normalized == 'critical') {
            return SocioWatchConstants.PRIORITY_CRITICAL;
        }

        return SocioWatchConstants.PRIORITY_MEDIUM;
    }

    private static String normalizeActionableType(
        String value
    ) {
        Set<String> allowedValues =
            new Set<String>{
                'Customer Complaint',
                'Support Request',
                'Churn Risk',
                'Sales Opportunity',
                'High Impact Mention',
                'Safety or Legal Concern',
                'Other'
            };

        if (String.isBlank(value)) {
            return 'Other';
        }

        for (String allowedValue : allowedValues) {
            if (
                allowedValue.equalsIgnoreCase(
                    value.trim()
                )
            ) {
                return allowedValue;
            }
        }

        return 'Other';
    }

    private static String truncate(
        String value,
        Integer maximumLength
    ) {
        if (
            value == null ||
            maximumLength == null ||
            value.length() <= maximumLength
        ) {
            return value;
        }

        return value.substring(
            0,
            maximumLength
        );
    }
}