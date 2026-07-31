/**
 * Centralized HTTP client for the SocioWatch AWS API.
 *
 * Security controls:
 * - Uses a Named Credential.
 * - Does not store or transmit credentials from Apex.
 * - Restricts HTTP methods.
 * - Restricts API paths.
 * - Rejects oversized request and response bodies.
 * - Uses a fixed timeout.
 * - Does not log request bodies, response bodies, or authorization headers.
 * - Returns sanitized error messages.
 */
public inherited sharing class SocioWatchApiClient {

    @TestVisible
    private static final String NAMED_CREDENTIAL =
        'callout:SocioWatch_API';

    @TestVisible
    private static final Integer TIMEOUT_MILLISECONDS = 30000;

    @TestVisible
    private static final Integer MAX_REQUEST_BODY_CHARACTERS = 100000;

    @TestVisible
    private static final Integer MAX_RESPONSE_BODY_CHARACTERS = 1000000;

    private static final Set<String> ALLOWED_METHODS = new Set<String>{
        'GET',
        'POST'
    };

    private static final Set<String> ALLOWED_PATHS = new Set<String>{
        '/v1/settings',
        '/v1/mentions',
        '/v1/chat',
        '/v1/sync'
    };

    /**
     * Performs a secure callout to an approved SocioWatch endpoint.
     *
     * @param method HTTP method. Only GET and POST are allowed.
     * @param path Relative SocioWatch API path.
     * @param body JSON request body. Null is allowed for GET requests.
     * @return Sanitized API response wrapper.
     */
    public static SocioWatchApiResponse send(
        String method,
        String path,
        String body
    ) {
        String normalizedMethod = normalizeMethod(method);
        String validatedPath = validateAndNormalizePath(path);

        validateBody(normalizedMethod, body);

        String correlationId = generateCorrelationId();

        HttpRequest request = new HttpRequest();
        request.setEndpoint(NAMED_CREDENTIAL + validatedPath);
        request.setMethod(normalizedMethod);
        request.setTimeout(TIMEOUT_MILLISECONDS);

        request.setHeader('Accept', 'application/json');
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('X-Correlation-Id', correlationId);

        if (String.isNotBlank(body)) {
            request.setBody(body);
        }

        HttpResponse response;

        try {
            response = new Http().send(request);
        } catch (System.CalloutException error) {
            System.debug(
                LoggingLevel.ERROR,
                'SocioWatch callout failed. Correlation ID: ' +
                correlationId
            );

            throw new SocioWatchApiException(
                'SocioWatch could not connect to the external service. ' +
                'Reference: ' + correlationId
            );
        }

        if (response == null) {
            throw new SocioWatchApiException(
                'SocioWatch received no response from the external service. ' +
                'Reference: ' + correlationId
            );
        }

        String responseBody = response.getBody();

        if (
            responseBody != null &&
            responseBody.length() > MAX_RESPONSE_BODY_CHARACTERS
        ) {
            System.debug(
                LoggingLevel.ERROR,
                'SocioWatch response exceeded the permitted size. ' +
                'Correlation ID: ' + correlationId
            );

            throw new SocioWatchApiException(
                'SocioWatch received an unexpectedly large response. ' +
                'Reference: ' + correlationId
            );
        }

        Integer statusCode = response.getStatusCode();

        if (statusCode < 200 || statusCode >= 300) {
            System.debug(
                LoggingLevel.ERROR,
                'SocioWatch API returned HTTP ' +
                statusCode +
                '. Correlation ID: ' +
                correlationId
            );

            throw buildStatusException(
                statusCode,
                correlationId
            );
        }

        return new SocioWatchApiResponse(
            statusCode,
            responseBody,
            correlationId
        );
    }

    /**
     * Convenience method for GET requests.
     */
    public static SocioWatchApiResponse get(String path) {
        return send(
            'GET',
            path,
            null
        );
    }

    /**
     * Convenience method for POST requests.
     */
    public static SocioWatchApiResponse post(
        String path,
        String jsonBody
    ) {
        return send(
            'POST',
            path,
            jsonBody
        );
    }

    private static String normalizeMethod(String method) {
        if (String.isBlank(method)) {
            throw new SocioWatchApiException(
                'An HTTP method is required.'
            );
        }

        String normalizedMethod = method.trim().toUpperCase();

        if (!ALLOWED_METHODS.contains(normalizedMethod)) {
            throw new SocioWatchApiException(
                'The requested HTTP method is not supported.'
            );
        }

        return normalizedMethod;
    }

    private static String validateAndNormalizePath(String path) {
        if (String.isBlank(path)) {
            throw new SocioWatchApiException(
                'A SocioWatch API path is required.'
            );
        }

        String normalizedPath = path.trim();

        if (!normalizedPath.startsWith('/')) {
            throw new SocioWatchApiException(
                'The SocioWatch API path is invalid.'
            );
        }

        if (
            normalizedPath.contains('://') ||
            normalizedPath.contains('\\') ||
            normalizedPath.contains('..') ||
            normalizedPath.contains('#') ||
            normalizedPath.contains('\r') ||
            normalizedPath.contains('\n')
        ) {
            throw new SocioWatchApiException(
                'The SocioWatch API path is invalid.'
            );
        }

        String basePath = normalizedPath;
        Integer queryPosition = normalizedPath.indexOf('?');

        if (queryPosition >= 0) {
            basePath = normalizedPath.substring(
                0,
                queryPosition
            );
        }

        if (!ALLOWED_PATHS.contains(basePath)) {
            throw new SocioWatchApiException(
                'The requested SocioWatch API path is not supported.'
            );
        }

        validateQueryString(
            basePath,
            normalizedPath
        );

        return normalizedPath;
    }

    private static void validateQueryString(
        String basePath,
        String completePath
    ) {
        Integer queryPosition = completePath.indexOf('?');

        if (queryPosition < 0) {
            return;
        }

        if (basePath != '/v1/mentions') {
            throw new SocioWatchApiException(
                'Query parameters are not allowed for this endpoint.'
            );
        }

        String queryString = completePath.substring(
            queryPosition + 1
        );

        if (String.isBlank(queryString)) {
            throw new SocioWatchApiException(
                'The SocioWatch query string is invalid.'
            );
        }

        List<String> parameters = queryString.split('&');

        for (String parameter : parameters) {
            List<String> nameAndValue = parameter.split('=', 2);

            if (
                nameAndValue.size() != 2 ||
                nameAndValue[0] != 'companyId' ||
                String.isBlank(nameAndValue[1])
            ) {
                throw new SocioWatchApiException(
                    'The SocioWatch query parameter is invalid.'
                );
            }

            validateIdentifier(nameAndValue[1]);
        }
    }

    private static void validateIdentifier(String encodedIdentifier) {
        String identifier;

        try {
            identifier = EncodingUtil.urlDecode(
                encodedIdentifier,
                'UTF-8'
            );
        } catch (Exception error) {
            throw new SocioWatchApiException(
                'The SocioWatch company identifier is invalid.'
            );
        }

        if (
            String.isBlank(identifier) ||
            identifier.length() > 100 ||
            !Pattern.matches(
                '^[A-Za-z0-9_-]+$',
                identifier
            )
        ) {
            throw new SocioWatchApiException(
                'The SocioWatch company identifier is invalid.'
            );
        }
    }

    private static void validateBody(
        String method,
        String body
    ) {
        if (method == 'GET' && String.isNotBlank(body)) {
            throw new SocioWatchApiException(
                'GET requests cannot contain a request body.'
            );
        }

        if (
            body != null &&
            body.length() > MAX_REQUEST_BODY_CHARACTERS
        ) {
            throw new SocioWatchApiException(
                'The SocioWatch request is too large.'
            );
        }

        if (String.isBlank(body)) {
            return;
        }

        try {
            JSON.deserializeUntyped(body);
        } catch (System.JSONException error) {
            throw new SocioWatchApiException(
                'The SocioWatch request body must contain valid JSON.'
            );
        }
    }

    private static String generateCorrelationId() {
        Blob randomValue = Crypto.generateAesKey(128);

        return EncodingUtil.convertToHex(randomValue);
    }

    private static SocioWatchApiException buildStatusException(
        Integer statusCode,
        String correlationId
    ) {
        String safeMessage;

        if (statusCode == 400) {
            safeMessage =
                'SocioWatch rejected the request because it was invalid.';
        } else if (
            statusCode == 401 ||
            statusCode == 403
        ) {
            safeMessage =
                'SocioWatch authentication or authorization failed.';
        } else if (statusCode == 404) {
            safeMessage =
                'The requested SocioWatch resource was not found.';
        } else if (statusCode == 409) {
            safeMessage =
                'The SocioWatch request conflicts with existing data.';
        } else if (statusCode == 429) {
            safeMessage =
                'SocioWatch is temporarily rate limited. Try again later.';
        } else if (statusCode >= 500) {
            safeMessage =
                'The SocioWatch service is temporarily unavailable.';
        } else {
            safeMessage =
                'The SocioWatch request could not be completed.';
        }

        return new SocioWatchApiException(
            safeMessage +
            ' Reference: ' +
            correlationId
        );
    }
}
