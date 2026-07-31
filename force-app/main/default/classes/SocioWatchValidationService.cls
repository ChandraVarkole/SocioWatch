/**
 * Central validation and normalization service for SocioWatch.
 *
 * Security controls:
 * - Rejects blank required values.
 * - Enforces maximum lengths.
 * - Rejects control characters.
 * - Normalizes whitespace.
 * - Removes duplicate keywords case-insensitively.
 * - Limits the total number of keywords.
 *
 * Client-side validation is not trusted. Apex must always validate again.
 */
public inherited sharing class SocioWatchValidationService {

    private static final String CONTROL_CHARACTER_PATTERN =
        '[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F\\x7F]';

    private static final String MULTIPLE_SPACE_PATTERN =
        '\\s+';

    private SocioWatchValidationService() {
    }

    /**
     * Validates and normalizes the company name.
     */
    public static String normalizeCompanyName(
        String companyName
    ) {
        String normalizedValue = normalizeRequiredText(
            companyName,
            'Company Name',
            SocioWatchConstants.MAX_COMPANY_NAME_LENGTH
        );

        return normalizedValue;
    }

    /**
     * Validates and normalizes the external alert identifier.
     */
    public static String normalizeAlertId(
        String alertId
    ) {
        String normalizedValue = normalizeRequiredText(
            alertId,
            'Alert ID',
            SocioWatchConstants.MAX_ALERT_ID_LENGTH
        );

        if (!Pattern.matches(
            '^[A-Za-z0-9._:-]+$',
            normalizedValue
        )) {
            throw new SocioWatchValidationException(
                'Alert ID contains unsupported characters.'
            );
        }

        return normalizedValue;
    }

    /**
     * Validates and normalizes a keyword list.
     *
     * Duplicate keywords are removed case-insensitively while preserving
     * the original order and capitalization of the first occurrence.
     */
    public static List<String> normalizeKeywords(
        List<String> keywords
    ) {
        if (keywords == null || keywords.isEmpty()) {
            throw new SocioWatchValidationException(
                'Enter at least one keyword.'
            );
        }

        if (
            keywords.size() >
            SocioWatchConstants.MAX_KEYWORD_COUNT
        ) {
            throw new SocioWatchValidationException(
                'You can configure up to ' +
                SocioWatchConstants.MAX_KEYWORD_COUNT +
                ' keywords.'
            );
        }

        List<String> normalizedKeywords =
            new List<String>();

        Set<String> keywordKeys =
            new Set<String>();

        for (String keyword : keywords) {
            String normalizedKeyword =
                normalizeRequiredText(
                    keyword,
                    'Keyword',
                    SocioWatchConstants.MAX_KEYWORD_LENGTH
                );

            String duplicateKey =
                normalizedKeyword.toLowerCase();

            if (!keywordKeys.contains(duplicateKey)) {
                keywordKeys.add(duplicateKey);
                normalizedKeywords.add(normalizedKeyword);
            }
        }

        if (normalizedKeywords.isEmpty()) {
            throw new SocioWatchValidationException(
                'Enter at least one keyword.'
            );
        }

        return normalizedKeywords;
    }

    /**
     * Converts the configuration Long Text Area value into a normalized list.
     *
     * Supports one keyword per line. Commas are also accepted to make
     * migration and manual editing easier.
     */
    public static List<String> parseKeywords(
        String storedKeywords
    ) {
        if (String.isBlank(storedKeywords)) {
            throw new SocioWatchValidationException(
                'Enter at least one keyword.'
            );
        }

        String normalizedSeparators =
            storedKeywords.replace('\r\n', '\n');

        normalizedSeparators =
            normalizedSeparators.replace('\r', '\n');

        normalizedSeparators =
            normalizedSeparators.replace(',', '\n');

        List<String> rawKeywords =
            normalizedSeparators.split('\n');

        return normalizeKeywords(rawKeywords);
    }

    /**
     * Converts a normalized keyword list into the Salesforce storage format.
     *
     * One keyword is stored per line.
     */
    public static String serializeKeywords(
        List<String> keywords
    ) {
        List<String> normalizedKeywords =
            normalizeKeywords(keywords);

        return String.join(
            normalizedKeywords,
            '\n'
        );
    }

    /**
     * Validates a SocioWatch company identifier returned by AWS.
     */
    public static String normalizeCompanyId(
        String companyId
    ) {
        if (String.isBlank(companyId)) {
            return null;
        }

        String normalizedValue = companyId.trim();

        if (
            normalizedValue.length() > 100 ||
            !Pattern.matches(
                '^[A-Za-z0-9_-]+$',
                normalizedValue
            )
        ) {
            throw new SocioWatchValidationException(
                'The SocioWatch company identifier is invalid.'
            );
        }

        return normalizedValue;
    }

    /**
     * Validates a SocioWatch tenant identifier returned by AWS.
     */
    public static String normalizeTenantId(
        String tenantId
    ) {
        if (String.isBlank(tenantId)) {
            return null;
        }

        String normalizedValue = tenantId.trim();

        if (
            normalizedValue.length() > 100 ||
            !Pattern.matches(
                '^[A-Za-z0-9_-]+$',
                normalizedValue
            )
        ) {
            throw new SocioWatchValidationException(
                'The SocioWatch tenant identifier is invalid.'
            );
        }

        return normalizedValue;
    }

    /**
     * Validates a Salesforce organization identifier.
     */
    public static String normalizeSalesforceOrgId(
        String organizationId
    ) {
        if (String.isBlank(organizationId)) {
            throw new SocioWatchValidationException(
                'The Salesforce organization identifier is required.'
            );
        }

        String normalizedValue =
            organizationId.trim();

        if (
            normalizedValue.length() != 15 &&
            normalizedValue.length() != 18
        ) {
            throw new SocioWatchValidationException(
                'The Salesforce organization identifier is invalid.'
            );
        }

        if (!Pattern.matches(
            '^[A-Za-z0-9]+$',
            normalizedValue
        )) {
            throw new SocioWatchValidationException(
                'The Salesforce organization identifier is invalid.'
            );
        }

        return normalizedValue;
    }

    /**
     * Creates a safely shortened error message for storage.
     *
     * This method must only receive already-sanitized application messages.
     * Never pass raw AWS response bodies, authorization headers, or stack traces.
     */
    public static String truncateSafeError(
        String safeErrorMessage
    ) {
        if (String.isBlank(safeErrorMessage)) {
            return null;
        }

        String normalizedValue =
            removeControlCharacters(
                safeErrorMessage.trim()
            );

        if (
            normalizedValue.length() >
            SocioWatchConstants.MAX_SAFE_ERROR_LENGTH
        ) {
            normalizedValue =
                normalizedValue.substring(
                    0,
                    SocioWatchConstants.MAX_SAFE_ERROR_LENGTH
                );
        }

        return normalizedValue;
    }

    /**
     * Normalizes a required text value.
     */
    @TestVisible
    private static String normalizeRequiredText(
        String value,
        String fieldLabel,
        Integer maximumLength
    ) {
        if (String.isBlank(value)) {
            throw new SocioWatchValidationException(
                fieldLabel + ' is required.'
            );
        }

        String normalizedValue =
            removeControlCharacters(value);

        normalizedValue =
            normalizedValue.trim();

        normalizedValue =
            normalizedValue.replaceAll(
                MULTIPLE_SPACE_PATTERN,
                ' '
            );

        if (String.isBlank(normalizedValue)) {
            throw new SocioWatchValidationException(
                fieldLabel + ' is required.'
            );
        }

        if (
            maximumLength != null &&
            normalizedValue.length() > maximumLength
        ) {
            throw new SocioWatchValidationException(
                fieldLabel +
                ' cannot exceed ' +
                maximumLength +
                ' characters.'
            );
        }

        return normalizedValue;
    }

    /**
     * Rejects hidden control characters instead of silently persisting them.
     */
    @TestVisible
    private static String removeControlCharacters(
        String value
    ) {
        if (value == null) {
            return null;
        }

        if (Pattern.compile(
            CONTROL_CHARACTER_PATTERN
        ).matcher(value).find()) {
            throw new SocioWatchValidationException(
                'The submitted value contains unsupported characters.'
            );
        }

        return value;
    }
}
