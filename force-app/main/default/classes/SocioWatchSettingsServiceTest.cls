@IsTest
private class SocioWatchSettingsServiceTest {
  private static final String ADMIN_ALIAS = 'swadmin';
  private static final String USER_ALIAS = 'swuser';

  private static final String COMPANY_ID = 'COMP-000001';
  private static final String TENANT_ID = 'TENANT-000001';
  private static final String ALERT_ID = 'alert_12345';

  /**
   * Creates:
   * - One test administrator
   * - One standard test user
   * - SocioWatch Admin permission-set assignment for the administrator
   *
   * Setup-object DML is isolated in @testSetup to prevent mixed-DML
   * conflicts with custom-object records created in individual tests.
   */
  @TestSetup
  static void createUsersAndPermissions() {
    Profile currentProfile = [
      SELECT Id
      FROM Profile
      WHERE Id = :UserInfo.getProfileId()
      LIMIT 1
    ];

    String uniqueSuffix = String.valueOf(DateTime.now().getTime());

    User adminUser = buildUser(
      currentProfile.Id,
      ADMIN_ALIAS,
      'sociowatch.admin.' + uniqueSuffix + '@example.test'
    );

    User standardUser = buildUser(
      currentProfile.Id,
      USER_ALIAS,
      'sociowatch.user.' + uniqueSuffix + '@example.test'
    );

    insert new List<User>{ adminUser, standardUser };

    PermissionSet adminPermissionSet = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'SocioWatch_Admin' AND IsOwnedByProfile = FALSE
      LIMIT 1
    ];

