// challenge view
window.challenge = window.getMdManager(
    {
        navToPrevious: "navToPreviousChallenge",
        navToCurrent: "navToCurrentChallenge",
        navToNext: "navToNextChallenge",
        navToApprove: "approveCurrentChallenge",
        navToRevert: "revertApproval",
        navToApproveAll: "approveAllChallenges",
        navToRevertAll: "revertAllApprovals",
        zeroMdElement: "zeromd",
        mdTitle: "challengeTitle",
        mdTitleTemplate: "Challenge {value}",
        mdSubtitle: "challengeSubtitle",
        mdSubtitleTemplate: "Subsite:  {value}",
        mdIndex: "challengeIndex",
        messageDialog: "challengeDialog",
        allowedMdPaths: ["/md/challenges/"]
    }
);
window.challenge.setPeriodicRefresh(10);
window.challenge.registerHotkeys();
