import { getMdManager } from "./mdmanager.js";
import { getRdpClient } from "./rdp-integration.js";

// challenge view
window.challenge = getMdManager(
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
        allowedMdPaths: ["/md/challenges/"],
        mdRetrievalMode: "challenges"
    }
);
window.challenge.setPeriodicRefresh(10);
window.challenge.registerHotkeys(['rdpContainer']);
