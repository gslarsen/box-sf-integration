public with sharing class CasesArchiveToBox {
    private static final String ACCOUNTS_FOLDER = '232841054083'; // change these to applicable Box folder IDs
    private static final String CONTACTS_FOLDER = '234058604832'; 
    private static final Integer DAYS = 60; // how many days back to look for cases; NOTE: change SOQL in fetchCasesAndMetadata() to be < LAST_N_DAYS:DAYS
    private static Map<Id, List<Object>> caseToEmailsAndAttachments = new Map<Id, List<Object>>();
    
    @future(callout=true)
    public static void archiveCases() {
        fetchCasesAndMetadata();
        if (caseToEmailsAndAttachments.isEmpty()) {
            System.debug('No cases found-returning');
            return;
        }
        
        List<Id> caseIds = new List<Id>(caseToEmailsAndAttachments.keySet());
        Map<Id, Id> emailIdToCaseId = new Map<Id, Id>();
        List<Id> emailIdsWithAttachments = fetchEmails(caseIds, emailIdToCaseId);
        List<Id> combinedIds = new List<Id>();
        combinedIds.addAll(caseIds);
        combinedIds.addAll(emailIdsWithAttachments);
        
        fetchAttachments(combinedIds, emailIdToCaseId, emailIdsWithAttachments);
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
                    new Map<String, List<Map<Id,Map<String,Object>>>>{'email' => new List<Map<Id,Map<String,Object>>>(), 'case' => new List<Map<Id,Map<String,Object>>>()}, // attachments
                    // new List<Map<Id, Map<String, Object>>>(), // attachments
                    new List<CaseComment>()
                });                
            }
        } else {
            System.debug('Case is not accessible');
        }
    }

    // Email Messages related to Cases
    private static List<String> fetchEmails(List<Id> caseIds, Map<Id, Id> emailIdToCaseId) {
        List<String> emailIdsWithAttachments = new List<String>();
        if (Schema.sObjectType.EmailMessage.isAccessible()) {
            for (EmailMessage e : [SELECT Id, ParentId, ActivityId, CreatedById, CreatedDate, LastModifiedDate, LastModifiedById, SystemModstamp, TextBody, HtmlBody, Headers, Subject, Name, FromName, FromAddress, ValidatedFromAddress, ToAddress, CcAddress, BccAddress, Incoming, HasAttachment, Status, MessageDate, IsDeleted, ReplyToEmailMessageId, IsExternallyVisible, MessageIdentifier, ThreadIdentifier, ClientThreadIdentifier, IsClientManaged, RelatedToId, IsTracked, IsOpened, FirstOpenedDate, LastOpenedDate, IsBounced, EmailTemplateId FROM EmailMessage WHERE ParentId IN :caseIds]) {
                if (caseToEmailsAndAttachments.containsKey(e.ParentId)) {
                    ((List<EmailMessage>)caseToEmailsAndAttachments.get(e.ParentId)[1]).add(e);
                    emailIdToCaseId.put(e.Id, e.ParentId);
                }
                if (e.HasAttachment) {
                    emailIdsWithAttachments.add(e.Id);
                }
            }
        } else { 
            System.debug('EmailMessage is not accessible');
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
            System.debug('CaseComment is not accessible');
        }
    }

    // Attachments related to Cases and Emails
    private static void fetchAttachments(List<Id> combinedIds, Map<Id, Id> emailIdToCaseId, List<Id> emailIdsWithAttachments) {
        if (!Schema.sObjectType.ContentDocumentLink.isAccessible() || !Schema.sObjectType.ContentVersion.isAccessible()) {
            System.debug('ContentDocumentLink or ContentVersion is not accessible');
            return;
        }
        List<ContentDocumentLink> contentDocumentLinks = [SELECT ContentDocumentId, LinkedEntityId FROM ContentDocumentLink WHERE LinkedEntityId IN :combinedIds];
        List<Id> contentDocumentIds = new List<Id>();
        Map<Id, Id> docIdToLinkedEntity = new Map<Id, Id>();
        for (ContentDocumentLink cdl : contentDocumentLinks) {
            contentDocumentIds.add(cdl.ContentDocumentId);
            docIdToLinkedEntity.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
        }

        Map<Id, Map<Id, Map<String, Object>>> docIdToAttachment = new  Map<Id, Map<Id, Map<String, Object>>>();
        for (ContentVersion cv : [SELECT ContentDocumentId, VersionData, Title, FileType, FileExtension FROM ContentVersion WHERE ContentDocumentId IN :contentDocumentIds AND IsLatest = true]) {
            Id linkedEntityId = docIdToLinkedEntity.get(cv.ContentDocumentId);
            Map<Id, Map<String, Object>> linkedEntityIdToAttachment = new Map<Id, Map<String, Object>>{
                linkedEntityId => new Map<String, Object>{
                'blob' => cv.VersionData,
                'fileName' => cv.Title,
                'fileType' => cv.FileType,
                'fileExtension' => cv.FileExtension,
                'emailSource' => emailIdsWithAttachments.contains(linkedEntityId)
            }};
            docIdToAttachment.put(cv.ContentDocumentId, linkedEntityIdToAttachment);
        }       

        for (ContentDocumentLink cdl : contentDocumentLinks) {
            Boolean isEmail = false;
            Id linkedEntityId = cdl.LinkedEntityId;
            if(emailIdToCaseId.containsKey(linkedEntityId)) {
                isEmail = true;
                // If the linked entity is an email, get the case ID from the email ID
                linkedEntityId = emailIdToCaseId.get(linkedEntityId);
            }
        
            if (caseToEmailsAndAttachments.containsKey(linkedEntityId)) {
                Map<Id, Map<String, Object>> linkedEntityIdToAttachment = docIdToAttachment.get(cdl.ContentDocumentId);
                if (linkedEntityIdToAttachment != null) {
                    if (isEmail) {
                        ((Map<String, List<Map<Id,Map<String,Object>>>>)caseToEmailsAndAttachments.get(linkedEntityId)[2]).get('email').add(linkedEntityIdToAttachment);
                    } else {
                        ((Map<String, List<Map<Id,Map<String,Object>>>>)caseToEmailsAndAttachments.get(linkedEntityId)[2]).get('case').add(linkedEntityIdToAttachment);          
                    }
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
        Map<String, List<Map<Id,Object>>> attachments = (Map<String, List<Map<Id,Object>>>) caseToEmailsAndAttachments.get(caseId)[2];
        // List<Map<Id, Map<String, Object>>> attachments = (List<Map<Id, Map<String, Object>>>) caseToEmailsAndAttachments.get(caseId)[2];
        List<CaseComment> comments = (List<CaseComment>) caseToEmailsAndAttachments.get(caseId)[3];
        Map<Id, Map<Id, Map<String, Object>>> attachmentsMap = new Map<Id, Map<Id, Map<String, Object>>>();
        String caseNumber = metadata.get('caseNumber');
        String accountId = metadata.get('accountId');
        String accountName = metadata.get('accountName');
        String contactId = metadata.get('contactId');
        String contactName = metadata.get('contactName');
        String parent = '';
        String id = '';
        String casesFolder = '';
        String caseIdFolder = '';

        if (type == 'Accounts') {
            parent = ACCOUNTS_FOLDER;
            id = accountId;
        } else if (type == 'Contacts') {
            parent = CONTACTS_FOLDER;
            id = contactId;
        }

        // parentCreatedNow and '-new' in accountOrContactFolder is to prevent unnecessary 'GET' for subfolders 
        Boolean parentCreatedNow = false;
        String accountOrContactFolder = getOrCreateFolder(parent, id, parentCreatedNow);
        if (accountOrContactFolder != null && accountOrContactFolder != '' & accountOrContactFolder.contains('-new')) {
            parentCreatedNow = true;
            accountOrContactFolder = accountOrContactFolder.replace('-new', '');
        } 

        if (accountOrContactFolder != null && accountOrContactFolder != '') {
            casesFolder = getOrCreateFolder(accountOrContactFolder, 'Cases', parentCreatedNow);
            if (casesFolder != null && casesFolder != '') {
                caseIdFolder = getOrCreateFolder(casesFolder, caseId + '-' + caseNumber, true);
                if (caseIdFolder != null && caseIdFolder != '') {
                    caseIdFolder = caseIdFolder.replace('-new', '');
                    System.debug('caseIdFolder: ' + caseIdFolder);
                    // access attachment Blob and its metadata related to case (note email is handled separately (i.e. attached to email)
                    for (Map<Id,Map<String,Object>> attachmentObj : (List<Map<Id,Map<String,Object>>>)attachments.get('case')) {
                        System.debug('attachmentObj: ' + attachmentObj);
                        Id linkedEntityId = new List<Id>(attachmentObj.keySet())[0];
                        System.debug('linkedEntityId: ' + linkedEntityId);
                        Map<String,Object> attachment = (Map<String, Object>)attachmentObj.get(linkedEntityId);
                        System.debug('attachment: ' + attachment);
                        // Boolean emailSource = (Boolean)attachmentDetails.get('emailSource');
                    //     if (emailSource) {
                    //         // we handle email attachments separately by attaching to .eml files
                    //         continue;
                    //     }
                        
                        Blob attachmentBinary = (Blob)attachment.get('blob');
                        String attachmentFilename = (String)attachment.get('fileName') + '.' + (String)attachment.get('fileExtension');
                        
                        attachmentsMap.put(linkedEntityId, attachmentObj);
                        
                        // Create a Map to hold the Blob and its metadata
                        Map<String, Object> blobAttachment = new Map<String, Object>{
                            'blob' => attachmentBinary,
                            'fileName' => attachmentFilename
                        }; 

                        uploadFileToBox(blobAttachment, caseIdFolder);
                    }

                    // Access EmailMessages
                    String emailMessagesContent = '';
                    // REMOVE? .eml files
                    List<String> emailMessagesContentEml = new List<String>();

                    for (EmailMessage e : emailMessages) {
                        // // Id, ParentId, ActivityId, CreatedById, CreatedDate, LastModifiedDate, LastModifiedById, SystemModstamp, TextBody, HtmlBody, Headers, Subject, Name, FromName, FromAddress, ValidatedFromAddress, ToAddress, CcAddress, BccAddress, Incoming, HasAttachment, Status, MessageDate, IsDeleted, ReplyToEmailMessageId, IsExternallyVisible, MessageIdentifier, ThreadIdentifier, ClientThreadIdentifier, IsClientManaged, RelatedToId, IsTracked, IsOpened, FirstOpenedDate, LastOpenedDate, IsBounced, EmailTemplateId
                        // String headers = '';
                        // if (e.Headers != null && e.Headers != '') {
                        //     headers = e.Headers.replace('>', '&gt;');
                        //     headers = headers.replace('<', '&lt;');
                        // }

                        // Map<Id,Map<String, Object>> emailAttachments = attachmentsMap.get(e.Id);
                        // List<Map<String, Object>> emailAttachmentsList = new List<Map<String, Object>>();
                        // String emailAttachmentsFiles = '[';
                        
                        // if (emailAttachments != null && emailAttachments.size() > 0) {
                        //     for (Map<String, Object> emailAttachment : emailAttachments.values()) {
                        //         emailAttachmentsFiles += emailAttachment.get('fileName') + '.' + emailAttachment.get('fileExtension') + ', ';
                        //         Map<String, Object> singleAttachmentMap = new Map<String, Object>();
                        //         singleAttachmentMap.put((String)emailAttachment.get('fileName') + '.' + emailAttachment.get('fileExtension'), emailAttachment.get('blob'));
                        //         emailAttachmentsList.add(singleAttachmentMap);                            }
                        // }

                        // System.debug('emailAttachmentsList: ' + emailAttachmentsList);
                        // emailAttachmentsFiles = emailAttachmentsFiles.removeEnd(', ') + ']';
                        // String emailContent = '<strong>Email Id: ' + e.Id + '</strong><br>' + 
                        // '<em>Other Fields:</em><br>' +
                        // 'Parent Id: ' + e.ParentId + '<br>' +
                        // 'Activity Id: ' + e.ActivityId + '<br>' +
                        // 'Created Date: ' + String.valueOf(e.CreatedDate) + '<br>' +
                        // 'Created By Id: ' + e.CreatedById + '<br>' +
                        // // 'Created By Name: ' + e.CreatedBy.Name + '<br>' +
                        // 'Last Modified Date: ' + String.valueOf(e.LastModifiedDate) + '<br>' +
                        // 'Last Modified By Id: ' + e.LastModifiedById + '<br>' +
                        // // 'Last Modified By Name: ' + e.LastModifiedBy.Name + '<br>' +
                        // 'System Modstamp: ' + String.valueOf(e.SystemModstamp) + '<br>' +
                        // // 'Text Body: ' + e.TextBody + '<br>' +
                        // // 'Html Body: ' + e.HtmlBody + '<br>' +
                        // // 'Subject: ' + e.Subject + '<br>' +
                        // 'Name: ' + e.Name + '<br>' +
                        // 'From Name: ' + e.FromName + '<br>' +
                        // 'From Address: ' + e.FromAddress + '<br>' +
                        // 'Validated From Address: ' + e.ValidatedFromAddress + '<br>' +
                        // 'To Address: ' + e.ToAddress + '<br>' +
                        // 'Cc Address: ' + e.CcAddress + '<br>' +
                        // 'Bcc Address: ' + e.BccAddress + '<br>' +
                        // 'Incoming: ' + e.Incoming + '<br>' +
                        // 'Status: ' + e.Status + '<br>' +
                        // 'Message Date: ' + String.valueOf(e.MessageDate) + '<br>' +
                        // 'Is Deleted: ' + e.IsDeleted + '<br>' +
                        // 'Reply To Email Message Id: ' + e.ReplyToEmailMessageId + '<br>' +
                        // 'Is Externally Visible: ' + e.IsExternallyVisible + '<br>' +
                        // 'Message Identifier: ' + e.MessageIdentifier + '<br>' +
                        // 'Thread Identifier: ' + e.ThreadIdentifier + '<br>' +
                        // 'Client Thread Identifier: ' + e.ClientThreadIdentifier + '<br>' +
                        // 'Is Client Managed: ' + e.IsClientManaged + '<br>' +
                        // 'Related To Id: ' + e.RelatedToId + '<br>' +
                        // 'Is Tracked: ' + e.IsTracked + '<br>' +
                        // 'Is Opened: ' + e.IsOpened + '<br>' +
                        // 'First Opened Date: ' + String.valueOf(e.FirstOpenedDate) + '<br>' +
                        // 'Last Opened Date: ' + String.valueOf(e.LastOpenedDate) + '<br>' +
                        // 'Is Bounced: ' + e.IsBounced + '<br>' +
                        // 'Email Template Id: ' + e.EmailTemplateId + '<br><br>' +
                        // '<strong>// EMAIL // </strong><br>' +
                        // 'Headers: ' +  headers + '<br>' +
                        // 'Has Attachment: ' + e.HasAttachment + '<br>' + 
                        // 'From: ' + e.FromName + ' [' + e.FromAddress + ']' + '<br>' + 
                        // 'Sent: ' + String.valueOf(e.MessageDate) + '<br>' + 
                        // 'To: ' + e.ToAddress + '<br>' +  
                        // 'Cc: ' + (e.CcAddress == null ? '' : e.CcAddress) + '<br>' + 
                        // 'Bcc: ' + (e.BccAddress == null ? '' : e.BccAddress) + '<br>' + 
                        // 'Subject: ' + e.Subject + '<br><br>' + e.HtmlBody + '<br><br>' +
                        // 'Attachments: ' + (emailAttachmentsFiles == null ? '' : emailAttachmentsFiles) + '<br><br>';
                        // emailMessagesContent += emailContent;

                        // REMOVE? .eml files preparation
                        String emailContentEml = 'From: ' + e.FromName + ' [' + e.FromAddress + ']' + '\n' + 
                            'Sent: ' + String.valueOf(e.MessageDate) + '\n' + 
                            'To: ' + e.ToAddress + '\n' +  
                            'Cc: ' + (e.CcAddress == null ? '' : e.CcAddress) + '\n' + 
                            'Bcc: ' + (e.BccAddress == null ? '' : e.BccAddress) + '\n' + 
                            'Subject: ' + e.Subject + '\n' + 
                            'MIME-Version: 1.0' + '\n' +
                            'Content-Type: multipart/mixed; boundary="main_boundary"\n\n'; // + '\n' + //alternative
                        
                        // Body parts
                        String body = '';
                        body += '--main_boundary\n';
                        body += 'Content-Type: multipart/alternative; boundary="alternative_boundary"\n\n';

                        if (String.isNotEmpty(e.TextBody)) {
                            body += '--alternative_boundary\n';
                            body += 'Content-Type: text/plain; charset=UTF-8\n\n';
                            body += e.TextBody + '\n\n';
                        }

                        body += '--alternative_boundary--\n\n';

                        // add attachments
                        if (e.HasAttachment) {
                            for (Map<Id,Map<String,Object>> attachmentObj : (List<Map<Id,Map<String,Object>>>)attachments.get('email')) {
                                System.debug('attachmentObj: ' + attachmentObj);
                                Id linkedEntityId = new List<Id>(attachmentObj.keySet())[0];
                                System.debug('linkedEntityId: ' + linkedEntityId);
                                if (linkedEntityId != e.Id) {
                                    continue;
                                }
                                Map<String,Object> attachment = (Map<String, Object>)attachmentObj.get(linkedEntityId);
                                System.debug('attachment: ' + attachment);
                                
                                
                                Blob attachmentBinary = (Blob)attachment.get('blob');
                                String attachmentFileName = (String)attachment.get('fileName') + '.' + (String)attachment.get('fileExtension');

                                Map<String, Object> emailAttachmentMap = new Map<String, Object>{
                                    'blob' => attachmentBinary,
                                    'fileName' => attachmentFileName
                                };
                                
                                body += '--main_boundary\n';
                                body += 'Content-Type: application/octet-stream; name="' + attachmentFileName + '"\n';
                                body += 'Content-Disposition: attachment; filename="' + attachmentFileName + '"\n';
                                body += 'Content-Transfer-Encoding: base64\n\n';
                                
                                String base64Data = EncodingUtil.base64Encode(attachmentBinary);
                                body += base64Data + '\n\n';                            
                            }
                        }

                        // End of the multipart/mixed section
                        body += '--main_boundary--\n\n';    
                        emailContentEml += body;                                           
                        emailMessagesContentEml.add(emailContentEml);
                    }

                    // Blob emailPdfBlob = Blob.toPdf(emailMessagesContent);
                    // String emailPdfFileName = 'Emails.pdf';

                    // // Create a Map to hold the PDF Blob and its metadata
                    // Map<String, Object> emailPdfAttachment = new Map<String, Object>{
                    //     'blob' => emailPdfBlob,
                    //     'fileName' => emailPdfFileName,
                    //     'fileType' => 'application/pdf'
                    // };

                    // // Upload the email details PDF to Box
                    // uploadFileToBox(emailPdfAttachment, caseIdFolder);

                    // REMOVE? .eml files
                    for (Integer i=0; i < emailMessagesContentEml.size(); ++i) {
                        String email = emailMessagesContentEml[i];
                        System.debug('EMAIL EML: ' + email);
                        Blob emailEmlBlob = Blob.valueOf(email);
                        String emailEmlFileName = 'Email' + (i+1) + '.eml';
                        
                        // Create a Map to hold the eml Blob and its metadata
                        Map<String, Object> emailEmlAttachment = new Map<String, Object>{
                            'blob' => emailEmlBlob,
                            'fileName' => emailEmlFileName,
                            'fileType' => 'text/plain'
                        };
    
                        // Upload the .eml to Box
                        uploadFileToBox(emailEmlAttachment, caseIdFolder);
                    }

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
                    'Number of Emails: ' + emailMessages.size();
                    
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

    private static String getOrCreateFolder(String parentId, String folderName, Boolean parentCreatedNow) {
        if (!parentCreatedNow) {
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
        
                // Return new folder ID and indicate new folder was created to prevent unnecessary 'GET' for subfolders 
                return newFolderId + '-' + 'new';
            }
        } else {
            System.debug('CREATED NOW: ' + folderName + ' for parentId: ' + parentId);
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
            if (base64File == null) {
                return null;
            }
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
        System.debug('headerEncoded length: ' + headerEncoded.length());
        String bodyEncoded = EncodingUtil.base64Encode(fileBody);
        System.debug('bodyEncoded length: ' + bodyEncoded.length());
        if (bodyEncoded.length() > 12000000) {
            System.debug('FILE SIZE OF: ' + fileName + ' IS TOO LARGE: ' + bodyEncoded.length());
            return null;
        }
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
        
        
        System.debug('footerEncoded length: ' + footerEncoded.length());
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
            if (fileResponse == null) {
                System.debug('http response is null; check filesize > 12MB; returning...');
                return;
            }
            if (fileResponse.getStatusCode() == 201) {
                System.debug('File uploaded successfully');
            } else {
                System.debug('Failed to upload file: ' + fileResponse.getBody());
            }
        }
    }    
}