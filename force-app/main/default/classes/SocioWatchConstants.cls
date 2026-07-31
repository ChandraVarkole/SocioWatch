/**
 * Central constants for the SocioWatch managed package.
 *
 * Keep user-facing text in Custom Labels.
 * Keep credentials in Named Credentials and External Credentials.
 */
public class SocioWatchConstants {

    private SocioWatchConstants() {
    }

    // API endpoints
    public static final String SETTINGS_ENDPOINT = '/v1/settings';
    public static final String MENTIONS_ENDPOINT = '/v1/mentions';
    public static final String CHAT_ENDPOINT = '/v1/chat';
    public static final String SYNC_ENDPOINT = '/v1/sync';

    // Custom permissions
    public static final String PERMISSION_MANAGE_SETTINGS =
        'SocioWatch_Manage_Settings';

    public static final String PERMISSION_RUN_SYNC =
        'SocioWatch_Run_Sync';

    public static final String PERMISSION_USE_CHAT =
        'SocioWatch_Use_Chat';

    // External platform
    public static final String EXTERNAL_PLATFORM_SALESFORCE =
        'salesforce';

    // Configuration limits
    public static final Integer MAX_COMPANY_NAME_LENGTH = 255;
    public static final Integer MAX_ALERT_ID_LENGTH = 255;
    public static final Integer MAX_KEYWORD_LENGTH = 100;
    public static final Integer MAX_KEYWORD_COUNT = 20;

    // Configuration status
    public static final String SYNC_STATUS_NOT_STARTED =
        'Not Started';

    public static final String SYNC_STATUS_IN_PROGRESS =
        'In Progress';

    public static final String SYNC_STATUS_SUCCESS =
        'Success';

    public static final String SYNC_STATUS_FAILED =
        'Failed';

    // Mention workflow status
    public static final String MENTION_STATUS_NEW =
        'New';

    public static final String MENTION_STATUS_REVIEWING =
        'Reviewing';

    public static final String MENTION_STATUS_RESPONSE_NEEDED =
        'Response Needed';

    public static final String MENTION_STATUS_RESPONDED =
        'Responded';

    public static final String MENTION_STATUS_RESOLVED =
        'Resolved';

    public static final String MENTION_STATUS_IGNORED =
        'Ignored';

    // Mention priorities
    public static final String PRIORITY_LOW =
        'Low';

    public static final String PRIORITY_MEDIUM =
        'Medium';

    public static final String PRIORITY_HIGH =
        'High';

    public static final String PRIORITY_CRITICAL =
        'Critical';

    // Generic limits
    public static final Integer MAX_SAFE_ERROR_LENGTH = 1000;
}
