/**
 * Runs the SocioWatch Salesforce import every hour.
 *
 * AWS collectors have their own schedules. This scheduler only
 * pulls mentions already available in AWS and upserts them into
 * Salesforce.
 */
public with sharing class SocioWatchSyncScheduler implements Schedulable {
  @TestVisible
  private static final String JOB_NAME = 'SocioWatch Mentions Job';

  @TestVisible
  private static final String LEGACY_JOB_NAME = 'SocioWatch Hourly Mention Import';

  @TestVisible
  private static final String HOURLY_CRON_EXPRESSION = '0 0 * * * ?';

  private static final Set<String> ACTIVE_STATES = new Set<String>{
    'WAITING',
    'ACQUIRED',
    'EXECUTING',
    'PAUSED',
    'BLOCKED',
    'PAUSED_BLOCKED'
  };

  private static final Set<String> HEALTHY_STATES = new Set<String>{
    'WAITING',
    'ACQUIRED',
    'EXECUTING'
  };

  /**
   * Ensures that exactly one current SocioWatch hourly import job exists.
   *
   * Saving enabled Settings calls this method, so subscriber administrators
   * do not need to run Execute Anonymous. A legacy-named job is replaced with
   * the current, customer-friendly name.
   */
  public static Id ensureScheduled() {
    Set<String> supportedJobNames = new Set<String>{
      JOB_NAME,
      LEGACY_JOB_NAME
    };

    // CronTrigger and CronJobDetail are Salesforce setup objects. This query
    // reads only SocioWatch job metadata and no subscriber business data.
    List<CronTrigger> scheduledJobs = [
      SELECT Id, State, CronExpression, CronJobDetail.Name
      FROM CronTrigger
      WHERE CronJobDetail.Name IN :supportedJobNames AND State IN :ACTIVE_STATES
      WITH SYSTEM_MODE
    ];

    CronTrigger healthyCurrentJob;
    List<CronTrigger> jobsToReplace = new List<CronTrigger>();

    for (CronTrigger scheduledJob : scheduledJobs) {
      Boolean isHealthyCurrentJob =
        scheduledJob.CronJobDetail.Name == JOB_NAME &&
        HEALTHY_STATES.contains(scheduledJob.State) &&
        scheduledJob.CronExpression == HOURLY_CRON_EXPRESSION;

      if (isHealthyCurrentJob && healthyCurrentJob == null) {
        healthyCurrentJob = scheduledJob;
      } else {
        jobsToReplace.add(scheduledJob);
      }
    }

    try {
      for (CronTrigger jobToReplace : jobsToReplace) {
        System.abortJob(jobToReplace.Id);
      }

      if (healthyCurrentJob != null) {
        return healthyCurrentJob.Id;
      }

      return System.schedule(
        JOB_NAME,
        HOURLY_CRON_EXPRESSION,
        new SocioWatchSyncScheduler()
      );
    } catch (AsyncException error) {
      System.debug(
        LoggingLevel.ERROR,
        'SocioWatch hourly job scheduling failed.'
      );

      throw new SocioWatchSettingsException(
        'SocioWatch could not schedule the hourly mentions job. ' +
        'Contact your Salesforce administrator.'
      );
    }
  }

  public void execute(SchedulableContext context) {
    List<SocioWatch_Configuration__c> configurations = [
      SELECT Id, Sync_Enabled__c, AWS_Company_Id__c
      FROM SocioWatch_Configuration__c
      WHERE Sync_Enabled__c = TRUE
      WITH USER_MODE
      ORDER BY CreatedDate ASC
      LIMIT 2
    ];

    if (
      configurations.size() != 1 ||
      String.isBlank(configurations[0].AWS_Company_Id__c)
    ) {
      return;
    }

    System.enqueueJob(new SocioWatchImportQueueable(configurations[0].Id));
  }
}
