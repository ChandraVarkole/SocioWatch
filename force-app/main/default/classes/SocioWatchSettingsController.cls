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
      throw createHandledException(error.getMessage());
    } catch (SocioWatchSettingsException error) {
      throw createHandledException(error.getMessage());
    } catch (Exception error) {
      throw createUnexpectedException(
        'Unexpected SocioWatch settings retrieval failure.',
        Label.SocioWatch_Unexpected_Error
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
      return SocioWatchSettingsService.saveSettings(request);
    } catch (SocioWatchAccessException error) {
      throw createHandledException(error.getMessage());
    } catch (SocioWatchValidationException error) {
      throw createHandledException(error.getMessage());
    } catch (SocioWatchApiException error) {
      throw createHandledException(error.getMessage());
    } catch (SocioWatchSettingsException error) {
      throw createHandledException(error.getMessage());
    } catch (Exception error) {
      throw createUnexpectedException(
        'Unexpected SocioWatch settings save failure.',
        Label.SocioWatch_Unexpected_Error
      );
    }
  }

  @AuraEnabled
  public static SocioWatchSettingsResponse getGoogleReviewsStatus(
    String companyId
  ) {
    try {
      return SocioWatchSettingsService.getGoogleReviewsStatus(companyId);
    } catch (Exception error) {
      if (
        error instanceof SocioWatchAccessException ||
        error instanceof SocioWatchValidationException ||
        error instanceof SocioWatchApiException
      ) {
        throw createHandledException(error.getMessage());
      }

      throw createUnexpectedException(
        'Unexpected Google Reviews status retrieval failure.',
        Label.SocioWatch_Unexpected_Error
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
        'SocioWatch permission check failed. Reference: ' + referenceId
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
    String normalizedMessage = SocioWatchValidationService.truncateSafeError(
      safeMessage
    );

    if (String.isBlank(normalizedMessage)) {
      normalizedMessage = Label.SocioWatch_Unexpected_Error;
    }

    AuraHandledException handledException = new AuraHandledException(
      normalizedMessage
    );

    handledException.setMessage(normalizedMessage);

    return handledException;
  }

  /**
   * Logs only a fixed internal context and returns a safe message with a
   * diagnostic reference. Raw exception details never reach the caller.
   */
  @TestVisible
  private static AuraHandledException createUnexpectedException(
    String logContext,
    String safeMessage
  ) {
    String referenceId = generateReferenceId();

    System.debug(LoggingLevel.ERROR, logContext + ' Reference: ' + referenceId);

    return createHandledException(safeMessage + ' Reference: ' + referenceId);
  }

  /**
   * Generates a safe diagnostic reference without exposing
   * implementation details.
   */
  @TestVisible
  private static String generateReferenceId() {
    Blob randomValue = Crypto.generateAesKey(128);

    return EncodingUtil.convertToHex(randomValue);
  }
}
