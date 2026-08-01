/**
 * Runs SocioWatch synchronization asynchronously.
 */
public with sharing class SocioWatchSyncQueueable
    implements Queueable, Database.AllowsCallouts {

    private Id configurationId;

    public SocioWatchSyncQueueable(Id configurationId) {
        this.configurationId = configurationId;
    }

    public void execute(QueueableContext context) {
        SocioWatchSyncService.runSync(
            configurationId
        );
    }
}
