import { getMdManager } from "./mdmanager.js";
import { getRdpClient } from "./rdp-integration.js";

// solution view
window.solution = getMdManager(
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
        allowedMdPaths: ["/md/challenges/", "/md/solutions/"],
        mdRetrievalMode: "solutions"
    }
);
window.solution.setPeriodicRefresh(10);
window.solution.registerHotkeys();


(async () => {
    const rdpClient = await getRdpClient(rdpContainer);
    if (rdpClient) {
        // You can now use rdpClient to interact with the RDP session
    }
    
})();
