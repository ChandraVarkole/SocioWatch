/**
 * Read-only analytics for the SocioWatch management overview.
 */
public with sharing class SocioWatchDashboardController {
  private static final Set<Integer> ALLOWED_PERIODS = new Set<Integer>{
    0,
    7,
    30,
    90
  };
  private static final Integer RECENT_MENTION_LIMIT = 18;

  @AuraEnabled(cacheable=true)
  public static DashboardData getDashboard(Integer days) {
    Integer safeDays = ALLOWED_PERIODS.contains(days) ? days : 30;
    DateTime startDate = safeDays == 0
      ? DateTime.newInstanceGmt(1970, 1, 1, 0, 0, 0)
      : System.now().addDays(-safeDays);

    DashboardData data = new DashboardData();
    data.periodDays = safeDays;
    data.generatedAt = System.now();

    List<SocioWatch_Configuration__c> configurations = [
      SELECT Full_License__c, AWS_Company_Id__c
      FROM SocioWatch_Configuration__c
      WITH USER_MODE
      ORDER BY CreatedDate ASC
      LIMIT 1
    ];
    data.showTrialBanner = false;
    data.trialDaysRemaining = 0;

    if (!configurations.isEmpty()) {
      applyTrialStatus(data, configurations[0]);
    }

    data.sources = toBreakdown(
      [
        SELECT Source__c label, COUNT(Id) total
        FROM SocioWatch_Mention__c
        WHERE Is_Relevant__c = TRUE AND Mention_Date__c >= :startDate
        WITH USER_MODE
        GROUP BY Source__c
        ORDER BY COUNT(Id) DESC
      ]
    );

    data.sentiments = toBreakdown(
      [
        SELECT Sentiment__c label, COUNT(Id) total
        FROM SocioWatch_Mention__c
        WHERE Is_Relevant__c = TRUE AND Mention_Date__c >= :startDate
        WITH USER_MODE
        GROUP BY Sentiment__c
        ORDER BY COUNT(Id) DESC
      ]
    );

    data.priorities = toBreakdown(
      [
        SELECT Priority__c label, COUNT(Id) total
        FROM SocioWatch_Mention__c
        WHERE Is_Relevant__c = TRUE AND Mention_Date__c >= :startDate
        WITH USER_MODE
        GROUP BY Priority__c
        ORDER BY COUNT(Id) DESC
      ]
    );

    data.statuses = toBreakdown(
      [
        SELECT Status__c label, COUNT(Id) total
        FROM SocioWatch_Mention__c
        WHERE Is_Relevant__c = TRUE AND Mention_Date__c >= :startDate
        WITH USER_MODE
        GROUP BY Status__c
        ORDER BY COUNT(Id) DESC
      ]
    );

    data.totalMentions = sumCounts(data.sources);
    data.newMentions = countFor(data.statuses, 'New');
    data.negativeMentions = countFor(data.sentiments, 'Negative');
    data.attentionMentions =
      countFor(data.priorities, 'High') + countFor(data.priorities, 'Critical');

    Date trendStart = Date.today().addDays(-13);
    Datetime trendStartDateTime = Datetime.newInstance(
      trendStart,
      Time.newInstance(0, 0, 0, 0)
    );
    List<AggregateResult> dailyResults = [
      SELECT DAY_ONLY(Mention_Date__c) mentionDay, COUNT(Id) total
      FROM SocioWatch_Mention__c
      WHERE Is_Relevant__c = TRUE AND Mention_Date__c >= :trendStartDateTime
      WITH USER_MODE
      GROUP BY DAY_ONLY(Mention_Date__c)
      ORDER BY DAY_ONLY(Mention_Date__c)
    ];
    data.dailyTrend = buildDailyTrend(dailyResults, trendStart);

    data.recentMentions = new List<MentionItem>();
    for (SocioWatch_Mention__c mention : [
      SELECT
        Id,
        Name,
        Title__c,
        Source__c,
        Source_URL__c,
        Author_Name__c,
        Sentiment__c,
        Priority__c,
        Status__c,
        Mention_Date__c,
        Mention_Text__c,
        Actionable_Type__c,
        Assigned_To__r.Name
      FROM SocioWatch_Mention__c
      WHERE Is_Relevant__c = TRUE AND Mention_Date__c >= :startDate
      WITH USER_MODE
      ORDER BY Mention_Date__c DESC
      LIMIT :RECENT_MENTION_LIMIT
    ]) {
      data.recentMentions.add(new MentionItem(mention));
    }

    return data;
  }

  private static void applyTrialStatus(
    DashboardData data,
    SocioWatch_Configuration__c configuration
  ) {
    if (
      configuration.Full_License__c ||
      String.isBlank(configuration.AWS_Company_Id__c)
    ) {
      return;
    }

    try {
      String requestBody = JSON.serialize(
        new Map<String, Object>{
          'companyId' => configuration.AWS_Company_Id__c,
          'externalAccountId' => UserInfo.getOrganizationId()
        }
      );
      SocioWatchApiResponse apiResponse = SocioWatchApiClient.post(
        SocioWatchConstants.SUBSCRIPTION_STATUS_ENDPOINT,
        requestBody
      );
      AwsSubscriptionStatus subscription = (AwsSubscriptionStatus) JSON.deserialize(
        apiResponse.responseBody,
        AwsSubscriptionStatus.class
      );

      if (
        subscription == null ||
        subscription.companyId != configuration.AWS_Company_Id__c
      ) {
        throw new SocioWatchApiException(
          'SocioWatch returned subscription status for a different company.'
        );
      }

      String status = String.isBlank(subscription.subscriptionStatus)
        ? ''
        : subscription.subscriptionStatus.trim().toUpperCase();

      data.showTrialBanner = status == 'TRIAL' || status == 'EXPIRED';
      data.trialDaysRemaining = subscription.trialDaysRemaining == null
        ? 0
        : Math.max(0, subscription.trialDaysRemaining);
    } catch (Exception error) {
      System.debug(
        LoggingLevel.WARN,
        'SocioWatch trial status is temporarily unavailable.'
      );
      data.showTrialBanner = false;
      data.trialDaysRemaining = 0;
    }
  }

  private static List<BreakdownItem> toBreakdown(
    List<AggregateResult> results
  ) {
    List<BreakdownItem> items = new List<BreakdownItem>();
    Integer totalCount = 0;

    for (AggregateResult result : results) {
      Integer count = (Integer) result.get('total');
      totalCount += count;
      items.add(
        new BreakdownItem(normalizeLabel((String) result.get('label')), count)
      );
    }

    for (BreakdownItem item : items) {
      item.percentage = totalCount == 0
        ? 0
        : Decimal.valueOf(item.count * 100).divide(totalCount, 1);
    }

    return items;
  }

  private static List<TrendItem> buildDailyTrend(
    List<AggregateResult> results,
    Date startDate
  ) {
    Map<Date, Integer> countsByDate = new Map<Date, Integer>();

    for (AggregateResult result : results) {
      countsByDate.put(
        (Date) result.get('mentionDay'),
        (Integer) result.get('total')
      );
    }

    List<TrendItem> trend = new List<TrendItem>();
    for (Integer offset = 0; offset < 14; offset++) {
      Date day = startDate.addDays(offset);
      trend.add(
        new TrendItem(
          String.valueOf(day),
          countsByDate.containsKey(day) ? countsByDate.get(day) : 0
        )
      );
    }

    return trend;
  }

  private static Integer sumCounts(List<BreakdownItem> items) {
    Integer total = 0;
    for (BreakdownItem item : items) {
      total += item.count;
    }
    return total;
  }

  private static Integer countFor(List<BreakdownItem> items, String label) {
    for (BreakdownItem item : items) {
      if (item.label == label) {
        return item.count;
      }
    }
    return 0;
  }

  private static String normalizeLabel(String label) {
    return String.isBlank(label) ? 'Unknown' : label;
  }

  public class DashboardData {
    @AuraEnabled
    public Integer periodDays { get; set; }
    @AuraEnabled
    public Datetime generatedAt { get; set; }
    @AuraEnabled
    public Boolean showTrialBanner { get; set; }
    @AuraEnabled
    public Integer trialDaysRemaining { get; set; }
    @AuraEnabled
    public Integer totalMentions { get; set; }
    @AuraEnabled
    public Integer newMentions { get; set; }
    @AuraEnabled
    public Integer attentionMentions { get; set; }
    @AuraEnabled
    public Integer negativeMentions { get; set; }
    @AuraEnabled
    public List<BreakdownItem> sources { get; set; }
    @AuraEnabled
    public List<BreakdownItem> sentiments { get; set; }
    @AuraEnabled
    public List<BreakdownItem> priorities { get; set; }
    @AuraEnabled
    public List<BreakdownItem> statuses { get; set; }
    @AuraEnabled
    public List<TrendItem> dailyTrend { get; set; }
    @AuraEnabled
    public List<MentionItem> recentMentions { get; set; }
  }

  private class AwsSubscriptionStatus {
    public String companyId { get; set; }
    public String subscriptionStatus { get; set; }
    public Boolean trialActive { get; set; }
    public Integer trialDaysRemaining { get; set; }
    public String trialStartAt { get; set; }
    public String trialEndsAt { get; set; }
    public Integer trialExtensionDays { get; set; }
  }

  public class BreakdownItem {
    @AuraEnabled
    public String label { get; set; }
    @AuraEnabled
    public Integer count { get; set; }
    @AuraEnabled
    public Decimal percentage { get; set; }

    public BreakdownItem(String label, Integer count) {
      this.label = label;
      this.count = count;
    }
  }

  public class TrendItem {
    @AuraEnabled
    public String day { get; set; }
    @AuraEnabled
    public Integer count { get; set; }

    public TrendItem(String day, Integer count) {
      this.day = day;
      this.count = count;
    }
  }

  public class MentionItem {
    @AuraEnabled
    public Id id { get; set; }
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public String title { get; set; }
    @AuraEnabled
    public String source { get; set; }
    @AuraEnabled
    public String sourceUrl { get; set; }
    @AuraEnabled
    public String author { get; set; }
    @AuraEnabled
    public String sentiment { get; set; }
    @AuraEnabled
    public String priority { get; set; }
    @AuraEnabled
    public String status { get; set; }
    @AuraEnabled
    public Datetime mentionDate { get; set; }
    @AuraEnabled
    public String mentionText { get; set; }
    @AuraEnabled
    public String actionableType { get; set; }
    @AuraEnabled
    public String assignedToName { get; set; }

    public MentionItem(SocioWatch_Mention__c mention) {
      id = mention.Id;
      name = mention.Name;
      title = mention.Title__c;
      source = normalizeLabel(mention.Source__c);
      sourceUrl = mention.Source_URL__c;
      author = mention.Author_Name__c;
      sentiment = normalizeLabel(mention.Sentiment__c);
      priority = normalizeLabel(mention.Priority__c);
      status = normalizeLabel(mention.Status__c);
      mentionDate = mention.Mention_Date__c;
      mentionText = mention.Mention_Text__c;
      actionableType = mention.Actionable_Type__c;
      assignedToName = mention.Assigned_To__r?.Name;
    }
  }
}
