@IsTest
private class SocioWatchSyncSchedulerTest {

    @IsTest
    static void schedulerEnqueuesSync() {
        insert new SocioWatch_Configuration__c(
            Company_Name__c = 'Tesla',
            Keywords__c = 'Tesla',
            Alert_Id__c = 'alert_12345',
            Sync_Enabled__c = true,
            AWS_Company_Id__c = 'COMP-000001',
            Tenant_Id__c = 'TENANT-000001',
            Salesforce_Org_Id__c =
                UserInfo.getOrganizationId(),
            Last_Sync_Status__c = 'Not Started'
        );

        Test.setMock(
            HttpCalloutMock.class,
            new SchedulerHttpMock()
        );

        Test.startTest();

        String jobId = System.schedule(
            'SocioWatch Scheduler Test',
            '0 0 0 1 1 ? 2099',
            new SocioWatchSyncScheduler()
        );

        Test.stopTest();

        System.assertNotEquals(null, jobId);
    }

    private class SchedulerHttpMock
        implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader(
                'Content-Type',
                'application/json'
            );

            if (
                request.getEndpoint().endsWith('/v1/sync')
            ) {
                response.setBody(
                    '{"message":"Synchronization completed successfully."}'
                );
            } else {
                response.setBody(
                    '{"companyId":"COMP-000001",' +
                    '"count":0,"mentions":[]}'
                );
            }

            return response;
        }
    }
}
