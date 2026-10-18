import { LightningElement, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { refreshApex } from "@salesforce/apex";
import LightningConfirm from "lightning/confirm";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getDashboard from "@salesforce/apex/SocioWatchDashboardController.getDashboard";
import getMetaOfferStatus from "@salesforce/apex/SocioWatchMetaController.getOfferStatus";
import markNotRelevant from "@salesforce/apex/SocioWatchMentionFeedbackController.markNotRelevant";
import SOCIOWATCH_LOGO from "@salesforce/resourceUrl/SocioWatchLogoHorizontal";
import USER_ID from "@salesforce/user/Id";

const META_ADD_ON_PREFERENCE_KEY = `sociowatch-meta-addon-offer-${USER_ID}`;
const ONE_WEEK_IN_MILLISECONDS = 7 * 24 * 60 * 60 * 1000;

const SOURCE_VISUALS = {
  x: { symbol: "X", className: "source-badge source-x" },
  youtube: { symbol: "▶", className: "source-badge source-youtube" },
  news: { symbol: "N", className: "source-badge source-news" },
  forum: { symbol: "F", className: "source-badge source-forum" },
  review: { symbol: "★", className: "source-badge source-review" }
};

const SENTIMENT_COLORS = {
  positive: "#1f9d74",
  neutral: "#6d5ce7",
  negative: "#df4b5f",
  mixed: "#ed9b31",
  unknown: "#a8b0bd"
};

export default class SocioWatchOverview extends NavigationMixin(
  LightningElement
) {
  logoUrl = SOCIOWATCH_LOGO;
  days = 30;
  dashboard;
  wiredResult;
  errorMessage;
  isRefreshing = false;
  feedbackMentionId;
  metaOfferStatus;
  metaOfferHidden = false;

  periodOptions = [
    { label: "Last 7 days", value: "7" },
    { label: "Last 30 days", value: "30" },
    { label: "Last 90 days", value: "90" },
    { label: "All time", value: "0" }
  ];

  connectedCallback() {
    this.loadMetaOfferPreference();
    this.loadMetaOfferStatus();
  }

  @wire(getDashboard, { days: "$days" })
  wiredDashboard(result) {
    this.wiredResult = result;
    const { data, error } = result;

    if (data) {
      this.dashboard = this.enrichDashboard(data);
      this.errorMessage = undefined;
    } else if (error) {
      this.dashboard = undefined;
      this.errorMessage = this.extractError(error);
    }
  }

  get selectedPeriod() {
    return String(this.days);
  }

  get isLoading() {
    return !this.dashboard && !this.errorMessage;
  }

  get isFeedbackUpdating() {
    return Boolean(this.feedbackMentionId);
  }

  get showTrialBanner() {
    return this.dashboard?.showTrialBanner !== false;
  }

  get showMetaAddOnBanner() {
    return this.metaOfferStatus === "ADD_ON_REQUIRED" && !this.metaOfferHidden;
  }

  get trialDaysRemaining() {
    return Number(this.dashboard?.trialDaysRemaining ?? 0);
  }

  get trialIsActive() {
    return this.trialDaysRemaining > 0;
  }

  get trialDayLabel() {
    return this.trialDaysRemaining === 1 ? "day" : "days";
  }

  get hasMentions() {
    return (this.dashboard?.totalMentions || 0) > 0;
  }

  get totalMentions() {
    return this.dashboard?.totalMentions || 0;
  }

  get newMentions() {
    return this.dashboard?.newMentions || 0;
  }

  get attentionMentions() {
    return this.dashboard?.attentionMentions || 0;
  }

  get negativeMentions() {
    return this.dashboard?.negativeMentions || 0;
  }

  get sources() {
    return this.dashboard?.sources || [];
  }

  get sentiments() {
    return this.dashboard?.sentiments || [];
  }

  get dailyTrend() {
    return this.dashboard?.dailyTrend || [];
  }

  get recentMentions() {
    return this.dashboard?.recentMentions || [];
  }

  get sentimentRingStyle() {
    if (!this.hasMentions) {
      return "background: #e9edf3";
    }

    let current = 0;
    const segments = this.sentiments.map((item) => {
      const start = current;
      current += Number(item.percentage || 0);
      const color =
        SENTIMENT_COLORS[item.label.toLowerCase()] || SENTIMENT_COLORS.unknown;
      return `${color} ${start}% ${current}%`;
    });

    if (current < 100) {
      segments.push(`#e9edf3 ${current}% 100%`);
    }

    return `background: conic-gradient(${segments.join(", ")})`;
  }

  handlePeriodChange(event) {
    this.days = Number(event.detail.value);
  }

  async handleRefresh() {
    this.isRefreshing = true;
    try {
      await refreshApex(this.wiredResult);
    } finally {
      this.isRefreshing = false;
    }
  }

  handleRemindMetaAddOn() {
    this.saveMetaOfferPreference({
      remindAfter: Date.now() + ONE_WEEK_IN_MILLISECONDS
    });
    this.metaOfferHidden = true;
  }

  handleDismissMetaAddOn() {
    this.saveMetaOfferPreference({ dismissed: true });
    this.metaOfferHidden = true;
  }

  openAllMentions() {
    this[NavigationMixin.Navigate]({
      type: "standard__objectPage",
      attributes: {
        objectApiName: "SocioWatch_Mention__c",
        actionName: "list"
      },
      state: {
        filterName: "All_Mentions"
      }
    });
  }

  openMention(event) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: event.currentTarget.dataset.id,
        objectApiName: "SocioWatch_Mention__c",
        actionName: "view"
      }
    });
  }

  async markMentionNotRelevant(event) {
    const mentionId = event.currentTarget.dataset.id;
    const confirmed = await LightningConfirm.open({
      label: "Mark mention as not relevant?",
      message:
        "This mention will be removed from SocioWatch views and excluded from future analysis.",
      theme: "warning"
    });

    if (!confirmed) {
      return;
    }

    this.feedbackMentionId = mentionId;

    try {
      await markNotRelevant({ mentionId });
      await refreshApex(this.wiredResult);

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Mention removed",
          message: "The mention was marked as not relevant.",
          variant: "success"
        })
      );
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Unable to update mention",
          message: this.extractError(error),
          variant: "error"
        })
      );
    } finally {
      this.feedbackMentionId = undefined;
    }
  }

  enrichDashboard(data) {
    const sourceItems = (data.sources || []).map((item) => {
      const visual = this.getSourceVisual(item.label);
      return {
        ...item,
        badgeClass: visual.className,
        symbol: visual.symbol,
        barStyle: `width: ${Math.max(item.percentage, 2)}%`
      };
    });

    const sentimentItems = (data.sentiments || []).map((item) => ({
      ...item,
      dotStyle: `background: ${
        SENTIMENT_COLORS[item.label.toLowerCase()] || SENTIMENT_COLORS.unknown
      }`
    }));

    const maxDailyCount = Math.max(
      ...(data.dailyTrend || []).map((item) => item.count),
      1
    );
    const dailyItems = (data.dailyTrend || []).map((item, index) => ({
      ...item,
      barStyle: `height: ${Math.max((item.count / maxDailyCount) * 100, 4)}%`,
      dayLabel: this.formatDay(item.day),
      showLabel: index === 0 || index === 6 || index === 13
    }));

    const mentionItems = (data.recentMentions || []).map((mention) => {
      const visual = this.getSourceVisual(mention.source);
      return {
        ...mention,
        displayTitle: mention.title || `${mention.source} mention`,
        excerpt: this.truncate(mention.mentionText, 170),
        hasExcerpt: Boolean(mention.mentionText),
        hasSourceUrl: Boolean(mention.sourceUrl),
        badgeClass: visual.className,
        symbol: visual.symbol,
        sentimentClass: `tag sentiment-${mention.sentiment.toLowerCase()}`,
        priorityClass: `tag priority-${mention.priority.toLowerCase()}`
      };
    });

    return {
      ...data,
      sources: sourceItems,
      sentiments: sentimentItems,
      dailyTrend: dailyItems,
      recentMentions: mentionItems
    };
  }

  getSourceVisual(source) {
    const key = (source || "web").toLowerCase();
    return (
      SOURCE_VISUALS[key] || {
        symbol: key.charAt(0).toUpperCase() || "W",
        className: "source-badge source-other"
      }
    );
  }

  formatDay(value) {
    const [year, month, day] = value.split("-").map(Number);
    return new Intl.DateTimeFormat("en-US", {
      month: "short",
      day: "numeric"
    }).format(new Date(year, month - 1, day));
  }

  truncate(value, length) {
    if (!value || value.length <= length) {
      return value;
    }
    return `${value.slice(0, length).trim()}…`;
  }

  async loadMetaOfferStatus() {
    try {
      this.metaOfferStatus = await getMetaOfferStatus();
    } catch {
      // The add-on offer must never prevent the Overview from loading.
      this.metaOfferStatus = undefined;
    }
  }

  loadMetaOfferPreference() {
    try {
      const storedValue = window.localStorage.getItem(
        META_ADD_ON_PREFERENCE_KEY
      );
      if (!storedValue) {
        return;
      }

      const preference = JSON.parse(storedValue);
      if (
        preference.dismissed === true ||
        Number(preference.remindAfter || 0) > Date.now()
      ) {
        this.metaOfferHidden = true;
      } else {
        window.localStorage.removeItem(META_ADD_ON_PREFERENCE_KEY);
      }
    } catch {
      this.metaOfferHidden = false;
    }
  }

  saveMetaOfferPreference(preference) {
    try {
      window.localStorage.setItem(
        META_ADD_ON_PREFERENCE_KEY,
        JSON.stringify(preference)
      );
    } catch {
      // Hiding still works for the current page when storage is unavailable.
    }
  }

  extractError(error) {
    return (
      error?.body?.message ||
      error?.message ||
      "The overview could not be loaded."
    );
  }
}
