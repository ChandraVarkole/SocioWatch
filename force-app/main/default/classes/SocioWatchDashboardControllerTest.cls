@IsTest
private class SocioWatchDashboardControllerTest {
  private static final String COMPANY_ID = 'COMP-000001';
  private static final String DASHBOARD_USER_ALIAS = 'swdash';

  @TestSetup
  static void createPermissionedUser() {
    SocioWatchTestUserFactory.createUserWithPermissionSet(
      DASHBOARD_USER_ALIAS,
      'SocioWatch_Admin'
    );
  }

  private static void createMentions() {
    SocioWatch_Configuration__c configuration = new SocioWatch_Configuration__c(
      Company_Name__c = 'Dashboard Test',
      Keywords__c = 'Dashboard Test',
      AWS_Company_Id__c = COMPANY_ID
    );
    insert configuration;

    Datetime nowValue = System.now();
    insert new List<SocioWatch_Mention__c>{
      buildMention(
        configuration.Id,
        'X-1',
        'X',
        'Negative',
        'Critical',
        'New',
        nowValue
      ),
      buildMention(
        configuration.Id,
        'YT-1',
        'YouTube',
        'Positive',
        'Low',
        'Resolved',
        nowValue.addDays(-1)
      ),
      buildMention(
        configuration.Id,
        'NEWS-1',
        'News',
        'Neutral',
        'High',
        'Reviewing',
        nowValue.addDays(-2)
      ),
      buildMention(
        configuration.Id,
        'OLD-1',
        'Forum',
        'Mixed',
        'Medium',
        'Responded',
        nowValue.addDays(-45)
      )
    };

    SocioWatch_Mention__c irrelevantMention = buildMention(
      configuration.Id,
      'IRRELEVANT-1',
      'News',
      'Negative',
      'Critical',
      'New',
      nowValue
    );
    irrelevantMention.Is_Relevant__c = false;
    insert irrelevantMention;
  }

  @IsTest
  static void returnsManagementSummaryForSelectedPeriod() {
    System.runAs(SocioWatchTestUserFactory.getUser(DASHBOARD_USER_ALIAS)) {
      createMentions();
      setTrialMock('TRIAL', 7);

      Test.startTest();
      SocioWatchDashboardController.DashboardData data = SocioWatchDashboardController.getDashboard(
        30
      );
      Test.stopTest();

      System.assertEquals(3, data.totalMentions);
      System.assertEquals(1, data.newMentions);
      System.assertEquals(2, data.attentionMentions);
      System.assertEquals(1, data.negativeMentions);
      System.assertEquals(true, data.showTrialBanner);
      System.assertEquals(7, data.trialDaysRemaining);
      System.assertEquals(3, data.recentMentions.size());
      System.assertEquals(14, data.dailyTrend.size());
      Set<String> sourceLabels = new Set<String>();
      for (SocioWatchDashboardController.BreakdownItem source : data.sources) {
        sourceLabels.add(source.label);
      }
      System.assertEquals(
        new Set<String>{ 'X', 'YouTube', 'News' },
        sourceLabels
      );
    }
  }

  @IsTest
  static void hidesTrialBannerForFullLicense() {
    System.runAs(SocioWatchTestUserFactory.getUser(DASHBOARD_USER_ALIAS)) {
      createMentions();
      SocioWatch_Configuration__c configuration = [
        SELECT Id, Full_License__c
        FROM SocioWatch_Configuration__c
        LIMIT 1
      ];
      configuration.Full_License__c = true;
      update configuration;

      Test.startTest();
      SocioWatchDashboardController.DashboardData data = SocioWatchDashboardController.getDashboard(
        30
      );
      Test.stopTest();

      System.assertEquals(false, data.showTrialBanner);
      System.assertEquals(0, data.trialDaysRemaining);
    }
  }

