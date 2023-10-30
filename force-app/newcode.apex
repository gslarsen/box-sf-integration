// Initialize the main Map
Map<Id, List<List<Object>>> caseToEmailsAndAttachments = new Map<Id, List<List<Object>>>();

// Additional Map to hold EmailMessage Id to Case Id mapping
Map<Id, Id> emailToCaseMap = new Map<Id, Id>();

// Step 1: Get Cases and store Ids
List<Id> caseIds = new List<Id>();
for (Case c : [SELECT Id, CaseNumber, Subject, Description FROM Case WHERE ClosedDate = LAST_N_DAYS:30]) {
    caseIds.add(c.Id);
    caseToEmailsAndAttachments.put(c.Id, new List<List<Object>>{
        new List<String>{c.CaseNumber, c.Subject, c.Description}, new List<EmailMessage>(), new List<Blob>()
    });
}

// Step 2: Get Emails in bulk and store in the Map
List<EmailMessage> emails = [SELECT Id, ParentId, HasAttachment, Subject, TextBody FROM EmailMessage WHERE ParentId IN :caseIds];
List<Id> emailIds = new List<Id>();
for (EmailMessage e : emails) {
    if (caseToEmailsAndAttachments.containsKey(e.ParentId)) {
        caseToEmailsAndAttachments.get(e.ParentId)[1].add(e);
        // Populate emailToCaseMap
        emailToCaseMap.put(e.Id, e.ParentId);
    }
    if (e.HasAttachment) {
        emailIds.add(e.Id);
    }
}

// Step 3: Get ContentDocumentLinks and then the Blob data
List<Id> combinedIds = new List<Id>();
combinedIds.addAll(caseIds);
combinedIds.addAll(emailIds);

List<ContentDocumentLink> contentDocumentLinks = [SELECT ContentDocumentId, LinkedEntityId FROM ContentDocumentLink WHERE LinkedEntityId IN :combinedIds];
List<Id> contentDocumentIds = new List<Id>();
for (ContentDocumentLink cdl : contentDocumentLinks) {
    contentDocumentIds.add(cdl.ContentDocumentId);
}

// Fetch binary data from ContentVersion
Map<Id, Blob> contentIdToData = new Map<Id, Blob>();
for (ContentVersion cv : [SELECT ContentDocumentId, VersionData FROM ContentVersion WHERE ContentDocumentId IN :contentDocumentIds]) {
    contentIdToData.put(cv.ContentDocumentId, cv.VersionData);
}

// Add binary data to the main Map
for (ContentDocumentLink cdl : contentDocumentLinks) {
    Id parentCaseId = cdl.LinkedEntityId;
    // Check if the LinkedEntityId is actually an EmailMessage Id
    if(emailToCaseMap.containsKey(cdl.LinkedEntityId)) {
        parentCaseId = emailToCaseMap.get(cdl.LinkedEntityId);
    }

    if (caseToEmailsAndAttachments.containsKey(parentCaseId)) {
        Blob contentData = contentIdToData.get(cdl.ContentDocumentId);
        if (contentData != null) {
            caseToEmailsAndAttachments.get(parentCaseId)[2].add(contentData);
        }
    }
}

// Debugging and further processing
for (Id caseId : caseToEmailsAndAttachments.keySet()) {
    // ... (your existing debug and further processing code)
}

// Now caseToEmailsAndAttachments contains metadata, EmailMessages, and Blob (binary data) for each Case
for (Id caseId : caseToEmailsAndAttachments.keySet()) {
    // Access metadata
    List<String> metadata = (List<String>) caseToEmailsAndAttachments.get(caseId)[0];
    System.debug('Case Id: ' + caseId);
    System.debug('CaseNumber: ' + metadata[0]);
    System.debug('Subject: ' + metadata[1]);
    System.debug('Description: ' + metadata[2]);

    // Access EmailMessages
    List<EmailMessage> emailMessages = (List<EmailMessage>) caseToEmailsAndAttachments.get(caseId)[1];
    System.debug('Number of Emails: ' + emailMessages.size());
    for (EmailMessage e : emailMessages) {
        System.debug('Email Id: ' + e.Id);
        System.debug('Email Subject: ' + e.Subject);
        System.debug('Email TextBody: ' + e.TextBody);
        // Additional email fields can be debugged here if queried
    }

    // Access Blob data
    List<Blob> blobs = (List<Blob>) caseToEmailsAndAttachments.get(caseId)[2];
    System.debug('Number of Attachments: ' + blobs.size());
    for (Blob b : blobs) {
        System.debug('Blob Size: ' + b.size());
        // Actual Blob data can be debugged, but it may not be human-readable
    }
}