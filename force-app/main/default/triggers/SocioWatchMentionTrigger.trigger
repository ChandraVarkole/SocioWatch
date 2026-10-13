trigger SocioWatchMentionTrigger on SocioWatch_Mention__c(after insert) {
  SocioWatchMentionLinkService.linkNewMentions(Trigger.new);
}
