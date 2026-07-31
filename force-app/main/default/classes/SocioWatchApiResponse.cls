/**
 * Sanitized response returned by the SocioWatch API client.
 */
public class SocioWatchApiResponse {

    public Integer statusCode { get; private set; }
    public String responseBody { get; private set; }
    public String correlationId { get; private set; }

    public SocioWatchApiResponse(
        Integer statusCode,
        String responseBody,
        String correlationId
    ) {
        this.statusCode = statusCode;
        this.responseBody = responseBody;
        this.correlationId = correlationId;
    }

    public Boolean isSuccessful() {
        return statusCode >= 200 && statusCode < 300;
    }
}
