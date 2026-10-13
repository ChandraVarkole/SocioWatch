/** @description Validated object and field API names used for author matching. */
public inherited sharing class SocioWatchMentionLinkTarget {
  /** @description Canonical API name of the configured target object. */
  public String objectApiName { get; private set; }
  /** @description Canonical API name of the configured match field. */
  public String fieldApiName { get; private set; }

  private SocioWatchMentionLinkTarget(String objectName, String fieldName) {
    objectApiName = objectName;
    fieldApiName = fieldName;
  }

  /**
   * @description Resolves case-insensitive API names and validates that they
   * can be matched.
   * @param objectApiName configured target object API name
   * @param fieldApiName configured match field API name
   * @return validated canonical target information
   */
  public static SocioWatchMentionLinkTarget resolve(
    String objectApiName,
    String fieldApiName
  ) {
    requireApiNames(objectApiName, fieldApiName);

    Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
    String objectName = findApiName(
      globalDescribe.keySet(),
      objectApiName.trim()
    );
    Schema.DescribeSObjectResult objectDescribe = requireQueryableObject(
      globalDescribe,
      objectName
    );
    Map<String, Schema.SObjectField> fields = objectDescribe.fields.getMap();
    String fieldName = findApiName(fields.keySet(), fieldApiName.trim());

    requireMatchField(fields, fieldName);

    return new SocioWatchMentionLinkTarget(
      objectDescribe.getName(),
      fields.get(fieldName).getDescribe().getName()
    );
  }

  private static void requireApiNames(
    String objectApiName,
    String fieldApiName
  ) {
    if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) {
      throw new SocioWatchValidationException(
        'Choose both an object API name and a match field API name for automatic mention linking.'
      );
    }
  }

  private static Schema.DescribeSObjectResult requireQueryableObject(
    Map<String, Schema.SObjectType> globalDescribe,
    String objectName
  ) {
    if (objectName == null) {
      throw new SocioWatchValidationException(
        'The author match object does not exist or cannot be queried.'
      );
    }

    Schema.DescribeSObjectResult objectDescribe = globalDescribe
      .get(objectName)
      .getDescribe();

    if (!objectDescribe.isQueryable() || !objectDescribe.isAccessible()) {
      throw new SocioWatchValidationException(
        'The author match object does not exist or cannot be queried.'
      );
    }

    return objectDescribe;
  }

  private static void requireMatchField(
    Map<String, Schema.SObjectField> fields,
    String fieldName
  ) {
    if (fieldName == null) {
      throw new SocioWatchValidationException(
        'The author match field does not exist on the selected object.'
      );
    }

    Schema.DescribeFieldResult fieldDescribe = fields
      .get(fieldName)
      .getDescribe();
    Set<Schema.DisplayType> supportedTypes = new Set<Schema.DisplayType>{
      Schema.DisplayType.String,
      Schema.DisplayType.Email,
      Schema.DisplayType.Phone
    };

    if (
      !fieldDescribe.isAccessible() ||
      !supportedTypes.contains(fieldDescribe.getType())
    ) {
      throw new SocioWatchValidationException(
        'Choose an accessible text, email, or phone field for author matching.'
      );
    }
  }

  private static String findApiName(
    Set<String> apiNames,
    String requestedName
  ) {
    for (String apiName : apiNames) {
      if (apiName.equalsIgnoreCase(requestedName)) {
        return apiName;
      }
    }

    return null;
  }
}
