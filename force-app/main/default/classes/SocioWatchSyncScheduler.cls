/**
 * Schedules SocioWatch synchronization.
 *
 * The scheduled class does not perform callouts directly.
 * It enqueues SocioWatchSyncQueueable, which supports callouts.
 */
public with sharing class SocioWatchSyncScheduler
    implements Schedulable {

    public void execute(SchedulableContext context) {
        List<SocioWatch_Configuration__c> configurations = [
            SELECT Id, Sync_Enabled__c, AWS_Company_Id__c
            FROM SocioWatch_Configuration__c
            WHERE Sync_Enabled__c = true
            WITH USER_MODE
            ORDER BY CreatedDate ASC
            LIMIT 2
        ];

        if (
            configurations.size() != 1 ||
            String.isBlank(
                configurations[0].AWS_Company_Id__c
            )
        ) {
            return;
        }

        System.enqueueJob(
            new SocioWatchSyncQueueable(
                configurations[0].Id
            )
        );
    }
}
