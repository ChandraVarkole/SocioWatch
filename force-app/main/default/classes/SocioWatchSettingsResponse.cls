/**
 * Safe Settings response returned to the SocioWatch LWC.
 *
 * This response intentionally excludes:
 * - API keys
 * - authorization headers
 * - raw AWS responses
 * - stack traces
 * - Named Credential details
 */
public class SocioWatchSettingsResponse {
  @AuraEnabled
  public Id configurationId { get; set; }

  @AuraEnabled
  public String configurationNumber { get; set; }

  @AuraEnabled
  public String companyName { get; set; }

  @AuraEnabled
  public String website { get; set; }

  @AuraEnabled
  public String llmMentionKeyword { get; set; }

  @AuraEnabled
  public String companyCity { get; set; }

  @AuraEnabled
  public String companyStateProvince { get; set; }

  @AuraEnabled
  public String companyCountry { get; set; }

  @AuraEnabled
  public Boolean googleReviewsEnabled { get; set; }

  @AuraEnabled
  public String googleReviewsResolutionStatus { get; set; }

  @AuraEnabled
  public String googleReviewsResolutionMessage { get; set; }

  @AuraEnabled
  public Boolean autoLinkMentions { get; set; }

  @AuraEnabled
  public String authorMatchObjectApiName { get; set; }

  @AuraEnabled
  public String authorMatchFieldApiName { get; set; }

  @AuraEnabled
  public List<String> keywords { get; set; }

  @AuraEnabled
  public Boolean syncEnabled { get; set; }

  @AuraEnabled
  public String companyId { get; set; }

  @AuraEnabled
  public String tenantId { get; set; }

  @AuraEnabled
  public String salesforceOrgId { get; set; }

  @AuraEnabled
  public Datetime lastSuccessfulSync { get; set; }

  @AuraEnabled
  public String lastSyncStatus { get; set; }

  @AuraEnabled
  public String message { get; set; }

  @AuraEnabled
  public Boolean created { get; set; }

  public SocioWatchSettingsResponse() {
    keywords = new List<String>();
    created = false;
    googleReviewsEnabled = true;
    autoLinkMentions = false;
  }

  public static SocioWatchSettingsResponse fromConfiguration(
    SocioWatch_Configuration__c configuration
  ) {
    SocioWatchSettingsResponse response = new SocioWatchSettingsResponse();

    if (configuration == null) {
      response.syncEnabled = true;
      response.lastSyncStatus = SocioWatchConstants.SYNC_STATUS_NOT_STARTED;

      return response;
    }

    response.configurationId = configuration.Id;
    response.configurationNumber = configuration.Name;
    response.companyName = configuration.Company_Name__c;
    response.website = configuration.Website__c;
    response.llmMentionKeyword = String.isBlank(
        configuration.LLM_Mention_Keyword__c
      )
      ? configuration.Company_Name__c
      : configuration.LLM_Mention_Keyword__c;
    response.companyCity = configuration.Company_City__c;
    response.companyStateProvince = configuration.Company_State_Province__c;
    response.companyCountry = configuration.Company_Country__c;
    response.googleReviewsEnabled = configuration.Google_Reviews_Enabled__c;
    response.autoLinkMentions = configuration.Auto_Link_Mentions__c;
    response.authorMatchObjectApiName = configuration.Author_Match_Object__c;
    response.authorMatchFieldApiName = configuration.Author_Match_Field__c;
    response.syncEnabled = configuration.Sync_Enabled__c;
    response.companyId = configuration.AWS_Company_Id__c;
    response.tenantId = configuration.Tenant_Id__c;
    response.salesforceOrgId = configuration.Salesforce_Org_Id__c;
    response.lastSuccessfulSync = configuration.Last_Successful_Sync__c;
    response.lastSyncStatus = configuration.Last_Sync_Status__c;

    if (String.isNotBlank(configuration.Keywords__c)) {
      response.keywords = SocioWatchValidationService.parseKeywords(
        configuration.Keywords__c
      );
    }

    return response;
  }

  public static AwsSettingsResult parseAwsResponse(String responseBody) {
    if (String.isBlank(responseBody)) {
      throw new SocioWatchApiException(
        'SocioWatch returned an empty settings response.'
      );
    }

    AwsSettingsResult result;

    try {
      result = (AwsSettingsResult) JSON.deserialize(
        responseBody,
        AwsSettingsResult.class
      );
    } catch (System.JSONException error) {
      throw new SocioWatchApiException(
        'SocioWatch returned an invalid settings response.'
      );
    }

    if (result == null) {
      throw new SocioWatchApiException(
        'SocioWatch returned an invalid settings response.'
      );
    }

    result.companyId = SocioWatchValidationService.normalizeCompanyId(
      result.companyId
    );

    result.tenantId = SocioWatchValidationService.normalizeTenantId(
      result.tenantId
    );

    if (String.isBlank(result.companyId) || String.isBlank(result.tenantId)) {
      throw new SocioWatchApiException(
        'SocioWatch did not return the required company information.'
      );
    }

    result.message = SocioWatchValidationService.truncateSafeError(
      result.message
    );

    return result;
  }

  public static GoogleReviewsStatusResult parseGoogleReviewsStatus(
    String responseBody
  ) {
    if (String.isBlank(responseBody)) {
      throw new SocioWatchApiException(
        'SocioWatch returned an empty Google Reviews status response.'
      );
    }

    GoogleReviewsStatusResult result;

    try {
      result = (GoogleReviewsStatusResult) JSON.deserialize(
        responseBody,
        GoogleReviewsStatusResult.class
      );
    } catch (System.JSONException error) {
      throw new SocioWatchApiException(
        'SocioWatch returned an invalid Google Reviews status response.'
      );
    }

    if (result == null) {
      throw new SocioWatchApiException(
        'SocioWatch returned an invalid Google Reviews status response.'
      );
    }

    result.companyId = SocioWatchValidationService.normalizeCompanyId(
      result.companyId
    );
    result.googleReviewsResolutionStatus = String.isBlank(
        result.googleReviewsResolutionStatus
      )
      ? 'PENDING'
      : result.googleReviewsResolutionStatus.trim().toUpperCase();
    result.googleReviewsResolutionMessage = SocioWatchValidationService.truncateSafeError(
      result.googleReviewsResolutionMessage
    );

    return result;
  }

  public class AwsSettingsResult {
    public String message { get; set; }
    public Boolean created { get; set; }
    public String tenantId { get; set; }
    public String companyId { get; set; }
    public String companyName { get; set; }
    public String llmMentionKeyword { get; set; }
    public String externalPlatform { get; set; }
    public String externalAccountId { get; set; }
    public String status { get; set; }
    public String googleReviewsResolutionStatus { get; set; }
    public String googleReviewsResolutionMessage { get; set; }
  }

  public class GoogleReviewsStatusResult {
    public String companyId { get; set; }
    public String googleReviewsResolutionStatus { get; set; }
    public String googleReviewsResolutionMessage { get; set; }
  }
}
