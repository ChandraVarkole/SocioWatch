/**
 * Safe Meta connection response returned to the Settings LWC.
 * Access tokens and secret identifiers are intentionally not represented.
 */
public class SocioWatchMetaConnectionResponse {
  @AuraEnabled
  public String status { get; set; }

  @AuraEnabled
  public String monitoringMode { get; set; }

  @AuraEnabled
  public String message { get; set; }

  @AuraEnabled
  public String authorizationUrl { get; set; }

  @AuraEnabled
  public Boolean hasStoredConnection { get; set; }

  @AuraEnabled
  public List<MetaPage> availablePages { get; set; }

  @AuraEnabled
  public MetaConnection connection { get; set; }

  public SocioWatchMetaConnectionResponse() {
    availablePages = new List<MetaPage>();
  }

  public static SocioWatchMetaConnectionResponse parse(String responseBody) {
    if (String.isBlank(responseBody)) {
      throw new SocioWatchApiException(
        'SocioWatch returned an empty Meta connection response.'
      );
    }

    SocioWatchMetaConnectionResponse response;
    try {
      response = (SocioWatchMetaConnectionResponse) JSON.deserialize(
        responseBody,
        SocioWatchMetaConnectionResponse.class
      );
    } catch (System.JSONException error) {
      throw new SocioWatchApiException(
        'SocioWatch returned an invalid Meta connection response.'
      );
    }

    if (response == null) {
      throw new SocioWatchApiException(
        'SocioWatch returned an invalid Meta connection response.'
      );
    }

    if (response.availablePages == null) {
      response.availablePages = new List<MetaPage>();
    }

    if (
      String.isNotBlank(response.authorizationUrl) &&
      !Pattern.matches(
        '(?i)^https://(www\\.)?facebook\\.com/[A-Za-z0-9._-]+/dialog/oauth\\?.+$',
        response.authorizationUrl
      )
    ) {
      throw new SocioWatchApiException(
        'SocioWatch returned an invalid Meta authorization address.'
      );
    }

    response.message = SocioWatchValidationService.truncateSafeError(
      response.message
    );
    return response;
  }

  public class MetaPage {
    @AuraEnabled
    public String pageId { get; set; }

    @AuraEnabled
    public String pageName { get; set; }

    @AuraEnabled
    public InstagramAccount instagramAccount { get; set; }
  }

  public class InstagramAccount {
    @AuraEnabled
    public String accountId { get; set; }

    @AuraEnabled
    public String username { get; set; }
  }

  public class MetaConnection {
    @AuraEnabled
    public String monitoringMode { get; set; }

    @AuraEnabled
    public String connectedAt { get; set; }

    @AuraEnabled
    public String lastCollectedAt { get; set; }

    @AuraEnabled
    public List<MetaPage> facebookPages { get; set; }

    @AuraEnabled
    public List<InstagramAccount> instagramAccounts { get; set; }
  }
}
