/**
 * Request received from the SocioWatch Settings LWC.
 *
 * This object contains no credentials or secrets.
 * All values must be validated again in Apex before use.
 */
public class SocioWatchSettingsRequest {
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
  public Boolean autoLinkMentions { get; set; }

  @AuraEnabled
  public String authorMatchObjectApiName { get; set; }

  @AuraEnabled
  public String authorMatchFieldApiName { get; set; }

  @AuraEnabled
  public List<String> keywords { get; set; }

  @AuraEnabled
  public Boolean syncEnabled { get; set; }

  public SocioWatchSettingsRequest() {
    keywords = new List<String>();
    syncEnabled = true;
    googleReviewsEnabled = true;
    autoLinkMentions = false;
  }

  public SocioWatchSettingsRequest normalizedCopy() {
    SocioWatchSettingsRequest normalized = new SocioWatchSettingsRequest();

    normalized.companyName = SocioWatchValidationService.normalizeCompanyName(
      companyName
    );

    normalized.website = normalizeWebsite(website);

    normalized.llmMentionKeyword = normalizeLlmMentionKeyword(
      llmMentionKeyword,
      normalized.companyName
    );

    normalized.companyCity = normalizeLocationValue(
      companyCity,
      'Company city'
    );

    normalized.companyStateProvince = normalizeLocationValue(
      companyStateProvince,
      'Company state or province'
    );

    normalized.companyCountry = normalizeLocationValue(
      companyCountry,
      'Company country'
    );

    Boolean hasAnyLocationValue =
      String.isNotBlank(normalized.companyCity) ||
      String.isNotBlank(normalized.companyStateProvince) ||
      String.isNotBlank(normalized.companyCountry);

    Boolean hasCompleteLocation =
      String.isNotBlank(normalized.companyCity) &&
      String.isNotBlank(normalized.companyStateProvince) &&
      String.isNotBlank(normalized.companyCountry);

    if (hasAnyLocationValue && !hasCompleteLocation) {
      throw new SocioWatchValidationException(
        'Company city, state or province, and country must all be provided.'
      );
    }

    normalized.keywords = SocioWatchValidationService.normalizeKeywords(
      keywords
    );

    normalized.syncEnabled = syncEnabled == null ? true : syncEnabled;

    normalized.googleReviewsEnabled = googleReviewsEnabled == null
      ? true
      : googleReviewsEnabled;

    normalized.autoLinkMentions = autoLinkMentions == true;

    normalized.authorMatchObjectApiName = normalizeSalesforceApiName(
      authorMatchObjectApiName,
      'Author match object'
    );

    normalized.authorMatchFieldApiName = normalizeSalesforceApiName(
      authorMatchFieldApiName,
      'Author match field'
    );

    return normalized;
  }

  public String toApiJson(String salesforceOrgId) {
    SocioWatchSettingsRequest normalized = normalizedCopy();

    String normalizedOrgId = SocioWatchValidationService.normalizeSalesforceOrgId(
      salesforceOrgId
    );

    Map<String, Object> payload = new Map<String, Object>{
      'companyName' => normalized.companyName,
      'llmMentionKeyword' => normalized.llmMentionKeyword,
      'website' => normalized.website,
      'externalPlatform' => SocioWatchConstants.EXTERNAL_PLATFORM_SALESFORCE,
      'externalAccountId' => normalizedOrgId,
      'keywords' => normalized.keywords,
      'syncEnabled' => normalized.syncEnabled,
      'googleReviewsEnabled' => normalized.googleReviewsEnabled,
      'googleReviewLocations' => buildGoogleReviewLocations(normalized)
    };

    return JSON.serialize(payload);
  }

  private static List<Object> buildGoogleReviewLocations(
    SocioWatchSettingsRequest normalized
  ) {
    List<Object> locations = new List<Object>();

    if (
      String.isBlank(normalized.companyCity) &&
      String.isBlank(normalized.companyStateProvince) &&
      String.isBlank(normalized.companyCountry)
    ) {
      return locations;
    }

    locations.add(
      new Map<String, Object>{
        'city' => normalized.companyCity,
        'state' => normalized.companyStateProvince,
        'country' => normalized.companyCountry
      }
    );

    return locations;
  }

  private static String normalizeLlmMentionKeyword(
    String value,
    String companyName
  ) {
    String normalized = String.isBlank(value)
      ? companyName
      : value.trim().replaceAll('\\s+', ' ');

    if (String.isBlank(normalized)) {
      throw new SocioWatchValidationException(
        'Enter one keyword to track in LLM answers such as ChatGPT.'
      );
    }

    if (normalized.length() > 250) {
      throw new SocioWatchValidationException(
        'LLM mention keyword cannot exceed 250 characters.'
      );
    }

    return normalized;
  }

  @TestVisible
  private static String normalizeLocationValue(String value, String label) {
    if (String.isBlank(value)) {
      return null;
    }

    String normalized = value.trim().replaceAll('\\s+', ' ');

    if (normalized.length() > 100) {
      throw new SocioWatchValidationException(
        label + ' cannot exceed 100 characters.'
      );
    }

    return normalized;
  }

  private static String normalizeSalesforceApiName(String value, String label) {
    if (String.isBlank(value)) {
      return null;
    }

    String normalized = value.trim();

    if (
      normalized.length() > 255 ||
      !Pattern.matches('^[A-Za-z][A-Za-z0-9_]*$', normalized)
    ) {
      throw new SocioWatchValidationException(
        label + ' is not a valid API name.'
      );
    }

    return normalized;
  }

  /**
   * Website is optional at the DTO level for backward compatibility
   * with existing configurations, but when supplied it must be a safe
   * absolute HTTP/HTTPS URL. The Settings LWC requires it for new saves.
   */
  @TestVisible
  private static String normalizeWebsite(String value) {
    if (String.isBlank(value)) {
      return null;
    }

    String normalized = value.trim();

    if (normalized.length() > 255) {
      throw new SocioWatchValidationException(
        'Company website must contain no more than 255 characters.'
      );
    }

    if (!Pattern.matches('(?i)^https?://[^\\s]+$', normalized)) {
      throw new SocioWatchValidationException(
        'Enter a valid company website URL including http:// or https://.'
      );
    }

    return normalized;
  }
}
