//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Test data factory for UoW Core package tests. Provides reusable methods to create
 * test data for standard SObjects, relationships, bulk scenarios, and permission testing.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Test Utilities
 * @see UoWTestHelpers
 * @see UoWTestMocks
 */
@isTest
public class UoWCoreTestDataFactory {

    public enum TestUserType {
        ADMIN,
        STANDARD_USER,
        MIN_ACCESS,
        PARTIAL_FIELD_ACCESS
    }

    public static final String PERMISSION_SET_CORE_SECURITY_TEST = 'UoWCoreSecurityTest';

    public static final String ADMIN_USER_ALIAS = 'uowadmin';
    public static final String STANDARD_USER_ALIAS = 'uowstand';
    public static final String MIN_ACCESS_USER_ALIAS = 'uowmin';
    public static final String PARTIAL_ACCESS_USER_ALIAS = 'uowpart';

    private static Map<TestUserType, Id> profileIdByType = new Map<TestUserType, Id>();
    private static Map<String, PermissionSet> permissionSetMapByName = new Map<String, PermissionSet>();

    // ============================================================================
    // STANDARD SOBJECTS
    // ============================================================================

    /**
     * Create a single Account with minimal required fields.
     *
     * @param name Account name
     * @return Account instance (not inserted)
     */
    public static Account createAccount(String name) {
        return new Account(
            Name = name,
            Industry = 'Technology',
            BillingCity = 'San Francisco',
            BillingState = 'CA',
            BillingCountry = 'USA'
        );
    }

    /**
     * Create multiple Accounts.
     *
     * @param count Number of accounts to create
     * @return List of Account instances
     */
    public static List<Account> createAccounts(Integer count) {
        List<Account> accounts = new List<Account>();
        for (Integer i = 1; i <= count; i++) {
            accounts.add(createAccount('Test Account ' + i));
        }
        return accounts;
    }

    /**
     * Create a single Account with minimal required fields and a fake Id.
     *
     * @param name Account name
     * @return Account instance (not inserted)
     */
    public static Account createExistingAccount(String name) {
        Account acc = createAccount(name);
        acc.Id = UoWTestHelpers.generateFakeId(Account.SObjectType);
        return acc;
    }

    /**
     * Create multiple Accounts with Ids.
     *
     * @param count Number of accounts to simulate existing records
     * @return List of Account instances
     */
    public static List<Account> createExistingAccounts(Integer count) {
        List<Account> accounts = new List<Account>();
        for (Integer i = 1; i <= count; i++) {
            Account newAccount= createAccount('Test Account ' + i);
            newAccount.Id = UoWTestHelpers.generateFakeId(Account.SObjectType, i);
            accounts.add(newAccount);
        }
        return accounts;
    }

    /**
     * Create a Contact.
     *
     * @param lastName Contact last name
     * @param accountId Related Account ID (can be null)
     * @return Contact instance
     */
    public static Contact createContact(String lastName, Id accountId) {
        return new Contact(
            FirstName = 'Test',
            LastName = lastName,
            AccountId = accountId,
            Email = lastName.toLowerCase().replaceAll(' ', '.') + '@test.com'
        );
    }

