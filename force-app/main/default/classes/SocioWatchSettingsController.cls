/**
 * Lightning controller for the SocioWatch Settings experience.
 *
 * Security controls:
 * - Uses explicit sharing.
 * - Delegates permission, CRUD, FLS, sharing, validation, callout,
 *   and DML enforcement to the service layer.
 * - Returns only safe, user-facing error messages.
 * - Does not expose stack traces, raw AWS responses, credentials,
 *   authorization headers, or Named Credential configuration.
 */
public with sharing class SocioWatchSettingsController {

    private SocioWatchSettingsController() {
    }

    /**
     * Returns the SocioWatch configuration available to the current user.
     *
     * This method is cacheable because it performs no DML or callouts.
     */
    @AuraEnabled(cacheable=true)
    public static SocioWatchSettingsResponse getSettings() {
        try {
            return SocioWatchSettingsService.getSettings();
        } catch (SocioWatchAccessException error) {
            throw createHandledException(
                error.getMessage()
            );
        } catch (SocioWatchValidationException error) {
            throw createHandledException(
                error.getMessage()
            );
        } catch (SocioWatchSettingsException error) {
            throw createHandledException(
                error.getMessage()
            );
        } catch (QueryException error) {
            String referenceId = generateReferenceId();

            System.debug(
                LoggingLevel.ERROR,
                'SocioWatch settings query failed. Reference: ' +
                referenceId
            );

            throw createHandledException(
                Label.SocioWatch_Unexpected_Error +
                ' Reference: ' +
                referenceId
            );
        } catch (Exception error) {
            String referenceId = generateReferenceId();

            System.debug(
                LoggingLevel.ERROR,
                'Unexpected SocioWatch settings retrieval failure. ' +
                'Reference: ' +
                referenceId
            );

            throw createHandledException(
                Label.SocioWatch_Unexpected_Error +
                ' Reference: ' +
                referenceId
            );
        }
    }

    /**
     * Validates and saves the SocioWatch configuration.
     *
     * The service performs:
     * - Custom permission enforcement
     * - Input validation
     * - AWS registration through the Named Credential
     * - User-mode database operations
     * - Singleton enforcement
     */
    @AuraEnabled
    public static SocioWatchSettingsResponse saveSettings(
        SocioWatchSettingsRequest request
    ) {
        try {
            return SocioWatchSettingsService.saveSettings(
                request
            );
        } catch (SocioWatchAccessException error) {
            throw createHandledException(
                error.getMessage()
            );
        } catch (SocioWatchValidationException error) {
            throw createHandledException(
                error.getMessage()
            );
        } catch (SocioWatchApiException error) {
            throw createHandledException(
                error.getMessage()
            );
        } catch (SocioWatchSettingsException error) {
            throw createHandledException(
                error.getMessage()
            );
        } catch (DmlException error) {
            String referenceId = generateReferenceId();

            System.debug(
                LoggingLevel.ERROR,
                'SocioWatch settings DML failed. Reference: ' +
                referenceId
            );

            throw createHandledException(
                'SocioWatch settings could not be saved. ' +
                'Verify your permissions and configuration. ' +
                'Reference: ' +
                referenceId
            );
        } catch (Exception error) {
            String referenceId = generateReferenceId();

            System.debug(
                LoggingLevel.ERROR,
                'Unexpected SocioWatch settings save failure. ' +
                'Reference: ' +
                referenceId
            );

            throw createHandledException(
                Label.SocioWatch_Unexpected_Error +
                ' Reference: ' +
                referenceId
            );
        }
    }

    /**
     * Returns whether the current user has access to manage Settings.
     *
     * This supports conditional rendering in the LWC.
     * The server still checks permission during every operation.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean canManageSettings() {
        try {
            return SocioWatchPermissionService.canManageSettings();
        } catch (Exception error) {
            String referenceId = generateReferenceId();

            System.debug(
                LoggingLevel.ERROR,
                'SocioWatch permission check failed. Reference: ' +
                referenceId
            );

            return false;
        }
    }

    /**
     * Creates an error the LWC can safely display.
     */
    @TestVisible
    private static AuraHandledException createHandledException(
        String safeMessage
    ) {
        String normalizedMessage =
            SocioWatchValidationService.truncateSafeError(
                safeMessage
            );

        if (String.isBlank(normalizedMessage)) {
            normalizedMessage =
                Label.SocioWatch_Unexpected_Error;
        }

        AuraHandledException handledException =
            new AuraHandledException(
                normalizedMessage
            );

        handledException.setMessage(
            normalizedMessage
        );

        return handledException;
    }

    /**
     * Generates a safe diagnostic reference without exposing
     * implementation details.
     */
    @TestVisible
    private static String generateReferenceId() {
        Blob randomValue =
            Crypto.generateAesKey(128);

        return EncodingUtil.convertToHex(
            randomValue
        );
    }
}