    insert new PermissionSetAssignment(
      AssigneeId = adminUser.Id,
      PermissionSetId = adminPermissionSet.Id
    );
  }

  // =====================================================
  // Permission tests
  // =====================================================

  @IsTest
  static void administratorHasSettingsPermission() {
    User adminUser = getUser(ADMIN_ALIAS);

    System.runAs(adminUser) {
      System.assertEquals(
        true,
        SocioWatchPermissionService.canManageSettings(),
        'The SocioWatch Admin permission set must grant ' +
        'the Manage Settings custom permission.'
      );

      System.assertEquals(
        true,
        SocioWatchSettingsController.canManageSettings()
      );
    }
  }

  @IsTest
  static void standardUserDoesNotHaveSettingsPermission() {
    User standardUser = getUser(USER_ALIAS);

    System.runAs(standardUser) {
      System.assertEquals(
        false,
        SocioWatchPermissionService.canManageSettings()
      );

      System.assertEquals(
        false,
        SocioWatchSettingsController.canManageSettings()
      );
    }
  }

  @IsTest
  static void standardUserCannotRetrieveSettings() {
    User standardUser = getUser(USER_ALIAS);

    System.runAs(standardUser) {
      try {
        SocioWatchSettingsController.getSettings();

        System.assert(
          false,
          'A user without the custom permission must be denied.'
        );
      } catch (AuraHandledException error) {
        System.assertEquals(
          'You do not have permission to perform this ' +
          'SocioWatch operation.',
          error.getMessage()
        );
      }
    }
  }

  @IsTest
  static void standardUserCannotSaveSettings() {
    User standardUser = getUser(USER_ALIAS);

    System.runAs(standardUser) {
      try {
        SocioWatchSettingsController.saveSettings(buildSettingsRequest());

        System.assert(
          false,
          'A user without the custom permission must be denied.'
        );
      } catch (AuraHandledException error) {
        System.assertEquals(
          'You do not have permission to perform this ' +
          'SocioWatch operation.',
          error.getMessage()
        );
      }
    }
  }

  // =====================================================
  // Empty Settings tests
  // =====================================================

  @IsTest
  static void returnsEmptySettingsWhenConfigurationDoesNotExist() {
    User adminUser = getUser(ADMIN_ALIAS);

    System.runAs(adminUser) {
      Test.startTest();

      SocioWatchSettingsResponse response = SocioWatchSettingsController.getSettings();

      Test.stopTest();

      System.assertEquals(null, response.configurationId);

      System.assertEquals(true, response.syncEnabled);

      System.assertEquals(true, response.googleReviewsEnabled);

      System.assertEquals(
        UserInfo.getOrganizationId(),
        response.salesforceOrgId
      );

      System.assertEquals(
        SocioWatchConstants.SYNC_STATUS_NOT_STARTED,
        response.lastSyncStatus
      );

      System.assertEquals(0, response.keywords.size());
    }
  }

  // =====================================================
  // Create Settings tests
  // =====================================================

  @IsTest
  static void saveSettingsCreatesSingletonConfiguration() {
    User adminUser = getUser(ADMIN_ALIAS);

    System.runAs(adminUser) {
      SocioWatchSettingsRequest request = buildSettingsRequest();

      String expectedRequestBody = request.toApiJson(
        UserInfo.getOrganizationId()
      );

      Test.setMock(
        HttpCalloutMock.class,
        buildSettingsSuccessMock(
          expectedRequestBody,
          true,
          'Company configuration created successfully.'
        )
      );

      Test.startTest();

      SocioWatchSettingsResponse response = SocioWatchSettingsController.saveSettings(
        request
      );

      Test.stopTest();

      System.assertNotEquals(null, response.configurationId);

      System.assertEquals('Tesla', response.companyName);

      System.assertEquals('Austin', response.companyCity);

      System.assertEquals('Texas', response.companyStateProvince);

      System.assertEquals('United States', response.companyCountry);

      System.assertEquals(true, response.googleReviewsEnabled);

      System.assertEquals(true, response.syncEnabled);

      System.assertEquals(COMPANY_ID, response.companyId);

      System.assertEquals(TENANT_ID, response.tenantId);

      System.assertEquals(true, response.created);

      System.assertEquals(2, response.keywords.size());

      System.assertEquals(
        'Company configuration created successfully.',
        response.message
      );

      List<SocioWatch_Configuration__c> records = [
        SELECT
          Id,
          Company_Name__c,
          Company_City__c,
          Company_State_Province__c,
          Company_Country__c,
          Google_Reviews_Enabled__c,
          Keywords__c,
          Sync_Enabled__c,
          AWS_Company_Id__c,
          Tenant_Id__c,
          Salesforce_Org_Id__c,
          Last_Sync_Status__c
        FROM SocioWatch_Configuration__c
        WITH USER_MODE
      ];

      System.assertEquals(
        1,
        records.size(),
        'Only one configuration record should be created.'
      );

      SocioWatch_Configuration__c savedRecord = records[0];

      System.assertEquals('Tesla', savedRecord.Company_Name__c);

      System.assertEquals('Austin', savedRecord.Company_City__c);

      System.assertEquals('Texas', savedRecord.Company_State_Province__c);

      System.assertEquals('United States', savedRecord.Company_Country__c);

      System.assertEquals(true, savedRecord.Google_Reviews_Enabled__c);

      System.assertEquals('Tesla\nTesla Motors', savedRecord.Keywords__c);

      System.assertEquals(COMPANY_ID, savedRecord.AWS_Company_Id__c);

      System.assertEquals(TENANT_ID, savedRecord.Tenant_Id__c);

      System.assertEquals(
        UserInfo.getOrganizationId(),
        savedRecord.Salesforce_Org_Id__c
      );

      System.assertEquals(
        SocioWatchConstants.SYNC_STATUS_NOT_STARTED,
        savedRecord.Last_Sync_Status__c
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
        ],
        'Saving enabled Settings must create the hourly mentions job.'
      );
    }
  }

  // =====================================================
  // Update Settings tests
  // =====================================================

  @IsTest
  static void saveSettingsUpdatesExistingSingleton() {
    User adminUser = getUser(ADMIN_ALIAS);

    System.runAs(adminUser) {
      SocioWatch_Configuration__c existingConfiguration = createConfiguration(
        'Original Company',
        'Original Keyword',
        'original_alert',
        'COMP-ORIGINAL',
        'TENANT-ORIGINAL'
      );

      SocioWatchSettingsRequest request = buildSettingsRequest();

      String expectedRequestBody = request.toApiJson(
        UserInfo.getOrganizationId()
      );

      Test.setMock(
        HttpCalloutMock.class,
        buildSettingsSuccessMock(
          expectedRequestBody,
          false,
          'Company configuration updated successfully.',
          'COMP-ORIGINAL',
          'TENANT-ORIGINAL'
        )
      );

      Test.startTest();

      SocioWatchSettingsResponse response = SocioWatchSettingsController.saveSettings(
        request
      );

      Test.stopTest();

      System.assertEquals(
        existingConfiguration.Id,
        response.configurationId,
        'The existing singleton record must be updated.'
      );

      System.assertEquals(false, response.created);

      System.assertEquals('Tesla', response.companyName);

      System.assertEquals('COMP-ORIGINAL', response.companyId);

      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM SocioWatch_Configuration__c
        ],
        'Saving Settings must not create a second record.'
      );

      SocioWatch_Configuration__c updatedRecord = [
        SELECT
          Company_Name__c,
          Company_City__c,
          Company_State_Province__c,
          Company_Country__c,
          Google_Reviews_Enabled__c,
          Keywords__c,
          AWS_Company_Id__c,
          Tenant_Id__c
        FROM SocioWatch_Configuration__c
        WHERE Id = :existingConfiguration.Id
        WITH USER_MODE
        LIMIT 1
      ];

      System.assertEquals('Tesla', updatedRecord.Company_Name__c);

      System.assertEquals('Austin', updatedRecord.Company_City__c);

      System.assertEquals('Texas', updatedRecord.Company_State_Province__c);

      System.assertEquals('United States', updatedRecord.Company_Country__c);

      System.assertEquals(true, updatedRecord.Google_Reviews_Enabled__c);

      System.assertEquals('Tesla\nTesla Motors', updatedRecord.Keywords__c);

      System.assertEquals('COMP-ORIGINAL', updatedRecord.AWS_Company_Id__c);

      System.assertEquals('TENANT-ORIGINAL', updatedRecord.Tenant_Id__c);
    }
  }

  @IsTest
  static void saveSettingsRejectsChangedCompanyMapping() {
    User adminUser = getUser(ADMIN_ALIAS);

    System.runAs(adminUser) {
      createConfiguration(
        'Original Company',
        'Original Keyword',
        'original_alert',
        'COMP-ORIGINAL',
        'TENANT-ORIGINAL'
      );

      SocioWatchSettingsRequest request = buildSettingsRequest();

      String expectedRequestBody = request.toApiJson(
        UserInfo.getOrganizationId()
      );

      Test.setMock(
        HttpCalloutMock.class,
        buildSettingsSuccessMock(
          expectedRequestBody,
          false,
          'Company configuration updated successfully.',
          'COMP-DIFFERENT',
          'TENANT-ORIGINAL'
        )
      );

      Test.startTest();

      try {
        SocioWatchSettingsController.saveSettings(request);

        System.assert(
          false,
          'An existing Salesforce org must not be remapped.'
        );
      } catch (AuraHandledException error) {
        System.assertEquals(
          'The SocioWatch company mapping does not match ' +
            'the existing Salesforce configuration. ' +
            'Contact SocioWatch support.',
          error.getMessage()
        );
      }

      Test.stopTest();
    }
  }

  @IsTest
  static void getSettingsReturnsExistingConfiguration() {
    User adminUser = getUser(ADMIN_ALIAS);

    System.runAs(adminUser) {
      SocioWatch_Configuration__c configuration = createConfiguration(
        'Tesla',
        'Tesla\nTesla Motors',
        ALERT_ID,
        COMPANY_ID,
        TENANT_ID
      );

      Test.startTest();

      SocioWatchSettingsResponse response = SocioWatchSettingsController.getSettings();

      Test.stopTest();

      System.assertEquals(configuration.Id, response.configurationId);

      System.assertEquals('Tesla', response.companyName);

      System.assertEquals(2, response.keywords.size());

      System.assertEquals(COMPANY_ID, response.companyId);

      System.assertEquals(TENANT_ID, response.tenantId);
    }
  }

  @IsTest
  static void getsGoogleReviewsResolutionStatus() {
    User adminUser = getUser(ADMIN_ALIAS);

    System.runAs(adminUser) {
      String expectedBody = JSON.serialize(
        new Map<String, Object>{
          'companyId' => COMPANY_ID,
          'externalAccountId' => UserInfo.getOrganizationId()
        }
      );
      Test.setMock(
        HttpCalloutMock.class,
        new SocioWatchHttpMock(
            200,
            '{"companyId":"' +
              COMPANY_ID +
              '","googleReviewsResolutionStatus":"RESOLVED",' +
              '"googleReviewsResolutionMessage":"Google Business Profile connected."}'
          )
          .expectRequest(
            'POST',
            'callout:SocioWatch_API/v1/settings/google-reviews-status',
            expectedBody
          )
      );

      Test.startTest();
      SocioWatchSettingsResponse response = SocioWatchSettingsController.getGoogleReviewsStatus(
        COMPANY_ID
      );
      Test.stopTest();

      System.assertEquals('RESOLVED', response.googleReviewsResolutionStatus);
      System.assertEquals(
        'Google Business Profile connected.',
        response.googleReviewsResolutionMessage
      );
    }
  }

  @IsTest
  static void standardUserCannotGetGoogleReviewsResolutionStatus() {
    User standardUser = getUser(USER_ALIAS);

    System.runAs(standardUser) {
      try {
        SocioWatchSettingsController.getGoogleReviewsStatus(COMPANY_ID);
        System.assert(false, 'A user without permission must be denied.');
      } catch (AuraHandledException error) {
        System.assertEquals(
          'You do not have permission to perform this SocioWatch operation.',
          error.getMessage()
        );
      }
    }
  }

  @IsTest
  static void rejectsBlankGoogleReviewsStatusCompanyId() {
    User adminUser = getUser(ADMIN_ALIAS);

    System.runAs(adminUser) {
      try {
        SocioWatchSettingsController.getGoogleReviewsStatus(' ');
        System.assert(false, 'A blank company ID must be rejected.');
      } catch (AuraHandledException error) {
        System.assertEquals(
          'A valid SocioWatch company is required.',
          error.getMessage()
        );
      }
    }
  }

  @IsTest
  static void handlesGoogleReviewsStatusApiFailure() {
    User adminUser = getUser(ADMIN_ALIAS);

    System.runAs(adminUser) {
      Test.setMock(
        HttpCalloutMock.class,
        new SocioWatchHttpMock(500, '{"message":"internal"}')
      );

      try {
        SocioWatchSettingsController.getGoogleReviewsStatus(COMPANY_ID);
        System.assert(false, 'An AWS failure must be surfaced safely.');
      } catch (AuraHandledException error) {
        System.assert(String.isNotBlank(error.getMessage()));
      }
    }
  }

  // =====================================================
  // Validation tests
  // =====================================================

  @IsTest
  static void controllerRejectsNullSettingsRequest() {
    User adminUser = getUser(ADMIN_ALIAS);

    System.runAs(adminUser) {
      try {
        SocioWatchSettingsController.saveSettings(null);

        System.assert(false, 'A null request must be rejected.');
      } catch (AuraHandledException error) {
        System.assertEquals(
          'SocioWatch settings are required.',
          error.getMessage()
        );
      }

      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM SocioWatch_Configuration__c
        ]
      );
    }
  }

  @IsTest
  static void controllerRejectsInvalidCompanyNameBeforeCallout() {
    User adminUser = getUser(ADMIN_ALIAS);

    System.runAs(adminUser) {
      SocioWatchSettingsRequest request = buildSettingsRequest();

      request.companyName = '   ';

      try {
        SocioWatchSettingsController.saveSettings(request);

        System.assert(false, 'Invalid input must be rejected.');
      } catch (AuraHandledException error) {
        System.assertEquals('Company Name is required.', error.getMessage());
      }

      System.assertEquals(
        0,
        Limits.getCallouts(),
        'Validation must occur before the AWS callout.'
      );
    }
  }

  // =====================================================
  // AWS response tests
  // =====================================================

  @IsTest
  static void controllerReturnsSafeMessageForAwsServerError() {
    User adminUser = getUser(ADMIN_ALIAS);

    System.runAs(adminUser) {
      Test.setMock(
        HttpCalloutMock.class,
        new SocioWatchHttpMock(
          500,
          JSON.serialize(
            new Map<String, Object>{
              'apiKey' => 'must-not-be-exposed',
              'stackTrace' => 'internal-details'
            }
          )
        )
      );

      Test.startTest();

      try {
        SocioWatchSettingsController.saveSettings(buildSettingsRequest());

        System.assert(false, 'An AWS server error must be returned safely.');
      } catch (AuraHandledException error) {
        System.assert(
          error.getMessage()
            .startsWith('The SocioWatch service is temporarily unavailable.'),
          'Unexpected message: ' + error.getMessage()
        );

        System.assertEquals(
          false,
          error.getMessage().contains('must-not-be-exposed')
        );

        System.assertEquals(
          false,
          error.getMessage().contains('internal-details')
        );

        System.assert(error.getMessage().contains('Reference:'));
      }

      Test.stopTest();

      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM SocioWatch_Configuration__c
        ],
        'No Salesforce record should be committed after ' + 'an AWS failure.'
      );
    }
  }

  @IsTest
  static void controllerRejectsMalformedAwsResponse() {
    User adminUser = getUser(ADMIN_ALIAS);

    System.runAs(adminUser) {
      Test.setMock(
        HttpCalloutMock.class,
        new SocioWatchHttpMock(200, '{"companyId":')
      );

      Test.startTest();

      try {
        SocioWatchSettingsController.saveSettings(buildSettingsRequest());

        System.assert(false, 'Malformed AWS JSON must be rejected.');
      } catch (AuraHandledException error) {
        System.assertEquals(
          'SocioWatch returned an invalid settings response.',
          error.getMessage()
        );
      }

      Test.stopTest();

      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM SocioWatch_Configuration__c
        ]
      );
    }
  }

  @IsTest
  static void controllerRejectsAwsResponseWithoutIdentifiers() {
    User adminUser = getUser(ADMIN_ALIAS);

    System.runAs(adminUser) {
      Test.setMock(
        HttpCalloutMock.class,
        new SocioWatchHttpMock(
          200,
          JSON.serialize(new Map<String, Object>{ 'message' => 'Success' })
        )
      );

      Test.startTest();

      try {
        SocioWatchSettingsController.saveSettings(buildSettingsRequest());

        System.assert(false, 'Missing identifiers must be rejected.');
      } catch (AuraHandledException error) {
        System.assertEquals(
          'SocioWatch did not return the required ' + 'company information.',
          error.getMessage()
        );
      }

      Test.stopTest();
    }
  }

  // =====================================================
  // Singleton integrity tests
  // =====================================================

  @IsTest
  static void multipleConfigurationsAreRejected() {
    User adminUser = getUser(ADMIN_ALIAS);

    System.runAs(adminUser) {
      createConfiguration(
        'Company One',
        'Keyword One',
        'alert_one',
        'COMP-ONE',
        'TENANT-ONE'
      );

      createConfiguration(
        'Company Two',
        'Keyword Two',
        'alert_two',
        'COMP-TWO',
        'TENANT-TWO'
      );

      try {
        SocioWatchSettingsController.getSettings();

        System.assert(false, 'Multiple configurations must be rejected.');
      } catch (AuraHandledException error) {
        System.assertEquals(
          'Multiple SocioWatch configurations were found. ' +
          'Contact your Salesforce administrator.',
          error.getMessage()
        );
      }
    }
  }

  // =====================================================
  // Controller helper tests
  // =====================================================

  @IsTest
  static void handledExceptionUsesGenericMessageForBlankInput() {
    AuraHandledException error = SocioWatchSettingsController.createHandledException(
      null
    );

    System.assertEquals(Label.SocioWatch_Unexpected_Error, error.getMessage());
  }

  @IsTest
  static void generatedReferenceIdIsNotBlank() {
    String referenceId = SocioWatchSettingsController.generateReferenceId();

    System.assert(String.isNotBlank(referenceId));

    System.assertEquals(
      32,
      referenceId.length(),
      'A 128-bit value represented as hexadecimal should ' +
      'contain 32 characters.'
    );
  }

  @IsTest
  static void unexpectedErrorsUseSafeMessageAndReference() {
    AuraHandledException error = SocioWatchSettingsController.createUnexpectedException(
      'Test-only internal context.',
      Label.SocioWatch_Unexpected_Error
    );

    System.assert(
      error.getMessage()
        .startsWith(Label.SocioWatch_Unexpected_Error + ' Reference: ')
    );

    System.assertEquals(
      false,
      error.getMessage().contains('Test-only internal context.')
    );
  }

  // =====================================================
  // Helpers
  // =====================================================

  private static User buildUser(
    Id profileId,
    String aliasValue,
    String username
  ) {
    return new User(
      Alias = aliasValue,
      Email = username,
      EmailEncodingKey = 'UTF-8',
      FirstName = 'SocioWatch',
      LastName = aliasValue,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profileId,
      TimeZoneSidKey = 'America/New_York',
      Username = username
    );
  }

  private static User getUser(String aliasValue) {
    return [
      SELECT Id, Alias
      FROM User
      WHERE Alias = :aliasValue
      LIMIT 1
    ];
  }

  private static SocioWatchSettingsRequest buildSettingsRequest() {
    SocioWatchSettingsRequest request = new SocioWatchSettingsRequest();

    request.companyName = 'Tesla';

    request.llmMentionKeyword = 'Tesla';

    request.companyCity = 'Austin';

    request.companyStateProvince = 'Texas';

    request.companyCountry = 'United States';

    request.googleReviewsEnabled = true;

    request.keywords = new List<String>{ 'Tesla', 'Tesla Motors' };

    request.syncEnabled = true;

    return request;
  }

  private static HttpCalloutMock buildSettingsSuccessMock(
    String expectedRequestBody,
    Boolean created,
    String responseMessage
  ) {
    return buildSettingsSuccessMock(
      expectedRequestBody,
      created,
      responseMessage,
      COMPANY_ID,
      TENANT_ID
    );
  }

  private static HttpCalloutMock buildSettingsSuccessMock(
    String expectedRequestBody,
    Boolean created,
    String responseMessage,
    String responseCompanyId,
    String responseTenantId
  ) {
    String responseBody = JSON.serialize(
      new Map<String, Object>{
        'message' => responseMessage,
        'created' => created,
        'tenantId' => responseTenantId,
        'companyId' => responseCompanyId,
        'companyName' => 'Tesla',
        'externalPlatform' => 'salesforce',
        'externalAccountId' => UserInfo.getOrganizationId(),
        'status' => 'Active'
      }
    );

    return new SettingsAndImportHttpMock(expectedRequestBody, responseBody);
  }

  private class SettingsAndImportHttpMock implements HttpCalloutMock {
    private String expectedSettingsBody;
    private String settingsResponseBody;

    private SettingsAndImportHttpMock(
      String expectedSettingsBody,
      String settingsResponseBody
    ) {
      this.expectedSettingsBody = expectedSettingsBody;
      this.settingsResponseBody = settingsResponseBody;
    }

    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setHeader('Content-Type', 'application/json');

      if (request.getEndpoint() == 'callout:SocioWatch_API/v1/settings') {
        System.assertEquals('POST', request.getMethod());
        System.assertEquals(expectedSettingsBody, request.getBody());
        response.setBody(settingsResponseBody);
        return response;
      }

      System.assertEquals('GET', request.getMethod());
      System.assert(
        request.getEndpoint().startsWith('callout:SocioWatch_API/v1/mentions?'),
        'The scheduled import must request mentions.'
      );
      response.setBody(
        '{"companyId":"' + COMPANY_ID + '","count":0,"mentions":[]}'
      );
      return response;
    }
  }

  private static SocioWatch_Configuration__c createConfiguration(
    String companyName,
    String keywords,
    String alertId,
    String companyId,
    String tenantId
  ) {
    SocioWatch_Configuration__c configuration = new SocioWatch_Configuration__c(
      Company_Name__c = companyName,
      Keywords__c = keywords,
      Alert_Id__c = alertId,
      Sync_Enabled__c = true,
      AWS_Company_Id__c = companyId,
      Tenant_Id__c = tenantId,
      Salesforce_Org_Id__c = buildUniqueOrgIdentifier(companyId),
      Last_Sync_Status__c = SocioWatchConstants.SYNC_STATUS_NOT_STARTED
    );

    Database.SaveResult result = Database.insert(
      configuration,
      AccessLevel.USER_MODE
    );

    System.assertEquals(
      true,
      result.isSuccess(),
      result.isSuccess()
        ? 'Expected the test configuration insert to succeed.'
        : result.getErrors()[0].getMessage()
    );

    configuration.Id = result.getId();

    return configuration;
  }

  /**
   * Salesforce_Org_Id__c is unique, so tests that intentionally
   * create multiple configuration records require different
   * synthetic 18-character identifiers.
   */
  private static String buildUniqueOrgIdentifier(String seed) {
    String hashValue = EncodingUtil.convertToHex(
      Crypto.generateDigest('MD5', Blob.valueOf(seed))
    );

    return '00D' + hashValue.substring(0, 15);
  }
}
