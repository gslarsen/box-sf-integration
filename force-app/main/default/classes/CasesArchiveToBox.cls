public with sharing class CaseArchiveHandler {
    public static final String ACCOUNTS_FOLDER = '232841054083';
    public static final String CONTACTS_FOLDER = '232841229558';
    // REMOVE TIME ITEMS
    private static DateTime startTime;
    private static Long startMs;
    private static DateTime endTime;
    private static Long endMs;
    
    @future(callout=true)
    public static void archiveCases() {
        // REMOVE TIME ITEMS
        startTime = DateTime.now();
        startMs = DateTime.now().getTime();
        
        Map<Id, List<List<Object>>> caseToEmailsAndAttachments = fetchCasesAndMetadata();
        if (caseToEmailsAndAttachments.isEmpty()) {
            return;
        }
        List<Id> caseIds = new List<Id>(caseToEmailsAndAttachments.keySet());

        Map<Id, Id> emailToCaseMap = new Map<Id, Id>();
        fetchEmails(caseToEmailsAndAttachments, caseIds, emailToCaseMap);

        List<Id> emailIds = new List<Id>(emailToCaseMap.keySet());
        List<Id> combinedIds = new List<Id>();
        combinedIds.addAll(caseIds);
        combinedIds.addAll(emailIds);

        fetchAttachments(caseToEmailsAndAttachments, combinedIds, emailToCaseMap);

        // Now caseToEmailsAndAttachments contains metadata, EmailMessages, and file binary data for each Case
        sendToBox(caseToEmailsAndAttachments);
    }

    // Case IDs and initial metadata
    private static Map<Id, List<List<Object>>> fetchCasesAndMetadata() {
        Map<Id, List<List<Object>>> caseToEmailsAndAttachments = new Map<Id, List<List<Object>>>();

        if (Schema.sObjectType.Case.isAccessible()) {
            List<Case> cases = [SELECT Id, CaseNumber, Subject, Description, ClosedDate, CreatedDate, Origin, AccountId, Account.Name, ContactId, Contact.Name, OwnerId, Owner.Name FROM Case WHERE ClosedDate = LAST_N_DAYS:60];
            if (cases.isEmpty()) {
                System.debug('No cases found...returning');
                return caseToEmailsAndAttachments;
            }
            for (Case c : cases) {
                caseToEmailsAndAttachments.put(c.Id, new List<List<Object>> {
                    new List<String>{c.CaseNumber, c.Subject, c.Description, String.valueOf(c.ClosedDate), String.valueOf(c.CreatedDate), c.Origin, c.AccountId, c.Account.Name, c.ContactId, c.Contact.Name, c.OwnerId, c.Owner.Name},
                    new List<EmailMessage>(),
                    new List<Map<String, Object>>() // List of Maps to store file metadata
                });                
            }
        } else {
            System.debug('Case is not accessible');
        }
        return caseToEmailsAndAttachments;
    }

    // Email Messages related to Cases
    private static void fetchEmails(Map<Id, List<List<Object>>> caseToEmailsAndAttachments, List<Id> caseIds, Map<Id, Id> emailToCaseMap) {
        if (Schema.sObjectType.EmailMessage.isAccessible()) {
            for (EmailMessage e : [SELECT Id, ParentId, HasAttachment, Subject, TextBody FROM EmailMessage WHERE ParentId IN :caseIds]) {
                if (caseToEmailsAndAttachments.containsKey(e.ParentId)) {
                    caseToEmailsAndAttachments.get(e.ParentId)[1].add(e);
                    emailToCaseMap.put(e.Id, e.ParentId);
                }
            }
        } else { 
            System.debug('Case is not accessible');
        }
    }

    // Attachments related to Cases and Emails
    private static void fetchAttachments(Map<Id, List<List<Object>>> caseToEmailsAndAttachments, List<Id> combinedIds, Map<Id, Id> emailToCaseMap) {
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
            if(emailToCaseMap.containsKey(cdl.LinkedEntityId)) {
                parentCaseId = emailToCaseMap.get(cdl.LinkedEntityId);
            }
        
            if (caseToEmailsAndAttachments.containsKey(parentCaseId)) {
                Map<String, Object> attachmentInfo = contentIdToData.get(cdl.ContentDocumentId);
                if (attachmentInfo != null) {
                    ((List<Map<String, Object>>)caseToEmailsAndAttachments.get(parentCaseId)[2]).add(attachmentInfo);
                }
            }
        }        
    }

    private static void sendToBox(Map<Id, List<List<Object>>> caseToEmailsAndAttachments) {
        for (Id caseId : caseToEmailsAndAttachments.keySet()) {
            // Access metadata
            List<String> metadata = (List<String>) caseToEmailsAndAttachments.get(caseId)[0];
            String caseNumber = metadata[0];
            String subject = metadata[1];
            String description = metadata[2];
            String closedDate = metadata[3];
            String createdDate = metadata[4];
            String origin = metadata[5];
            String accountId = metadata[6];
            String accountName = metadata[7];
            String contactId = metadata[8];
            String contactName = metadata[9];
            String ownerId = metadata[10];
            String ownerName = metadata[11];

            // get or create folder(s) - send data
            String acctFolder = '';
            String contactFolder = '';
            String casesFolder = '';
            String caseIdFolder = '';

            if (accountId != null && accountId != '') {
                acctFolder = getOrCreateFolder(ACCOUNTS_FOLDER, accountId);
                if (acctFolder != null && acctFolder != '') {
                    casesFolder = getOrCreateFolder(acctFolder, 'Cases');
                    if (casesFolder != null && casesFolder != '') {
                        caseIdFolder = getOrCreateFolder(casesFolder, caseId);
                        if (caseIdFolder != null && caseIdFolder != '') {
                            // Access Blob data and Metadata
                            List<Map<String, Object>> attachments = (List<Map<String, Object>>) caseToEmailsAndAttachments.get(caseId)[2];
                            for (Map<String, Object> attachment : attachments) {
                                Blob contentData = (Blob)attachment.get('blob');
                                String fileName = (String)attachment.get('fileName');
                                String fileExtension = (String)attachment.get('fileExtension');
                                
                                // Create a Map to hold the House Blob and its metadata
                                Map<String, Object> houseAttachment = new Map<String, Object>{
                                    'blob' => contentData,
                                    'fileName' => fileName + '.' + fileExtension
                                }; 
                                uploadFileToBox(houseAttachment, caseIdFolder);
                            }

                            // Access EmailMessages
                            List<EmailMessage> emailMessages = (List<EmailMessage>) caseToEmailsAndAttachments.get(caseId)[1];
                            String emailMessagesContent = '';

                            for (EmailMessage e : emailMessages) {
                                String emailContent = 'Email Id: ' + e.Id + '<br>' + 'Email Subject: ' + e.Subject + '<br>' + 'Email TextBody: ' + e.TextBody + '<br><br>';
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
                            // Create a Map to hold the EmailMessages Blob and its metadata
                            Map<String, Object> emailMessagesAttachment = new Map<String, Object>{
                                'blob' => Blob.valueOf(emailMessagesContent),
                                'fileName' => 'EmailMessages.html'
                            };
                            
                            // Create Case files & upload
                            String pdfContent = 'Case Number: ' + caseNumber + '<br>' + 'Subject: ' + subject + '<br>' +
                            'Description: ' + description + '<br>' + 'Closed Date: ' + closedDate + '<br>' +
                            'Created Date: ' + createdDate + '<br>' + 'Origin: ' + origin + '<br>' +
                            'Account Id: ' + accountId + '<br>' + 'Account Name: ' + accountName + '<br>' + 
                            'Contact Id: ' + contactId + '<br>' + 'Contact Name: ' + contactName + '<br>' + 
                            'Owner Id: ' + ownerId + '<br>' + 'Owner Name: ' + ownerName + '<br>' +
                            'Number of Emails: ' + emailMessages.size() + '<br>' +
                            'Number of Attachments: ' + attachments.size() + '<br>' + '...more fields';
                            Blob pdfBlob = Blob.toPdf(pdfContent);
                            String pdfFileName = 'Case-details.pdf';
                            System.debug('PDF CONTENT: ' + pdfContent);
                            System.debug(EncodingUtil.base64Encode(pdfBlob));
                            // Create a Map to hold the PDF Blob and its metadata
                            Map<String, Object> pdfAttachment = new Map<String, Object>{
                                'blob' => pdfBlob,
                                'fileName' => pdfFileName,
                                'fileType' => 'application/pdf'
                            };

                            // Upload the case details PDF to Box
                            uploadFileToBox(pdfAttachment, caseIdFolder);
                        }
                    }
                } 
            } else if (contactId != null && contactId != '') {
                contactFolder = getOrCreateFolder(CONTACTS_FOLDER, contactId);
                if (contactFolder != null && contactFolder != '') {
                    casesFolder = getOrCreateFolder(contactFolder, 'Cases');
                    if (casesFolder != null && casesFolder != '') {
                        caseIdFolder = getOrCreateFolder(casesFolder, caseId);
                        if (caseIdFolder != null && caseIdFolder != '') {
                            // Create Case files & upload
                        }
                    }
                } 
            } 
        }
    }

    private static HttpResponse makeBoxApiCall(String endpoint, String method, String attributes, Blob fileBlob, String body, String fileName) {
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setMethod(method);
    
        if (fileBlob != null) {
            req.setEndpoint('callout:boxUpload/' + endpoint);
        } else {
            System.debug('FILE BLOB IS NULL for fileName: ' + fileName + ' and attributes: ' + attributes);
            req.setEndpoint('callout:box/' + endpoint);
        }
        
        if (String.isNotBlank(body) && fileBlob == null) {
            req.setHeader('Content-Type', 'application/json');
            req.setBody(body);
        }
        
        if (fileBlob != null) {
            Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(attributes);
            Map<String, Object> m2 = (Map<String, Object>) m.get('parent');
            String folderId = (String) m2.get('id');
            blob base64EncodeFile = base64EncodeFileContent(fileBlob, filename);
            String boundary = '----------------------------123456789';
            body = '{"name":"' + fileName + '", "parent":{"id":"' + folderId + '"}}';
            req.setBody(body);
            req.setBodyAsBlob(base64EncodeFile);
            req.setHeader('Content-Type','multipart/form-data; boundary=' + boundary);
        }
    
        HttpResponse res = http.send(req);
        return res;
    }    

    public static blob base64EncodeFileContent(Blob fileBody, String fileName){
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

    private static String getOrCreateFolder(String parentId, String folderName) {
        // Check if folder exists
        HttpResponse res = makeBoxApiCall('folders/' + parentId + '/items', 'GET', null, null, null, null);
    
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
    
        // If folder does not exist, create it
        String folderBody = '{"name":"' + folderName + '", "parent": {"id":"' + parentId + '"}}';
        HttpResponse createRes = makeBoxApiCall('folders', 'POST', null, null, folderBody, null);
        if (createRes.getStatusCode() == 201) {
            // Parse JSON response to get new folder ID
            Map<String, Object> createResponse = (Map<String, Object>) JSON.deserializeUntyped(createRes.getBody());
            String newFolderId = (String) createResponse.get('id');
    
            // Return new folder ID
            return newFolderId;
        }
    
        return null; // Error condition
    }
    
    private static void uploadFileToBox(Map<String, Object> attachment, String caseIdFolder) {
        Blob fileBlob = (Blob) attachment.get('blob');
        String fileName = (String) attachment.get('fileName');
        System.debug('FILE BLOB: ' + fileBlob);
        System.debug('FILE NAME: ' + fileName);
        if (caseIdFolder != null && caseIdFolder != '') {
            String fileEndpoint = 'files/content?parent_id=' + caseIdFolder;
            Map<String, Object> parentFolder = new Map<String, Object>{ 'id' => caseIdFolder };
            Map<String, Object> attributes = new Map<String, Object>{
                'name' => fileName,
                'parent' => parentFolder,
                'content_created_at' => '',
                'content_modified_at' => ''
            };
            String fileBody = JSON.serialize(attributes);
            HttpResponse fileResponse = makeBoxApiCall(fileEndpoint, 'POST', fileBody, fileBlob, null, fileName);
            
            if (fileResponse.getStatusCode() == 201) {
                System.debug('File uploaded successfully');
            } else {
                System.debug('Failed to upload file: ' + fileResponse.getBody());
            }
        }
        // REMOVE TIME ITEMS
        endTime = DateTime.now();
        endMs = DateTime.now().getTime();
        System.debug('TOTAL TIME: ' + (endMs - startMs));
    }    
}