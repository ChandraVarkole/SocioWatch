import { LightningElement } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import SOCIOWATCH_LOGO from "@salesforce/resourceUrl/SocioWatchLogoHorizontal";

import askQuestion from "@salesforce/apex/SocioWatchChatController.askQuestion";

import CHAT_TITLE from "@salesforce/label/c.SocioWatch_Chat_Title";

import CHAT_PLACEHOLDER from "@salesforce/label/c.SocioWatch_Chat_Placeholder";

import UNEXPECTED_ERROR from "@salesforce/label/c.SocioWatch_Unexpected_Error";

const MAX_HISTORY_MESSAGES = 10;

export default class SocioWatchChat extends LightningElement {
  logoUrl = SOCIOWATCH_LOGO;
  question = "";
  messages = [];
  isLoading = false;
  messageSequence = 0;
  renderedMessageSequence = 0;

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

  get isNewConversationDisabled() {
    return this.isLoading || !this.hasMessages;
  }

  handleQuestionChange(event) {
    this.question = event.target.value;
  }

  handleSuggestion(event) {
    this.question = event.currentTarget.dataset.question;
    this.handleAsk();
  }

  handleComposerKeyDown(event) {
    if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
      event.preventDefault();
      this.handleAsk();
    }
  }

  renderedCallback() {
    if (this.renderedMessageSequence === this.messageSequence) {
      return;
    }

    this.renderedMessageSequence = this.messageSequence;

    const messageContainer = this.template.querySelector(".messages");

    if (messageContainer) {
      messageContainer.scrollTop = messageContainer.scrollHeight;
    }
  }

  async handleAsk() {
    const submittedQuestion = this.question.trim();

    if (!submittedQuestion) {
      return;
    }

    // History contains only messages that existed
    // before the current question.
    const history = this.buildHistory();

    const userMessageId = this.addMessage(
      "You",
      "user",
      submittedQuestion,
      "message user-message"
    );

    this.question = "";
    this.isLoading = true;

    try {
      const answer = await askQuestion({
        question: submittedQuestion,
        historyJson: JSON.stringify(history)
      });

      this.addMessage(
        "SocioWatch",
        "assistant",
        answer,
        "message assistant-message"
      );
    } catch (error) {
      // Keep the failed question visible, but do not
      // include it in later conversation history.
      this.excludeMessageFromHistory(userMessageId);

      this.dispatchEvent(
        new ShowToastEvent({
          title: "SocioWatch Error",
          message: error?.body?.message || this.labels.unexpectedError,
          variant: "error",
          mode: "sticky"
        })
      );
    } finally {
      this.isLoading = false;
    }
  }

  buildHistory() {
    return this.messages
      .filter((message) => message.includeInHistory)
      .slice(-MAX_HISTORY_MESSAGES)
      .map((message) => ({
        role: message.role,
        text: message.text
      }));
  }

  handleNewConversation() {
    this.question = "";
    this.messages = [];
    this.messageSequence = 0;
    this.renderedMessageSequence = 0;
  }

  addMessage(sender, role, text, cssClass) {
    this.messageSequence += 1;

    const messageId = this.messageSequence;

    this.messages = [
      ...this.messages,
      {
        id: messageId,
        sender,
        role,
        text,
        cssClass,
        avatar: role === "assistant" ? "SW" : "You",
        avatarClass:
          role === "assistant"
            ? "message-avatar assistant-avatar"
            : "message-avatar user-avatar",
        timeLabel: new Intl.DateTimeFormat("en-US", {
          hour: "numeric",
          minute: "2-digit"
        }).format(new Date()),
        includeInHistory: true
      }
    ];

    return messageId;
  }

  excludeMessageFromHistory(messageId) {
    this.messages = this.messages.map((message) => {
      if (message.id !== messageId) {
        return message;
      }

      return {
        ...message,
        includeInHistory: false
      };
    });
  }
}
