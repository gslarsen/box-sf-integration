public with sharing class GenerateEmailSamples {
    private static final Integer DAYS = 60; // how many days back to look for cases; NOTE: change SOQL in fetchCasesAndMetadata() to be < LAST_N_DAYS:DAYS
    private static final String EMAIL_SAMPLES_TO = 'notime2bbrief@gmail.com'; // change this to the email address you want to send the email samples to
    private static final Integer MAX_EMAILS_TO_SAMPLE = 1; // change this to the max number of emails samples to send via email (one email per sample email)
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
        processEmails();
    }

    // Case IDs and initial metadata - NEED TO GET DESIRED FIELDS AS > 300 in use
    private static Map<Id, Case> fetchCasesAndMetadata(){
        if(Schema.sObjectType.Case.isAccessible()){
            String query = 'SELECT Id, CaseNumber, Subject, Description, ClosedDate, CreatedDate, CreatedById, LastModifiedById, Origin, AccountId, Account.Name, ContactId, Contact.Name, OwnerId, Owner.Name, Status FROM Case WHERE ClosedDate = LAST_N_DAYS:' + DAYS;
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
                        'status' => c.Status
                    },
                    new List<EmailMessage>(),
                    // attachments related to cases and emails
                    new Map<String, List<Map<Id,Map<String,Object>>>>{'email' => new List<Map<Id,Map<String,Object>>>(), 'case' => new List<Map<Id,Map<String,Object>>>()}
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

    private static void processEmails(){
        for(Id caseId : caseToEmailsAndAttachments.keySet()){
            if(calloutLimitReached){
                System.debug('Callout limit reached; caseId: ' + caseId + ' will not be deleted from SF and any remaining cases will not be processed in this run, rather they will be processed in the next run');
                cases.remove(caseId);
                break;
            }
            List<EmailMessage> emailMessages = (List<EmailMessage>) caseToEmailsAndAttachments.get(caseId)[1];
            Map<String, List<Map<Id,Object>>> attachments = (Map<String, List<Map<Id,Object>>>) caseToEmailsAndAttachments.get(caseId)[2];
            List<Map<String,String>> emailMessagesContentEml = new List<Map<String,String>>();
            Integer countEmails = 0;

            for(EmailMessage e : emailMessages){
                countEmails++;
                if(countEmails > MAX_EMAILS_TO_SAMPLE){
                    break;
                }
                String emailDate = String.valueOf(e.MessageDate);
                String emailContent = prepareEmail(e, (List<Map<Id,Map<String,Object>>>)attachments.get('email'));
                if(emailContent == null || emailContent == ''){
                    System.debug('emailContent is null or empty');
                    continue;
                }
                emailMessagesContentEml.add(new Map<String,String>{emailDate => emailContent});
            }
            // create .eml files and send
            for(Integer i=0; i < emailMessagesContentEml.size(); ++i){
                String emailDate = new List<String>(emailMessagesContentEml[i].keySet())[0];
                String email = emailMessagesContentEml[i].get(emailDate) ;
                Blob emailEmlBlob = Blob.valueOf(email);
                String emailEmlFileName = emailDate + '.eml';

                if(!sendEmail(emailEmlBlob, emailEmlFileName, EMAIL_SAMPLES_TO)){
                    System.debug('Failed to send email file: ' + emailEmlFileName + ' caseId: ' + caseId + ' will not be deleted from SF');
                    cases.remove(caseId);
                }
            }
        }
    }

    private static Boolean sendEmail(Blob emailEmlBlob, String emailEmlFileName, String recipientEmail) {
        System.debug('Attempting to send email with attachment: ' + emailEmlFileName + ' to: ' + recipientEmail);
        Integer emailInvocations = Limits.getEmailInvocations();
        Integer limitEmailInvocations = Limits.getLimitEmailInvocations();
        System.debug(emailInvocations + ' of ' + limitEmailInvocations + ' email invocations used');
        if(emailInvocations >= limitEmailInvocations){
            System.debug('Callout limit reached');
            calloutLimitReached = true;
            return false;
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

        String[] toAddresses = new String[] {recipientEmail};
        mail.setToAddresses(toAddresses);
        mail.setSubject('EML Attachment Email');
        mail.setPlainTextBody('Please see the attached email');

        // Create the email attachment
        Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
        attachment.setBody(emailEmlBlob);
        attachment.setFileName(emailEmlFileName);
        attachment.setContentType('message/rfc822'); // MIME type for .eml files

        mail.setFileAttachments(new Messaging.EmailFileAttachment[] { attachment });

        // Send the email
        Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        if (results.size() > 0 && results[0].isSuccess()) {
            return true;
        } else {
            // Handle the failure case
            System.debug('Failed to send email with attachment: ' + emailEmlFileName);
            return false;
        }
    }

    private static String prepareEmail(EmailMessage e, List<Map<Id,Map<String,Object>>> attachments){
        // headers
        String emailContentEml = 'From: ' + e.FromName + ' [' + e.FromAddress + ']' + '\n' +
            'Date: ' + (e.MessageDate).format('EEE, dd MMM yyyy HH:mm:ss Z') + '\n' +
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
}