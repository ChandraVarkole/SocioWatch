/**
 * Coordinates Salesforce with the AWS-hosted Meta connection service.
 * Salesforce never receives or stores a Meta access token.
 */
public with sharing class SocioWatchMetaService {
  private static final Set<String> MONITORING_MODES = new Set<String>{
    'FACEBOOK',
    'FACEBOOK_AND_INSTAGRAM'
  };

  private SocioWatchMetaService() {
  }

  public static SocioWatchMetaConnectionResponse getConnection() {
    return sendRequest(
      SocioWatchConstants.META_STATUS_ENDPOINT,
      new Map<String, Object>()
    );
  }

  public static SocioWatchMetaConnectionResponse startConnection(
    String monitoringMode,
    String returnOrigin
  ) {
    String normalizedMode = normalizeMonitoringMode(monitoringMode);
    String normalizedOrigin = normalizeSalesforceOrigin(returnOrigin);
    return sendRequest(
      SocioWatchConstants.META_CONNECT_ENDPOINT,
      new Map<String, Object>{
        'monitoringMode' => normalizedMode,
        'returnOrigin' => normalizedOrigin,
        'acknowledgementVersion' => SocioWatchConstants.META_ACKNOWLEDGEMENT_VERSION
      }
    );
  }

  public static SocioWatchMetaConnectionResponse saveSelection(
    List<String> facebookPageIds
  ) {
    List<String> normalizedPageIds = normalizePageIds(facebookPageIds);
    return sendRequest(
      SocioWatchConstants.META_SELECT_ENDPOINT,
      new Map<String, Object>{
        'facebookPageIds' => normalizedPageIds,
        'acknowledgementVersion' => SocioWatchConstants.META_ACKNOWLEDGEMENT_VERSION
      }
    );
  }

  public static SocioWatchMetaConnectionResponse disconnect() {
    return sendRequest(
      SocioWatchConstants.META_DISCONNECT_ENDPOINT,
      new Map<String, Object>()
    );
  }

  private static SocioWatchMetaConnectionResponse sendRequest(
    String endpoint,
    Map<String, Object> requestValues
  ) {
    SocioWatchPermissionService.requireManageSettings();
    SocioWatch_Configuration__c configuration = getConfiguration();

    requestValues.put('companyId', configuration.AWS_Company_Id__c);
    requestValues.put('externalAccountId', UserInfo.getOrganizationId());

    SocioWatchApiResponse response = SocioWatchApiClient.post(
      endpoint,
      JSON.serialize(requestValues)
    );
    return SocioWatchMetaConnectionResponse.parse(response.responseBody);
  }

  private static SocioWatch_Configuration__c getConfiguration() {
    List<SocioWatch_Configuration__c> configurations = [
      SELECT Id, AWS_Company_Id__c
      FROM SocioWatch_Configuration__c
      WITH USER_MODE
      ORDER BY CreatedDate ASC
      LIMIT 2
    ];

    if (
      configurations.size() != 1 ||
      String.isBlank(configurations[0].AWS_Company_Id__c)
    ) {
      throw new SocioWatchValidationException(
        'Save the SocioWatch settings before connecting Facebook or Instagram.'
      );
    }
    return configurations[0];
  }

  private static String normalizeMonitoringMode(String monitoringMode) {
    String normalized = String.isBlank(monitoringMode)
      ? ''
      : monitoringMode.trim().toUpperCase();
    if (!MONITORING_MODES.contains(normalized)) {
      throw new SocioWatchValidationException(
        'Choose Facebook only or Facebook and Instagram.'
      );
    }
    return normalized;
  }

  private static String normalizeSalesforceOrigin(String returnOrigin) {
    String normalized = String.isBlank(returnOrigin)
      ? ''
      : returnOrigin.trim().toLowerCase();
    if (
      !Pattern.matches(
        '^https://[a-z0-9.-]+(\\.lightning\\.force\\.com|\\.my\\.salesforce\\.com|\\.salesforce\\.com)$',
        normalized
      )
    ) {
      throw new SocioWatchValidationException(
        'Salesforce could not open the secure Meta connection.'
      );
    }
    return normalized;
  }

  private static List<String> normalizePageIds(List<String> pageIds) {
    if (pageIds == null || pageIds.isEmpty() || pageIds.size() > 250) {
      throw new SocioWatchValidationException(
        'Select at least one Facebook Page.'
      );
    }

    List<String> normalized = new List<String>();
    Set<String> uniqueIds = new Set<String>();
    for (String pageId : pageIds) {
      String value = String.isBlank(pageId) ? '' : pageId.trim();
      if (!Pattern.matches('^[A-Za-z0-9_-]{1,128}$', value)) {
        throw new SocioWatchValidationException(
          'Select a valid Facebook Page.'
        );
      }
      if (!uniqueIds.add(value)) {
        throw new SocioWatchValidationException(
          'The Facebook Page selection contains duplicates.'
        );
      }
      normalized.add(value);
    }
    return normalized;
  }
}
