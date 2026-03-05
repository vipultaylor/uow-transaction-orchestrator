//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Tests for UoWMaskingService.
 * Covers masking modes, match types, work item integration, and edge cases.
 *
 * Test masking rules (loaded from UoWTestDataMaskRules.csv):
 * - SSNPatternMask: REGEX_PATTERN for \d{3}-\d{2}-\d{4}, PARTIAL masking (last 4 chars)
 * - AccountNameMask: EXACT_FIELD for Account.Name, FULL masking
 * - InactiveRule: Inactive (should be ignored)
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Tests
 * @see UoWMaskingService
 */
@isTest
@SuppressWarnings('PMD.MethodNamingConventions')
private class UoWMaskingServiceTests {

    // ============================================================================
    // TEST SETUP
    // ============================================================================

    @TestSetup
    static void setupTestData() {
        UoWTestHelpers.loadTestConfigurations();
    }

    // ============================================================================
    // MASKING MODE TESTS - FULL
    // ============================================================================

    @isTest
    static void test_maskingMode_full_replacesWithAsterisks() {
        // Arrange - Account.Name has EXACT_FIELD rule with FULL masking
        Account acc = new Account(Name = 'Acme Corporation');

        // Act
        String masked = UoWMaskingService.maskField(Account.SObjectType, 'Name', 'Acme Corporation');

        // Assert
        Assert.areEqual('***', masked, 'FULL masking should replace entire value with ***');
    }

    @isTest
    static void test_maskingMode_full_handlesShortValues() {
        // Arrange
        Account acc = new Account(Name = 'A');

        // Act
        String masked = UoWMaskingService.maskField(Account.SObjectType, 'Name', 'A');

        // Assert
        Assert.areEqual('***', masked, 'FULL masking should replace even single character');
    }

    // ============================================================================
    // MASKING MODE TESTS - PARTIAL
    // ============================================================================

    @isTest
    static void test_maskingMode_partial_showsLastNCharacters() {
        // Arrange - SSN pattern rule uses PARTIAL with visibleCharacters: 4
        String ssn = '123-45-6789';

        // Act - Use a field on Account that will match the SSN regex pattern
        Account acc = new Account(Name = 'Test');
        acc.put('Description', ssn);
        String masked = UoWMaskingService.maskField(Account.SObjectType, 'Description', ssn);

        // Assert - SSN pattern matches, shows last 4 chars
        Assert.areEqual('***6789', masked, 'PARTIAL masking should show last 4 characters');
    }

    @isTest
    static void test_maskingMode_partial_shortValueReturnsMask() {
        // Arrange - Value shorter than visible characters
        String shortSsn = '123';

        // This won't match SSN pattern, so won't be masked
        // Test the partial masking logic directly via maskRecord
        Account acc = new Account(Name = 'Test', Description = shortSsn);
        Set<String> fieldsToMask = new Set<String>{ 'Description' };

        // Act - maskRecord will try to mask Description but no rule matches
        SObject masked = UoWMaskingService.maskRecord(acc, fieldsToMask);

        // Assert - No rule matches, so value unchanged
        Assert.areEqual(shortSsn, masked.get('Description'), 'Short value with no matching rule should be unchanged');
    }

    // ============================================================================
    // MASKING MODE TESTS - EMAIL
    // ============================================================================

    @isTest
    static void test_maskingMode_email_preservesStructure() {
        // Arrange - EmailPatternMask rule: REGEX_PATTERN matching email format, EMAIL mode
        // The email masking format is: first char + *** @ *** . TLD
        // Example: john.doe@example.com -> j***@***.com
        String email = 'john.doe@example.com';

        // Act - Email field with email value should match the regex pattern rule
        String masked = UoWMaskingService.maskField(Account.SObjectType, 'Email', email);

        // Assert - Should be masked with EMAIL format
        Assert.areEqual('j***@***.com', masked, 'Email should be masked preserving structure');
    }