  @IsTest
  static void supportsAllTimeAndDefaultsInvalidPeriods() {
    System.runAs(SocioWatchTestUserFactory.getUser(DASHBOARD_USER_ALIAS)) {
      createMentions();
      setTrialMock('TRIAL', 7);

      SocioWatchDashboardController.DashboardData allTime = SocioWatchDashboardController.getDashboard(
        0
      );
      SocioWatchDashboardController.DashboardData defaultPeriod = SocioWatchDashboardController.getDashboard(
        12
      );

      System.assertEquals(4, allTime.totalMentions);
      System.assertEquals(0, allTime.periodDays);
      System.assertEquals(30, defaultPeriod.periodDays);
    }
  }

  @IsTest
  static void hidesTrialBeforeConfigurationExists() {
    System.runAs(SocioWatchTestUserFactory.getUser(DASHBOARD_USER_ALIAS)) {
      createMentions();
      delete [SELECT Id FROM SocioWatch_Mention__c];
      delete [SELECT Id FROM SocioWatch_Configuration__c];

      Test.startTest();
      SocioWatchDashboardController.DashboardData data = SocioWatchDashboardController.getDashboard(
        30
      );
      Test.stopTest();

      System.assertEquals(false, data.showTrialBanner);
      System.assertEquals(0, data.trialDaysRemaining);
    }
  }

  @IsTest
  static void displaysAwsTrialExtension() {
    System.runAs(SocioWatchTestUserFactory.getUser(DASHBOARD_USER_ALIAS)) {
      createMentions();
      setTrialMock('TRIAL', 12);

      Test.startTest();
      SocioWatchDashboardController.DashboardData data = SocioWatchDashboardController.getDashboard(
        30
      );
      Test.stopTest();

      System.assertEquals(true, data.showTrialBanner);
      System.assertEquals(12, data.trialDaysRemaining);
    }
  }

  @IsTest
  static void keepsDashboardAvailableWhenTrialStatusIsUnavailable() {
    System.runAs(SocioWatchTestUserFactory.getUser(DASHBOARD_USER_ALIAS)) {
      createMentions();
      Test.setMock(
        HttpCalloutMock.class,
        new SocioWatchHttpMock(500, '{"message":"Unavailable"}')
      );

      Test.startTest();
      SocioWatchDashboardController.DashboardData data = SocioWatchDashboardController.getDashboard(
        30
      );
      Test.stopTest();

      System.assertEquals(3, data.totalMentions);
      System.assertEquals(false, data.showTrialBanner);
    }
  }

  private static void setTrialMock(String status, Integer daysRemaining) {
    String requestBody = JSON.serialize(
      new Map<String, Object>{
        'companyId' => COMPANY_ID,
        'externalAccountId' => UserInfo.getOrganizationId()
      }
    );
    String responseBody = JSON.serialize(
      new Map<String, Object>{
        'companyId' => COMPANY_ID,
        'subscriptionStatus' => status,
        'trialActive' => status == 'TRIAL',
        'trialDaysRemaining' => daysRemaining,
        'trialStartAt' => '2026-10-09T12:00:00+00:00',
        'trialEndsAt' => '2026-10-16T12:00:00+00:00',
        'trialExtensionDays' => 0
      }
    );

    Test.setMock(
      HttpCalloutMock.class,
      new SocioWatchHttpMock(200, responseBody)
        .expectRequest(
          'POST',
          'callout:SocioWatch_API/v1/settings/subscription-status',
          requestBody
        )
    );
  }

  private static SocioWatch_Mention__c buildMention(
    Id configurationId,
    String externalId,
    String source,
    String sentiment,
    String priority,
    String status,
    Datetime mentionDate
  ) {
    return new SocioWatch_Mention__c(
      Configuration__c = configurationId,
      External_Mention_Id__c = externalId,
      Mention_Date__c = mentionDate,
      Synced_At__c = System.now(),
      Title__c = source + ' mention',
      Mention_Text__c = 'A useful summary for management.',
      Source__c = source,
      Source_URL__c = 'https://example.com/' + externalId,
      Sentiment__c = sentiment,
      Priority__c = priority,
      Status__c = status
    );
  }
}
