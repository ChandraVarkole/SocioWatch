@IsTest
public class SocioWatchTestUserFactory {
  public static User createUserWithPermissionSet(
    String aliasValue,
    String permissionSetName
  ) {
    Profile currentProfile = [
      SELECT Id
      FROM Profile
      WHERE Id = :UserInfo.getProfileId()
      LIMIT 1
    ];
    String uniqueSuffix = String.valueOf(DateTime.now().getTime());
    User testUser = new User(
      Alias = aliasValue,
      Email = aliasValue + '@example.test',
      EmailEncodingKey = 'UTF-8',
      LastName = 'SocioWatch Test',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = currentProfile.Id,
      TimeZoneSidKey = 'America/New_York',
      Username = aliasValue + '.' + uniqueSuffix + '@example.test'
    );
    insert testUser;

    Id permissionSetId = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :permissionSetName AND IsOwnedByProfile = FALSE
      LIMIT 1
    ]
    .Id;
    insert new PermissionSetAssignment(
      AssigneeId = testUser.Id,
      PermissionSetId = permissionSetId
    );

    return testUser;
  }

  public static User getUser(String aliasValue) {
    return [SELECT Id FROM User WHERE Alias = :aliasValue LIMIT 1];
  }
}
