//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Session context capture for UnitOfWork transactions.
 * Captures user identity, auth session, organization, and request context.
 *
 * EFFICIENCY: Information is cached statically since it doesn't change
 * within a transaction. Use getInstance() to access cached data.
 *
 * This class consolidates all user/session/environment information in one place,
 * separating it from transaction execution state (UoWContext).
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Core
 * @see UoWContext
 * @see UoWGovernorLimits
 */
public inherited sharing class UoWSessionContext {

    // ============================================================================
    // STATIC CACHE - Captured once per transaction
    // ============================================================================

    private static UoWSessionContext cachedInstance;

    /**
     * Get cached session context (captured once per transaction).
     *
     * @return UoWSessionContext instance with all session data
     */
    public static UoWSessionContext getInstance() {
        if (cachedInstance == null) {
            cachedInstance = new UoWSessionContext();
        }
        return cachedInstance;
    }

    /**
     * Reset cache (for testing).
     */
    @TestVisible
    private static void resetCache() {
        cachedInstance = null;
        cachedOrganization = null;
    }

    // ============================================================================
    // PUBLIC PROPERTIES - USER IDENTITY
    // ============================================================================

    // Basic identity
    public Id userId { get; private set; }
    public String username { get; private set; }
    public String userEmail { get; private set; }
    public String firstName { get; private set; }
    public String lastName { get; private set; }
    public String name { get; private set; }
    public String userType { get; private set; }

    // Profile
    public Id profileId { get; private set; }
    public String profileName { get; private set; }

    // Role
    public Id userRoleId { get; private set; }
    public String userRoleName { get; private set; }

    // License
    public String userLicenseName { get; private set; }

    // Federation/SSO
    public String federationIdentifier { get; private set; }

    // ============================================================================
    // PUBLIC PROPERTIES - USER PREFERENCES
    // ============================================================================

    public String locale { get; private set; }
    public String language { get; private set; }
    public String timeZoneSidKey { get; private set; }
    public String timeZoneName { get; private set; }
    public Integer timeZoneOffset { get; private set; }
    public String uiTheme { get; private set; }
    public String uiThemeDisplayed { get; private set; }

    // ============================================================================
    // PUBLIC PROPERTIES - ORGANIZATION
    // ============================================================================

    public Id organizationId { get; private set; }
    public String organizationName { get; private set; }
    public String organizationInstanceName { get; private set; }
    public String organizationType { get; private set; }
    public String organizationNamespacePrefix { get; private set; }
    public Boolean isSandbox { get; private set; }

    // ============================================================================
    // PUBLIC PROPERTIES - AUTH SESSION
    // ============================================================================

    public AuthSessionInfo authSession { get; private set; }

    // ============================================================================
    // PUBLIC PROPERTIES - REQUEST/EXECUTION
    // ============================================================================

    public String requestId { get; private set; }
    public String quiddity { get; private set; }
    public Boolean isAsyncContext { get; private set; }
    public Boolean isTestContext { get; private set; }

    // ============================================================================
    // PUBLIC PROPERTIES - METADATA
    // ============================================================================

    public DateTime capturedAt { get; private set; }

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    private UoWSessionContext() {
        this.capturedAt = DateTime.now();
        captureUserIdentity();
        captureUserPreferences();
        captureOrganization();
        captureRequest();
        captureAuthSession();
    }

    // ============================================================================
    // PRIVATE METHODS - USER CAPTURE
    // ============================================================================

    // Capture basic user identity (no SOQL needed)
    private void captureUserIdentity() {
        this.userId = UserInfo.getUserId();
        this.username = UserInfo.getUserName();
        this.userEmail = UserInfo.getUserEmail();
        this.firstName = UserInfo.getFirstName();
        this.lastName = UserInfo.getLastName();
        this.name = UserInfo.getName();
        this.profileId = UserInfo.getProfileId();
        this.userType = UserInfo.getUserType();

        // Extended info requires SOQL
        captureExtendedUserInfo();
    }

    // Capture extended user info via SOQL
    private void captureExtendedUserInfo() {
        try {
            List<User> users = [
                SELECT Profile.Name,
                       UserRole.Name,
                       UserRoleId,
                       FederationIdentifier,
                       Profile.UserLicense.Name
                FROM User
                WHERE Id = :this.userId
                WITH USER_MODE
                LIMIT 1
            ];

            if (!users.isEmpty()) {
                User currentUser = users[0];
                this.profileName = currentUser.Profile?.Name;
                this.userRoleId = currentUser.UserRoleId;
                this.userRoleName = currentUser.UserRole?.Name;
                this.federationIdentifier = currentUser.FederationIdentifier;
                this.userLicenseName = currentUser.Profile?.UserLicense?.Name;
            }
        } catch (Exception ex) {
            // Silently fail - this info is nice-to-have, not critical
        }
    }

    // Capture user preferences (no SOQL needed)
    private void captureUserPreferences() {
        this.locale = UserInfo.getLocale();
        this.language = UserInfo.getLanguage();

        TimeZone tz = UserInfo.getTimeZone();
        if (tz != null) {
            this.timeZoneSidKey = tz.getId();
            this.timeZoneName = tz.getDisplayName();
            this.timeZoneOffset = tz.getOffset(DateTime.now());
        }

        this.uiTheme = UserInfo.getUiTheme();
        this.uiThemeDisplayed = UserInfo.getUiThemeDisplayed();
    }

    // ============================================================================
    // PRIVATE METHODS - ORGANIZATION CAPTURE
    // ============================================================================

    private static Organization cachedOrganization;

    // Capture organization information
    private void captureOrganization() {
        this.organizationId = UserInfo.getOrganizationId();
        this.organizationName = UserInfo.getOrganizationName();

        // Get extended Organization details via SOQL (cached)
        Organization org = getOrganizationInfo();
        if (org != null) {
            this.organizationInstanceName = org.InstanceName;
            this.organizationType = org.OrganizationType;
            this.organizationNamespacePrefix = org.NamespacePrefix;
            this.isSandbox = org.IsSandbox;
        }
    }

    // Get Organization info (cached - only query once per transaction)
    private Organization getOrganizationInfo() {
        if (cachedOrganization == null) {
            try {
                List<Organization> orgs = [
                    SELECT InstanceName, OrganizationType, NamespacePrefix, IsSandbox
                    FROM Organization
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!orgs.isEmpty()) {
                    cachedOrganization = orgs[0];
                }
            } catch (Exception ex) {
                // Silently fail
            }
        }
        return cachedOrganization;
    }

    // ============================================================================
    // PRIVATE METHODS - REQUEST CAPTURE
    // ============================================================================

    // Capture request/transaction context
    private void captureRequest() {
        Request currentRequest = Request.getCurrent();
        System.Quiddity currentQuiddity = currentRequest.getQuiddity();

        this.requestId = currentRequest.getRequestId();
        this.quiddity = currentQuiddity?.name();

        this.isAsyncContext = currentQuiddity == System.Quiddity.BATCH_APEX ||
                              currentQuiddity == System.Quiddity.QUEUEABLE ||
                              currentQuiddity == System.Quiddity.FUTURE ||
                              currentQuiddity == System.Quiddity.SCHEDULED;

        this.isTestContext = currentQuiddity == System.Quiddity.RUNTEST_DEPLOY ||
                             currentQuiddity == System.Quiddity.RUNTEST_SYNC ||
                             currentQuiddity == System.Quiddity.RUNTEST_ASYNC;
    }

    // ============================================================================
    // PRIVATE METHODS - AUTH SESSION CAPTURE
    // ============================================================================

    // Capture auth session information
    private void captureAuthSession() {
        this.authSession = new AuthSessionInfo();
    }

    // ============================================================================
    // PUBLIC API - CONVENIENCE METHODS
    // ============================================================================

    /**
     * Check if user is a guest user.
     *
     * @return True if user is a guest user
     */
    public Boolean isGuestUser() {
        return this.userType == 'Guest';
    }

    /**
     * Check if user is a community/portal user.
     *
     * @return True if user is a community or portal user
     */
    public Boolean isCommunityUser() {
        return this.userType == 'CspLitePortal' ||
               this.userType == 'CustomerSuccess' ||
               this.userType == 'PowerCustomerSuccess' ||
               this.userType == 'PowerPartner' ||
               this.userType == 'CsnOnly';
    }

    /**
     * Check if session is impersonated (admin logged in as user).
     *
     * @return True if this is an impersonated session
     */
    public Boolean isImpersonated() {
        return this.authSession != null && this.authSession.isImpersonated == true;
    }

    // ============================================================================
    // INNER CLASSES - AUTH SESSION
    // ============================================================================

    /**
     * Auth session details from AuthSession object.
     * Captures how the user authenticated and session security level.
     */
    public class AuthSessionInfo {

        // ============================================================================
        // PUBLIC PROPERTIES
        // ============================================================================

        // Session identity
        public Id sessionId { get; private set; }
        public Id parentSessionId { get; private set; }
        public Id usersId { get; private set; }

        // Login details
        public String loginType { get; private set; }
        public String loginHistoryId { get; private set; }

        // Session type and security
        public String sessionType { get; private set; }
        public String sessionSecurityLevel { get; private set; }

        // Client information
        public String sourceIp { get; private set; }

        // Impersonation tracking
        public Boolean isImpersonated { get; private set; }

        // Logout URL for Experience Cloud users
        public String logoutUrl { get; private set; }

        // Timestamps
        public DateTime createdDate { get; private set; }
        public DateTime lastModifiedDate { get; private set; }
        public Boolean isCurrent { get; private set; }

        // ============================================================================
        // CONSTRUCTORS
        // ============================================================================

        public AuthSessionInfo() {
            this.isImpersonated = false;
            capture();
        }

        // ============================================================================
        // PRIVATE METHODS
        // ============================================================================

        private void capture() {
            // Check if AuthSession is accessible
            if (!Schema.sObjectType.AuthSession.isAccessible()) {
                return;
            }

            try {
                // Get current session ID
                String currentSessionId = UserInfo.getSessionId();
                if (String.isBlank(currentSessionId)) {
                    return;
                }

                // Query AuthSession for current user's active session
                List<AuthSession> sessions = [
                    SELECT Id,
                           ParentId,
                           UsersId,
                           LoginType,
                           LoginHistoryId,
                           SessionType,
                           SessionSecurityLevel,
                           SourceIp,
                           LogoutUrl,
                           CreatedDate,
                           LastModifiedDate,
                           IsCurrent
                    FROM AuthSession
                    WHERE UsersId = :UserInfo.getUserId()
                      AND IsCurrent = true
                    WITH USER_MODE
                    LIMIT 1
                ];

                if (!sessions.isEmpty()) {
                    AuthSession session = sessions[0];
                    this.sessionId = session.Id;
                    this.parentSessionId = session.ParentId;
                    this.usersId = session.UsersId;
                    this.loginType = session.LoginType;
                    this.loginHistoryId = session.LoginHistoryId;
                    this.sessionType = session.SessionType;
                    this.sessionSecurityLevel = session.SessionSecurityLevel;
                    this.sourceIp = session.SourceIp;
                    this.logoutUrl = session.LogoutUrl;
                    this.createdDate = session.CreatedDate;
                    this.lastModifiedDate = session.LastModifiedDate;
                    this.isCurrent = session.IsCurrent;

                    // Check for impersonation
                    checkImpersonation();
                }
            } catch (Exception ex) {
                // Silently fail - auth session info is nice-to-have
            }
        }

        // Check if current session is impersonated
        private void checkImpersonation() {
            if (String.isBlank(this.loginHistoryId)) {
                return;
            }

            try {
                // Check LoginHistory for impersonation indicator
                if (Schema.sObjectType.LoginHistory.isAccessible()) {
                    List<LoginHistory> histories = [
                        SELECT Id
                        FROM LoginHistory
                        WHERE Id = :this.loginHistoryId
                          AND LoginType = 'Impersonated User'
                        WITH USER_MODE
                        LIMIT 1
                    ];
                    this.isImpersonated = !histories.isEmpty();
                }
            } catch (Exception ex) {
                // Silently fail
            }
        }
    }
}