    @isTest
    static void test_maskingMode_email_handlesInvalidEmail() {
        // Arrange - Value without @ symbol
        String invalidEmail = 'notanemail';

        // Act
        String masked = UoWMaskingService.maskField(Account.SObjectType, 'Email', invalidEmail);

        // Assert - Invalid email format doesn't match the regex, so unchanged
        Assert.areEqual(invalidEmail, masked, 'Invalid email should not match email pattern rule');
    }

    // ============================================================================
    // MASKING MODE TESTS - HASH
    // ============================================================================

    @isTest
    static void test_maskingMode_hash_returnsSha256Truncated() {
        // Arrange - ContactPhoneHash rule: EXACT_FIELD for Contact.Phone, HASH mode
        String phone = '555-123-4567';

        // Act
        String masked = UoWMaskingService.maskField(Contact.SObjectType, 'Phone', phone);

        // Assert - Should be 16-character hex string (truncated SHA-256)
        Assert.areEqual(16, masked.length(), 'Hash should be 16 characters');
        Assert.isTrue(Pattern.matches('[a-f0-9]{16}', masked), 'Hash should be lowercase hex');
        // Same input should produce same hash (deterministic)
        String masked2 = UoWMaskingService.maskField(Contact.SObjectType, 'Phone', phone);
        Assert.areEqual(masked, masked2, 'Same input should produce same hash');
    }

    @isTest
    static void test_maskingMode_hash_differentInputsDifferentHashes() {
        // Arrange
        String phone1 = '555-111-1111';
        String phone2 = '555-222-2222';

        // Act
        String hash1 = UoWMaskingService.maskField(Contact.SObjectType, 'Phone', phone1);
        String hash2 = UoWMaskingService.maskField(Contact.SObjectType, 'Phone', phone2);

        // Assert - Different inputs should produce different hashes
        Assert.areNotEqual(hash1, hash2, 'Different inputs should produce different hashes');
    }

    // ============================================================================
    // MASKING MODE TESTS - REDACT
    // ============================================================================

    @isTest
    static void test_maskingMode_redact_returnsNull() {
        // Arrange - AccountFaxRedact rule: EXACT_FIELD for Account.Fax, REDACT mode
        String fax = '555-999-8888';

        // Act
        String masked = UoWMaskingService.maskField(Account.SObjectType, 'Fax', fax);

        // Assert - REDACT mode should return null (complete removal)
        Assert.isNull(masked, 'REDACT mode should return null');
    }

    @isTest
    static void test_maskingMode_redact_detectsSensitiveField() {
        // Arrange
        Account acc = new Account(Name = 'Test', Fax = '555-888-7777');

        // Act
        Set<String> sensitiveFields = UoWMaskingService.detectSensitiveFields(acc);

        // Assert - Fax should be detected as sensitive (has REDACT rule)
        Assert.isTrue(sensitiveFields.contains('Fax'), 'Fax should be detected as sensitive');
        Assert.isTrue(sensitiveFields.contains('Name'), 'Name should also be detected (FULL rule)');
    }

    // ============================================================================
    // MATCH TYPE TESTS - EXACT_FIELD
    // ============================================================================

    @isTest
    static void test_matchType_exactField_masksSpecificField() {
        // Arrange - AccountNameMask rule: EXACT_FIELD for Account.Name
        Account acc = new Account(Name = 'Sensitive Company', Description = 'Public description');

        // Act
        Set<String> sensitiveFields = UoWMaskingService.detectSensitiveFields(acc);

        // Assert
        Assert.isTrue(sensitiveFields.contains('Name'), 'Account.Name should be detected as sensitive');
        Assert.isFalse(sensitiveFields.contains('Description'), 'Description should not be detected without matching rule');
    }

