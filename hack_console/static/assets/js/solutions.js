import { getMdManager } from "./mdmanager.js";

// solution view
window.solution = getMdManager(
    {
        navToPrevious: "navToPreviousSolution",
        navToCurrent: "navToCurrentSolution",
        navToNext: "navToNextSolution",
        navToApprove: "approveCurrentSolution",
        navToRevert: "revertApproval",
        navToApproveAll: "approveAllSolutions",
        navToRevertAll: "revertAllApprovals",
        zeroMdElement: "zeromd",
        mdTitle: "solutionTitle",
        mdTitleTemplate: "Solution {value}",
        mdSubtitle: "solutionSubtitle",
        mdSubtitleTemplate: "Subsite:  {value}",
        mdIndex: "solutionIndex",
        messageDialog: "solutionDialog",
        allowedMdPaths: ["/md/challenges/", "/md/solutions/"],
        mdRetrievalMode: "solutions"
    }
);
window.solution.setPeriodicRefresh(10);
window.solution.registerHotkeys(['rdpContainer']);

