import { LightningElement } from "lwc";
import LightningConfirm from "lightning/confirm";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import SOCIOWATCH_LOGO from "@salesforce/resourceUrl/SocioWatchLogoHorizontal";

import canManageSettings from "@salesforce/apex/SocioWatchSettingsController.canManageSettings";

import getSettings from "@salesforce/apex/SocioWatchSettingsController.getSettings";

import saveSettings from "@salesforce/apex/SocioWatchSettingsController.saveSettings";

import getGoogleReviewsStatus from "@salesforce/apex/SocioWatchSettingsController.getGoogleReviewsStatus";

import startSync from "@salesforce/apex/SocioWatchSyncController.startSync";

import SETTINGS_TITLE from "@salesforce/label/c.SocioWatch_Settings_Title";

import COMPANY_NAME from "@salesforce/label/c.SocioWatch_Company_Name";

import KEYWORDS from "@salesforce/label/c.SocioWatch_Keywords";

import SAVE from "@salesforce/label/c.SocioWatch_Save";

import SAVE_SUCCESS from "@salesforce/label/c.SocioWatch_Save_Success";

import SYNC_NOW from "@salesforce/label/c.SocioWatch_Sync_Now";

import SYNC_SUCCESS from "@salesforce/label/c.SocioWatch_Sync_Success";

import ACCESS_DENIED from "@salesforce/label/c.SocioWatch_Access_Denied";

import UNEXPECTED_ERROR from "@salesforce/label/c.SocioWatch_Unexpected_Error";

const MAX_KEYWORD_COUNT = 20;
const MAX_KEYWORD_LENGTH = 100;
const KEYWORD_SUGGESTION_SUFFIXES = [
  "Customer Support",
  "Products",
  "Services",
  "Reviews",
  "Complaints",
  "Offers",
  "Discounts",
  "Quality",
  "Customer Service"
];

export default class SocioWatchSettings extends LightningElement {
  logoUrl = SOCIOWATCH_LOGO;
  companyName = "";
  llmMentionKeyword = "";
  website = "";
  companyCity = "";
  companyStateProvince = "";
  companyCountry = "United States";
  autoLinkMentions = false;
  authorMatchObjectApiName = "Account";
  authorMatchFieldApiName = "Name";
  keywordsText = "";
  keywordDraft = "";
  syncEnabled = true;
  googleReviewsResolutionStatus = "";
  googleReviewsResolutionMessage = "";
  savedGoogleProfileSignature = "";

  configurationId;
  configurationNumber;
  companyId;
  tenantId;
  salesforceOrgId;
  lastSuccessfulSync;
  lastSyncStatus = "Not Started";

  hasAccess = false;
  isLoading = true;
  isSaving = false;
  isVerifyingGoogleProfile = false;
  isSyncing = false;

  labels = {
    settingsTitle: SETTINGS_TITLE,
    companyName: COMPANY_NAME,
    keywords: KEYWORDS,
    save: SAVE,
    saveSuccess: SAVE_SUCCESS,
    syncNow: SYNC_NOW,
    syncSuccess: SYNC_SUCCESS,
    accessDenied: ACCESS_DENIED,
    unexpectedError: UNEXPECTED_ERROR
  };

  connectedCallback() {
    this.initialize();
  }

  get hasSavedConfiguration() {
    return Boolean(this.configurationId);
  }

  get monitoringStatus() {
    return this.syncEnabled ? "Active" : "Disabled";
  }

  get monitoringBadgeClass() {
    return this.syncEnabled ? "status-badge" : "status-badge disabled";
  }

  get syncBadgeClass() {
    const status = (this.lastSyncStatus || "").toLowerCase();

    if (status === "failed") {
      return "sync-badge error";
    }

    if (status === "in progress" || status === "not started") {
      return "sync-badge warning";
    }

    return "sync-badge";
  }

  get keywordCount() {
    return this.parseKeywords().length;
  }

  get hasKeywords() {
    return this.keywordCount > 0;
  }