    /**
     * Create multiple Contacts.
     *
     * @param count Number of contacts to create
     * @param accountId Related Account ID
     * @return List of Contact instances
     */
    public static List<Contact> createContacts(Integer count, Id accountId) {
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 1; i <= count; i++) {
            contacts.add(createContact('Contact ' + i, accountId));
        }
        return contacts;
    }

    /**
     * Create an Opportunity.
     *
     * @param name Opportunity name
     * @param accountId Related Account ID
     * @return Opportunity instance
     */
    public static Opportunity createOpportunity(String name, Id accountId) {
        return new Opportunity(
            Name = name,
            AccountId = accountId,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = 100000
        );
    }

    /**
     * Create multiple Opportunities.
     *
     * @param count Number of opportunities to create
     * @param accountId Related Account ID
     * @return List of Opportunity instances
     */
    public static List<Opportunity> createOpportunities(Integer count, Id accountId) {
        List<Opportunity> opportunities = new List<Opportunity>();
        for (Integer i = 1; i <= count; i++) {
            opportunities.add(createOpportunity('Opportunity ' + i, accountId));
        }
        return opportunities;
    }

    /**
     * Create a Case.
     *
     * @param subject Case subject
     * @param accountId Related Account ID
     * @return Case instance
     */
    public static Case createCase(String subject, Id accountId) {
        return new Case(
            Subject = subject,
            AccountId = accountId,
            Status = 'New',
            Origin = 'Web',
            Priority = 'Medium'
        );
    }


    /**
     * Create multiple Cases.
     *
     * @param count Number of cases to create
     * @param accountId Related Account ID
     * @return List of Case instances
     */
    public static List<Case> createCases(Integer count, Id accountId) {
        List<Case> cases = new List<Case>();
        for (Integer i = 1; i <= count; i++) {
            cases.add(createCase('Case ' + i, accountId));
        }
        return cases;
    }

    // ============================================================================
    // SECURITY TEST DATA - Intentionally Invalid Data for Org-Independent Testing
    // ============================================================================

    /**
     * Create an Account with blank Name (guaranteed to fail validation).
     * Used for security tests where we want to verify security enforcement
     * occurs BEFORE DML validation fails.
     *
     * @return Account with missing Name field
     */
    public static List<Account> createAccountsWithBlankName(Integer count) {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            accounts.add(new Account(
                Industry = 'Technology'
                // Name intentionally omitted - required field, will fail validation
            ));
        }
        return accounts;
    }

    /**
     * Create an Account with oversized Name (guaranteed to fail validation).
     * Account.Name has a 255 character limit. This creates a 256 character name.
     * Used for partial field access tests where we want to verify field stripping
     * occurs before DML fails on a different validation error.
     *
     * @param includeInaccessibleField If true, includes Industry field which will be
     *        stripped when user lacks FLS access
     * @return Account with oversized Name field
     */
    public static List<Account> createAccountWithOversizedName(Integer count, Boolean includeInaccessibleField) {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            Account acc = new Account(
                Name = ''.rightPad(256, 'X')  // 256 chars exceeds 255 limit
            );

            if (includeInaccessibleField) {
                acc.Industry = 'Technology';  // Will be stripped by FLS enforcement
            }

            accounts.add(acc);
        }

        return accounts;
    }

    /**
     * Create an invalid Contact (missing required LastName field).
     * NOTE: Account.Name is NOT required in Salesforce, so we use Contact.LastName instead.
     *
     * @return Contact instance with missing required field
     */
    public static Contact createInvalidContact() {
        return new Contact(
            FirstName = 'Invalid',
            Email = 'invalid@test.com'
            // LastName field intentionally omitted - this is REQUIRED
        );
    }

    // ============================================================================
    // OTHER DATA FACTORIES
    // ============================================================================

    public static List<Messaging.SingleEmailMessage> createEmailsWithNoRecipients(Integer count) {
        return createEmails(count, false);
    }

    /**
     * Create multiple Email Messages.
     *
     * @param count Number of email messages to create
     * @return List of Email instances
     */
    public static List<Messaging.SingleEmailMessage> createEmails(Integer count, Boolean setToAddresses) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Integer i = 0; i < count; i++) {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            if(setToAddresses) {
                email.setToAddresses(new List<String>{'test' + i + '@example.com'});
            }
            email.setSubject('Test ' + i);
            email.setPlainTextBody('Body');
            emails.add(email);
        }
        return emails;
    }


    // ============================================================================
    // USER CREATION FOR PERMISSION TESTS
    // ============================================================================

    public static User getTestUser(TestUserType userType) {
        Id profileId = getProfileId(userType);
        String userAlias = getUserAlias(userType);
        return [SELECT Id, Username FROM User WHERE Profile.Id = :profileId AND Alias = :userAlias LIMIT 1];
    }

    /**
     * Create a Minimum Access User with UoWCoreSecurityTest permission set.
     * This user has object-level access to Account but only Name field access.
     * Used by UoWCoreSecurityTests to test partial field access (FLS stripping) scenarios.
     *
     * Why Minimum Access profile?
     * - Standard User profile has full FLS access to standard Account fields (including Industry)
     * - Minimum Access profile has NO object/field access by default
     * - Adding UoWCoreSecurityTest PS grants ONLY Account object + Name field (required field)
     * - This ensures Industry and other fields will be stripped by Security.stripInaccessible()
     *
     * Security Test Scenario:
     * - User can create/edit Account records (object-level access from PS)
     * - User can only access Account.Name field (required field, auto-included)
     * - Other fields (Industry, Description, etc.) will be stripped by Security.stripInaccessible()
     *
     * @return Test user with partial field access
     */
    public static User createPartialAccessUser() {
        User testUser = createTestUser(TestUserType.PARTIAL_FIELD_ACCESS, true);

        // Assign UoWCoreSecurityTest permission set (grants Account object + Name field only)
        PermissionSet ps = getPermissionSet(PERMISSION_SET_CORE_SECURITY_TEST);
        insert new PermissionSetAssignment(
            AssigneeId = testUser.Id,
            PermissionSetId = ps.Id
        );

        return testUser;
    }

    public static User createTestUser(TestUserType userType) {
        User testUser = createtestUser(userType, false);
        return testUser;
    }

    public static User createtestUser(TestUserType userType, Boolean insertUser) {
        Id testUserProfileId = getProfileId(userType);
        String userAlias = getUserAlias(userType);
        String uniqueId = String.valueOf(Datetime.now().getTime());

        User testUser = new User(
            FirstName = 'Test',
            LastName = 'UoW User ' + uniqueId,
            Email = userAlias + uniqueId + '@uow.test.com',
            Username = userAlias + uniqueId + '@uow.test.com',
            Alias = userAlias,
            ProfileId = testUserProfileId,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        if(insertUser) {
            insert testUser;
        }

        return testUser;
    }

    private static Id getProfileId(TestUserType userType) {
        if(profileIdByType.containsKey(userType)){
            return profileIdByType.get(userType);
        }

        String profileAdmin = 'System Administrator';
        String profileMinAccess = 'Minimum Access - Salesforce';
        String profileStandardUser = 'Standard User';

        //Get the profiles
        Set<String> profileNames = new Set<String>{
            profileAdmin,
            profileMinAccess,
            profileStandardUser
        };

        //Query Profiles
        Map<String, Id> profileMapByName = new Map<String, Id>();
        for(Profile p : [SELECT Id, Name FROM Profile WHERE Name IN :profileNames]){
            profileMapByName.put(p.Name, p.Id);
        }

        Id profileIdToReturn;
        switch on userType {
            when ADMIN {
                profileIdToReturn = profileMapByName.get(profileAdmin);
            }
            when STANDARD_USER {
                profileIdToReturn = profileMapByName.get(profileStandardUser);
            }
            when MIN_ACCESS {
                profileIdToReturn = profileMapByName.get(profileMinAccess);
            }
            when PARTIAL_FIELD_ACCESS {
                profileIdToReturn = profileMapByName.get(profileMinAccess);
            }
            when else {
                profileIdToReturn = profileMapByName.get(profileStandardUser);
            }
        }
        return profileIdToReturn;
    }

    private static String getUserAlias(TestUserType userType) {
        switch on userType {
            when ADMIN {
                return ADMIN_USER_ALIAS;
            }
            when STANDARD_USER {
                return STANDARD_USER_ALIAS;
            }
            when MIN_ACCESS {
                return MIN_ACCESS_USER_ALIAS;
            }
            when PARTIAL_FIELD_ACCESS {
                return PARTIAL_ACCESS_USER_ALIAS;
            }
            when else {
                return STANDARD_USER_ALIAS;
            }
        }
    }

    private static PermissionSet getPermissionSet(String permSetName) {
        if(permissionSetMapByName.containsKey(permSetName)){
            return permissionSetMapByName.get(permSetName);
        }

        //Get the profiles
        Set<String> permSetNames = new Set<String>{
            PERMISSION_SET_CORE_SECURITY_TEST
        };

        //Check if the permission set name needs to be added to the set
        if(permSetNames.contains(permSetName) == false){
            permSetNames.add(permSetName);
        }

        for(PermissionSet ps : [SELECT Id, Name FROM PermissionSet WHERE Name IN :permSetNames]){
            permissionSetMapByName.put(ps.Name, ps);
        }

        return permissionSetMapByName.get(permSetName);
    }

}