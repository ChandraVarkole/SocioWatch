/**
 * Centralized custom-permission checks for SocioWatch features.
 *
 * Custom permissions control feature access only.
 * CRUD, FLS, sharing, and record access must still be enforced
 * by the service performing the database operation.
 */
public with sharing class SocioWatchPermissionService {

    private SocioWatchPermissionService() {
    }

    public static Boolean canManageSettings() {
        return hasPermission(
            SocioWatchConstants.PERMISSION_MANAGE_SETTINGS
        );
    }

    public static Boolean canRunSync() {
        return hasPermission(
            SocioWatchConstants.PERMISSION_RUN_SYNC
        );
    }

    public static Boolean canUseChat() {
        return hasPermission(
            SocioWatchConstants.PERMISSION_USE_CHAT
        );
    }

    public static void requireManageSettings() {
        requirePermission(
            SocioWatchConstants.PERMISSION_MANAGE_SETTINGS
        );
    }

    public static void requireRunSync() {
        requirePermission(
            SocioWatchConstants.PERMISSION_RUN_SYNC
        );
    }

    public static void requireUseChat() {
        requirePermission(
            SocioWatchConstants.PERMISSION_USE_CHAT
        );
    }

    @TestVisible
    private static Boolean hasPermission(
        String permissionDeveloperName
    ) {
        if (String.isBlank(permissionDeveloperName)) {
            return false;
        }

        return FeatureManagement.checkPermission(
            permissionDeveloperName
        );
    }

    @TestVisible
    private static void requirePermission(
        String permissionDeveloperName
    ) {
        if (!hasPermission(permissionDeveloperName)) {
            throw new SocioWatchAccessException(
                'You do not have permission to perform this ' +
                'SocioWatch operation.'
            );
        }
    }
}
