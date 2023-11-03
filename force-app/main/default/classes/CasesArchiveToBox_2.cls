public with sharing class CasesArchiveToBox {
    private static final String ACCOUNTS_FOLDER = '232841054083'; // change these to applicable Box folder IDs
    private static final String CONTACTS_FOLDER = '232841229558'; 
    private static final Integer DAYS = 60; // how many days back to look for cases; NOTE: change SOQL in fetchCasesAndMetadata() to be < LAST_N_DAYS:DAYS
    private static Map<Id, List<Object>> caseToEmailsAndAttachments = new Map<Id, List<Object>>();
    
    // @future(callout=true)
    public static void archiveCases() {
        fetchCasesAndMetadata();
        if (caseToEmailsAndAttachments.isEmpty()) {
            System.debug('No cases found-returning');
            return;
        }
        
        List<Id> caseIds = new List<Id>(caseToEmailsAndAttachments.keySet());
        Map<Id, Id> emailToCaseMap = new Map<Id, Id>();
        List<Id> emailIds = fetchEmails(caseIds, emailToCaseMap);
        List<Id> combinedIds = new List<Id>();
        combinedIds.addAll(caseIds);
        combinedIds.addAll(emailIds);
        
        fetchAttachments(combinedIds, emailToCaseMap);
        fetchComments(caseIds);
        sendToBox();
    }

    // Case IDs and initial metadata
    private static void fetchCasesAndMetadata() {

        if (Schema.sObjectType.Case.isAccessible()) {
            String query = 'SELECT Id, CaseNumber, Subject, Description, ClosedDate, CreatedDate, CreatedById, LastModifiedById, Origin, AccountId, Account.Name, ContactId, Contact.Name, OwnerId, Owner.Name, Status, Priority, Reason, Type, SuppliedEmail, SuppliedCompany, SuppliedName, SuppliedPhone FROM Case WHERE ClosedDate = LAST_N_DAYS:' + DAYS;
            List<Case> cases = Database.query(query);
            if (cases.isEmpty()) {
                System.debug('No cases found-returning');
            }
            for (Case c : cases) {
                caseToEmailsAndAttachments.put(c.Id, new List<Object> {
                    new Map<String, String>{
                        'caseNumber' => c.CaseNumber, 
                        'subject' => c.Subject, 
                        'description' => c.Description, 
                        'closedDate' => String.valueOf(c.ClosedDate), 
                        'createdDate' => String.valueOf(c.CreatedDate),
                        'origin' => c.Origin, 
                        'accountId' => c.AccountId, 
                        'accountName' => c.Account.Name, 
                        'contactId' => c.ContactId, 
                        'contactName' => c.Contact.Name, 
                        'ownerId' => c.OwnerId, 
                        'ownerName' => c.Owner.Name, 
                        'lastModifiedById' => c.LastModifiedById,
                        'createdById' => c.CreatedById,
                        'status' => c.Status, 
                        'priority' => c.Priority, 
                        'reason' => c.Reason, 
                        'type' => c.Type, 
                        'suppliedEmail' => c.SuppliedEmail, 
                        'suppliedCompany' => c.SuppliedCompany, 
                        'suppliedName' => c.SuppliedName, 
                        'suppliedPhone' => c.SuppliedPhone
                    },
                    new List<EmailMessage>(),
                    new List<Map<String, Object>>(), // attachments
                    new List<CaseComment>()
                });                
            }
        } else {
            System.debug('Case is not accessible');
        }
    }

    // Email Messages related to Cases
    private static List<String> fetchEmails(List<Id> caseIds, Map<Id, Id> emailToCaseMap) {
        List<String> emailIdsWithAttachments = new List<String>();
        if (Schema.sObjectType.EmailMessage.isAccessible()) {
            for (EmailMessage e : [SELECT Id, ParentId, HasAttachment, FromName, FromAddress, MessageDate, ToAddress, CcAddress, BccAddress, Subject, HtmlBody FROM EmailMessage WHERE ParentId IN :caseIds]) {
                if (caseToEmailsAndAttachments.containsKey(e.ParentId)) {
                    ((List<EmailMessage>)caseToEmailsAndAttachments.get(e.ParentId)[1]).add(e);
                    emailToCaseMap.put(e.Id, e.ParentId);
                }
                if (e.HasAttachment) {
                    emailIdsWithAttachments.add(e.Id);
                }
            }
        } else { 
            System.debug('Case is not accessible');
        }
        return emailIdsWithAttachments;
    }

    // comments related to Cases
    private static void fetchComments(List<Id> caseIds) {
        if (Schema.sObjectType.CaseComment.isAccessible()) {
            for (CaseComment c : [SELECT Id, ParentId, CommentBody, CreatedDate, CreatedById, CreatedBy.Name FROM CaseComment WHERE ParentId IN :caseIds]) {
                if (caseToEmailsAndAttachments.containsKey(c.ParentId)) {
                    ((List<CaseComment>)caseToEmailsAndAttachments.get(c.ParentId)[3]).add(c);
                }
            }
        } else { 
            System.debug('Case is not accessible');
        }
    }

    // Attachments related to Cases and Emails
    private static void fetchAttachments(List<Id> combinedIds, Map<Id, Id> emailToCaseMap) {
        if (!Schema.sObjectType.ContentDocumentLink.isAccessible() || !Schema.sObjectType.ContentVersion.isAccessible()) {
            System.debug('ContentDocumentLink or ContentVersion is not accessible');
            return;
        }
        List<ContentDocumentLink> contentDocumentLinks = [SELECT ContentDocumentId, LinkedEntityId FROM ContentDocumentLink WHERE LinkedEntityId IN :combinedIds];
        List<Id> contentDocumentIds = new List<Id>();
        for (ContentDocumentLink cdl : contentDocumentLinks) {
            contentDocumentIds.add(cdl.ContentDocumentId);
        }

        Map<Id, Map<String, Object>> contentIdToData = new Map<Id, Map<String, Object>>();
        for (ContentVersion cv : [SELECT ContentDocumentId, VersionData, Title, FileType, FileExtension FROM ContentVersion WHERE ContentDocumentId IN :contentDocumentIds]) {
            Map<String, Object> attachmentInfo = new Map<String, Object>{
                'blob' => cv.VersionData,
                'fileName' => cv.Title,
                'fileType' => cv.FileType,
                'fileExtension' => cv.FileExtension
            };
            contentIdToData.put(cv.ContentDocumentId, attachmentInfo);
        }       

        for (ContentDocumentLink cdl : contentDocumentLinks) {
            Id parentCaseId = cdl.LinkedEntityId;
            if(emailToCaseMap.containsKey(parentCaseId)) {
                parentCaseId = emailToCaseMap.get(parentCaseId);
            }
        
            if (caseToEmailsAndAttachments.containsKey(parentCaseId)) {
                Map<String, Object> attachmentInfo = contentIdToData.get(cdl.ContentDocumentId);
                if (attachmentInfo != null) {
                    ((List<Map<String, Object>>)caseToEmailsAndAttachments.get(parentCaseId)[2]).add(attachmentInfo);
                }
            }
        }        
    }

    private static void sendToBox() {
        for (Id caseId : caseToEmailsAndAttachments.keySet()) {
            Map<String, String> metadata = (Map<String, String>) caseToEmailsAndAttachments.get(caseId)[0];
            String accountId = metadata.get('accountId');
            String contactId = metadata.get('contactId');
            if (accountId != null && accountId != '') {
                prepareFoldersAndUpload(caseId, 'Accounts');
            } else if (contactId != null && contactId != '') {
                prepareFoldersAndUpload(caseId, 'Contacts');
            } else {
                return;
            }
        }
    }

    // create folder structure Accounts or Contacts folder
    private static void prepareFoldersAndUpload(String caseId, String type) {
        if (caseId == null || caseId == '' || caseToEmailsAndAttachments == null || type == null || type == '') {
            return;
        } 
        
        Map<String, String> metadata = (Map<String, String>) caseToEmailsAndAttachments.get(caseId)[0];
        List<EmailMessage> emailMessages = (List<EmailMessage>) caseToEmailsAndAttachments.get(caseId)[1];
        List<Map<String, Object>> attachments = (List<Map<String, Object>>) caseToEmailsAndAttachments.get(caseId)[2];
        List<CaseComment> comments = (List<CaseComment>) caseToEmailsAndAttachments.get(caseId)[3];
        String accountId = metadata.get('accountId');
        String contactId = metadata.get('contactId');
        String parent = '';
        String id = '';
        String folder = '';
        String casesFolder = '';
        String caseIdFolder = '';

        if (type == 'Accounts') {
            parent = ACCOUNTS_FOLDER;
            id = accountId;
        } else if (type == 'Contacts') {
            parent = CONTACTS_FOLDER;
            id = contactId;
        }

        folder = getOrCreateFolder(parent, id);
        if (folder != null && folder != '') {
            casesFolder = getOrCreateFolder(folder, 'Cases');
            if (casesFolder != null && casesFolder != '') {
                caseIdFolder = getOrCreateFolder(casesFolder, caseId);
                if (caseIdFolder != null && caseIdFolder != '') {
                    // Access Blob data and Metadata
                    for (Map<String, Object> attachment : attachments) {
                        Blob contentData = (Blob)attachment.get('blob');
                        String fileName = (String)attachment.get('fileName');
                        String fileExtension = (String)attachment.get('fileExtension');
                        
                        // Create a Map to hold the Blob and its metadata
                        Map<String, Object> blobAttachment = new Map<String, Object>{
                            'blob' => contentData,
                            'fileName' => fileName + '.' + fileExtension
                        }; 
                        uploadFileToBox(blobAttachment, caseIdFolder);
                    }

                    // Access EmailMessages
                    String emailMessagesContent = '';

                    for (EmailMessage e : emailMessages) {
                        String emailContent = 'Email Id: ' + e.Id + '<br>' + 
                        'From: ' + e.FromName + ' [' + e.FromAddress + ']' + '<br>' + 
                        'Sent: ' + String.valueOf(e.MessageDate) + '<br>' + 
                        'To: ' + e.ToAddress + '<br>' +  
                        'Cc: ' + (e.CcAddress == null ? '' : e.CcAddress) + '<br>' + 
                        'Bcc: ' + (e.BccAddress == null ? '' : e.BccAddress) + '<br>' + 
                        'Subject: ' + e.Subject + '<br><br>' + e.HtmlBody + '<br><br>';
                        emailMessagesContent += emailContent;
                    }
                    Blob emailPdfBlob = Blob.toPdf(emailMessagesContent);
                    String emailPdfFileName = 'Emails.pdf';

                    // Create a Map to hold the PDF Blob and its metadata
                    Map<String, Object> emailPdfAttachment = new Map<String, Object>{
                        'blob' => emailPdfBlob,
                        'fileName' => emailPdfFileName,
                        'fileType' => 'application/pdf'
                    };

                    // Upload the email details PDF to Box
                    uploadFileToBox(emailPdfAttachment, caseIdFolder);
                    
                    // Create Case files & upload
                    String pdfContent = 'Case Number: ' + metadata.get('caseNumber') + '<br>' + 'Subject: ' + metadata.get('subject') + '<br>' +
                    'Status: ' + metadata.get('status') + '<br>' + 'Priority: ' + metadata.get('priority') + '<br>' +
                    'Description: ' + metadata.get('description') + '<br>' + 'Closed Date: ' + metadata.get('closedDate') + '<br>' +
                    'Created Date: ' + metadata.get('createdDate') + '<br>' + 'Origin: ' + metadata.get('origin') + '<br>' +
                    'Created By Id: ' + metadata.get('createdById') + '<br>' +
                    'Last Modified By Id: ' + metadata.get('lastModifiedById') + '<br>' + 
                    'Account Id: ' + accountId + '<br>' + 'Account Name: ' + metadata.get('accountName') + '<br>' + 
                    'Contact Id: ' + contactId + '<br>' + 'Contact Name: ' + metadata.get('contactName') + '<br>' + 
                    'Owner Id: ' + metadata.get('ownerId') + '<br>' + 'Owner Name: ' + metadata.get('ownerName') + '<br>' +
                    'Reason: ' + metadata.get('reason') + '<br>' + 'Type: ' + metadata.get('caseType') + '<br>' +
                    'Supplied Email: ' + metadata.get('suppliedEmail') + '<br>' + 'Supplied Company: ' + metadata.get('suppliedCompany') + '<br>' +
                    'Supplied Name: ' + metadata.get('suppliedName') + '<br>' + 'Supplied Phone: ' + metadata.get('suppliedPhone') + '<br>' +
                    'Number of Emails: ' + emailMessages.size() + '<br>' +
                    'Number of Attachments: ' + attachments.size();
                    
                    // Access Comments
                    String commentsContent = '';

                    for (CaseComment c : comments) {
                        commentsContent += 'Comment Id: ' + c.Id + '<br>' + 
                        'Created Date: ' + c.CreatedDate + '<br>' + 
                        'Created By Id: ' + c.CreatedById + '<br>' +
                        'Created By Name: ' + c.CreatedBy.Name + '<br>' +  
                        'Comment: ' + c.CommentBody + '<br><br>';
                    }

                    pdfContent += '<br><br>' + commentsContent;
                    Blob pdfBlob = Blob.toPdf(pdfContent);
                    String pdfFileName = 'Case-details.pdf';
                    Map<String, Object> pdfAttachment = new Map<String, Object>{
                        'blob' => pdfBlob,
                        'fileName' => pdfFileName,
                        'fileType' => 'application/pdf'
                    };

                    uploadFileToBox(pdfAttachment, caseIdFolder);
                }
            }
        } 
        // REMOVE CASE
        // deleteCase(caseId);
    }

    private static String getOrCreateFolder(String parentId, String folderName) {
        // Check if folder exists
        HttpResponse res = makeBoxApiCall(new Map<String, String>{'endpoint' => 'folders/' + parentId + '/items', 'method' => 'GET', 'attributes' => null, 'body' => null, 'fileName' => null}, null);
    
        if (res.getStatusCode() == 200) {
            // Parse the JSON response
            Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    
            List<Object> entries = (List<Object>) jsonResponse.get('entries');
    
            for (Object entryObj : entries) {
                Map<String, Object> entry = (Map<String, Object>) entryObj;
                String type = (String) entry.get('type');
                String name = (String) entry.get('name');
                String id = (String) entry.get('id');
    
                if (type == 'folder' && name == folderName) {
                    // Folder exists, return the folder ID
                    return id;
                }
            }
        }
    
        // folder does not exist, so create it
        String folderBody = '{"name":"' + folderName + '", "parent": {"id":"' + parentId + '"}}';
        HttpResponse createRes = makeBoxApiCall(new Map<String, String>{'endpoint' => 'folders', 'method' => 'POST', 'attributes' => null, 'body' => folderBody, 'fileName' => null}, null);
        if (createRes.getStatusCode() == 201) {
            // Parse JSON response to get new folder ID
            Map<String, Object> createResponse = (Map<String, Object>) JSON.deserializeUntyped(createRes.getBody());
            String newFolderId = (String) createResponse.get('id');
    
            // Return new folder ID
            return newFolderId;
        }
    
        return null; // Error condition
    }

    private static HttpResponse makeBoxApiCall(Map<String, String> config, Blob fileBlob) {
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setMethod(config.get('method'));
    
        if (fileBlob != null) {
            req.setEndpoint('callout:boxUpload/' + config.get('endpoint'));
        } else {
            System.debug('FILE BLOB IS NULL for fileName: ' + config.get('fileName') + ' and attributes: ' + config.get('attributes'));
            req.setEndpoint('callout:box/' + config.get('endpoint'));
        }
        
        if (String.isNotBlank(config.get('body')) && fileBlob == null) {
            req.setHeader('Content-Type', 'application/json');
            req.setBody(config.get('body'));
        }
        
        if (fileBlob != null) {
            Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(config.get('attributes'));
            Map<String, Object> m2 = (Map<String, Object>) m.get('parent');
            String folderId = (String) m2.get('id');
            blob base64File = base64EncodeBinary(fileBlob, config.get('fileName'));
            String boundary = '----------------------------123456789';
            String body = '{"name":"' + config.get('fileName') + '", "parent":{"id":"' + folderId + '"}}';
            req.setBody(body);
            req.setBodyAsBlob(base64File);
            req.setHeader('Content-Type','multipart/form-data; boundary=' + boundary);
        }
    
        HttpResponse res = http.send(req);
        return res;
    }    

    public static blob base64EncodeBinary(Blob fileBody, String fileName){
        String boundary = '----------------------------123456789';
        String header = '--'+boundary+'\nContent-Disposition: form-data; name="file"; filename="' + fileName+'";\nContent-Type: application/octet-stream';
        String footer = '--'+boundary+'--';             
        String headerEncoded = EncodingUtil.base64Encode(Blob.valueOf(header+'\r\n\r\n'));
        while(headerEncoded.endsWith('='))
        {
            header+=' ';
            headerEncoded = EncodingUtil.base64Encode(Blob.valueOf(header+'\r\n\r\n'));
        }
        String bodyEncoded = EncodingUtil.base64Encode(fileBody);
        Blob bodyBlob = null;
        String last4Bytes = bodyEncoded.substring(bodyEncoded.length()-4,bodyEncoded.length());
  
        if(last4Bytes.endsWith('==')) {
            last4Bytes = last4Bytes.substring(0,2) + '0K';
            bodyEncoded = bodyEncoded.substring(0,bodyEncoded.length()-4) + last4Bytes;
        } else if(last4Bytes.endsWith('=')) {
            last4Bytes = last4Bytes.substring(0,3) + 'N';
            bodyEncoded = bodyEncoded.substring(0,bodyEncoded.length()-4) + last4Bytes;
            footer = '\n' + footer;
        } else {
            footer = '\r\n' + footer;
        }

        String footerEncoded = EncodingUtil.base64Encode(Blob.valueOf(footer));
        bodyBlob = EncodingUtil.base64Decode(headerEncoded+bodyEncoded+footerEncoded);
        return bodyBlob;
    }

    private static void uploadFileToBox(Map<String, Object> attachment, String caseIdFolder) {
        Blob fileBlob = (Blob) attachment.get('blob');
        String fileName = (String) attachment.get('fileName');
        System.debug('FILE BLOB: ' + fileBlob);
        System.debug('FILE NAME: ' + fileName);
        if (caseIdFolder != null && caseIdFolder != '') {
            String fileEndpoint = 'files/content?parent_id=' + caseIdFolder;
            Map<String, Object> parentFolder = new Map<String, Object>{ 'id' => caseIdFolder };
            Map<String, Object> fileAttributes = new Map<String, Object>{
                'name' => fileName,
                'parent' => parentFolder,
                'content_created_at' => '',
                'content_modified_at' => ''
            };
            String attributes = JSON.serialize(fileAttributes);
            HttpResponse fileResponse = makeBoxApiCall(new Map<String, String>{'endpoint' => fileEndpoint, 'method' => 'POST', 'attributes' => attributes, 'body' => null, 'fileName' => fileName}, fileBlob);
            
            if (fileResponse.getStatusCode() == 201) {
                System.debug('File uploaded successfully');
            } else {
                System.debug('Failed to upload file: ' + fileResponse.getBody());
            }
        }
    }    
}