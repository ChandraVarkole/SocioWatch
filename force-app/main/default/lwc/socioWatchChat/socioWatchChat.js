import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import askQuestion from
    '@salesforce/apex/SocioWatchChatController.askQuestion';

import CHAT_TITLE from
    '@salesforce/label/c.SocioWatch_Chat_Title';

import CHAT_PLACEHOLDER from
    '@salesforce/label/c.SocioWatch_Chat_Placeholder';

import UNEXPECTED_ERROR from
    '@salesforce/label/c.SocioWatch_Unexpected_Error';

export default class SocioWatchChat extends LightningElement {
    question = '';
    messages = [];
    isLoading = false;
    messageSequence = 0;

    labels = {
        title: CHAT_TITLE,
        placeholder: CHAT_PLACEHOLDER,
        unexpectedError: UNEXPECTED_ERROR
    };

    get hasMessages() {
        return this.messages.length > 0;
    }

    get isAskDisabled() {
        return this.isLoading || !this.question.trim();
    }

    handleQuestionChange(event) {
        this.question = event.target.value;
    }

    async handleAsk() {
        const submittedQuestion = this.question.trim();

        if (!submittedQuestion) {
            return;
        }

        this.addMessage(
            'You',
            submittedQuestion,
            'message user-message'
        );

        this.question = '';
        this.isLoading = true;

        try {
            const answer = await askQuestion({
                question: submittedQuestion
            });

            this.addMessage(
                'SocioWatch',
                answer,
                'message assistant-message'
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'SocioWatch Error',
                    message:
                        error?.body?.message ||
                        this.labels.unexpectedError,
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }

    addMessage(sender, text, cssClass) {
        this.messageSequence += 1;

        this.messages = [
            ...this.messages,
            {
                id: this.messageSequence,
                sender,
                text,
                cssClass
            }
        ];
    }
}