  get keywordItems() {
    return this.parseKeywords().map((keyword) => ({
      key: keyword.toLowerCase(),
      label: keyword,
      removeLabel: `Remove ${keyword}`
    }));
  }

  get isKeywordAddDisabled() {
    return this.isSaving || !this.keywordDraft.trim();
  }

  get keywordSuggestions() {
    if (!this.companyName.trim()) {
      return [];
    }

    const existingKeywords = new Set(
      this.parseKeywords().map((keyword) => keyword.toLowerCase())
    );
    const limitReached = this.keywordCount >= MAX_KEYWORD_COUNT;

    return KEYWORD_SUGGESTION_SUFFIXES.filter(
      (suggestion) => !existingKeywords.has(suggestion.toLowerCase())
    ).map((suggestion) => ({
      key: suggestion.toLowerCase(),
      label: suggestion,
      disabled: this.isSaving || limitReached
    }));
  }

  get hasKeywordSuggestions() {
    return this.keywordSuggestions.length > 0;
  }

  get isSaveDisabled() {
    return this.isLoading || this.isSaving || this.isSyncing || !this.hasAccess;
  }

  get isSyncDisabled() {
    return (
      this.isLoading ||
      this.isSaving ||
      this.isSyncing ||
      !this.hasAccess ||
      !this.configurationId ||
      !this.companyId ||
      this.googleReviewsResolutionStatus !== "RESOLVED" ||
      !this.syncEnabled
    );
  }

  get hasGoogleReviewsResolutionStatus() {
    return Boolean(this.googleReviewsResolutionStatus);
  }

  get googleProfileSignature() {
    return [
      this.companyName,
      this.website,
      this.companyCity,
      this.companyStateProvince,
      this.companyCountry
    ]
      .map((value) => (value || "").trim().toLowerCase())
      .join("|");
  }

  get googleProfileInputsChanged() {
    return this.googleProfileSignature !== this.savedGoogleProfileSignature;
  }

  get isGoogleReviewsResolutionPending() {
    return this.googleReviewsResolutionStatus === "PENDING";
  }

  get showInlineGoogleReviewsSpinner() {
    return this.isGoogleReviewsResolutionPending && !this.isSaving;
  }

  get googleReviewsStatusText() {
    if (this.googleReviewsResolutionStatus === "RESOLVED") {
      return "Google Business Profile connected.";
    }

    if (this.googleReviewsResolutionStatus === "UNRESOLVED") {
      return (
        this.googleReviewsResolutionMessage ||
        "Google Business Profile not found. Verify the company name and location."
      );
    }

    return "Checking for a matching Google Business Profile.";
  }

  get googleReviewsStatusClass() {
    if (this.googleReviewsResolutionStatus === "RESOLVED") {
      return "google-reviews-status resolved";
    }

    if (this.googleReviewsResolutionStatus === "UNRESOLVED") {
      return "google-reviews-status unresolved";
    }

    return "google-reviews-status pending";
  }

  get saveProgressAlternativeText() {
    return this.isVerifyingGoogleProfile
      ? "Saving settings and verifying Google Business Profile"
      : "Saving settings";
  }

  get saveProgressTitle() {
    return this.isVerifyingGoogleProfile
      ? "Verifying Google Business Profile"
      : "Saving settings";
  }

  get saveProgressMessage() {
    return this.isVerifyingGoogleProfile
      ? "Matching the company name and location with Google."
      : "Your changes are being saved.";
  }

  async initialize() {
    this.isLoading = true;

    try {
      this.hasAccess = await canManageSettings();

      if (!this.hasAccess) {
        return;
      }

      const settings = await getSettings();
      this.applySettings(settings);

      if (this.companyId) {
        await this.refreshGoogleReviewsStatus();
      }
    } catch (error) {
      this.hasAccess = false;
      this.showError(error);
    } finally {
      this.isLoading = false;
    }
  }

