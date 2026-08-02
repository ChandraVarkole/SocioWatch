/**
 * LWC entry point for manual synchronization.
 */
public with sharing class SocioWatchSyncController {

    private SocioWatchSyncController() {
    }

    @AuraEnabled
    public static Id startSync() {
        try {
            SocioWatchPermissionService.requireRunSync();

            List<SocioWatch_Configuration__c> configurations = [
                SELECT Id, Sync_Enabled__c, AWS_Company_Id__c
                FROM SocioWatch_Configuration__c
                WITH USER_MODE
                ORDER BY CreatedDate ASC
                LIMIT 2
            ];

            if (configurations.isEmpty()) {
                throw new SocioWatchValidationException(
                    'Save the SocioWatch settings before running a sync.'
                );
            }

            if (configurations.size() > 1) {
                throw new SocioWatchValidationException(
                    'Multiple SocioWatch configurations were found.'
                );
            }

            SocioWatch_Configuration__c configuration =
                configurations[0];

            if (!configuration.Sync_Enabled__c) {
                throw new SocioWatchValidationException(
                    'Synchronization is disabled.'
                );
            }

            if (String.isBlank(configuration.AWS_Company_Id__c)) {
                throw new SocioWatchValidationException(
                    'Save the SocioWatch settings before running a sync.'
                );
            }

            return System.enqueueJob(
                new SocioWatchSyncQueueable(configuration.Id)
            );

        } catch (SocioWatchAccessException error) {
            throw createHandledException(error.getMessage());

        } catch (SocioWatchValidationException error) {
            throw createHandledException(error.getMessage());

        } catch (Exception error) {
            throw createHandledException(
                Label.SocioWatch_Unexpected_Error
            );
        }
    }

    private static AuraHandledException createHandledException(
        String message
    ) {
        AuraHandledException handledError =
            new AuraHandledException(message);

        handledError.setMessage(message);

        return handledError;
    }
}