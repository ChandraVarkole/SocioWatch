@IsTest
private class SocioWatchSyncSchedulerTest {
  @IsTest
  static void ensureScheduledCreatesOnlyOneMentionsJob() {
    Test.startTest();

    Id firstJobId = SocioWatchSyncScheduler.ensureScheduled();
    Id secondJobId = SocioWatchSyncScheduler.ensureScheduled();

    Test.stopTest();

    System.assertEquals(
      firstJobId,
      secondJobId,
      'Repeated setup must reuse the active SocioWatch job.'
    );

    List<CronTrigger> jobs = [
      SELECT Id, CronExpression, CronJobDetail.Name
      FROM CronTrigger
      WHERE
        CronJobDetail.Name = :SocioWatchSyncScheduler.JOB_NAME
        AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
      WITH SYSTEM_MODE
    ];

    System.assertEquals(1, jobs.size());
    System.assertEquals(
      SocioWatchSyncScheduler.HOURLY_CRON_EXPRESSION,
      jobs[0].CronExpression
    );
  }

  @IsTest
  static void ensureScheduledReplacesLegacyJobName() {
    List<CronTrigger> legacyJobs = [
      SELECT Id
      FROM CronTrigger
      WHERE
        CronJobDetail.Name = :SocioWatchSyncScheduler.LEGACY_JOB_NAME
        AND State IN (
          'WAITING',
          'ACQUIRED',
          'EXECUTING',
          'PAUSED',
          'BLOCKED',
          'PAUSED_BLOCKED'
        )
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    Id legacyJobId = legacyJobs.isEmpty()
      ? System.schedule(
          SocioWatchSyncScheduler.LEGACY_JOB_NAME,
          '0 0 0 1 1 ? 2099',
          new SocioWatchSyncScheduler()
        )
      : legacyJobs[0].Id;

    Test.startTest();

    Id currentJobId = SocioWatchSyncScheduler.ensureScheduled();

    Test.stopTest();

    System.assertNotEquals(legacyJobId, currentJobId);

    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM CronTrigger
        WHERE
          Id = :legacyJobId
          AND State IN (
            'WAITING',
            'ACQUIRED',
            'EXECUTING',
            'PAUSED',
            'BLOCKED',
            'PAUSED_BLOCKED'
          )
        WITH SYSTEM_MODE
      ],
      'The legacy-named job must no longer be active.'
    );

    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM CronTrigger
        WHERE
          CronJobDetail.Name = :SocioWatchSyncScheduler.JOB_NAME
          AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
        WITH SYSTEM_MODE
      ]
    );
  }

  @IsTest
  static void schedulerEnqueuesSync() {
    insert new SocioWatch_Configuration__c(
      Company_Name__c = 'Tesla',
      Keywords__c = 'Tesla',
      Alert_Id__c = 'alert_12345',
      Sync_Enabled__c = true,
      AWS_Company_Id__c = 'COMP-000001',
      Tenant_Id__c = 'TENANT-000001',
      Salesforce_Org_Id__c = UserInfo.getOrganizationId(),
      Last_Sync_Status__c = 'Not Started'
    );

    Test.setMock(HttpCalloutMock.class, new SchedulerHttpMock());

    Test.startTest();

    String jobId = System.schedule(
      'SocioWatch Scheduler Test',
      '0 0 0 1 1 ? 2099',
      new SocioWatchSyncScheduler()
    );

    Test.stopTest();

    System.assertNotEquals(null, jobId);
  }

  private class SchedulerHttpMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setHeader('Content-Type', 'application/json');

      if (request.getEndpoint().endsWith('/v1/sync')) {
        response.setBody(
          '{"message":"Synchronization completed successfully."}'
        );
      } else {
        response.setBody(
          '{"companyId":"COMP-000001",' + '"count":0,"mentions":[]}'
        );
      }

      return response;
    }
  }
}