  applySettings(settings) {
    if (!settings) {
      return;
    }

    this.configurationId = settings.configurationId;
    this.configurationNumber = settings.configurationNumber;
    this.companyName = settings.companyName || "";
    this.llmMentionKeyword =
      settings.llmMentionKeyword || settings.companyName || "";
    this.website = settings.website || "";
    this.companyCity = settings.companyCity || "";
    this.companyStateProvince = settings.companyStateProvince || "";
    this.companyCountry = settings.companyCountry || "United States";
    this.autoLinkMentions = settings.autoLinkMentions === true;
    this.authorMatchObjectApiName =
      settings.authorMatchObjectApiName || "Account";
    this.authorMatchFieldApiName = settings.authorMatchFieldApiName || "Name";
    this.syncEnabled = settings.syncEnabled !== false;
    this.companyId = settings.companyId;
    this.tenantId = settings.tenantId;
    this.salesforceOrgId = settings.salesforceOrgId;
    this.lastSuccessfulSync = settings.lastSuccessfulSync;
    this.lastSyncStatus = settings.lastSyncStatus || "Not Started";

    if (settings.googleReviewsResolutionStatus) {
      this.googleReviewsResolutionStatus =
        settings.googleReviewsResolutionStatus.toUpperCase();
    }

    if (settings.googleReviewsResolutionMessage) {
      this.googleReviewsResolutionMessage =
        settings.googleReviewsResolutionMessage;
    }

    this.keywordsText = Array.isArray(settings.keywords)
      ? settings.keywords
          .map((keyword) => this.toDisplayKeyword(keyword))
          .filter(Boolean)
          .join("\n")
      : "";
    this.keywordDraft = "";
    this.savedGoogleProfileSignature = this.googleProfileSignature;
  }

  handleCompanyNameChange(event) {
    const previousCompanyName = this.companyName.trim();

    this.companyName = event.target.value;

    if (
      !this.llmMentionKeyword.trim() ||
      this.llmMentionKeyword.trim() === previousCompanyName
    ) {
      this.llmMentionKeyword = event.target.value;
    }
  }

  handleLlmMentionKeywordChange(event) {
    this.llmMentionKeyword = event.target.value;
  }

  handleWebsiteChange(event) {
    this.website = event.target.value;
  }

  handleCompanyCityChange(event) {
    this.companyCity = event.target.value;
  }

  handleCompanyStateProvinceChange(event) {
    this.companyStateProvince = event.target.value;
  }

  handleCompanyCountryChange(event) {
    this.companyCountry = event.target.value;
  }

  handleAutoLinkMentionsChange(event) {
    this.autoLinkMentions = event.target.checked;
  }

  handleAuthorMatchObjectChange(event) {
    this.authorMatchObjectApiName = event.target.value;
  }

  handleAuthorMatchFieldChange(event) {
    this.authorMatchFieldApiName = event.target.value;
  }

  handleKeywordDraftChange(event) {
    this.keywordDraft = event.target.value;
    this.setKeywordsError("");
  }

  handleKeywordKeyDown(event) {
    if (event.key === "Enter") {
      event.preventDefault();
      this.commitKeywordDraft();
    }
  }

  handleAddKeyword() {
    this.commitKeywordDraft();
  }

  handleAddSuggestion(event) {
    this.keywordDraft = event.currentTarget.dataset.keyword;
    this.commitKeywordDraft();
  }

  handleRemoveKeyword(event) {
    const keywordToRemove = event.currentTarget.dataset.keyword;

    this.keywordsText = this.parseKeywords()
      .filter((keyword) => keyword !== keywordToRemove)
      .join("\n");
    this.setKeywordsError("");
  }

  commitKeywordDraft() {
    if (!this.keywordDraft.trim()) {
      return true;
    }

    const keywords = this.parseKeywords(
      `${this.keywordsText}\n${this.keywordDraft}`
    );

    if (keywords.length > MAX_KEYWORD_COUNT) {
      this.setKeywordsError(
        `You can configure up to ${MAX_KEYWORD_COUNT} keywords.`
      );
      return false;
    }

    const longKeyword = keywords.find(
      (keyword) => this.toStoredKeyword(keyword).length > MAX_KEYWORD_LENGTH
    );

    if (longKeyword) {
      this.setKeywordsError(
        `Each keyword must contain no more than ` +
          `${MAX_KEYWORD_LENGTH} characters.`
      );
      return false;
    }

    this.keywordsText = keywords.join("\n");
    this.keywordDraft = "";
    this.setKeywordsError("");
    return true;
  }

