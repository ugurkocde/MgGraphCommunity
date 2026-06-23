@{
    # PSScriptAnalyzer configuration for MgGraphCommunity.
    # CI fails the build on Error-severity findings; warnings are advisory.
    IncludeDefaultRules = $true
    Severity            = @('Error', 'Warning')

    ExcludeRules = @(
        # The persisted-cache path on Windows intentionally round-trips the payload
        # through ConvertTo-SecureString -AsPlainText so ConvertFrom-SecureString can
        # DPAPI-encrypt it. That is the documented DPAPI pattern, not a credential leak.
        'PSAvoidUsingConvertToSecureStringWithPlainText',

        # High false-positive rate here: flags parameter-set switches (e.g. -UseDeviceCode,
        # -Identity) that drive ParameterSetName without being referenced in the body, and
        # scriptblock parameters consumed indirectly.
        'PSReviewUnusedParameter',

        # Internal state setters and header helpers do not mutate external/system state;
        # ShouldProcess would add noise without value (the official SDK does not add it
        # to its connect/header helpers either).
        'PSUseShouldProcessForStateChangingFunctions',

        # Resolve-MgcScopes / ConvertTo-MgcHashtable return collections; plural nouns read
        # correctly for these helpers.
        'PSUseSingularNouns',

        # Several catch blocks intentionally swallow best-effort cleanup/parse failures
        # (stream disposal, optional JSON error-body parsing) and are commented as such.
        'PSAvoidUsingEmptyCatchBlock'
    )
}
