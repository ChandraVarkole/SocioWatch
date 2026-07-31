@IsTest
public class SocioWatchHttpMock implements HttpCalloutMock {

    private Integer responseStatusCode;
    private String responseBody;
    private Map<String, String> responseHeaders;

    private String expectedMethod;
    private String expectedEndpoint;
    private String expectedRequestBody;

    public SocioWatchHttpMock(
        Integer responseStatusCode,
        String responseBody
    ) {
        this.responseStatusCode = responseStatusCode;
        this.responseBody = responseBody;
        this.responseHeaders = new Map<String, String>{
            'Content-Type' => 'application/json'
        };
    }

    public SocioWatchHttpMock expectRequest(
        String method,
        String endpoint,
        String requestBody
    ) {
        this.expectedMethod = method;
        this.expectedEndpoint = endpoint;
        this.expectedRequestBody = requestBody;

        return this;
    }

    public SocioWatchHttpMock withResponseHeader(
        String name,
        String value
    ) {
        responseHeaders.put(name, value);
        return this;
    }

    public HttpResponse respond(HttpRequest request) {
        if (expectedMethod != null) {
            System.assertEquals(
                expectedMethod,
                request.getMethod(),
                'Unexpected HTTP method.'
            );
        }

        if (expectedEndpoint != null) {
            System.assertEquals(
                expectedEndpoint,
                request.getEndpoint(),
                'Unexpected endpoint.'
            );
        }

        if (expectedRequestBody != null) {
            System.assertEquals(
                expectedRequestBody,
                request.getBody(),
                'Unexpected request body.'
            );
        }

        System.assertEquals(
            'application/json',
            request.getHeader('Accept'),
            'The client must request JSON.'
        );

        System.assertEquals(
            'application/json',
            request.getHeader('Content-Type'),
            'The client must send JSON.'
        );

        System.assertNotEquals(
            null,
            request.getHeader('X-Correlation-Id'),
            'A correlation ID must be included.'
        );

        System.assert(
            String.isNotBlank(
                request.getHeader('X-Correlation-Id')
            ),
            'The correlation ID cannot be blank.'
        );

        HttpResponse response = new HttpResponse();
        response.setStatusCode(responseStatusCode);
        response.setBody(responseBody);

        for (String headerName : responseHeaders.keySet()) {
            response.setHeader(
                headerName,
                responseHeaders.get(headerName)
            );
        }

        return response;
    }
}
