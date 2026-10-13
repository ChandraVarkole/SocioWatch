List<SocioWatch_Mention__c> mentions = [
    SELECT Id, Is_Relevant__c
    FROM SocioWatch_Mention__c
    WHERE Is_Relevant__c = false
];

for (SocioWatch_Mention__c mention : mentions) {
    mention.Is_Relevant__c = true;
}

if (!mentions.isEmpty()) {
    update mentions;
}

System.debug('Backfilled mentions: ' + mentions.size());