  handleSyncEnabledChange(event) {
    this.syncEnabled = event.target.checked;
  }

  async handleSave() {
    if (!this.commitKeywordDraft()) {
      return;
    }

    if (!this.validateForm()) {
      return;
    }

    const shouldVerifyGoogleProfile = this.googleProfileInputsChanged;

    this.isVerifyingGoogleProfile = shouldVerifyGoogleProfile;
    this.isSaving = true;

    try {
      const request = {
        companyName: this.companyName.trim(),
        llmMentionKeyword: this.llmMentionKeyword.trim(),
        website: this.website.trim(),
        companyCity: this.companyCity.trim(),
        companyStateProvince: this.companyStateProvince.trim(),
        companyCountry: this.companyCountry.trim(),
        googleReviewsEnabled: true,
        autoLinkMentions: this.autoLinkMentions,
        authorMatchObjectApiName: this.authorMatchObjectApiName.trim(),
        authorMatchFieldApiName: this.authorMatchFieldApiName.trim(),
        keywords: this.parseKeywords().map((keyword) =>
          this.toStoredKeyword(keyword)
        ),
        syncEnabled: this.syncEnabled
      };

      const savedSettings = await saveSettings({
        request
      });

      this.applySettings(savedSettings);

      if (!shouldVerifyGoogleProfile) {
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Success",
            message: savedSettings?.message || this.labels.saveSuccess,
            variant: "success"
          })
        );
        return;
      }

      const resolutionStatus = await this.waitForGoogleReviewsResolution();

      if (resolutionStatus !== "RESOLVED") {
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Google Business Profile not found",
            message:
              this.googleReviewsResolutionMessage ||
              "Update the company name to exactly match the Google Business Profile and verify the location, then save again.",
            variant: "error",
            mode: "dismissible"
          })
        );
        return;
      }

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Success",
          message: savedSettings?.message || this.labels.saveSuccess,
          variant: "success"
        })
      );
    } catch (error) {
      this.showError(error);
    } finally {
      this.isSaving = false;
      this.isVerifyingGoogleProfile = false;
    }
  }

  async refreshGoogleReviewsStatus() {
    const status = await getGoogleReviewsStatus({
      companyId: this.companyId
    });

    this.googleReviewsResolutionStatus = (
      status?.googleReviewsResolutionStatus || "PENDING"
    ).toUpperCase();
    this.googleReviewsResolutionMessage =
      status?.googleReviewsResolutionMessage ||
      "Checking for a matching Google Business Profile.";

    return this.googleReviewsResolutionStatus;
  }

  async waitForGoogleReviewsResolution() {
    /* eslint-disable no-await-in-loop, @lwc/lwc/no-async-operation --
     * Resolution runs asynchronously in AWS. Polling keeps the user on the
     * Settings page until the profile is resolved or needs correction.
     */
    for (let attempt = 0; attempt < 30; attempt += 1) {
      const status = await this.refreshGoogleReviewsStatus();

      if (status === "RESOLVED" || status === "UNRESOLVED") {
        return status;
      }

      await new Promise((resolve) => setTimeout(resolve, 3000));
    }
    /* eslint-enable no-await-in-loop, @lwc/lwc/no-async-operation */

    this.googleReviewsResolutionStatus = "PENDING";
    this.googleReviewsResolutionMessage =
      "Google Business Profile matching is still running. Please try again shortly.";
    return "PENDING";
  }

  async handleSync() {
    if (this.lastSuccessfulSync) {
      const confirmed = await LightningConfirm.open({
        label: "Are you sure?",
        message:
          "A scheduled job already imports mentions automatically. Sync Now requests an immediate collection and imports any mentions currently available. New mentions will be processed and inserted as they become available. Continue?",
        theme: "warning"
      });

      if (!confirmed) {
        return;
      }
    }

    this.isSyncing = true;

    try {
      await startSync();

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Sync requested",
          message: this.labels.syncSuccess,
          variant: "info"
        })
      );

      this.lastSyncStatus = "In Progress";
    } catch (error) {
      this.showError(error);
    } finally {
      this.isSyncing = false;
    }
  }

  validateForm() {
    const inputComponents = [
      ...this.template.querySelectorAll("lightning-input, lightning-textarea")
    ];

    const baseFieldsValid = inputComponents.reduce(
      (isValid, inputComponent) => {
        inputComponent.reportValidity();

        return isValid && inputComponent.checkValidity();
      },
      true
    );

    if (!baseFieldsValid) {
      return false;
    }

    const keywords = this.parseKeywords();

    if (keywords.length === 0) {
      this.setKeywordsError("Enter at least one keyword.");

      return false;
    }

    if (keywords.length > MAX_KEYWORD_COUNT) {
      this.setKeywordsError(
        `You can configure up to ${MAX_KEYWORD_COUNT} keywords.`
      );

      return false;
    }

    const longKeyword = keywords.find(
      (keyword) => this.toStoredKeyword(keyword).length > MAX_KEYWORD_LENGTH
    );

    if (longKeyword) {
      this.setKeywordsError(
        `Each keyword must contain no more than ` +
          `${MAX_KEYWORD_LENGTH} characters.`
      );

      return false;
    }

    this.setKeywordsError("");

    return true;
  }

  parseKeywords(sourceText = this.keywordsText) {
    const rawValues = (sourceText || "")
      .replace(/\r\n/g, "\n")
      .replace(/\r/g, "\n")
      .replace(/,/g, "\n")
      .split("\n");

    const uniqueKeywords = [];
    const normalizedKeys = new Set();

    rawValues.forEach((rawValue) => {
      const keyword = rawValue.trim().replace(/\s+/g, " ");

      if (!keyword) {
        return;
      }

      const duplicateKey = keyword.toLowerCase();

      if (!normalizedKeys.has(duplicateKey)) {
        normalizedKeys.add(duplicateKey);
        uniqueKeywords.push(keyword);
      }
    });

    return uniqueKeywords;
  }

  toDisplayKeyword(keyword) {
    const normalizedKeyword = (keyword || "").trim();
    const company = this.companyName.trim();
    const companyPrefix = `${company} `;

    if (
      company &&
      normalizedKeyword.toLowerCase().startsWith(companyPrefix.toLowerCase())
    ) {
      return normalizedKeyword.slice(companyPrefix.length).trim();
    }

    return normalizedKeyword;
  }

  toStoredKeyword(keyword) {
    const normalizedKeyword = (keyword || "").trim();
    const company = this.companyName.trim();
    const normalizedCompany = company.toLowerCase();
    const normalizedValue = normalizedKeyword.toLowerCase();

    if (
      !company ||
      !normalizedKeyword ||
      normalizedValue === normalizedCompany ||
      normalizedValue.startsWith(`${normalizedCompany} `)
    ) {
      return normalizedKeyword;
    }

    return `${company} ${normalizedKeyword}`;
  }

  setKeywordsError(message) {
    const keywordsInput = this.template.querySelector(
      '[data-field="keywords"]'
    );

    if (!keywordsInput) {
      return;
    }

    keywordsInput.setCustomValidity(message);
    keywordsInput.reportValidity();
  }

  showError(error) {
    const message = this.extractSafeErrorMessage(error);

    this.dispatchEvent(
      new ShowToastEvent({
        title: "SocioWatch Error",
        message,
        variant: "error",
        mode: "sticky"
      })
    );
  }

  extractSafeErrorMessage(error) {
    const serverMessage = error?.body?.message;

    if (typeof serverMessage === "string" && serverMessage.trim()) {
      return serverMessage;
    }

    const clientMessage = error?.message;

    if (typeof clientMessage === "string" && clientMessage.trim()) {
      return clientMessage;
    }

    return this.labels.unexpectedError;
  }
}