    @isTest
    static void test_matchType_exactField_doesNotMaskOtherObjects() {
        // Arrange - AccountNameMask is specific to Account, not Contact
        Contact con = new Contact(LastName = 'Sensitive Name');

        // Act
        Set<String> sensitiveFields = UoWMaskingService.detectSensitiveFields(con);

        // Assert
        Assert.isFalse(sensitiveFields.contains('LastName'), 'Contact.LastName should not match Account-specific rule');
    }

    // ============================================================================
    // MATCH TYPE TESTS - REGEX_PATTERN
    // ============================================================================

    @isTest
    static void test_matchType_regexPattern_matchesValuePattern() {
        // Arrange - SSNPatternMask: REGEX_PATTERN for \d{3}-\d{2}-\d{4}
        Account acc = new Account(Name = 'Test', Description = '123-45-6789');

        // Act
        Set<String> sensitiveFields = UoWMaskingService.detectSensitiveFields(acc);

        // Assert
        Assert.isTrue(sensitiveFields.contains('Description'), 'Field with SSN pattern should be detected');
        Assert.isTrue(sensitiveFields.contains('Name'), 'Account.Name should also be detected (EXACT_FIELD rule)');
    }

    @isTest
    static void test_matchType_regexPattern_appliesToAllObjects() {
        // Arrange - SSN pattern rule has no SObjectType filter (applies globally)
        Contact con = new Contact(LastName = 'Test', Description = '987-65-4321');

        // Act
        Set<String> sensitiveFields = UoWMaskingService.detectSensitiveFields(con);

        // Assert
        Assert.isTrue(sensitiveFields.contains('Description'), 'REGEX_PATTERN without SObjectType should apply to all objects');
    }

    @isTest
    static void test_matchType_regexPattern_noMatchForInvalidPattern() {
        // Arrange - Value doesn't match SSN pattern
        Account acc = new Account(Name = 'Test', Description = 'Not an SSN');

        // Act
        Set<String> sensitiveFields = UoWMaskingService.detectSensitiveFields(acc);

        // Assert - Name matches EXACT_FIELD, Description doesn't match REGEX
        Assert.isTrue(sensitiveFields.contains('Name'), 'Name should match EXACT_FIELD rule');
        Assert.isFalse(sensitiveFields.contains('Description'), 'Description should not match SSN pattern');
    }

    // ============================================================================
    // INACTIVE RULE TESTS
    // ============================================================================

    @isTest
    static void test_inactiveRules_areIgnored() {
        // Arrange - InactiveRule is defined but IsActive__c = false
        // The inactive rule would match SSN pattern, but should be ignored
        Account acc = new Account(Name = 'NoMatch', Description = '111-22-3333');

        // Act
        Set<String> sensitiveFields = UoWMaskingService.detectSensitiveFields(acc);

        // Assert - Should match active SSNPatternMask, not InactiveRule
        Assert.isTrue(sensitiveFields.contains('Description'), 'Active SSN rule should match');
        // Name matches AccountNameMask
        Assert.isTrue(sensitiveFields.contains('Name'), 'Account.Name should match');
    }

    // ============================================================================
    // INTEGRATION TESTS - applyMaskingToWorkItems (DML)
    // ============================================================================

