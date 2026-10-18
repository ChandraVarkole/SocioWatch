@IsTest
private class SocioWatchMetaServiceTest {
  private static final String ADMIN_ALIAS = 'swmeta';
  private static final String USER_ALIAS = 'swuser';
  private static final String COMPANY_ID = 'sw_meta_company';

  @TestSetup
  static void createAdmin() {
    SocioWatchTestUserFactory.createUserWithPermissionSet(
      ADMIN_ALIAS,
      'SocioWatch_Admin'
    );
    SocioWatchTestUserFactory.createUserWithPermissionSet(
      USER_ALIAS,
      'SocioWatch_User'
    );
  }

  @IsTest
  static void standardUserCanSeeOfferButCannotManageConnection() {
    User adminUser = SocioWatchTestUserFactory.getUser(ADMIN_ALIAS);
    System.runAs(adminUser) {
      insertConfiguration();
    }

    User standardUser = SocioWatchTestUserFactory.getUser(USER_ALIAS);
    System.runAs(standardUser) {
      Test.setMock(
        HttpCalloutMock.class,
        new MetaHttpMock(
          SocioWatchConstants.META_STATUS_ENDPOINT,
          '{"status":"ADD_ON_REQUIRED"}'
        )
      );

      Test.startTest();
      System.assertEquals(
        'ADD_ON_REQUIRED',
        SocioWatchMetaController.getOfferStatus()
      );
      try {
        SocioWatchMetaController.startConnection(
          'FACEBOOK',
          'https://example.lightning.force.com'
        );
        System.assert(
          false,
          'Standard users must not manage Meta connections.'
        );
      } catch (AuraHandledException error) {
        System.assertEquals(
          'You do not have permission to perform this SocioWatch operation.',
          error.getMessage()
        );
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void statusReturnsPaidAddOnStateWithoutCredentials() {
    User adminUser = SocioWatchTestUserFactory.getUser(ADMIN_ALIAS);
    System.runAs(adminUser) {
      insertConfiguration();
      Test.setMock(
        HttpCalloutMock.class,
        new MetaHttpMock(
          SocioWatchConstants.META_STATUS_ENDPOINT,
          '{"status":"ADD_ON_REQUIRED","hasStoredConnection":false}'
        )
      );

      Test.startTest();
      SocioWatchMetaConnectionResponse response = SocioWatchMetaController.getConnection();
      Test.stopTest();

      System.assertEquals('ADD_ON_REQUIRED', response.status);
      System.assertEquals(false, response.hasStoredConnection);
    }
  }

  @IsTest
  static void startConnectionReturnsOnlyValidatedFacebookUrl() {
    User adminUser = SocioWatchTestUserFactory.getUser(ADMIN_ALIAS);
    System.runAs(adminUser) {
      insertConfiguration();
      String authorizationUrl = 'https://www.facebook.com/v26.0/dialog/oauth?client_id=example';
      Test.setMock(
        HttpCalloutMock.class,
        new MetaHttpMock(
          SocioWatchConstants.META_CONNECT_ENDPOINT,
          JSON.serialize(
            new Map<String, Object>{ 'authorizationUrl' => authorizationUrl }
          )
        )
      );

      Test.startTest();
      SocioWatchMetaConnectionResponse response = SocioWatchMetaController.startConnection(
        'FACEBOOK_AND_INSTAGRAM',
        'https://example.lightning.force.com'
      );
      Test.stopTest();

      System.assertEquals(authorizationUrl, response.authorizationUrl);
    }
  }

  @IsTest
  static void invalidAuthorizationHostIsRejected() {
    User adminUser = SocioWatchTestUserFactory.getUser(ADMIN_ALIAS);
    System.runAs(adminUser) {
      insertConfiguration();
      Test.setMock(
        HttpCalloutMock.class,
        new MetaHttpMock(
          SocioWatchConstants.META_CONNECT_ENDPOINT,
          '{"authorizationUrl":"https://attacker.example/oauth"}'
        )
      );

      Test.startTest();
      try {
        SocioWatchMetaController.startConnection(
          'FACEBOOK',
          'https://example.lightning.force.com'
        );
        System.assert(false, 'An untrusted OAuth host must be rejected.');
      } catch (AuraHandledException error) {
        System.assertEquals(
          'SocioWatch returned an invalid Meta authorization address.',
          error.getMessage()
        );
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void savesSelectedFacebookPages() {
    User adminUser = SocioWatchTestUserFactory.getUser(ADMIN_ALIAS);
    System.runAs(adminUser) {
      insertConfiguration();
      Test.setMock(
        HttpCalloutMock.class,
        new MetaHttpMock(
          SocioWatchConstants.META_SELECT_ENDPOINT,
          '{"status":"CONNECTED","monitoringMode":"FACEBOOK"}'
        )
      );

      Test.startTest();
      SocioWatchMetaConnectionResponse response = SocioWatchMetaController.saveSelection(
        new List<String>{ 'page-123' }
      );
      Test.stopTest();

      System.assertEquals('CONNECTED', response.status);
      System.assertEquals('FACEBOOK', response.monitoringMode);
    }
  }

  @IsTest
  static void connectedResponseDeserializesAccountMetadata() {
    User adminUser = SocioWatchTestUserFactory.getUser(ADMIN_ALIAS);
    System.runAs(adminUser) {
      insertConfiguration();
      Test.setMock(
        HttpCalloutMock.class,
        new MetaHttpMock(
          SocioWatchConstants.META_STATUS_ENDPOINT,
          '{"status":"CONNECTED","monitoringMode":"FACEBOOK_AND_INSTAGRAM",' +
            '"message":"Connected","hasStoredConnection":true,' +
            '"availablePages":[{"pageId":"page-123","pageName":"SocioWatch",' +
            '"instagramAccount":{"accountId":"ig-123","username":"getsociowatch"}}],' +
            '"connection":{"monitoringMode":"FACEBOOK_AND_INSTAGRAM",' +
            '"connectedAt":"2026-10-18T10:00:00Z",' +
            '"lastCollectedAt":"2026-10-18T12:00:00Z",' +
            '"facebookPages":[{"pageId":"page-123","pageName":"SocioWatch"}],' +
            '"instagramAccounts":[{"accountId":"ig-123","username":"getsociowatch"}]}}'
        )
      );

      Test.startTest();
      SocioWatchMetaConnectionResponse response = SocioWatchMetaController.getConnection();
      Test.stopTest();

      System.assertEquals('CONNECTED', response.status);
      System.assertEquals('Connected', response.message);
      System.assertEquals(true, response.hasStoredConnection);
      System.assertEquals(1, response.availablePages.size());
      System.assertEquals('SocioWatch', response.availablePages[0].pageName);
      System.assertEquals(
        'getsociowatch',
        response.availablePages[0].instagramAccount.username
      );
      System.assertEquals(1, response.connection.facebookPages.size());
      System.assertEquals(1, response.connection.instagramAccounts.size());
      System.assertEquals(
        '2026-10-18T12:00:00Z',
        response.connection.lastCollectedAt
      );
    }
  }

  @IsTest
  static void disconnectReturnsNotConnected() {
    User adminUser = SocioWatchTestUserFactory.getUser(ADMIN_ALIAS);
    System.runAs(adminUser) {
      insertConfiguration();
      Test.setMock(
        HttpCalloutMock.class,
        new MetaHttpMock(
          SocioWatchConstants.META_DISCONNECT_ENDPOINT,
          '{"status":"NOT_CONNECTED","hasStoredConnection":false}'
        )
      );

      Test.startTest();
      SocioWatchMetaConnectionResponse response = SocioWatchMetaController.disconnect();
      Test.stopTest();

      System.assertEquals('NOT_CONNECTED', response.status);
      System.assertEquals(false, response.hasStoredConnection);
    }
  }

  @IsTest
  static void invalidMonitoringModeReturnsSafeValidationError() {
    User adminUser = SocioWatchTestUserFactory.getUser(ADMIN_ALIAS);
    System.runAs(adminUser) {
      insertConfiguration();

      Test.startTest();
      try {
        SocioWatchMetaController.startConnection(
          'INSTAGRAM_ONLY',
          'https://example.lightning.force.com'
        );
        System.assert(false, 'Instagram-only mode must not be accepted.');
      } catch (AuraHandledException error) {
        System.assertEquals(
          'Choose Facebook only or Facebook and Instagram.',
          error.getMessage()
        );
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void responseParserRejectsEmptyMalformedAndNullPayloads() {
    assertInvalidResponse(
      '',
      'SocioWatch returned an empty Meta connection response.'
    );
    assertInvalidResponse(
      '{not-json}',
      'SocioWatch returned an invalid Meta connection response.'
    );
    assertInvalidResponse(
      'null',
      'SocioWatch returned an invalid Meta connection response.'
    );

    SocioWatchMetaConnectionResponse response = SocioWatchMetaConnectionResponse.parse(
      '{"status":"NOT_CONNECTED"}'
    );
    System.assertEquals(0, response.availablePages.size());
  }

  private static void assertInvalidResponse(
    String responseBody,
    String expectedMessage
  ) {
    try {
      SocioWatchMetaConnectionResponse.parse(responseBody);
      System.assert(false, 'The response should have been rejected.');
    } catch (SocioWatchApiException error) {
      System.assertEquals(expectedMessage, error.getMessage());
    }
  }

  private static void insertConfiguration() {
    insert new SocioWatch_Configuration__c(
      Company_Name__c = 'Meta Test Company',
      Keywords__c = '["Meta Test Company"]',
      Sync_Enabled__c = true,
      AWS_Company_Id__c = COMPANY_ID,
      Tenant_Id__c = 'tenant_meta_company',
      Salesforce_Org_Id__c = UserInfo.getOrganizationId(),
      Last_Sync_Status__c = SocioWatchConstants.SYNC_STATUS_NOT_STARTED
    );
  }

  private class MetaHttpMock implements HttpCalloutMock {
    private String expectedPath;
    private String responseBody;

    private MetaHttpMock(String expectedPath, String responseBody) {
      this.expectedPath = expectedPath;
      this.responseBody = responseBody;
    }

    public HttpResponse respond(HttpRequest request) {
      System.assertEquals('POST', request.getMethod());
      System.assertEquals(
        'callout:SocioWatch_API' + expectedPath,
        request.getEndpoint()
      );
      Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
        request.getBody()
      );
      System.assertEquals(COMPANY_ID, body.get('companyId'));
      System.assertEquals(
        UserInfo.getOrganizationId(),
        body.get('externalAccountId')
      );

      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setHeader('Content-Type', 'application/json');
      response.setBody(responseBody);
      return response;
    }
  }
}
