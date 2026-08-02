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
    public List<String> keywords { get; set; }

    @AuraEnabled
    public String alertId { get; set; }

    @AuraEnabled
    public Boolean syncEnabled { get; set; }

    public SocioWatchSettingsRequest() {
        keywords = new List<String>();
        syncEnabled = true;
    }

    public SocioWatchSettingsRequest normalizedCopy() {
        SocioWatchSettingsRequest normalized =
            new SocioWatchSettingsRequest();

        normalized.companyName =
            SocioWatchValidationService.normalizeCompanyName(
                companyName
            );

        normalized.alertId =
            SocioWatchValidationService.normalizeAlertId(
                alertId
            );

        normalized.keywords =
            SocioWatchValidationService.normalizeKeywords(
                keywords
            );

        normalized.syncEnabled =
            syncEnabled == null
                ? true
                : syncEnabled;

        return normalized;
    }

    public String toApiJson(String salesforceOrgId) {
        SocioWatchSettingsRequest normalized =
            normalizedCopy();

        String normalizedOrgId =
            SocioWatchValidationService.normalizeSalesforceOrgId(
                salesforceOrgId
            );

        Map<String, Object> payload =
            new Map<String, Object>{
                'companyName' => normalized.companyName,
                'externalPlatform' =>
                    SocioWatchConstants.EXTERNAL_PLATFORM_SALESFORCE,
                'externalAccountId' => normalizedOrgId,
                'keywords' => normalized.keywords,
                'alertId' => normalized.alertId,
                'syncEnabled' => normalized.syncEnabled
            };

        return JSON.serialize(payload);
    }
}