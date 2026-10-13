import { api, LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import LightningConfirm from "lightning/confirm";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import markNotRelevant from "@salesforce/apex/SocioWatchMentionFeedbackController.markNotRelevant";

export default class SocioWatchMarkNotRelevant extends NavigationMixin(
  LightningElement
) {
  @api recordId;
  isRunning = false;

  @api
  async invoke() {
    if (this.isRunning) {
      return;
    }

    const confirmed = await LightningConfirm.open({
      label: "Mark mention as not relevant?",
      message:
        "This mention will be removed from SocioWatch views and excluded from future analysis.",
      theme: "warning"
    });

    if (!confirmed) {
      return;
    }

    this.isRunning = true;

    try {
      await markNotRelevant({ mentionId: this.recordId });

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Mention removed",
          message: "The mention was marked as not relevant.",
          variant: "success"
        })
      );

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
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Unable to update mention",
          message:
            error?.body?.message ||
            error?.message ||
            "The mention could not be updated.",
          variant: "error"
        })
      );
    } finally {
      this.isRunning = false;
    }
  }
}
