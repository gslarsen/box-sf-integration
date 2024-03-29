public with sharing class ArchiveEmailsToBox_uncomment {
    private static final String ACCOUNTS_FOLDER_ID = '232841054083'; // change these to applicable Box folder IDs
    private static final String CONTACTS_FOLDER_ID = '234058604832';
    private static final String BOX_GET_CRED = 'box'; // change these to applicable named credential
    private static final String BOX_UPLOAD_CRED = 'boxUpload';
    private static final Integer DAYS = 60; // how many days back to look for cases; NOTE: change SOQL in fetchCasesAndMetadata() to be < LAST_N_DAYS:DAYS
    private static Map<Id, List<Object>> caseToEmailsAndAttachments = new Map<Id, List<Object>>();
    private static Map<Id, Case> cases = new Map<Id, Case>();
    private static Boolean calloutLimitReached = false;

    @future(callout=true)
    public static void archiveCases(){
        cases = fetchCasesAndMetadata();
        if(cases.isEmpty()){
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
        // fetchComments(caseIds); // NOTE: uncomment this line to fetch comments
        sendToBox();
        // List<Case> casesToDelete = new List<Case>(cases.values()); // NOTE: uncomment this line to delete cases from SF
        // deleteCases(casesToDelete); // NOTE: uncomment this line to delete cases from SF
    }

    // Case IDs and initial metadata - NEED TO GET DESIRED FIELDS AS > 300 in use
    private static Map<Id, Case> fetchCasesAndMetadata(){
        if(Schema.sObjectType.Case.isAccessible()){
            String query = 'SELECT Id, CaseNumber, Subject, Description, ClosedDate, CreatedDate, CreatedById, LastModifiedById, Origin, AccountId, Account.Name, ContactId, Contact.Name, OwnerId, Owner.Name, Status, Priority, Reason, Type, SuppliedEmail, SuppliedCompany, SuppliedName, SuppliedPhone FROM Case WHERE ClosedDate = LAST_N_DAYS:' + DAYS;
            Map<Id, Case> caseMap = new Map<Id, Case>((List<Case>) Database.query(query));
            if(caseMap.isEmpty()){
                System.debug('No cases found-returning');
            }

            for(Case c : caseMap.values()){
                caseToEmailsAndAttachments.put(c.Id, new List<Object>{
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
                    // attachments related to cases and emails
                    new Map<String, List<Map<Id,Map<String,Object>>>>{'email' => new List<Map<Id,Map<String,Object>>>(), 'case' => new List<Map<Id,Map<String,Object>>>()}//, // NOTE: uncomment this comma to fetch comments
                    // new List<CaseComment>() // NOTE: uncomment this line to fetch comments
                });
            }
            return caseMap;
        }else{
            System.debug('Case is not accessible');
            return null;
        }
    }

    private static List<String> fetchEmails(List<Id> caseIds, Map<Id, Id> emailIdToCaseId){
        List<String> emailIdsWithAttachments = new List<String>();
        if(Schema.sObjectType.EmailMessage.isAccessible()){
            for(EmailMessage e : [SELECT Id, ParentId, TextBody, Subject, Name, FromName, FromAddress, ToAddress, CcAddress, BccAddress, HasAttachment, MessageDate, IsDeleted FROM EmailMessage WHERE ParentId IN :caseIds]){
                if(caseToEmailsAndAttachments.containsKey(e.ParentId)){
                    ((List<EmailMessage>)caseToEmailsAndAttachments.get(e.ParentId)[1]).add(e);
                    emailIdToCaseId.put(e.Id, e.ParentId);
                }
                if(e.HasAttachment){
                    emailIdsWithAttachments.add(e.Id);
                }
            }
        }else{
            System.debug('EmailMessage is not accessible');
        }
        return emailIdsWithAttachments;
    }

    // private static void fetchComments(List<Id> caseIds){
    //     if(Schema.sObjectType.CaseComment.isAccessible()){
    //         for(CaseComment c : [SELECT Id, ParentId, CommentBody, CreatedDate, CreatedById, CreatedBy.Name FROM CaseComment WHERE ParentId IN :caseIds]){
    //             if(caseToEmailsAndAttachments.containsKey(c.ParentId)){
    //                 ((List<CaseComment>)caseToEmailsAndAttachments.get(c.ParentId)[3]).add(c);
    //             }
    //         }
    //     }else{
    //         System.debug('CaseComment is not accessible');
    //     }
    // }

    private static void fetchAttachments(List<Id> combinedIds, Map<Id, Id> emailIdToCaseId, List<Id> emailIdsWithAttachments){
        if(!Schema.sObjectType.ContentDocumentLink.isAccessible() || !Schema.sObjectType.ContentVersion.isAccessible()){
            System.debug('ContentDocumentLink or ContentVersion is not accessible');
            return;
        }
        List<ContentDocumentLink> contentDocumentLinks = [SELECT ContentDocumentId, LinkedEntityId FROM ContentDocumentLink WHERE LinkedEntityId IN :combinedIds];
        List<Id> contentDocumentIds = new List<Id>();
        Map<Id, Id> docIdToLinkedEntity = new Map<Id, Id>();
        for(ContentDocumentLink cdl : contentDocumentLinks){
            contentDocumentIds.add(cdl.ContentDocumentId);
            docIdToLinkedEntity.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
        }

        Map<Id, Map<Id, Map<String, Object>>> docIdToAttachment = new  Map<Id, Map<Id, Map<String, Object>>>();
        for(ContentVersion cv : [SELECT ContentDocumentId, VersionData, Title, FileExtension FROM ContentVersion WHERE ContentDocumentId IN :contentDocumentIds AND IsLatest = true]){
            Id linkedEntityId = docIdToLinkedEntity.get(cv.ContentDocumentId);
            Map<Id, Map<String, Object>> linkedEntityIdToAttachment = new Map<Id, Map<String, Object>>{
                linkedEntityId => new Map<String, Object>{
                'blob' => cv.VersionData,
                'fileName' => cv.Title,
                'fileExtension' => cv.FileExtension
            }};
            docIdToAttachment.put(cv.ContentDocumentId, linkedEntityIdToAttachment);
        }

        for(ContentDocumentLink cdl : contentDocumentLinks){
            Boolean isEmail = false;
            Id linkedEntityId = cdl.LinkedEntityId;
            if(emailIdToCaseId.containsKey(linkedEntityId)){
                isEmail = true;
                // If the linked entity is an email, get the case ID from the email ID
                linkedEntityId = emailIdToCaseId.get(linkedEntityId);
            }

            if(caseToEmailsAndAttachments.containsKey(linkedEntityId)){
                Map<Id, Map<String, Object>> linkedEntityIdToAttachment = docIdToAttachment.get(cdl.ContentDocumentId);
                if(isEmail){
                    ((Map<String, List<Map<Id,Map<String,Object>>>>)caseToEmailsAndAttachments.get(linkedEntityId)[2]).get('email').add(linkedEntityIdToAttachment);
                }else{
                    ((Map<String, List<Map<Id,Map<String,Object>>>>)caseToEmailsAndAttachments.get(linkedEntityId)[2]).get('case').add(linkedEntityIdToAttachment);
                }
            }
        }
    }

    private static void sendToBox(){
        for(Id caseId : caseToEmailsAndAttachments.keySet()){
            if(calloutLimitReached){
                System.debug('Callout limit reached; caseId: ' + caseId + ' will not be deleted from SF and any remaining cases will not be processed in this run, rather they will be processed in the next run');
                cases.remove(caseId);
                break;
            }
            Map<String, String> metadata = (Map<String, String>) caseToEmailsAndAttachments.get(caseId)[0];
            String accountId = metadata.get('accountId');
            String contactId = metadata.get('contactId');
            if(accountId != null && accountId != ''){
                prepAndUpload(caseId, ACCOUNTS_FOLDER_ID, accountId);
            }else if(contactId != null && contactId != ''){
                prepAndUpload(caseId, CONTACTS_FOLDER_ID, contactId);
            }else{
                System.debug('Both accountId and contactId are null or empty - caseId: ' + caseId + ' will not be deleted from SF');
                cases.remove(caseId);
            }
        }
    }

    private static void prepAndUpload(String caseId, String accountsOrContactsFolderId, String acctOrContactId){
        Map<String, String> metadata = (Map<String, String>) caseToEmailsAndAttachments.get(caseId)[0];
        String caseNumber = metadata.get('caseNumber');
        String createdDate = metadata.get('createdDate');
        String closedDate = metadata.get('closedDate');

        if(caseNumber == null || caseNumber == '' || createdDate == null || createdDate == '' || closedDate == null || closedDate == ''){
            System.debug('caseNumber, createdDate or closedDate is null or empty - caseId: ' + caseId + ' will not be deleted from SF');
            cases.remove(caseId);
            return;
        }
        // remove time from dates
        String regexTime = '\\s\\d{2}:\\d{2}:\\d{2}';
        createdDate = createdDate.replaceAll(regexTime, '');
        closedDate = closedDate.replaceAll(regexTime, '');
        // remove leading zeros from case #
        String regexLeadingZeros = '^0+';
        caseNumber = caseNumber.replaceAll(regexLeadingZeros, '');
        String id = acctOrContactId;

        String accountOrContactFolderId = getOrCreateFolder(accountsOrContactsFolderId, id);
        if(accountOrContactFolderId == null || accountOrContactFolderId == ''){
            System.debug('accountOrContactFolderId is null or empty - caseId: ' + caseId + ' will not be deleted from SF');
            cases.remove(caseId);
            return;
        }

        String casesFolderId = getOrCreateFolder(accountOrContactFolderId, 'Cases');
        if(casesFolderId == null || casesFolderId == ''){
            System.debug('casesFolderId is null or empty - caseId: ' + caseId + ' will not be deleted from SF');
            cases.remove(caseId);
            return;
        }

        String caseFolderId = getOrCreateFolder(casesFolderId, caseNumber + '_' + createdDate + '_' + closedDate);
        if(caseFolderId == null || caseFolderId == ''){
            System.debug('caseFolderId Id is null or empty - caseId: ' + caseId + ' will not be deleted from SF');
            cases.remove(caseId);
            return;
        }
        // UNCOMMENT as req'd - send attachments, emails and details to Box
        // sendAttachmentsToBox(caseId, caseFolderId);
        sendEmailsToBox(caseId, caseFolderId);
        // sendDetailsToBox(caseId, caseFolderId);
    }

    // private static void sendAttachmentsToBox(String caseId, String caseFolderId){
    //     Map<String, List<Map<Id,Object>>> attachments = (Map<String, List<Map<Id,Object>>>) caseToEmailsAndAttachments.get(caseId)[2];

    //     for(Map<Id,Map<String,Object>> attachmentObj : (List<Map<Id,Map<String,Object>>>)attachments.get('case')){
    //         Id linkedEntityId = new List<Id>(attachmentObj.keySet())[0];
    //         Map<String,Object> attachment = (Map<String, Object>)attachmentObj.get(linkedEntityId);
    //         Blob attachmentBinary = (Blob)attachment.get('blob');
    //         String attachmentFilename = (String)attachment.get('fileName') + '.' + (String)attachment.get('fileExtension');

    //         Map<String, Object> blobAttachment = new Map<String, Object>{
    //             'blob' => attachmentBinary,
    //             'fileName' => attachmentFilename
    //         };
    //         if(!uploadFileToBox(blobAttachment, caseFolderId)){
    //             System.debug('Failed to upload case attachment file: ' + attachmentFilename + ' caseId: ' + caseId + ' will not be deleted from SF');
    //             cases.remove(caseId);
    //         }
    //     }
    // }

    private static void sendEmailsToBox(String caseId, String caseFolderId){
        List<EmailMessage> emailMessages = (List<EmailMessage>) caseToEmailsAndAttachments.get(caseId)[1];
        Map<String, List<Map<Id,Object>>> attachments = (Map<String, List<Map<Id,Object>>>) caseToEmailsAndAttachments.get(caseId)[2];
        // store data for each email message
        List<Map<String,String>> emailMessagesContentEml = new List<Map<String,String>>();

        for(EmailMessage e : emailMessages){
            String emailSent = String.valueOf(e.MessageDate);
            String emailContent = prepareEmail(e, (List<Map<Id,Map<String,Object>>>)attachments.get('email'));
            if(emailContent == null || emailContent == ''){
                System.debug('emailContent is null or empty');
                continue;
            }
            emailMessagesContentEml.add(new Map<String,String>{emailSent => emailContent});
        }
        // create .eml files and upload
        for(Integer i=0; i < emailMessagesContentEml.size(); ++i){
            String emailSent = new List<String>(emailMessagesContentEml[i].keySet())[0];
            String email = emailMessagesContentEml[i].get(emailSent) ;
            Blob emailEmlBlob = Blob.valueOf(email);
            String emailEmlFileName = emailSent + '.eml';

            Map<String, Object> emailEmlAttachment = new Map<String, Object>{
                'blob' => emailEmlBlob,
                'fileName' => emailEmlFileName,
                'fileType' => 'text/plain'
            };
            if(!uploadFileToBox(emailEmlAttachment, caseFolderId)){
                System.debug('Failed to upload email file: ' + emailEmlFileName + ' caseId: ' + caseId + ' will not be deleted from SF');
                cases.remove(caseId);
            }
        }
    }

    // private static void sendDetailsToBox(String caseId, String caseFolderId){
    //     Map<String, String> metadata = (Map<String, String>) caseToEmailsAndAttachments.get(caseId)[0];
    //     List<CaseComment> comments = (List<CaseComment>) caseToEmailsAndAttachments.get(caseId)[3];

    //     String pdfContent = 'Case Number: ' + metadata.get('caseNumber') + '<br>' + 'Subject: ' + metadata.get('subject') + '<br>' +
    //     'Status: ' + metadata.get('status') + '<br>' + 'Priority: ' + metadata.get('priority') + '<br>' +
    //     'Description: ' + metadata.get('description') + '<br>' + 'Closed Date: ' + metadata.get('closedDate') + '<br>' +
    //     'Created Date: ' + metadata.get('createdDate') + '<br>' + 'Origin: ' + metadata.get('origin') + '<br>' +
    //     'Created By Id: ' + metadata.get('createdById') + '<br>' +
    //     'Last Modified By Id: ' + metadata.get('lastModifiedById') + '<br>' +
    //     'Account Id: ' + metadata.get('accountId') + '<br>' + 'Account Name: ' + metadata.get('accountName') + '<br>' +
    //     'Contact Id: ' + metadata.get('contactId') + '<br>' + 'Contact Name: ' + metadata.get('contactName') + '<br>' +
    //     'Owner Id: ' + metadata.get('ownerId') + '<br>' + 'Owner Name: ' + metadata.get('ownerName') + '<br>' +
    //     'Reason: ' + metadata.get('reason') + '<br>' + 'Type: ' + metadata.get('caseType') + '<br>' +
    //     'Supplied Email: ' + metadata.get('suppliedEmail') + '<br>' + 'Supplied Company: ' + metadata.get('suppliedCompany') + '<br>' +
    //     'Supplied Name: ' + metadata.get('suppliedName') + '<br>' + 'Supplied Phone: ' + metadata.get('suppliedPhone');

    //     String commentsContent = '';
    //     for(CaseComment c : comments){
    //         commentsContent += 'Comment Id: ' + c.Id + '<br>' +
    //         'Created Date: ' + c.CreatedDate + '<br>' +
    //         'Created By Id: ' + c.CreatedById + '<br>' +
    //         'Created By Name: ' + c.CreatedBy.Name + '<br>' +
    //         'Comment: ' + c.CommentBody + '<br><br>';
    //     }

    //     pdfContent += '<br><br>' + commentsContent;
    //     Blob pdfBlob = Blob.toPdf(pdfContent);
    //     String pdfFileName = 'details.pdf';
    //     Map<String, Object> pdfAttachment = new Map<String, Object>{
    //         'blob' => pdfBlob,
    //         'fileName' => pdfFileName,
    //         'fileType' => 'application/pdf'
    //     };
    //     if(!uploadFileToBox(pdfAttachment, caseFolderId)){
    //         System.debug('Failed to upload case details file: ' + pdfFileName + ' caseId: ' + caseId + ' will not be deleted from SF');
    //         cases.remove(caseId);
    //     }
    // }

    private static String prepareEmail(EmailMessage e, List<Map<Id,Map<String,Object>>> attachments){
        // headers
        String emailContentEml = 'From: ' + e.FromName + ' [' + e.FromAddress + ']' + '\n' +
            'Sent: ' + String.valueOf(e.MessageDate) + '\n' +
            'To: ' + e.ToAddress + '\n' +
            'Cc: ' + (e.CcAddress == null ? '' : e.CcAddress) + '\n' +
            'Bcc: ' + (e.BccAddress == null ? '' : e.BccAddress) + '\n' +
            'Subject: ' + e.Subject + '\n' +
            'MIME-Version: 1.0' + '\n' +
            'Content-Type: multipart/mixed; boundary="main_boundary"\n\n';
        // body
        String body = '';
        body += '--main_boundary\n';
        body += 'Content-Type: multipart/alternative; boundary="alternate_boundary"\n\n';

        if(String.isNotEmpty(e.TextBody)){
            body += '--alternate_boundary\n';
            body += 'Content-Type: text/plain; charset=UTF-8\n\n';
            body += e.TextBody + '\n\n';
        }

        body += '--alternate_boundary--\n\n';

        // attachments
        if(e.HasAttachment){
            for(Map<Id,Map<String,Object>> attachmentObj : attachments){
                Id linkedEntityId = new List<Id>(attachmentObj.keySet())[0];
                if(linkedEntityId != e.Id){
                    continue;
                }

                Map<String,Object> attachment = (Map<String, Object>)attachmentObj.get(linkedEntityId);
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

        body += '--main_boundary--\n\n';
        emailContentEml += body;
        return emailContentEml;
    }

    private static String getOrCreateFolder(String parentId, String folderName){
        String folderBody = '{"name":"' + folderName + '", "parent": {"id":"' + parentId + '"}}';
        HttpResponse createRes = makeBoxApiCall(new Map<String, String>{'endpoint' => 'folders', 'method' => 'POST', 'attributes' => null, 'body' => folderBody, 'fileName' => null}, null);
        if(createRes == null){
            System.debug('http response is null; failed to get/create folder: ' + folderName + ' in parent folder: ' + parentId);
            return '';
        }
        if(createRes.getStatusCode() == 201){
            try{
                Map<String, Object> createResponse = (Map<String, Object>) JSON.deserializeUntyped(createRes.getBody());
                String newFolderId = (String) createResponse.get('id');
                return newFolderId;
            }catch(JSONException e){
                System.debug('Failed to parse JSON response: ' + e.getMessage());
                return '';
            }catch(Exception e){
                System.debug('An error has occurred: ' + e.getMessage());
                return '';
            }
        }
        if(createRes.getStatusCode() == 409){
            try{
                // check if folder already exists and if so, return the folder ID
                Map<String, Object> createResponse = (Map<String, Object>)JSON.deserializeUntyped(createRes.getBody());
                if(createResponse.get('code') == 'item_name_in_use'){
                    Map<String, Object> contextInfo = (Map<String, Object>)createResponse.get('context_info');
                    List<Object> conflicts = (List<Object>)contextInfo.get('conflicts');
                    Map<String, Object> conflict = (Map<String, Object>)conflicts[0];
                    String folderId = (String)conflict.get('id');
                    return folderId;
                }
            }catch(JSONException e){
                System.debug('Failed to parse JSON response: ' + e.getMessage());
                return '';
            }catch(Exception e){
                System.debug('An error has occurred: ' + e.getMessage());
                return '';
            }
        }
        System.debug('Failed to get/create folder: ' + createRes.getBody());
        return '';
    }

    private static HttpResponse makeBoxApiCall(Map<String, String> config, Blob fileBlob){
        Integer callouts = Limits.getCallouts();
        if(callouts == Limits.getLimitCallouts()){
            calloutLimitReached = true;
            System.debug('Callout limit reached: ' + callouts + '; no further callouts will be made');
            return null;
        }
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setMethod(config.get('method'));
        req.setTimeout(120000);

        if(fileBlob != null){
            req.setEndpoint('callout:' + BOX_UPLOAD_CRED + '/' + config.get('endpoint'));
        }else{
            req.setEndpoint('callout:' + BOX_GET_CRED + '/' + config.get('endpoint'));
        }

        if(String.isNotBlank(config.get('body')) && fileBlob == null){
            req.setHeader('Content-Type', 'application/json');
            req.setBody(config.get('body'));
        }

        if (fileBlob != null) {
			String boundary = '--boundary';
            blob base64File = prepareMultipartFormBinary(fileBlob, config.get('fileName'));
            if (base64File == null) {
                return null;
            }
            req.setHeader('Content-Type','multipart/form-data; boundary=' + boundary);
            req.setBodyAsBlob(base64File);
        }
        try{
            HttpResponse res = http.send(req);
            return res;
        }catch(CalloutException e){
            System.debug('A callout error has occurred: ' + e.getMessage());
            return null;
        }
    }

    // this method enables posting multipart/form-data to Box
    // ref: https://github.com/box/box-salesforce-sdk/blob/master/src/classes/BoxBase64.cls Origin with background: https://enreeco.blogspot.com/2013/01/salesforce-apex-post-mutipartform-data.html
    public static Blob prepareMultipartFormBinary(Blob fileBody, String fileName){
        if(fileBody == null || fileName == null || fileName == ''){
            return null;
        }
        String boundary = '--boundary';
        String header = '--' + boundary + '\nContent-Disposition: form-data; name="file"; filename="' + fileName + '";\nContent-Type: application/octet-stream';
        String footer = '--' + boundary + '--';
        String headerEncoded = EncodingUtil.base64Encode(Blob.valueOf(header + '\r\n\r\n'));

		while(headerEncoded.endsWith('=')){
            header += ' ';
            headerEncoded = EncodingUtil.base64Encode(Blob.valueOf(header + '\r\n\r\n'));
        }

        String bodyEncoded = EncodingUtil.base64Encode(fileBody);
		// 12MB limit from SF; due to string bloat with base64 encoding, this results in an
		// effective file size limit of 8.6MB for asynch Apex (https://developer.box.com/guides/tooling/salesforce-toolkit/methods/)
        if(bodyEncoded.length() > 12000000){
            System.debug('FILE SIZE OF: ' + fileName + ' IS TOO LARGE: ' + bodyEncoded.length());
            return null;
        }

        Blob bodyBlob = null;
        String last4Bytes = bodyEncoded.substring(bodyEncoded.length()-4,bodyEncoded.length());

        if(last4Bytes.endsWith('==')){ // indicate 4 bits of padding added to end of string
            last4Bytes = last4Bytes.substring(0,2) + '0K'; // replace with '0K', which represents the remaining Base64 characters to finish with CRLF
            bodyEncoded = bodyEncoded.substring(0,bodyEncoded.length()-4) + last4Bytes;
        }else if(last4Bytes.endsWith('=')){
            last4Bytes = last4Bytes.substring(0,3) + 'N';  // replace with 'N' for remainder of CR
            bodyEncoded = bodyEncoded.substring(0,bodyEncoded.length()-4) + last4Bytes;
            footer = '\n' + footer; // handle LF
        }else{
            footer = '\r\n' + footer;
        }

        String footerEncoded = EncodingUtil.base64Encode(Blob.valueOf(footer));
        bodyBlob = EncodingUtil.base64Decode(headerEncoded + bodyEncoded + footerEncoded);
        return bodyBlob;
    }

    private static Boolean uploadFileToBox(Map<String, Object> attachment, String caseFolderId){
        Blob fileBlob = (Blob) attachment.get('blob');
        String fileName = (String) attachment.get('fileName');
        String fileEndpoint = 'files/content?parent_id=' + caseFolderId;
        HttpResponse fileResponse = makeBoxApiCall(new Map<String, String>{'endpoint' => fileEndpoint, 'method' => 'POST', 'body' => null, 'fileName' => fileName}, fileBlob);

        if(fileResponse == null){
            System.debug('http response is null; file: ' + fileName + ' not uploaded and case in caseFolderId: ' + caseFolderId + ' will not be deleted from SF');
            return false;
        }
        if(fileResponse.getStatusCode() == 201){
            System.debug('File uploaded successfully');
            return true;
        }
        if(fileResponse.getStatusCode() == 409){
            try{
                // check if file already exists and if so, return true
                Map<String, Object> createResponse = (Map<String, Object>)JSON.deserializeUntyped(fileResponse.getBody());
                if(createResponse.get('code') == 'item_name_in_use'){
                    Map<String, Object> contextInfo = (Map<String, Object>)createResponse.get('context_info');
                    Map<String, Object> conflicts = (Map<String, Object>)contextInfo.get('conflicts');
                    String boxFileName = (String)conflicts.get('name');
                    return boxFileName == fileName;
                }
                return false;
            }catch(JSONException e){
                System.debug('Failed to parse JSON response: ' + e.getMessage());
                return false;
            }catch(Exception e){
                System.debug('An error has occurred: ' + e.getMessage());
                return false;
            }
        }
        System.debug('Failed to upload file: ' + fileName + '; response: ' + fileResponse.getBody() + '; case in caseFolderId: ' + caseFolderId + ' will not be deleted from SF');
        return false;
    }

    // private static void deleteCases(List<Case> cases){
    //     if(cases.isEmpty()){
    //         System.debug('No cases to delete');
    //         return;
    //     }
    //     if(Schema.sObjectType.Case.isDeletable()){
    //         try{
    //             delete cases;
    //         }catch(DmlException e){
    //             System.debug('A DML error deleting cases has occurred: ' + e.getMessage());
    //             for(Integer i = 0; i < e.getNumDml(); i++) {
    //                 System.debug('Error occurred on record with ID: ' + e.getDmlId(i) + '; message: ' + e.getDmlMessage(i));
    //             }
    //         }catch(Exception e){
    //             System.debug('An error deleting cases has occurred: ' + e.getMessage());
    //         }
    //     }else{
    //         System.debug('Case object is not deletable');
    //     }
    // }
}