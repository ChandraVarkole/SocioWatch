/**
 * Imports SocioWatch mentions already available in AWS.
 *
 * This queueable intentionally does not trigger AWS collectors.
 */
public with sharing class SocioWatchImportQueueable implements Queueable, Database.AllowsCallouts {
  private Id configurationId;

  public SocioWatchImportQueueable(Id configurationId) {
    this.configurationId = configurationId;
  }

  public void execute(QueueableContext context) {
    SocioWatchSyncService.runImport(configurationId);
  }
}
