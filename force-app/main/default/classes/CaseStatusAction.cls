public with sharing class CaseStatusAction {

    public class Request {
        @InvocableVariable(
            label='Case Number'
            description='The customer\'s 8-digit support case number, exactly as typed, including leading zeros. Example: 00001027.'
            required=true)
        public String caseNumber;
    }

    public class Result {
        @InvocableVariable(label='Found' description='True if the case was found and its status can be shared with the customer.')
        public Boolean found;

        @InvocableVariable(label='Status' description='Current status of the case, for example New or Working. Empty if not found.')
        public String status;

        @InvocableVariable(label='Subject' description='Short subject of the case. Empty if not found.')
        public String subject;

        @InvocableVariable(label='Last Updated' description='When the case was last updated, as readable text. Empty if not found.')
        public String lastUpdated;

        @InvocableVariable(label='Message' description='A sentence to relay to the customer when Found is false.')
        public String message;
    }

    private static final Pattern CASE_NUMBER_PATTERN = Pattern.compile('^\\d{8}$');

    @InvocableMethod(
        label='Get Case Status'
        description='Looks up the current status of an existing support case using its 8-digit case number. Use only after the customer has given a case number.')
    public static List<Result> getStatus(List<Request> requests) {

        // 1. Validate and collect valid numbers (no query yet)
        Set<String> validNumbers = new Set<String>();
        for (Request req : requests) {
            String num = normalize(req);
            if (num != null) {
                validNumbers.add(num);
            }
        }

        // 2. One query for all valid numbers, enforcing the running user's access
        Map<String, Case> casesByNumber = new Map<String, Case>();
        Boolean queryFailed = false;
        if (!validNumbers.isEmpty()) {
            try {
                for (Case c : [
                    SELECT CaseNumber, Status, Subject, LastModifiedDate
                    FROM Case
                    WHERE CaseNumber IN :validNumbers
                    WITH USER_MODE
                ]) {
                    casesByNumber.put(c.CaseNumber, c);
                }
            } catch (QueryException e) {
                // e.g. the agent user lacks object or field access in user mode
                queryFailed = true;
            }
        }

        // 3. Build one Result per Request, in the same order (Part 3)
                List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(buildResult(normalize(req), casesByNumber, queryFailed));
        }
        return results;
    }

    private static Result buildResult(String num, Map<String, Case> casesByNumber, Boolean queryFailed) {
        Result res = new Result();
        res.found = false;

        if (num == null) {
            res.message = 'That does not look like a valid case number. Case numbers have exactly 8 digits, for example 00001027.';
        } else if (queryFailed) {
            res.message = 'Case details are not available right now.';
        } else if (!casesByNumber.containsKey(num)) {
            res.message = 'No case found with this number.';
        } else {
            Case c = casesByNumber.get(num);
            res.found = true;
            res.status = c.Status;
            res.subject = c.Subject;
            res.lastUpdated = c.LastModifiedDate.format('d MMMM yyyy, HH:mm');
        }
        return res;
    }

    // Returns the trimmed number if it is exactly 8 digits, otherwise null
    private static String normalize(Request req) {
        if (req == null || String.isBlank(req.caseNumber)) {
            return null;
        }
        String num = req.caseNumber.trim();
        return CASE_NUMBER_PATTERN.matcher(num).matches() ? num : null;
    }
}