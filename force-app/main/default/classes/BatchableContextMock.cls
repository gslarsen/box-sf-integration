public class BatchableContextMock implements Database.BatchableContext {
    private ID jobId;

    public BatchableContextMock() {
        this.jobId = '001000000000ABC'; // Use a dummy ID
    }

    public ID getJobId() {
        return this.jobId;
    }

    public ID getBatchJobId() {
        return this.jobId;
    }

    public Integer getProcessInstanceId() {
        return 0;
    }

    public Map<String, Object> getTriggerOperation() {
        return new Map<String, Object>();
    }

    public ID getChildJobId() {
        return null;
    }
}
