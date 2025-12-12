// solution view
window.solution = window.getMdManager(
    {
        navToPrevious: "navToPreviousSolution",
        navToCurrent: "navToCurrentSolution",
        navToNext: "navToNextSolution",
        navToApprove: "approveCurrentSolution",
        navToRevert: "revertApproval",
        navToApproveAll: "approveAllChallenges",
        navToRevertAll: "revertAllApprovals",
        zeroMdElement: "zeromd",
        mdTitle: "solutionTitle",
        mdTitleTemplate: "Solution {value}",
        mdSubtitle: "solutionSubtitle",
        mdSubtitleTemplate: "Subsite:  {value}",
        mdIndex: "solutionIndex",
        messageDialog: "solutionDialog",
        allowedMdPaths: ["/md/challenges/", "/md/solutions/"]
    }
);
window.solution.setPeriodicRefresh(10);
window.solution.registerHotkeys();


