import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import canManageSettings from
    '@salesforce/apex/SocioWatchSettingsController.canManageSettings';

import getSettings from
    '@salesforce/apex/SocioWatchSettingsController.getSettings';

import saveSettings from
    '@salesforce/apex/SocioWatchSettingsController.saveSettings';

import SETTINGS_TITLE from
    '@salesforce/label/c.SocioWatch_Settings_Title';

import SETTINGS_DESCRIPTION from
    '@salesforce/label/c.SocioWatch_Settings_Description';

import COMPANY_NAME from
    '@salesforce/label/c.SocioWatch_Company_Name';

import KEYWORDS from
    '@salesforce/label/c.SocioWatch_Keywords';

import ALERT_ID from
    '@salesforce/label/c.SocioWatch_Alert_Id';

import SYNC_ENABLED from
    '@salesforce/label/c.SocioWatch_Sync_Enabled';

import SAVE from
    '@salesforce/label/c.SocioWatch_Save';

import SAVE_SUCCESS from
    '@salesforce/label/c.SocioWatch_Save_Success';

import ACCESS_DENIED from
    '@salesforce/label/c.SocioWatch_Access_Denied';

import UNEXPECTED_ERROR from
    '@salesforce/label/c.SocioWatch_Unexpected_Error';

const MAX_KEYWORD_COUNT = 20;
const MAX_KEYWORD_LENGTH = 100;

export default class SocioWatchSettings extends LightningElement {
    companyName = '';
    keywordsText = '';
    alertId = '';
    syncEnabled = true;

    configurationId;
    configurationNumber;
    companyId;
    tenantId;
    salesforceOrgId;
    lastSuccessfulSync;
    lastSyncStatus = 'Not Started';

    hasAccess = false;
    isLoading = true;
    isSaving = false;

    labels = {
        settingsTitle: SETTINGS_TITLE,
        settingsDescription: SETTINGS_DESCRIPTION,
        companyName: COMPANY_NAME,
        keywords: KEYWORDS,
        alertId: ALERT_ID,
        syncEnabled: SYNC_ENABLED,
        save: SAVE,
        saveSuccess: SAVE_SUCCESS,
        accessDenied: ACCESS_DENIED,
        unexpectedError: UNEXPECTED_ERROR
    };

    connectedCallback() {
        this.initialize();
    }

    get hasSavedConfiguration() {
        return Boolean(this.configurationId);
    }

    get isSaveDisabled() {
        return this.isLoading || this.isSaving || !this.hasAccess;
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
        this.companyName = settings.companyName || '';
        this.alertId = settings.alertId || '';
        this.syncEnabled = settings.syncEnabled !== false;
        this.companyId = settings.companyId;
        this.tenantId = settings.tenantId;
        this.salesforceOrgId = settings.salesforceOrgId;
        this.lastSuccessfulSync = settings.lastSuccessfulSync;
        this.lastSyncStatus =
            settings.lastSyncStatus || 'Not Started';

        this.keywordsText = Array.isArray(settings.keywords)
            ? settings.keywords.join('\n')
            : '';
    }

    handleCompanyNameChange(event) {
        this.companyName = event.target.value;
    }

    handleKeywordsChange(event) {
        this.keywordsText = event.target.value;
    }

    handleAlertIdChange(event) {
        this.alertId = event.target.value;
    }

    handleSyncEnabledChange(event) {
        this.syncEnabled = event.target.checked;
    }

    async handleSave() {
        if (!this.validateForm()) {
            return;
        }

        this.isSaving = true;

        try {
            const request = {
                companyName: this.companyName.trim(),
                keywords: this.parseKeywords(),
                alertId: this.alertId.trim(),
                syncEnabled: this.syncEnabled
            };

            const savedSettings = await saveSettings({
                request
            });

            this.applySettings(savedSettings);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message:
                        savedSettings?.message ||
                        this.labels.saveSuccess,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.showError(error);
        } finally {
            this.isSaving = false;
        }
    }

    validateForm() {
        const inputComponents = [
            ...this.template.querySelectorAll(
                'lightning-input, lightning-textarea'
            )
        ];

        const baseFieldsValid = inputComponents.reduce(
            (isValid, inputComponent) => {
                inputComponent.reportValidity();

                return isValid &&
                    inputComponent.checkValidity();
            },
            true
        );

        if (!baseFieldsValid) {
            return false;
        }

        const keywords = this.parseKeywords();

        if (keywords.length === 0) {
            this.setKeywordsError(
                'Enter at least one keyword.'
            );

            return false;
        }

        if (keywords.length > MAX_KEYWORD_COUNT) {
            this.setKeywordsError(
                `You can configure up to ${MAX_KEYWORD_COUNT} keywords.`
            );

            return false;
        }

        const longKeyword = keywords.find(
            (keyword) =>
                keyword.length > MAX_KEYWORD_LENGTH
        );

        if (longKeyword) {
            this.setKeywordsError(
                `Each keyword must contain no more than ` +
                `${MAX_KEYWORD_LENGTH} characters.`
            );

            return false;
        }

        this.setKeywordsError('');

        return true;
    }

    parseKeywords() {
        const rawValues = (this.keywordsText || '')
            .replace(/\r\n/g, '\n')
            .replace(/\r/g, '\n')
            .replace(/,/g, '\n')
            .split('\n');

        const uniqueKeywords = [];
        const normalizedKeys = new Set();

        rawValues.forEach((rawValue) => {
            const keyword = rawValue
                .trim()
                .replace(/\s+/g, ' ');

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
                title: 'SocioWatch Error',
                message,
                variant: 'error',
                mode: 'sticky'
            })
        );
    }

    extractSafeErrorMessage(error) {
        const serverMessage = error?.body?.message;

        if (
            typeof serverMessage === 'string' &&
            serverMessage.trim()
        ) {
            return serverMessage;
        }

        const clientMessage = error?.message;

        if (
            typeof clientMessage === 'string' &&
            clientMessage.trim()
        ) {
            return clientMessage;
        }

        return this.labels.unexpectedError;
    }
}