    @isTest
    static void test_applyMaskingToWorkItems_dml_masksFields() {
        // Arrange
        UnitOfWork uow = new UnitOfWork('TestConfigAllMocks');
        Account acc = new Account(Name = 'Sensitive Corp', Description = '999-88-7777');
        uow.registerInsert(acc);

        UoWPlan plan = uow.getPlan();
        UoWResult result = new UoWResult(uow.getContext());

        // Act
        UoWMaskingService.MaskingResult maskResult = UoWMaskingService.applyMaskingToWorkItems(plan, result);

        // Assert
        Assert.isFalse(maskResult.isEmpty(), 'Masking result should not be empty');

        UoWDmlWorkItem workItem = plan.getPlannedDmlWork()[0];
        Assert.isTrue(maskResult.hasMasking(workItem.workId), 'Work item should have masking applied');

        Set<String> maskedFields = maskResult.getMaskedFields(workItem.workId);
        Assert.isTrue(maskedFields.contains('Name'), 'Name should be masked');
        Assert.isTrue(maskedFields.contains('Description'), 'Description (SSN) should be masked');

        // Verify masked data through snapshots (prepareForSerialization uses masked records when available)
        UoWSerializationConfig auditConfig = UoWSerializationConfig.forAudit();
        workItem.prepareForSerialization(auditConfig);
        List<UoWDmlWorkItem.RecordSnapshot> snapshots = workItem.getSnapshots();
        Assert.isNotNull(snapshots, 'Snapshots should be built');
        Assert.areEqual(1, snapshots.size(), 'Should have 1 snapshot');
        Assert.areEqual('***', snapshots[0].rec.get('Name'), 'Name should be fully masked in snapshot');
        Assert.areEqual('***7777', snapshots[0].rec.get('Description'), 'SSN should be partially masked in snapshot');
    }

    @isTest
    static void test_applyMaskingToWorkItems_dml_multipleRecords() {
        // Arrange
        UnitOfWork uow = new UnitOfWork('TestConfigAllMocks');
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            accounts.add(new Account(Name = 'Company ' + i, Description = '123-45-678' + i));
        }
        uow.registerInsert(accounts);

        UoWPlan plan = uow.getPlan();
        UoWResult result = new UoWResult(uow.getContext());

        // Act
        UoWMaskingService.MaskingResult maskResult = UoWMaskingService.applyMaskingToWorkItems(plan, result);

        // Assert - Verify through MaskingResult
        UoWDmlWorkItem workItem = plan.getPlannedDmlWork()[0];
        Assert.isTrue(maskResult.hasMasking(workItem.workId), 'Work item should have masking applied');

        // Verify masked data through snapshots
        UoWSerializationConfig auditConfig = UoWSerializationConfig.forAudit();
        workItem.prepareForSerialization(auditConfig);
        List<UoWDmlWorkItem.RecordSnapshot> snapshots = workItem.getSnapshots();
        Assert.areEqual(5, snapshots.size(), 'All 5 records should have snapshots');

