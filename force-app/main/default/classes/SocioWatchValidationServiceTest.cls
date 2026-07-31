@IsTest
private class SocioWatchValidationServiceTest {

    @IsTest
    static void normalizesCompanyName() {
        String result =
            SocioWatchValidationService.normalizeCompanyName(
                '  Tesla   Motors  '
            );

        System.assertEquals(
            'Tesla Motors',
            result
        );
    }

    @IsTest
    static void rejectsBlankCompanyName() {
        assertValidationMessage(
            new ValidationAction(
                ValidationActionType.COMPANY_NAME,
                '   '
            ),
            'Company Name is required.'
        );
    }

    @IsTest
    static void rejectsCompanyNameOverMaximumLength() {
        String longName =
            repeatCharacter(
                'A',
                SocioWatchConstants.MAX_COMPANY_NAME_LENGTH + 1
            );

        assertValidationMessage(
            new ValidationAction(
                ValidationActionType.COMPANY_NAME,
                longName
            ),
            'Company Name cannot exceed ' +
            SocioWatchConstants.MAX_COMPANY_NAME_LENGTH +
            ' characters.'
        );
    }

    @IsTest
    static void normalizesAlertId() {
        String result =
            SocioWatchValidationService.normalizeAlertId(
                '  alert_12345  '
            );

        System.assertEquals(
            'alert_12345',
            result
        );
    }

    @IsTest
    static void rejectsUnsupportedAlertCharacters() {
        assertValidationMessage(
            new ValidationAction(
                ValidationActionType.ALERT_ID,
                'alert<script>'
            ),
            'Alert ID contains unsupported characters.'
        );
    }

    @IsTest
    static void removesDuplicateKeywordsIgnoringCase() {
        List<String> result =
            SocioWatchValidationService.normalizeKeywords(
                new List<String>{
                    'Tesla',
                    ' tesla ',
                    'Tesla   Motors',
                    'Battery'
                }
            );

        System.assertEquals(
            3,
            result.size()
        );

        System.assertEquals(
            'Tesla',
            result[0]
        );

        System.assertEquals(
            'Tesla Motors',
            result[1]
        );

        System.assertEquals(
            'Battery',
            result[2]
        );
    }

    @IsTest
    static void parsesNewlineAndCommaSeparatedKeywords() {
        List<String> result =
            SocioWatchValidationService.parseKeywords(
                'Tesla\r\nTesla Motors,Battery'
            );

        System.assertEquals(
            new List<String>{
                'Tesla',
                'Tesla Motors',
                'Battery'
            },
            result
        );
    }

    @IsTest
    static void serializesKeywordsOnePerLine() {
        String result =
            SocioWatchValidationService.serializeKeywords(
                new List<String>{
                    'Tesla',
                    'Tesla Motors'
                }
            );

        System.assertEquals(
            'Tesla\nTesla Motors',
            result
        );
    }

    @IsTest
    static void rejectsEmptyKeywordList() {
        try {
            SocioWatchValidationService.normalizeKeywords(
                new List<String>()
            );

            System.assert(
                false,
                'Expected a validation exception.'
            );
        } catch (SocioWatchValidationException error) {
            System.assertEquals(
                'Enter at least one keyword.',
                error.getMessage()
            );
        }
    }

    @IsTest
    static void rejectsTooManyKeywords() {
        List<String> keywords = new List<String>();

        for (
            Integer index = 0;
            index <
                SocioWatchConstants.MAX_KEYWORD_COUNT + 1;
            index++
        ) {
            keywords.add(
                'Keyword ' + index
            );
        }

        try {
            SocioWatchValidationService.normalizeKeywords(
                keywords
            );

            System.assert(
                false,
                'Expected a validation exception.'
            );
        } catch (SocioWatchValidationException error) {
            System.assertEquals(
                'You can configure up to ' +
                SocioWatchConstants.MAX_KEYWORD_COUNT +
                ' keywords.',
                error.getMessage()
            );
        }
    }

    @IsTest
    static void rejectsKeywordOverMaximumLength() {
        String longKeyword =
            repeatCharacter(
                'K',
                SocioWatchConstants.MAX_KEYWORD_LENGTH + 1
            );

        try {
            SocioWatchValidationService.normalizeKeywords(
                new List<String>{
                    longKeyword
                }
            );

            System.assert(
                false,
                'Expected a validation exception.'
            );
        } catch (SocioWatchValidationException error) {
            System.assertEquals(
                'Keyword cannot exceed ' +
                SocioWatchConstants.MAX_KEYWORD_LENGTH +
                ' characters.',
                error.getMessage()
            );
        }
    }

