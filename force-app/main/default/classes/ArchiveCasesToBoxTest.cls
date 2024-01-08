/**
 * This class contains unit tests for validating the behavior of Apex classes
 * and triggers.
 *
 * Unit tests are class methods that verify whether a particular piece
 * of code is working properly. Unit test methods take no arguments,
 * commit no data to the database, and are flagged with the testMethod
 * keyword in the method definition.
 *
 * All test methods in an org are executed whenever Apex code is deployed
 * to a production org to confirm correctness, ensure code
 * coverage, and prevent regressions. All Apex classes are
 * required to have at least 75% code coverage in order to be deployed
 * to a production org. In addition, all triggers must have some code coverage.
 *
 * The @isTest class annotation indicates this class only contains test
 * methods. Classes defined with the @isTest annotation do not count against
 * the org size limit for all Apex scripts.
 *
 * See the Apex Language Reference for more information about Testing and Code Coverage.
 */
@isTest
private class ArchiveCasesToBoxTest {
    // Mock classs for HTTP callouts
    private class HttpCalloutMockSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest request){
            // Create a fake HTTP response
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"id": "fakeId"}');
            response.setStatusCode(201);
            return response;
        }
    }

    private class HttpCalloutMockFail implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest request){
            // Create a fake HTTP response
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"type": "error"}');
            response.setStatusCode(400);
            return response;
        }
    }

    private class HttpCalloutMock409Folder implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest request){
            // Create a fake HTTP response
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"type":"error","status":409,"code":"item_name_in_use","context_info":{"conflicts":[{"type":"folder","id":"236457074091","sequence_id":"3","etag":"3","name":"1034_2023-11-22_2023-11-22"}]},"help_url":"","message":"Item with the same name already exists","request_id":"gi3kjqhki82gv726"}');
            response.setStatusCode(409);
            return response;
        }
    }

    private class HttpCalloutMock409File implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest request){
            // Create a fake HTTP response
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"type":"error","status":409,"code":"item_name_in_use","context_info":{"conflicts":{"type":"file","id":"1376407667429","file_version":{"type":"file_version","id":"1507763368229","sha1":"b91054179db580950120ee3e69804b063cb6180f"},"sequence_id":"0","etag":"0","sha1":"b91054179db580950120ee3e69804b063cb6180f","name":"details.pdf"}},"help_url":"http:","message":"Item with the same name already exists","request_id":"d0d6j3hki8sni8e2"}');
            response.setStatusCode(409);
            return response;
        }
    }

    @isTest
    static void testStartMethod() {
        // Setup test data
        List<Case> cases = new List<Case>();
        for(Integer i = 0; i < 5; i++) {
            if(Math.mod(i, 2) == 0){
                cases.add(new Case(Status = 'Closed',Origin = 'Web',Subject='Test Case: ' + i,Description='Test Description: ' + i));
            } else {
                cases.add(new Case(Status = 'New',Origin = 'Web',Subject='Test Case: ' + i,Description='Test Description: ' + i));

            }
        }
        insert cases;

        // Create a new instance of ArchiveCasesToBox
        ArchiveCasesToBox batchable = new ArchiveCasesToBox();

        // Call the start method
        Database.QueryLocator locator = batchable.start(null);

        // Iterate over the returned QueryLocator
        Database.QueryLocatorIterator it = locator.iterator();

        // Assert the expected results
        Integer count = 0;
        while(it.hasNext()) {
            Case c = (Case)it.next();
            System.assert(c != null, 'Case should not be null');
            System.assertEquals('Closed', c.Status, 'Case should be closed');
            count++;
        }

        System.assertEquals(3, count, 'Correct number of cases should be returned');
    }

    // @isTest
    // static void testExecuteMethod() { // delete? this method and the accompanying BatchableContextMock class - it's not required by SF
    //      // Set the mock callout class
    //      Test.setMock(HttpCalloutMock.class, new HttpCalloutMockSuccess());

    //     Account testAccount = new Account(Name = 'Test Account');
    //     insert testAccount;

    //     List<Case> cases = new List<Case>();
    //     for(Integer i = 0; i < 5; i++) {
    //         if(Math.mod(i, 2) == 0){
    //             cases.add(new Case(Status = 'Closed', Origin = 'Web', Subject='Test Case: ' + i, Description='Test Description: ' + i, AccountId = testAccount.Id));
    //         } else {
    //             cases.add(new Case(Status = 'New', Origin = 'Web', Subject='Test Case: ' + i, Description='Test Description: ' + i, AccountId = testAccount.Id));
    //         }
    //     }
    //     insert cases;

    //     // Create a new instance of ArchiveCasesToBox
    //     ArchiveCasesToBox batchable = new ArchiveCasesToBox();

    //     // Call the start method
    //     Database.QueryLocator locator = batchable.start(null);

    //     // Get the first batch of cases
    //     Database.QueryLocatorIterator it = locator.iterator();
    //     List<Case> firstBatch = new List<Case>();
    //     for(Integer i = 0; i < 200 && it.hasNext(); i++) {
    //         firstBatch.add((Case)it.next());
    //     }

    //     // Create a new instance of Database.BatchableContext
    //     Test.startTest();
    //     Database.BatchableContext bc = new BatchableContextMock(); // Assume you have a mock for Database.BatchableContext
    //     batchable.execute(bc, firstBatch);
    //     Test.stopTest();

    //     // Assert the expected results
    //     System.assertEquals(3, (ArchiveCasesToBox.cases).size(), 'Correct number of cases should be ready for deleting');
    // }

    @isTest
    static void testArchiveCasesSuccessfulBox(){
         // Set the mock callout class
         Test.setMock(HttpCalloutMock.class, new HttpCalloutMockSuccess());

        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        Contact testContact = new Contact(LastName = 'TestContact', AccountId = testAccount.Id);
        insert testContact;

        List<Case> cases = new List<Case>();
        for(Integer i = 0; i < 5; i++) {
            Case c;
            if(Math.mod(i, 2) == 0){
                c = new Case(Status = 'Closed', Origin = 'Web', Subject='Test Case: ' + i, Description='Test Description: ' + i, AccountId=testAccount.Id);
            } else {
                c = new Case(Status = 'New', Origin = 'Web', Subject='Test Case: ' + i, Description='Test Description: ' + i, AccountId=testAccount.Id);
            }
            cases.add(c);
        }

        insert cases;
        for(Case c : cases) {
            Test.setCreatedDate(c.Id, DateTime.now());
        }

        // MODIFY DATE CRITERION: Query the cases from the database to get the system fields
        List<Case> queriedCases = [SELECT Id, CaseNumber, Subject, Description, ClosedDate, CreatedDate, CreatedById, LastModifiedById, Origin, AccountId, Account.Name, ContactId, Contact.Name, OwnerId, Owner.Name, Status, Priority, Reason, Type, SuppliedEmail, SuppliedCompany, SuppliedName, SuppliedPhone FROM Case WHERE ClosedDate = LAST_N_DAYS:60];

        // Create a new instance of ArchiveCasesToBox
        Test.startTest();
        ArchiveCasesToBox.archiveCases(queriedCases);
        Test.stopTest();

        // Assert the expected results
        System.assertEquals(3, (ArchiveCasesToBox.cases).size(), 'Correct number of cases should be ready for deleting');
    }

    @isTest
    static void testArchiveCasesFailBox(){
         // Set the mock callout class
         Test.setMock(HttpCalloutMock.class, new HttpCalloutMockFail());

        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        Contact testContact = new Contact(LastName = 'TestContact', AccountId = testAccount.Id);
        insert testContact;

        List<Case> cases = new List<Case>();
        for(Integer i = 0; i < 5; i++) {
            Case c;
            if(Math.mod(i, 2) == 0){
                c = new Case(Status = 'Closed', Origin = 'Web', Subject='Test Case: ' + i, Description='Test Description: ' + i, AccountId=testAccount.Id);
            } else {
                c = new Case(Status = 'New', Origin = 'Web', Subject='Test Case: ' + i, Description='Test Description: ' + i, AccountId=testAccount.Id);
            }
            cases.add(c);
        }

        insert cases;
        for(Case c : cases) {
            Test.setCreatedDate(c.Id, DateTime.now());
        }

        // MODIFY DATE CRITERION: Query the cases from the database to get the system fields
        List<Case> queriedCases = [SELECT Id, CaseNumber, Subject, Description, ClosedDate, CreatedDate, CreatedById, LastModifiedById, Origin, AccountId, Account.Name, ContactId, Contact.Name, OwnerId, Owner.Name, Status, Priority, Reason, Type, SuppliedEmail, SuppliedCompany, SuppliedName, SuppliedPhone FROM Case WHERE ClosedDate = LAST_N_DAYS:60];

        // Create a new instance of ArchiveCasesToBox
        Test.startTest();
        ArchiveCasesToBox.archiveCases(queriedCases);
        Test.stopTest();

        // Assert the expected results
        System.assertEquals(0, (ArchiveCasesToBox.cases).size(), 'No cases should be ready for deleting');
    }

    @isTest
    static void testFetchEmails(){
        // Prepare test data
        Case c = new Case(Subject = 'Test Case', Status = 'New');
        insert c;

        EmailMessage e = new EmailMessage(
            ParentId = c.Id,
            FromName = 'Test Sender',
            FromAddress = 'test@example.com',
            MessageDate = DateTime.now(),
            ToAddress = 'recipient@example.com',
            CcAddress = 'cc@example.com',
            BccAddress = 'bcc@example.com',
            Subject = 'Test Subject',
            TextBody = 'Test Body'
        );
        insert e;

        // Prepare attachments
        Blob blobBody = Blob.valueOf('Unit Test Attachment Body');
        Attachment attachment = new Attachment(
            Name = 'TestAttachment.txt',
            Body = blobBody,
            ParentId = e.Id
        );
        insert attachment;

        // Prepare caseToEmailsAndAttachments
        ArchiveCasesToBox.caseToEmailsAndAttachments = new Map<Id, List<Object>>{
            c.Id => new List<Object>{new List<Id>(), new List<EmailMessage>()}
        };

        // Prepare emailIdToCaseId
        Map<Id, Id> emailIdToCaseId = new Map<Id, Id>();

        // Call the method to test
        Test.startTest();
        List<String> emailIdsWithAttachments = ArchiveCasesToBox.fetchEmails(new List<Id>{c.Id}, emailIdToCaseId);
        Test.stopTest();

        // Add assertions to verify the results
        System.assertEquals(1, emailIdsWithAttachments.size(), 'emailIdsWithAttachments size should be 1');
        System.assertEquals(e.Id, emailIdsWithAttachments[0], 'emailIdsWithAttachments should contain the emailId');
        System.assertEquals(c.Id, emailIdToCaseId.get(e.Id), 'emailIdToCaseId should contain the emailId and caseId');
    }

    @isTest
    static void testFetchComments(){
        // Prepare test data
        Case c = new Case(Subject = 'Test Case', Status = 'New');
        insert c;

        CaseComment comment = new CaseComment(ParentId = c.Id, CommentBody = 'Test Comment');
        insert comment;

        // Prepare caseToEmailsAndAttachments
        ArchiveCasesToBox.caseToEmailsAndAttachments = new Map<Id, List<Object>>{
            c.Id => new List<Object>{new List<Id>(), new List<EmailMessage>(), new List<Id>(), new List<CaseComment>()}
        };

        // Call the method to test
        Test.startTest();
        ArchiveCasesToBox.fetchComments(new List<Id>{c.Id});
        Test.stopTest();

        // Add assertions to verify the results
        List<CaseComment> fetchedComments = (List<CaseComment>)ArchiveCasesToBox.caseToEmailsAndAttachments.get(c.Id)[3];
        System.assertEquals(1, fetchedComments.size(), 'fetchedComments size should be 1');
        System.assertEquals(comment.Id, fetchedComments[0].Id, 'fetchedComments should contain the commentId');
    }

    @isTest
    static void testFetchAttachments(){
        // Prepare test data
        Case c = new Case(Subject = 'Test Case', Status = 'New');
        insert c;

        EmailMessage e = new EmailMessage(
            ParentId = c.Id,
            FromName = 'Test Sender',
            FromAddress = 'test@example.com',
            MessageDate = DateTime.now(),
            ToAddress = 'recipient@example.com',
            CcAddress = 'cc@example.com',
            BccAddress = 'bcc@example.com',
            Subject = 'Test Subject',
            TextBody = 'Test Body'
        );
        insert e;

        ContentVersion cv = new ContentVersion(
            Title = 'Test',
            PathOnClient = 'Test.txt',
            VersionData = Blob.valueOf('Test Content'),
            IsMajorVersion = true
        );
        insert cv;

        List<ContentDocumentLink> links = new List<ContentDocumentLink>{
            new ContentDocumentLink(ContentDocumentId = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId, LinkedEntityId = c.Id, ShareType = 'V'),
            new ContentDocumentLink(ContentDocumentId = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId, LinkedEntityId = e.Id, ShareType = 'V')
        };
        insert links;

        // Prepare caseToEmailsAndAttachments
        ArchiveCasesToBox.caseToEmailsAndAttachments = new Map<Id, List<Object>>{
            c.Id => new List<Object>{new List<Id>(), new List<EmailMessage>(), new Map<String, List<Map<Id,Map<String,Object>>>>{'case' => new List<Map<Id,Map<String,Object>>>(), 'email' => new List<Map<Id,Map<String,Object>>>()}, new List<CaseComment>()}
        };

        // Prepare emailIdToCaseId
        Map<Id, Id> emailIdToCaseId = new Map<Id, Id>{e.Id => c.Id};

        // Prepare combinedIds
        List<Id> combinedIds = new List<Id>{c.Id, e.Id};

        // Call the method to test
        Test.startTest();
        ArchiveCasesToBox.fetchAttachments(combinedIds, emailIdToCaseId, new List<Id>{e.Id});
        Test.stopTest();

        // Add assertions to verify the results
        Map<String, List<Map<Id,Map<String,Object>>>> fetchedAttachments = (Map<String, List<Map<Id,Map<String,Object>>>>)ArchiveCasesToBox.caseToEmailsAndAttachments.get(c.Id)[2];
        System.assertEquals(1, fetchedAttachments.get('case').size(), 'case size should be 1');
        System.assertEquals(1, fetchedAttachments.get('email').size(), 'email size should be 1');
    }

    @isTest
    static void testSendToBoxCalloutLimitReached(){
        // Prepare test data
        ArchiveCasesToBox.calloutLimitReached = true;
        List<Case> testCases = new List<Case>();
        Case c = new Case(Subject = 'Test Case', Status = 'New');
        insert c;
        testCases.add(c);

        String caseFolderId = '67890';
        Map<String, String> metadata = new Map<String, String>{
            'caseNumber' => c.CaseNumber,
            'subject' => 'Test Subject'
        };

        ArchiveCasesToBox.caseToEmailsAndAttachments.put(c.Id, new List<Object>{metadata, null, null, null});
        Map<Id, Case> caseMap = new Map<Id, Case>((List<Case>) testCases);
        ArchiveCasesToBox.cases = caseMap;
        // // Set up the mock
        // Test.setMock(HttpCalloutMock.class, new HttpCalloutMockSuccess());

        // Call the method to test
        Test.startTest();
        ArchiveCasesToBox.sendToBox();
        Test.stopTest();

        // Add assertions to verify the results
        System.assertEquals(0, ArchiveCasesToBox.cases.size(), 'cases should be empty');
    }

    @isTest
    static void testSendDetailsToBox(){
        // Prepare test data
        List<Case> testCases = new List<Case>();
        Case c = new Case(Subject = 'Test Case', Status = 'New');
        insert c;
        testCases.add(c);

        String caseFolderId = '67890';
        Map<String, String> metadata = new Map<String, String>{
            'caseNumber' => c.CaseNumber,
            'subject' => 'Test Subject'
        };
        List<CaseComment> comments = new List<CaseComment>{
            new CaseComment(ParentId = c.Id, CommentBody = 'Test Comment')
        };
        ArchiveCasesToBox.caseToEmailsAndAttachments.put(c.Id, new List<Object>{metadata, null, null, comments});
        Map<Id, Case> caseMap = new Map<Id, Case>((List<Case>) testCases);
        ArchiveCasesToBox.cases = caseMap;
        // Set up the mock
        Test.setMock(HttpCalloutMock.class, new HttpCalloutMockSuccess());

        // Call the method to test
        Test.startTest();
        ArchiveCasesToBox.sendDetailsToBox(c.Id, caseFolderId);
        Test.stopTest();

        // Add assertions to verify the results
        System.assertEquals(true, ArchiveCasesToBox.cases.containsKey(c.Id), 'cases should contain the caseId');
    }

    @isTest
    static void testSendToBoxAccountIdNull(){
        // Prepare test data
        List<Case> testCases = new List<Case>();
        Case c = new Case(Subject = 'Test Case', Status = 'New');
        insert c;
        testCases.add(c);
        for(Case testCase : testCases) {
            Test.setCreatedDate(testCase.Id, DateTime.now());
        }

        String caseFolderId = '67890';
        List<Case> queriedCases = [SELECT Id, CaseNumber, Subject, Description, ClosedDate, CreatedDate, CreatedById, LastModifiedById, Origin, AccountId, Account.Name, ContactId, Contact.Name, OwnerId, Owner.Name, Status, Priority, Reason, Type, SuppliedEmail, SuppliedCompany, SuppliedName, SuppliedPhone FROM Case WHERE ClosedDate = LAST_N_DAYS:60];
        // Case queriedCase = queriedCases[0]; !!! this is not used anywhere
        Map<String, String> metadata = new Map<String, String>{
            // 'caseNumber' => queriedCase.CaseNumber,
            // 'createdDate' => queriedCase.CreatedDate.format('yyyy-MM-dd'),
            // 'closedDate' => queriedCase.ClosedDate.format('yyyy-MM-dd'),
            'subject' => 'Test Subject',
            'accountId' => null,
            'contactId' => '1234567890ABCDE'
        };

        ArchiveCasesToBox.caseToEmailsAndAttachments.put(c.Id, new List<Object>{metadata, null, null, null});
        Map<Id, Case> caseMap = new Map<Id, Case>((List<Case>) testCases);
        ArchiveCasesToBox.cases = caseMap;
        // Set up the mock
        Test.setMock(HttpCalloutMock.class, new HttpCalloutMockSuccess());

        // Call the method to test
        Test.startTest();
        ArchiveCasesToBox.sendToBox();
        Test.stopTest();

        // Add assertions to verify the results
        System.assertEquals(0, ArchiveCasesToBox.cases.size(), 'cases should be empty');
    }

    @isTest
    static void testSendAttachmentsToBox() {
        // Prepare test data
        List<Case> testCases = new List<Case>();
        Case c = new Case(Subject = 'Test Case', Status = 'New');
        insert c;
        testCases.add(c);

        String caseFolderId = '67890';
        Map<Id, Map<String, Object>> attachmentObj = new Map<Id, Map<String, Object>>{
            c.Id => new Map<String, Object>{
                'blob' => Blob.valueOf('Test Content'),
                'fileName' => 'Test.txt'
            }
        };
        List<Map<Id,Map<String,Object>>> attachmentsList = new List<Map<Id,Map<String,Object>>>();
        attachmentsList.add(attachmentObj);

        Map<String, List<Map<Id, Object>>> attachments = new Map<String, List<Map<Id,Map<String,Object>>>>{'email' => attachmentsList, 'case' => attachmentsList};
        ArchiveCasesToBox.caseToEmailsAndAttachments.put(c.Id, new List<Object>{null, null, attachments, null});
        Map<Id, Case> caseMap = new Map<Id, Case>((List<Case>) testCases);
        ArchiveCasesToBox.cases = caseMap;

        // Set up the mock
        Test.setMock(HttpCalloutMock.class, new HttpCalloutMockSuccess());

        // Call the method to test
        Test.startTest();
        ArchiveCasesToBox.sendAttachmentsToBox(c.Id, caseFolderId);
        Test.stopTest();

        // Add assertions to verify the results
        System.assertEquals(true, ArchiveCasesToBox.cases.containsKey(c.Id), 'cases should contain the caseId');
    }

    @isTest
    static void testSendEmailsToBox() {
        // Prepare test data
        List<Case> testCases = new List<Case>();
        Case c = new Case(Subject = 'Test Case', Status = 'New');
        insert c;
        testCases.add(c);

        String caseFolderId = '67890';
        List<EmailMessage> emailMessages = new List<EmailMessage>{
            new EmailMessage(MessageDate = DateTime.now(), TextBody = 'Test Body', Subject = 'Test Subject', FromName = 'Test Sender', FromAddress = 'test@test.com', ToAddress = 'test2@test.com')
        };
        Map<Id, Map<String, Object>> attachmentObj = new Map<Id, Map<String, Object>>{
            c.Id => new Map<String, Object>{
                'blob' => Blob.valueOf('Test Content'),
                'fileName' => 'Test.txt'
            }
        };
        List<Map<Id,Map<String,Object>>> attachmentsList = new List<Map<Id,Map<String,Object>>>();
        attachmentsList.add(attachmentObj);

        Map<String, List<Map<Id, Object>>> attachments = new Map<String, List<Map<Id,Map<String,Object>>>>{'email' => attachmentsList, 'case' => attachmentsList};
        ArchiveCasesToBox.caseToEmailsAndAttachments.put(c.Id, new List<Object>{null, emailMessages, attachments, null});
        Map<Id, Case> caseMap = new Map<Id, Case>((List<Case>) testCases);
        ArchiveCasesToBox.cases = caseMap;

        // Set up the mock
        Test.setMock(HttpCalloutMock.class, new HttpCalloutMockSuccess());

        // Call the method to test
        Test.startTest();
        ArchiveCasesToBox.sendEmailsToBox(c.Id, caseFolderId);
        Test.stopTest();

        // Add assertions to verify the results
        System.assertEquals(true, ArchiveCasesToBox.cases.containsKey(c.Id), 'cases should contain the caseId');
    }

    @isTest
    static void testPrepareEmail(){
        // Prepare test data
        EmailMessage e = new EmailMessage(
            FromName = 'Test Sender',
            FromAddress = 'test@example.com',
            MessageDate = DateTime.now(),
            ToAddress = 'recipient@example.com',
            CcAddress = 'cc@example.com',
            BccAddress = 'bcc@example.com',
            Subject = 'Test Subject',
            TextBody = 'Test Body'
        );
        insert e;

        // Prepare attachments
        Blob blobBody = Blob.valueOf('Unit Test Attachment Body');
        Attachment attachment = new Attachment(
            Name = 'TestAttachment.txt',
            Body = blobBody,
            ParentId = e.Id
        );
        insert attachment;

        List<Map<Id,Map<String,Object>>> attachments = new List<Map<Id,Map<String,Object>>>();
        Map<String, Object> attachmentMap = new Map<String, Object>{
            'blob' => blobBody,
            'fileName' => 'TestAttachment',
            'fileExtension' => 'txt'
        };
        attachments.add(new Map<Id,Map<String,Object>>{
            e.Id => attachmentMap
        });

        // Select the EmailMessage record
        EmailMessage selectedEmail = [SELECT Id, FromName, FromAddress, MessageDate, ToAddress, CcAddress, BccAddress, Subject, TextBody, HasAttachment FROM EmailMessage WHERE Id = :e.Id];
        System.debug('selectedEmail: ' + selectedEmail);
        // Call the method to test
        Test.startTest();
        String emailContent = ArchiveCasesToBox.prepareEmail(selectedEmail, attachments);
        Test.stopTest();

        // Add assertions to verify the results
        System.assert(emailContent.contains('From: Test Sender [test@example.com]'), 'Email content should contain the From address');
        System.assert(emailContent.contains('To: recipient@example.com'), 'Email content should contain the To address');
        System.assert(emailContent.contains('Cc: cc@example.com'), 'Email content should contain the Cc address');
        System.assert(emailContent.contains('Bcc: bcc@example.com'), 'Email content should contain the Bcc address');
        System.assert(emailContent.contains('Subject: Test Subject'), 'Email content should contain the Subject');
        System.assert(emailContent.contains('Test Body'), 'Email content should contain the Body');
        System.assert(emailContent.contains('TestAttachment.txt'), 'Email content should contain the Attachment name');
    }

    @isTest
    static void testGetOrCreateFolderFail(){
        // Prepare test data
        String parentId = '12345';
        String folderName = 'TestFolder';

        // Set up the mock
        Test.setMock(HttpCalloutMock.class, new HttpCalloutMockFail());

        // Call the method to test
        Test.startTest();
        String folderId = ArchiveCasesToBox.getOrCreateFolder(parentId, folderName);
        Test.stopTest();

        // Add assertions to verify the results
        System.assertEquals('', folderId, 'Folder should not be created or retrieved');
    }

    @isTest
    static void testGetOrCreateFolder409(){
        // Prepare test data
        String parentId = '12345';
        String folderName = 'TestFolder';

        // Set up the mock
        Test.setMock(HttpCalloutMock.class, new HttpCalloutMock409Folder());

        // Call the method to test
        Test.startTest();
        String folderId = ArchiveCasesToBox.getOrCreateFolder(parentId, folderName);
        Test.stopTest();

        // Add assertions to verify the results
        System.assertNotEquals('', folderId, 'Folder should be created or retrieved');
        System.assertNotEquals(null, folderId, 'Folder should be created or retrieved');
    }

    @isTest
    static void testUploadFileToBoxFail(){
        // Prepare test data
        Map<String, Object> attachment = new Map<String, Object>{
            'blob' => Blob.valueOf('Test Content'),
            'fileName' => 'Test.txt'
        };
        String caseFolderId = '12345';

        // Set up the mock
        Test.setMock(HttpCalloutMock.class, new HttpCalloutMockFail());

        // Call the method to test
        Test.startTest();
        Boolean isUploaded = ArchiveCasesToBox.uploadFileToBox(attachment, caseFolderId);
        Test.stopTest();

        // Add assertions to verify the results
        System.assertEquals(false, isUploaded, 'File should not be uploaded');
    }

    @isTest
    static void testUploadFileToBox409(){
        // Prepare test data
        Map<String, Object> attachment = new Map<String, Object>{
            'blob' => Blob.valueOf('Test Content'),
            'fileName' => 'Test.txt'
        };
        String caseFolderId = '12345';

        // Set up the mock
        Test.setMock(HttpCalloutMock.class, new HttpCalloutMock409File());

        // Call the method to test
        Test.startTest();
        Boolean isUploaded = ArchiveCasesToBox.uploadFileToBox(attachment, caseFolderId);
        Test.stopTest();

        // Add assertions to verify the results
        System.assertEquals(false, isUploaded, 'File should not be uploaded, as it already exists');
    }

    @isTest
    static void testDeleteCases(){
        // Prepare test data
        List<Case> cases = new List<Case>{
            new Case(Subject = 'Test Case 1', Status = 'New'),
            new Case(Subject = 'Test Case 2', Status = 'New')
        };
        insert cases;

        // Call the method to test
        Test.startTest();
        ArchiveCasesToBox.deleteCases(cases);
        Test.stopTest();

        // Add assertions to verify the results
        List<Case> remainingCases = [SELECT Id FROM Case WHERE Id IN :cases];
        System.assertEquals(0, remainingCases.size(), 'Cases should be deleted');
    }
}