/**
 * Service layer for the SocioWatch singleton configuration.
 *
 * Security controls:
 * - Requires the Manage SocioWatch Settings custom permission.
 * - Uses explicit sharing.
 * - Uses user-mode queries and DML for subscriber data access.
 * - Performs the AWS callout before DML.
 * - Does not store credentials or raw AWS responses.
 * - Returns only sanitized application errors.
 */
public with sharing class SocioWatchSettingsService {
  private SocioWatchSettingsService() {
  }

  /**
   * Retrieves the configuration visible to the current user.
   */
  public static SocioWatchSettingsResponse getSettings() {
    SocioWatchPermissionService.requireManageSettings();

    Id configurationId = findSingletonConfigurationId();

    if (configurationId == null) {
      SocioWatchSettingsResponse emptyResponse = new SocioWatchSettingsResponse();

      emptyResponse.syncEnabled = true;
      emptyResponse.salesforceOrgId = UserInfo.getOrganizationId();

      emptyResponse.lastSyncStatus = SocioWatchConstants.SYNC_STATUS_NOT_STARTED;

      return emptyResponse;
    }

    SocioWatch_Configuration__c configuration = getAccessibleConfiguration(
      configurationId
    );

    return SocioWatchSettingsResponse.fromConfiguration(configuration);
  }

  public static SocioWatchSettingsResponse getGoogleReviewsStatus(
    String companyId
  ) {
    SocioWatchPermissionService.requireManageSettings();

    String normalizedCompanyId = SocioWatchValidationService.normalizeCompanyId(
      companyId
    );

    if (String.isBlank(normalizedCompanyId)) {
      throw new SocioWatchValidationException(
        'A valid SocioWatch company is required.'
      );
    }

    String requestBody = JSON.serialize(
      new Map<String, Object>{
        'companyId' => normalizedCompanyId,
        'externalAccountId' => UserInfo.getOrganizationId()
      }
    );

    SocioWatchApiResponse apiResponse = SocioWatchApiClient.post(
      SocioWatchConstants.GOOGLE_REVIEWS_STATUS_ENDPOINT,
      requestBody
    );
    SocioWatchSettingsResponse.GoogleReviewsStatusResult awsStatus = SocioWatchSettingsResponse.parseGoogleReviewsStatus(
      apiResponse.responseBody
    );

    if (awsStatus.companyId != normalizedCompanyId) {
      throw new SocioWatchApiException(
        'SocioWatch returned Google Reviews status for a different company.'
      );
    }

    SocioWatchSettingsResponse response = new SocioWatchSettingsResponse();
    response.companyId = normalizedCompanyId;
    response.googleReviewsResolutionStatus = awsStatus.googleReviewsResolutionStatus;
    response.googleReviewsResolutionMessage = awsStatus.googleReviewsResolutionMessage;
    return response;
  }

  /**
   * Validates settings, registers them with AWS, and then saves
   * the Salesforce singleton configuration.
   *
   * The callout occurs before DML to prevent an uncommitted-work
   * callout exception.
   */
  public static SocioWatchSettingsResponse saveSettings(
    SocioWatchSettingsRequest request
  ) {
    SocioWatchPermissionService.requireManageSettings();

    if (request == null) {
      throw new SocioWatchValidationException(
        'SocioWatch settings are required.'
      );
    }

    SocioWatchSettingsRequest normalizedRequest = request.normalizedCopy();

    SocioWatchMentionLinkService.validateConfiguration(normalizedRequest);

    String salesforceOrgId = SocioWatchValidationService.normalizeSalesforceOrgId(
      UserInfo.getOrganizationId()
    );

    Id existingConfigurationId = findSingletonConfigurationId();

    SocioWatch_Configuration__c existingConfiguration;

    if (existingConfigurationId != null) {
      // Confirm the current user can access the existing singleton
      // and preserve the permanent SocioWatch company mapping.
      existingConfiguration = getAccessibleConfiguration(
        existingConfigurationId
      );
    }

    String apiRequestBody = normalizedRequest.toApiJson(salesforceOrgId);

    SocioWatchApiResponse apiResponse = SocioWatchApiClient.post(
      SocioWatchConstants.SETTINGS_ENDPOINT,
      apiRequestBody
    );

    SocioWatchSettingsResponse.AwsSettingsResult awsResult = SocioWatchSettingsResponse.parseAwsResponse(
      apiResponse.responseBody
    );

    validateStableCompanyMapping(existingConfiguration, awsResult);

    SocioWatch_Configuration__c configuration = buildConfigurationRecord(
      existingConfiguration,
      normalizedRequest,
      awsResult,
      salesforceOrgId
    );

    saveConfiguration(configuration, existingConfiguration == null);

    if (normalizedRequest.syncEnabled == true) {
      SocioWatchSyncScheduler.ensureScheduled();
    }

    SocioWatch_Configuration__c savedConfiguration = getAccessibleConfiguration(
      configuration.Id
    );

    SocioWatchSettingsResponse response = SocioWatchSettingsResponse.fromConfiguration(
      savedConfiguration
    );

    response.created = awsResult.created == true;

    response.googleReviewsResolutionStatus = awsResult.googleReviewsResolutionStatus;
    response.googleReviewsResolutionMessage = awsResult.googleReviewsResolutionMessage;

    response.message = String.isBlank(awsResult.message)
      ? Label.SocioWatch_Save_Success
      : awsResult.message;

    return response;
  }

  /**
   * Locates the one configuration record across the organization.
   *
   * This system-mode query is used only to enforce the global singleton.
   * It returns only record IDs and does not expose field data.
   *
   * The record is queried again in user mode before any data is read.
   */
  @TestVisible
  private static Id findSingletonConfigurationId() {
    List<SocioWatch_Configuration__c> configurations = [
      SELECT Id
      FROM SocioWatch_Configuration__c
      WITH SYSTEM_MODE
      LIMIT 2
    ];

    if (configurations.isEmpty()) {
      return null;
    }

    if (configurations.size() > 1) {
      throw new SocioWatchSettingsException(
        'Multiple SocioWatch configurations were found. ' +
        'Contact your Salesforce administrator.'
      );
    }

    return configurations[0].Id;
  }

  /**
   * Retrieves the singleton using current-user object, field,
   * sharing, and record permissions.
   */
  @TestVisible
  private static SocioWatch_Configuration__c getAccessibleConfiguration(
    Id configurationId
  ) {
    if (configurationId == null) {
      return null;
    }

    List<SocioWatch_Configuration__c> configurations = [
      SELECT
        Id,
        Name,
        Company_Name__c,
        LLM_Mention_Keyword__c,
        Website__c,
        Company_City__c,
        Company_State_Province__c,
        Company_Country__c,
        Google_Reviews_Enabled__c,
        Auto_Link_Mentions__c,
        Author_Match_Object__c,
        Author_Match_Field__c,
        Keywords__c,
        Sync_Enabled__c,
        AWS_Company_Id__c,
        Tenant_Id__c,
        Salesforce_Org_Id__c,
        Last_Successful_Sync__c,
        Last_Sync_Status__c
      FROM SocioWatch_Configuration__c
      WHERE Id = :configurationId
      WITH USER_MODE
      LIMIT 1
    ];

    if (configurations.isEmpty()) {
      throw new SocioWatchAccessException(
        'You do not have access to the SocioWatch configuration.'
      );
    }

    return configurations[0];
  }

  /**
   * Prevents an existing Salesforce org from being remapped to a
   * different SocioWatch company or tenant during a settings save.
   */
  @TestVisible
  private static void validateStableCompanyMapping(
    SocioWatch_Configuration__c existingConfiguration,
    SocioWatchSettingsResponse.AwsSettingsResult awsResult
  ) {
    if (existingConfiguration == null) {
      return;
    }

    if (
      String.isNotBlank(existingConfiguration.AWS_Company_Id__c) &&
      existingConfiguration.AWS_Company_Id__c != awsResult.companyId
    ) {
      throw new SocioWatchSettingsException(
        'The SocioWatch company mapping does not match ' +
          'the existing Salesforce configuration. ' +
          'Contact SocioWatch support.'
      );
    }

    if (
      String.isNotBlank(existingConfiguration.Tenant_Id__c) &&
      existingConfiguration.Tenant_Id__c != awsResult.tenantId
    ) {
      throw new SocioWatchSettingsException(
        'The SocioWatch tenant mapping does not match ' +
          'the existing Salesforce configuration. ' +
          'Contact SocioWatch support.'
      );
    }
  }

  /**
   * Builds the Salesforce record from validated input and the
   * validated AWS response.
   */
  @TestVisible
  private static SocioWatch_Configuration__c buildConfigurationRecord(
    SocioWatch_Configuration__c existingConfiguration,
    SocioWatchSettingsRequest request,
    SocioWatchSettingsResponse.AwsSettingsResult awsResult,
    String salesforceOrgId
  ) {
    SocioWatch_Configuration__c configuration = new SocioWatch_Configuration__c();

    if (existingConfiguration != null) {
      configuration.Id = existingConfiguration.Id;
    }

    configuration.Company_Name__c = request.companyName;

    configuration.LLM_Mention_Keyword__c = request.llmMentionKeyword;

    configuration.Website__c = request.website;

    configuration.Company_City__c = request.companyCity;

    configuration.Company_State_Province__c = request.companyStateProvince;

    configuration.Company_Country__c = request.companyCountry;

    configuration.Google_Reviews_Enabled__c = request.googleReviewsEnabled;

    configuration.Auto_Link_Mentions__c = request.autoLinkMentions;

    configuration.Author_Match_Object__c = request.authorMatchObjectApiName;

    configuration.Author_Match_Field__c = request.authorMatchFieldApiName;

    configuration.Keywords__c = SocioWatchValidationService.serializeKeywords(
      request.keywords
    );

    configuration.Sync_Enabled__c = request.syncEnabled;

    configuration.AWS_Company_Id__c = existingConfiguration != null &&
      String.isNotBlank(existingConfiguration.AWS_Company_Id__c)
      ? existingConfiguration.AWS_Company_Id__c
      : awsResult.companyId;

    configuration.Tenant_Id__c = existingConfiguration != null &&
      String.isNotBlank(existingConfiguration.Tenant_Id__c)
      ? existingConfiguration.Tenant_Id__c
      : awsResult.tenantId;

    configuration.Salesforce_Org_Id__c = salesforceOrgId;

    if (existingConfiguration == null) {
      configuration.Last_Sync_Status__c = SocioWatchConstants.SYNC_STATUS_NOT_STARTED;
    }

    return configuration;
  }

  /**
   * Saves the configuration in user mode.
   */
  @TestVisible
  private static void saveConfiguration(
    SocioWatch_Configuration__c configuration,
    Boolean isNew
  ) {
    try {
      if (isNew) {
        Database.SaveResult insertResult = Database.insert(
          configuration,
          AccessLevel.USER_MODE
        );

        if (!insertResult.isSuccess()) {
          throw buildDmlException(insertResult.getErrors());
        }

        configuration.Id = insertResult.getId();
      } else {
        Database.SaveResult updateResult = Database.update(
          configuration,
          AccessLevel.USER_MODE
        );

        if (!updateResult.isSuccess()) {
          throw buildDmlException(updateResult.getErrors());
        }
      }
    } catch (SocioWatchSettingsException error) {
      throw error;
    } catch (DmlException error) {
      System.debug(LoggingLevel.ERROR, 'SocioWatch configuration DML failed.');

      throw new SocioWatchSettingsException(
        'SocioWatch settings could not be saved. ' +
        'Verify your object and field permissions.'
      );
    }
  }

  /**
   * Converts DML errors into a safe package exception.
   */
  @TestVisible
  private static SocioWatchSettingsException buildDmlException(
    Database.Error[] errors
  ) {
    String safeMessage = 'SocioWatch settings could not be saved.';

    if (errors != null && !errors.isEmpty()) {
      StatusCode dmlStatusCode = errors[0].getStatusCode();

      if (
        dmlStatusCode ==
        StatusCode.INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY ||
        dmlStatusCode == StatusCode.INSUFFICIENT_ACCESS_OR_READONLY
      ) {
        safeMessage = 'You do not have permission to save SocioWatch settings.';
      } else if (
        dmlStatusCode == StatusCode.DUPLICATE_VALUE ||
        dmlStatusCode == StatusCode.DUPLICATES_DETECTED
      ) {
        safeMessage = 'A SocioWatch configuration already exists.';
      } else if (
        dmlStatusCode == StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION
      ) {
        safeMessage = 'The SocioWatch configuration did not pass validation.';
      }
    }

    return new SocioWatchSettingsException(safeMessage);
  }
}
