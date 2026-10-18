/** Lightning controller for the Salesforce Meta connection modal. */
public with sharing class SocioWatchMetaController {
  private SocioWatchMetaController() {
  }

  @AuraEnabled
  public static SocioWatchMetaConnectionResponse getConnection() {
    try {
      return SocioWatchMetaService.getConnection();
    } catch (Exception error) {
      throw handled(error);
    }
  }

  @AuraEnabled
  public static SocioWatchMetaConnectionResponse startConnection(
    String monitoringMode,
    String returnOrigin
  ) {
    try {
      return SocioWatchMetaService.startConnection(
        monitoringMode,
        returnOrigin
      );
    } catch (Exception error) {
      throw handled(error);
    }
  }

  @AuraEnabled
  public static SocioWatchMetaConnectionResponse saveSelection(
    List<String> facebookPageIds
  ) {
    try {
      return SocioWatchMetaService.saveSelection(facebookPageIds);
    } catch (Exception error) {
      throw handled(error);
    }
  }

  @AuraEnabled
  public static SocioWatchMetaConnectionResponse disconnect() {
    try {
      return SocioWatchMetaService.disconnect();
    } catch (Exception error) {
      throw handled(error);
    }
  }

  private static AuraHandledException handled(Exception error) {
    String message;
    if (
      error instanceof SocioWatchAccessException ||
      error instanceof SocioWatchValidationException ||
      error instanceof SocioWatchApiException
    ) {
      message = error.getMessage();
    } else {
      message = Label.SocioWatch_Unexpected_Error;
    }

    message = SocioWatchValidationService.truncateSafeError(message);
    AuraHandledException result = new AuraHandledException(message);
    result.setMessage(message);
    return result;
  }
}