    @IsTest
    static void rejectsControlCharacters() {
        String invalidValue =
            'Tesla' +
            String.fromCharArray(
                new List<Integer>{ 1 }
            );

        try {
            SocioWatchValidationService.normalizeCompanyName(
                invalidValue
            );

            System.assert(
                false,
                'Expected a validation exception.'
            );
        } catch (SocioWatchValidationException error) {
            System.assertEquals(
                'The submitted value contains unsupported characters.',
                error.getMessage()
            );
        }
    }

    @IsTest
    static void validatesCompanyAndTenantIdentifiers() {
        System.assertEquals(
            'COMP-000001',
            SocioWatchValidationService.normalizeCompanyId(
                ' COMP-000001 '
            )
        );

        System.assertEquals(
            'TENANT_000001',
            SocioWatchValidationService.normalizeTenantId(
                ' TENANT_000001 '
            )
        );
    }

    @IsTest
    static void allowsNullOptionalIdentifiers() {
        System.assertEquals(
            null,
            SocioWatchValidationService.normalizeCompanyId(
                null
            )
        );

        System.assertEquals(
            null,
            SocioWatchValidationService.normalizeTenantId(
                ' '
            )
        );
    }

    @IsTest
    static void rejectsInvalidCompanyIdentifier() {
        try {
            SocioWatchValidationService.normalizeCompanyId(
                '../COMP-000001'
            );

            System.assert(
                false,
                'Expected a validation exception.'
            );
        } catch (SocioWatchValidationException error) {
            System.assertEquals(
                'The SocioWatch company identifier is invalid.',
                error.getMessage()
            );
        }
    }

    @IsTest
    static void validatesSalesforceOrgIdentifiers() {
        System.assertEquals(
            '00D000000000001',
            SocioWatchValidationService
                .normalizeSalesforceOrgId(
                    '00D000000000001'
                )
        );

        System.assertEquals(
            '00D000000000001AAA',
            SocioWatchValidationService
                .normalizeSalesforceOrgId(
                    '00D000000000001AAA'
                )
        );
    }

    @IsTest
    static void rejectsInvalidSalesforceOrgIdentifier() {
        try {
            SocioWatchValidationService
                .normalizeSalesforceOrgId(
                    'invalid-org'
                );

            System.assert(
                false,
                'Expected a validation exception.'
            );
        } catch (SocioWatchValidationException error) {
            System.assertEquals(
                'The Salesforce organization identifier is invalid.',
                error.getMessage()
            );
        }
    }

    @IsTest
    static void truncatesSafeErrors() {
        String longMessage =
            repeatCharacter(
                'E',
                SocioWatchConstants.MAX_SAFE_ERROR_LENGTH + 50
            );

        String result =
            SocioWatchValidationService.truncateSafeError(
                longMessage
            );

        System.assertEquals(
            SocioWatchConstants.MAX_SAFE_ERROR_LENGTH,
            result.length()
        );
    }

    private enum ValidationActionType {
        COMPANY_NAME,
        ALERT_ID
    }

    private class ValidationAction {

        private ValidationActionType actionType;
        private String inputValue;

        private ValidationAction(
            ValidationActionType actionType,
            String inputValue
        ) {
            this.actionType = actionType;
            this.inputValue = inputValue;
        }

        private void execute() {
            if (
                actionType ==
                ValidationActionType.COMPANY_NAME
            ) {
                SocioWatchValidationService
                    .normalizeCompanyName(
                        inputValue
                    );
            } else {
                SocioWatchValidationService
                    .normalizeAlertId(
                        inputValue
                    );
            }
        }
    }

    private static void assertValidationMessage(
        ValidationAction action,
        String expectedMessage
    ) {
        try {
            action.execute();

            System.assert(
                false,
                'Expected a validation exception.'
            );
        } catch (SocioWatchValidationException error) {
            System.assertEquals(
                expectedMessage,
                error.getMessage()
            );
        }
    }

    private static String repeatCharacter(
        String characterValue,
        Integer count
    ) {
        List<String> values = new List<String>();

        for (
            Integer index = 0;
            index < count;
            index++
        ) {
            values.add(characterValue);
        }

        return String.join(
            values,
            ''
        );
    }
}
