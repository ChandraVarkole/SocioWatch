/**
 * Safe exception used for SocioWatch API failures.
 *
 * Do not include credentials, authorization headers, raw stack traces,
 * or complete external-service responses in exception messages.
 */
public class SocioWatchApiException extends Exception {
}
