@IsTest
private class CaseStatusActionTest {

    @TestSetup
    static void setup() {
        insert new Case(Subject = 'X200 Pro reboots every 10 minutes', Status = 'New', Origin = 'Web');
    }

    // CaseNumber is an auto-number, so read back the value Salesforce assigned
    private static String existingCaseNumber() {
        return [SELECT CaseNumber FROM Case LIMIT 1].CaseNumber;
    }

    private static CaseStatusAction.Request req(String num) {
        CaseStatusAction.Request r = new CaseStatusAction.Request();
        r.caseNumber = num;
        return r;
    }

    @IsTest
    static void returnsStatusForExistingCase() {
        String num = existingCaseNumber();

        Test.startTest();
        List<CaseStatusAction.Result> results =
            CaseStatusAction.getStatus(new List<CaseStatusAction.Request>{ req(num) });
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.isTrue(results[0].found);
        Assert.areEqual('New', results[0].status);
        Assert.areEqual('X200 Pro reboots every 10 minutes', results[0].subject);
        Assert.isNotNull(results[0].lastUpdated);
        Assert.isNull(results[0].message);
    }

    @IsTest
    static void rejectsInvalidFormatWithoutQuerying() {
        Test.startTest();
        List<CaseStatusAction.Result> results = CaseStatusAction.getStatus(
            new List<CaseStatusAction.Request>{ req('1027'), req(''), req(null), req('case 00001027') });
        Integer queriesUsed = Limits.getQueries();
        Test.stopTest();

        Assert.areEqual(0, queriesUsed, 'Invalid input must not reach SOQL');
        for (CaseStatusAction.Result r : results) {
            Assert.isFalse(r.found);
            Assert.isTrue(r.message.contains('8 digits'));
        }
    }

    @IsTest
    static void returnsNotFoundForUnknownNumber() {
        Test.startTest();
        List<CaseStatusAction.Result> results =
            CaseStatusAction.getStatus(new List<CaseStatusAction.Request>{ req('99999999') });
        Test.stopTest();

        Assert.isFalse(results[0].found);
        Assert.areEqual('No case found with this number.', results[0].message);
        Assert.isNull(results[0].status);
    }

    @IsTest
    static void keepsResultsInRequestOrder() {
        String num = existingCaseNumber();

        Test.startTest();
        List<CaseStatusAction.Result> results = CaseStatusAction.getStatus(
            new List<CaseStatusAction.Request>{ req('1027'), req(num), req('99999999') });
        Test.stopTest();

        Assert.areEqual(3, results.size());
        Assert.isFalse(results[0].found);
        Assert.isTrue(results[0].message.contains('8 digits'));
        Assert.isTrue(results[1].found);
        Assert.areEqual('No case found with this number.', results[2].message);
    }

    @IsTest
    static void doesNotExposeCaseToUserWithoutAccess() {
        String num = existingCaseNumber();
        User noAccess = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1].Id,
            Username = 'noaccess' + Datetime.now().getTime() + '@casestatus.test',
            LastName = 'NoAccess', Email = 'noaccess@casestatus.test', Alias = 'noacc',
            TimeZoneSidKey = 'Europe/Paris', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
        insert noAccess;

        List<CaseStatusAction.Result> results;
        System.runAs(noAccess) {
            Test.startTest();
            results = CaseStatusAction.getStatus(new List<CaseStatusAction.Request>{ req(num) });
            Test.stopTest();
        }

        Assert.isFalse(results[0].found, 'A user without access must not see the case');
        Assert.isNull(results[0].status);
        Assert.isNull(results[0].subject);
    }
}