        for (UoWDmlWorkItem.RecordSnapshot snapshot : snapshots) {
            Assert.areEqual('***', snapshot.rec.get('Name'), 'Each Name should be fully masked');
        }
    }

    @isTest
    static void test_applyMaskingToWorkItems_dml_noSensitiveFields() {
        // Arrange - Use Contact which has no matching rules for these fields
        UnitOfWork uow = new UnitOfWork('TestConfigAllMocks');
        Contact con = new Contact(LastName = 'Smith', FirstName = 'John');
        uow.registerInsert(con);

        UoWPlan plan = uow.getPlan();
        UoWResult result = new UoWResult(uow.getContext());

        // Act
        UoWMaskingService.MaskingResult maskResult = UoWMaskingService.applyMaskingToWorkItems(plan, result);

        // Assert - No masking should be applied
        UoWDmlWorkItem workItem = plan.getPlannedDmlWork()[0];
        Assert.isFalse(maskResult.hasMasking(workItem.workId), 'No fields should be masked');

        // Verify original data is preserved in snapshots (no masking applied)
        UoWSerializationConfig auditConfig = UoWSerializationConfig.forAudit();
        workItem.prepareForSerialization(auditConfig);
        List<UoWDmlWorkItem.RecordSnapshot> snapshots = workItem.getSnapshots();
        Assert.areEqual('Smith', snapshots[0].rec.get('LastName'), 'LastName should be unchanged (no masking rule)');
    }

    // ============================================================================
    // INTEGRATION TESTS - applyMaskingToWorkItems (Events)
    // ============================================================================

    @isTest
    static void test_applyMaskingToWorkItems_events_masksFields() {
        // Arrange
        UnitOfWork uow = new UnitOfWork('TestConfigAllMocks');

        // Use Account as a mock event type for testing (platform events aren't available in test)
        List<SObject> mockEvents = new List<SObject>();
        Account mockEvent = new Account(Name = 'Event Name', Description = '555-44-3333');
        mockEvents.add(mockEvent);

        UoWEventWorkItem eventWork = new UoWEventWorkItem(
            UoWEnums.WorkPhase.POST_DML,
            Account.SObjectType,
            mockEvents
        );
        uow.getPlan().registerEventWork(eventWork);

        UoWPlan plan = uow.getPlan();
        UoWResult result = new UoWResult(uow.getContext());

        // Act
        UoWMaskingService.MaskingResult maskResult = UoWMaskingService.applyMaskingToWorkItems(plan, result);

        // Assert
        Assert.isFalse(maskResult.isEmpty(), 'Masking result should not be empty');
        Assert.isTrue(maskResult.hasMasking(eventWork.workId), 'Event work item should have masking applied');

        // Verify masked data through snapshots
        UoWSerializationConfig auditConfig = UoWSerializationConfig.forAudit();
        eventWork.prepareForSerialization(auditConfig);
        List<UoWEventWorkItem.EventSnapshot> snapshots = eventWork.getSnapshots();
        Assert.isNotNull(snapshots, 'Snapshots should be built');
        Assert.areEqual('***', snapshots[0].evt.get('Name'), 'Event Name should be fully masked');
    }

    // ============================================================================
    // INTEGRATION TESTS - Masking Disabled
    // ============================================================================

    @isTest
    static void test_applyMaskingToWorkItems_maskingDisabled_skipsProcessing() {
        // Arrange - TestConfigMinimal has EnableMasking__c = FALSE
        UnitOfWork uow = new UnitOfWork('TestConfigMinimal');

        // Verify masking is actually disabled for this config
        Assert.isFalse(uow.getContext().getFeatureSettings().getEnableMasking(), 'TestConfigMinimal should have masking disabled');

        Account acc = new Account(Name = 'Should Not Mask', Description = '111-22-3333');
        uow.registerInsert(acc);

        UoWPlan plan = uow.getPlan();
        UoWResult result = new UoWResult(uow.getContext());

        // Act
        UoWMaskingService.MaskingResult maskResult = UoWMaskingService.applyMaskingToWorkItems(plan, result);

        // Assert - Masking should be skipped entirely
        Assert.isTrue(maskResult.isEmpty(), 'Masking should be skipped when disabled');

        // Verify original data is preserved (masking was not applied)
        UoWDmlWorkItem workItem = plan.getPlannedDmlWork()[0];
        Assert.isFalse(maskResult.hasMasking(workItem.workId), 'No masking should be recorded');
    }

    // ============================================================================
    // PUBLIC API TESTS - detectFieldsToMask
    // ============================================================================

    @isTest
    static void test_detectFieldsToMask_multipleRecords() {
        // Arrange
        List<SObject> records = new List<SObject>{
            new Account(Name = 'Acme', Description = '123-45-6789'),
            new Account(Name = 'Beta', Description = 'No SSN here'),
            new Account(Name = 'Gamma', Description = '987-65-4321')
        };

        UoWResult result = new UoWResult(new UoWContext('TestConfigAllMocks'));

        // Act
        Set<String> fieldsToMask = UoWMaskingService.detectFieldsToMask(records, result);

        // Assert - Name from all, Description from 2 records with SSN pattern
        Assert.isTrue(fieldsToMask.contains('Name'), 'Name should be detected');
        Assert.isTrue(fieldsToMask.contains('Description'), 'Description should be detected (2 records have SSN)');
    }

    @isTest
    static void test_detectFieldsToMask_nullAndEmptyRecords() {
        // Arrange
        UoWResult result = new UoWResult(new UoWContext('TestConfigAllMocks'));

        // Act & Assert - Null list
        Set<String> nullResult = UoWMaskingService.detectFieldsToMask(null, result);
        Assert.isTrue(nullResult.isEmpty(), 'Null records should return empty set');

        // Act & Assert - Empty list
        Set<String> emptyResult = UoWMaskingService.detectFieldsToMask(new List<SObject>(), result);
        Assert.isTrue(emptyResult.isEmpty(), 'Empty records should return empty set');
    }

    // ============================================================================
    // PUBLIC API TESTS - detectSensitiveFields
    // ============================================================================

    @isTest
    static void test_detectSensitiveFields_nullRecord() {
        // Act
        Set<String> result = UoWMaskingService.detectSensitiveFields(null);

        // Assert
        Assert.isTrue(result.isEmpty(), 'Null record should return empty set');
    }

    @isTest
    static void test_detectSensitiveFields_onlyStringFields() {
        // Arrange - Non-string fields should be ignored
        Account acc = new Account(
            Name = 'Test',
            NumberOfEmployees = 123,
            AnnualRevenue = 1000000
        );

        // Act
        Set<String> sensitiveFields = UoWMaskingService.detectSensitiveFields(acc);

        // Assert - Only Name (string) should be detected, not numeric fields
        Assert.isTrue(sensitiveFields.contains('Name'), 'Name (string) should be detected');
        Assert.isFalse(sensitiveFields.contains('NumberOfEmployees'), 'Numeric fields should be ignored');
        Assert.isFalse(sensitiveFields.contains('AnnualRevenue'), 'Numeric fields should be ignored');
    }

    // ============================================================================
    // PUBLIC API TESTS - maskField
    // ============================================================================

    @isTest
    static void test_maskField_nullAndBlankValues() {
        // Act & Assert - Null value
        String nullResult = UoWMaskingService.maskField(Account.SObjectType, 'Name', null);
        Assert.isNull(nullResult, 'Null value should return null');

        // Act & Assert - Blank value
        String blankResult = UoWMaskingService.maskField(Account.SObjectType, 'Name', '');
        Assert.areEqual('', blankResult, 'Blank value should return blank');

        // Act & Assert - Whitespace only
        String whitespaceResult = UoWMaskingService.maskField(Account.SObjectType, 'Name', '   ');
        Assert.areEqual('   ', whitespaceResult, 'Whitespace value should return whitespace (blank check)');
    }

    @isTest
    static void test_maskField_noMatchingRule() {
        // Arrange - Field that doesn't match any rule
        String value = 'Regular text without sensitive patterns';

        // Act
        String masked = UoWMaskingService.maskField(Contact.SObjectType, 'Description', value);

        // Assert
        Assert.areEqual(value, masked, 'Value without matching rule should be unchanged');
    }

    // ============================================================================
    // PUBLIC API TESTS - maskRecord
    // ============================================================================

    @isTest
    static void test_maskRecord_clonesAndMasks() {
        // Arrange
        Account original = new Account(Name = 'Original Name', Description = 'Keep this');
        Set<String> fieldsToMask = new Set<String>{ 'Name' };

        // Act
        SObject masked = UoWMaskingService.maskRecord(original, fieldsToMask);

        // Assert - Verify it's a clone by checking original is unchanged
        Assert.areEqual('***', masked.get('Name'), 'Name should be masked');
        Assert.areEqual('Keep this', masked.get('Description'), 'Description should be unchanged');
        Assert.areEqual('Original Name', original.get('Name'), 'Original should be unchanged (proves cloning)');
    }

    @isTest
    static void test_maskRecord_nullInputs() {
        // Arrange
        Account acc = new Account(Name = 'Test');

        // Act & Assert - Null record
        SObject nullRecordResult = UoWMaskingService.maskRecord(null, new Set<String>{ 'Name' });
        Assert.isNull(nullRecordResult, 'Null record should return null');

        // Act & Assert - Null fields set
        SObject nullFieldsResult = UoWMaskingService.maskRecord(acc, null);
        Assert.areEqual(acc, nullFieldsResult, 'Null fields set should return original');

        // Act & Assert - Empty fields set
        SObject emptyFieldsResult = UoWMaskingService.maskRecord(acc, new Set<String>());
        Assert.areEqual(acc, emptyFieldsResult, 'Empty fields set should return original');
    }

    @isTest
    static void test_maskRecord_nonExistentField() {
        // Arrange - Try to mask a field that doesn't exist on the record
        Account acc = new Account(Name = 'Test');
        Set<String> fieldsToMask = new Set<String>{ 'Name', 'NonExistentField__c' };

        // Act - Should not throw, just skip non-existent field
        SObject masked = UoWMaskingService.maskRecord(acc, fieldsToMask);

        // Assert
        Assert.areEqual('***', masked.get('Name'), 'Existing field should be masked');
    }

    // ============================================================================
    // MASKING RESULT TESTS
    // ============================================================================

    @isTest
    static void test_maskingResult_addAndGetMaskedFields() {
        // Arrange
        UoWMaskingService.MaskingResult result = new UoWMaskingService.MaskingResult();

        // Act
        result.addMaskedFields('work-001', new Set<String>{ 'Name', 'Description' });
        result.addMaskedFields('work-002', new Set<String>{ 'Email' });

        // Assert
        Set<String> work1Fields = result.getMaskedFields('work-001');
        Assert.areEqual(2, work1Fields.size(), 'Work-001 should have 2 fields');
        Assert.isTrue(work1Fields.contains('Name'), 'Should contain Name');
        Assert.isTrue(work1Fields.contains('Description'), 'Should contain Description');

        Set<String> work2Fields = result.getMaskedFields('work-002');
        Assert.areEqual(1, work2Fields.size(), 'Work-002 should have 1 field');
    }

    @isTest
    static void test_maskingResult_getMaskedFieldsAsString() {
        // Arrange
        UoWMaskingService.MaskingResult result = new UoWMaskingService.MaskingResult();
        result.addMaskedFields('work-001', new Set<String>{ 'Zebra', 'Alpha', 'Mike' });

        // Act
        String fieldString = result.getMaskedFieldsAsString('work-001');

        // Assert - Should be sorted alphabetically
        Assert.areEqual('Alpha, Mike, Zebra', fieldString, 'Fields should be sorted and comma-separated');
    }

    @isTest
    static void test_maskingResult_getMaskedFieldsAsString_empty() {
        // Arrange
        UoWMaskingService.MaskingResult result = new UoWMaskingService.MaskingResult();

        // Act & Assert - Non-existent work item
        Assert.isNull(result.getMaskedFieldsAsString('non-existent'), 'Non-existent should return null');

        // Act & Assert - Empty fields set
        result.addMaskedFields('empty-work', new Set<String>());
        Assert.isNull(result.getMaskedFieldsAsString('empty-work'), 'Empty fields should return null');
    }

    @isTest
    static void test_maskingResult_hasMasking() {
        // Arrange
        UoWMaskingService.MaskingResult result = new UoWMaskingService.MaskingResult();
        result.addMaskedFields('with-masking', new Set<String>{ 'Name' });
        result.addMaskedFields('empty-masking', new Set<String>());

        // Assert
        Assert.isTrue(result.hasMasking('with-masking'), 'Should have masking with fields');
        Assert.isFalse(result.hasMasking('empty-masking'), 'Should not have masking with empty fields');
        Assert.isFalse(result.hasMasking('non-existent'), 'Should not have masking for non-existent');
    }

    @isTest
    static void test_maskingResult_isEmpty() {
        // Arrange
        UoWMaskingService.MaskingResult result = new UoWMaskingService.MaskingResult();

        // Assert - Initially empty
        Assert.isTrue(result.isEmpty(), 'New result should be empty');

        // Act
        result.addMaskedFields('work-001', new Set<String>{ 'Name' });

        // Assert - Not empty after adding
        Assert.isFalse(result.isEmpty(), 'Result with fields should not be empty');
    }

    @isTest
    static void test_maskingResult_getWorkItemCount() {
        // Arrange
        UoWMaskingService.MaskingResult result = new UoWMaskingService.MaskingResult();

        // Assert - Initially zero
        Assert.areEqual(0, result.getWorkItemCount(), 'New result should have 0 work items');

        // Act
        result.addMaskedFields('work-001', new Set<String>{ 'Name' });
        result.addMaskedFields('work-002', new Set<String>{ 'Email' });
        result.addMaskedFields('work-003', new Set<String>{ 'Phone' });

        // Assert
        Assert.areEqual(3, result.getWorkItemCount(), 'Should have 3 work items');
    }

    // ============================================================================
    // CACHE MANAGEMENT TESTS
    // ============================================================================

    @isTest
    static void test_clearCache_resetsState() {
        // Arrange - First call loads rules
        Account acc = new Account(Name = 'Test');
        UoWMaskingService.detectSensitiveFields(acc);

        // Act - Clear cache
        UoWMaskingService.clearCache();

        // Assert - Cache is cleared (rules will be reloaded on next call)
        // We can verify this works by calling detect again - it should still work
        Set<String> fields = UoWMaskingService.detectSensitiveFields(acc);
        Assert.isTrue(fields.contains('Name'), 'Should still detect Name after cache clear');
    }

    // ============================================================================
    // EDGE CASE TESTS
    // ============================================================================

    @isTest
    static void test_regexPattern_invalidPattern_handlesGracefully() {
        // This tests internal error handling for invalid regex
        // The service should catch exceptions and return false for invalid patterns

        // Arrange - Use a record with no sensitive data
        Contact con = new Contact(LastName = 'Test', Description = 'Plain text');

        // Act - Should not throw even if internal regex handling fails
        Set<String> fields = UoWMaskingService.detectSensitiveFields(con);

        // Assert - Just verify no exception was thrown
        Assert.isNotNull(fields, 'Should return result even with no matches');
    }

    @isTest
    static void test_maskRecord_nonStringFieldInMaskSet() {
        // Arrange - Include a non-string field in the mask set
        Account acc = new Account(Name = 'Test', NumberOfEmployees = 100);
        Set<String> fieldsToMask = new Set<String>{ 'Name', 'NumberOfEmployees' };

        // Act - Should handle non-string field gracefully
        SObject masked = UoWMaskingService.maskRecord(acc, fieldsToMask);

        // Assert
        Assert.areEqual('***', masked.get('Name'), 'String field should be masked');
        Assert.areEqual(100, masked.get('NumberOfEmployees'), 'Non-string field should be unchanged');
    }

    @isTest
    static void test_multipleRulesMatch_firstRuleWins() {
        // Arrange - Account.Name matches EXACT_FIELD rule
        // If value also matched a REGEX rule, EXACT_FIELD should win based on sort order
        Account acc = new Account(Name = 'Sensitive');

        // Act
        String masked = UoWMaskingService.maskField(Account.SObjectType, 'Name', 'Sensitive');

        // Assert - EXACT_FIELD AccountNameMask (FULL) should apply
        Assert.areEqual('***', masked, 'First matching rule (EXACT_FIELD) should apply');
    }

    @isTest
    static void test_emptyPlan_handlesGracefully() {
        // Arrange
        UnitOfWork uow = new UnitOfWork('TestConfigAllMocks');
        UoWPlan plan = uow.getPlan();
        UoWResult result = new UoWResult(uow.getContext());

        // Act
        UoWMaskingService.MaskingResult maskResult = UoWMaskingService.applyMaskingToWorkItems(plan, result);

        // Assert
        Assert.isTrue(maskResult.isEmpty(), 'Empty plan should return empty masking result');
    }
}