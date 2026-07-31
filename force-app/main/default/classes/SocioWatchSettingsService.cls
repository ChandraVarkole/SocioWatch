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
            SocioWatchSettingsResponse emptyResponse =
                new SocioWatchSettingsResponse();

            emptyResponse.syncEnabled = true;
            emptyResponse.salesforceOrgId =
                UserInfo.getOrganizationId();

            emptyResponse.lastSyncStatus =
                SocioWatchConstants.SYNC_STATUS_NOT_STARTED;

            return emptyResponse;
        }

        SocioWatch_Configuration__c configuration =
            getAccessibleConfiguration(configurationId);

        return SocioWatchSettingsResponse.fromConfiguration(
            configuration
        );
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

        SocioWatchSettingsRequest normalizedRequest =
            request.normalizedCopy();

        String salesforceOrgId =
            SocioWatchValidationService
                .normalizeSalesforceOrgId(
                    UserInfo.getOrganizationId()
                );

        Id existingConfigurationId =
            findSingletonConfigurationId();

        if (existingConfigurationId != null) {
            // Confirm the current user can access the existing singleton.
            getAccessibleConfiguration(existingConfigurationId);
        }

        String apiRequestBody =
            normalizedRequest.toApiJson(
                salesforceOrgId
            );

        SocioWatchApiResponse apiResponse =
            SocioWatchApiClient.post(
                SocioWatchConstants.SETTINGS_ENDPOINT,
                apiRequestBody
            );

        SocioWatchSettingsResponse.AwsSettingsResult awsResult =
            SocioWatchSettingsResponse.parseAwsResponse(
                apiResponse.responseBody
            );

        SocioWatch_Configuration__c configuration =
            buildConfigurationRecord(
                existingConfigurationId,
                normalizedRequest,
                awsResult,
                salesforceOrgId
            );

        saveConfiguration(
            configuration,
            existingConfigurationId == null
        );

        SocioWatch_Configuration__c savedConfiguration =
            getAccessibleConfiguration(
                configuration.Id
            );

        SocioWatchSettingsResponse response =
            SocioWatchSettingsResponse.fromConfiguration(
                savedConfiguration
            );

        response.created =
            awsResult.created == true;

        response.message =
            String.isBlank(awsResult.message)
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
            ORDER BY CreatedDate ASC
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
    private static SocioWatch_Configuration__c
        getAccessibleConfiguration(
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
                Keywords__c,
                Alert_Id__c,
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
     * Builds the Salesforce record from validated input and the
     * validated AWS response.
     */
    @TestVisible
    private static SocioWatch_Configuration__c
        buildConfigurationRecord(
            Id existingConfigurationId,
            SocioWatchSettingsRequest request,
            SocioWatchSettingsResponse.AwsSettingsResult awsResult,
            String salesforceOrgId
        ) {
        SocioWatch_Configuration__c configuration =
            new SocioWatch_Configuration__c();

        if (existingConfigurationId != null) {
            configuration.Id =
                existingConfigurationId;
        }

        configuration.Company_Name__c =
            request.companyName;

        configuration.Keywords__c =
            SocioWatchValidationService.serializeKeywords(
                request.keywords
            );

        configuration.Alert_Id__c =
            request.alertId;

        configuration.Sync_Enabled__c =
            request.syncEnabled;

        configuration.AWS_Company_Id__c =
            awsResult.companyId;

        configuration.Tenant_Id__c =
            awsResult.tenantId;

        configuration.Salesforce_Org_Id__c =
            salesforceOrgId;

        if (existingConfigurationId == null) {
            configuration.Last_Sync_Status__c =
                SocioWatchConstants.SYNC_STATUS_NOT_STARTED;
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
                Database.SaveResult insertResult =
                    Database.insert(
                        configuration,
                        AccessLevel.USER_MODE
                    );

                if (!insertResult.isSuccess()) {
                    throw buildDmlException(
                        insertResult.getErrors()
                    );
                }

                configuration.Id =
                    insertResult.getId();
            } else {
                Database.SaveResult updateResult =
                    Database.update(
                        configuration,
                        AccessLevel.USER_MODE
                    );

                if (!updateResult.isSuccess()) {
                    throw buildDmlException(
                        updateResult.getErrors()
                    );
                }
            }
        } catch (SocioWatchSettingsException error) {
            throw error;
        } catch (DmlException error) {
            System.debug(
                LoggingLevel.ERROR,
                'SocioWatch configuration DML failed.'
            );

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
        String safeMessage =
            'SocioWatch settings could not be saved.';

        if (errors != null && !errors.isEmpty()) {
            StatusCode statusCode =
                errors[0].getStatusCode();

            if (
                statusCode ==
                    StatusCode.INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY ||
                statusCode ==
                    StatusCode.INSUFFICIENT_ACCESS_OR_READONLY
            ) {
                safeMessage =
                    'You do not have permission to save ' +
                    'SocioWatch settings.';
            } else if (
                statusCode ==
                    StatusCode.DUPLICATE_VALUE ||
                statusCode ==
                    StatusCode.DUPLICATES_DETECTED
            ) {
                safeMessage =
                    'A SocioWatch configuration already exists.';
            } else if (
                statusCode ==
                    StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION
            ) {
                safeMessage =
                    'The SocioWatch configuration did not pass validation.';
            }
        }

        return new SocioWatchSettingsException(
            safeMessage
        );
    }
}
