class ChallengeManager {
    #challenges = [];
    #currentStep = null;
    #currentChallenge = null;
    #refreshSeconds = 0;
    #refreshTimeout = null;
    #isSubSite = false;
    constructor() {
        document.getElementById("navToPreviousChallenge").style.display = "none";
        document.getElementById("navToPreviousChallenge").addEventListener("click", this.navToPreviousChallenge.bind(this));
        document.getElementById("navToCurrentChallenge").addEventListener("click", this.navToCurrentChallenge.bind(this));
        document.getElementById("navToNextChallenge").style.display = "none";
        document.getElementById("navToNextChallenge").addEventListener("click", this.navToNextChallenge.bind(this));
        if(document.getElementById("approveCurrentChallenge")) {
            document.getElementById("approveCurrentChallenge").addEventListener("click", this.approveCurrentChallenge.bind(this));
        }
        if(document.getElementById("revertApproval")) {
            document.getElementById("revertApproval").addEventListener("click", this.revertApproval.bind(this));
        }
        if(document.getElementById("approveAllChallenges")) {
            document.getElementById("approveAllChallenges").addEventListener("click", this.approveAllChallenges.bind(this));
        }
        if(document.getElementById("revertAllApprovals")) {
            document.getElementById("revertAllApprovals").addEventListener("click", this.revertAllApprovals.bind(this));
        }

        this.#setZeroMdListener();

        this.refresh();
    }

    gotoSubSiteMd(path) {
        if(path.startsWith("/md/challenges/") || path.startsWith("/md/solutions/") && path.endsWith(".md")) {
            this.#isSubSite = true;
            if(document.getElementById("challengeSubtitle")) {
                document.getElementById("challengeSubtitle").style.display = "block";
                document.getElementById("challengeSubtitle").innerText = "Subsite: " + path.substring(path.lastIndexOf("/") + 1);
            }
            document.getElementById("zeromd").src = path;
        }
    }

    #setZeroMdListener() {
        var that = this;
        var currentUrl = new URL(window.location.href);
        console.log("Current URL", currentUrl);
        document.getElementById("zeromd").addEventListener('zero-md-rendered', function() {
            var mdBase = document.getElementById("zeromd").src.substring(0, document.getElementById("zeromd").src.lastIndexOf("/") + 1);
            console.log("configuring markdown links");
            var nodes = document.getElementById("zeromd").shadowRoot.querySelectorAll('a[href]');
            nodes.forEach(function(node) {
                var href = new URL(node.href);
                if(href.host !== currentUrl.host) {
                    // external link
                    node.target = "_blank";
                    return;
                }
                if((href.pathname.startsWith("/md/challenges/") || href.pathname.startsWith("/md/solutions/")) && href.pathname.endsWith(".md")) {
                    node.href="#";
                    node.addEventListener("click", function(event) {
                        event.preventDefault();
                        that.gotoSubSiteMd(href.pathname);
                    });
                }
            });
            console.log("configuring markdown images");
            document.getElementById("zeromd").shadowRoot.querySelectorAll('img').forEach(function(img) {
                if(img.src) {
                    // is it at the same host
                    if(img.src.startsWith(currentUrl.origin)) {
                        let rp = img.src.substring(currentUrl.origin.length);
                        if(!rp.startsWith("/md/challenges/") && !rp.startsWith("/md/solutions/")) {
                            img.src = mdBase + rp;
                        }
                    }
                }
            });

        });
    }

    async getChallenges() {
        return fetch("/api/list/challenges")
            .then(response => response.json());
    }

    async getUnlockedStep() {
        try {  
            var data = await fetch("/api/get/challenge")
                .then(response => response.json());
            console.log("Current challenge", data);
            if(data.challenge) {
                return parseInt(data.challenge);
            }
        }
        catch {
            console.log("Error fetching current unlocked challenge");
            return 1;
        }
        return 1;
    }

    async refresh() {
        console.log("Refreshing");
        try{
            var requiresRendering = false;
            try {
                this.#challenges = await this.getChallenges();
                console.log("Challenges", this.#challenges);
            }
            catch {
                console.log("Error fetching challenges");
            }
            try {
                var currentStep = await this.getUnlockedStep();
                if(currentStep > 0) {
                    if(this.#currentStep !== currentStep) {
                        requiresRendering = true;
                        if(this.#currentStep !== null) {
                            if(currentStep > this.#currentStep ) {
                                this.#currentStep = currentStep; // ensure that the current step is updated before informing the user
                                this.#informUserOfNewStep();
                            }
                            else {
                                this.#currentStep = currentStep; // ensure that the current step is updated before informing the user
                                this.#informUserOfRevokedStep();
                            }
                        }                            
                    }
                    this.#currentStep = currentStep;
                    if(this.#currentChallenge === null) {
                        this.#currentChallenge = Math.max(1, Math.min(this.#currentStep, this.#challenges.length));
                        requiresRendering = true;

                    }
                }
            }
            catch {
                console.log("Error fetching current challenge");
            }
            if(requiresRendering) {
                this.#render();
            }
        }
        finally {
            this.#setRefreshTimer();
        }
    }

    #closeDialog() {
        try {
            if(document.getElementById("challengeDialog")) {
                let dialog = document.getElementById("challengeDialog");
                dialog.classList.remove("show");
            }
        }
        catch {}
    }
    #acceptDialog() {
        this.navToCurrentChallenge();
        this.#closeDialog();
    }

    #showDialog(message, title="Challenge Update") {
        if(document.getElementById("challengeDialog")) {
            try {
                let dialog = document.getElementById("challengeDialog");
                if(dialog.querySelector("button.dialog-close")) {
                    dialog.querySelector("button.dialog-close").onclick = this.#closeDialog.bind(this);
                }
                if(dialog.querySelector("button.cancel-dialog")) {
                    dialog.querySelector("button.cancel-dialog").onclick = this.#closeDialog.bind(this);
                }
                if(dialog.querySelector("button.accept-dialog")) {
                    dialog.querySelector("button.accept-dialog").onclick = this.#acceptDialog.bind(this);
                }
                dialog.classList.remove("show");
                dialog.querySelector(".dialog-title").innerText = title;
                dialog.querySelector(".dialog-body").innerText = message;
                dialog.classList.add("show");
            }
            catch {
                this.#closeDialog();
                alert(message);
            }
        }
        else {
            alert(message);
        }
    }

    #informUserOfNewStep() {
        if(this.#currentStep > this.#challenges.length) {
            this.#showDialog("Congratulations! What an achievement! You have completed all challenges! 🎉", "Challenges completed 🎉");
        }
        else {
            this.#showDialog("Solution got approved, you have unlocked another challenge! 🎉", "Challenge unlocked 🎉");
        }
    }
    #informUserOfRevokedStep() {
        this.#showDialog("Challenge got revoked, back to the previous challenge! 😞", "Challenge revoked");
    }

    #setRefreshTimer() {
        if(this.#refreshTimeout) {
            clearTimeout(this.#refreshTimeout);
            this.#refreshTimeout = null;
        }
        if(this.#refreshSeconds > 0) {
            this.#refreshTimeout = setTimeout(this.refresh.bind(this), this.#refreshSeconds * 1000);
        }
    }
    setPeriodicRefresh(seconds) {
        seconds = parseFloat(seconds);
        if(seconds < 0) {
            seconds = 0;
        }
        this.#refreshSeconds = seconds;
        this.#setRefreshTimer();
    }
    getPeriodicRefresh() {
        return this.#refreshSeconds;
    }


    #render() {
        if(this.#currentStep < this.#currentChallenge) {
            this.#currentChallenge = this.#currentStep;
        }
        if(this.#challenges.length === 0) {
            console.log("No challenges available");
            return;
        }

        if(document.getElementById("challengeSubtitle")) {
            document.getElementById("challengeSubtitle").style.display = "none";
        }

        if(this.#currentStep > this.#challenges.length) {
            document.getElementById("challengeIndex").innerText = "All done! 🎉";
        }
        else {
            document.getElementById("challengeIndex").innerText = this.#currentStep;
        }

        // not at the first challenge
        if(this.#currentChallenge > 1) {
            document.getElementById("navToPreviousChallenge").style.display = "block";
        }
        else {
            document.getElementById("navToPreviousChallenge").style.display = "none";
        }
        // not at the last challenge
        if(
            this.#currentChallenge < this.#challenges.length &&
            this.#currentChallenge < this.#currentStep

        ){
            document.getElementById("navToNextChallenge").style.display = "block";
        }
        else {
            document.getElementById("navToNextChallenge").style.display = "none";
        }
        // approve - not at the last approved challenge
        if(document.getElementById("approveCurrentChallenge")) {
            if(this.#currentStep < this.#challenges.length + 1) {
                document.getElementById("approveCurrentChallenge").style.display = "block";
            }
            else {
                document.getElementById("approveCurrentChallenge").style.display = "none";
            }

        }
        // approve all - not at the last approved challenge
        if(document.getElementById("approveAllChallenges")) {
            if(this.#currentStep < this.#challenges.length + 1) {
                document.getElementById("approveAllChallenges").style.display = "block";
            }
            else {
                document.getElementById("approveAllChallenges").style.display = "none";
            }
        }
        // revert - not at the first approved challenge
        if(document.getElementById("revertApproval")) {
            if(this.#currentStep > 1) {
                document.getElementById("revertApproval").style.display = "block";
            }
            else {
                document.getElementById("revertApproval").style.display = "none";
            }
        }
        // revert all - not at the first approved challenge
        if(document.getElementById("revertAllApprovals")) {
            if(this.#currentStep > 1) {
                document.getElementById("revertAllApprovals").style.display = "block";
            }
            else {
                document.getElementById("revertAllApprovals").style.display = "none";
            }
        }

        var mdUrl = "/md/challenges/";
        if(window.defaultChallengeUrl) {
            mdUrl = window.defaultChallengeUrl;
        }
        if(mdUrl.endsWith("/")) {
            mdUrl = mdUrl.substring(0, mdUrl.length - 1);
        }
        var realcurrentChallenge = Math.max(1, Math.min(this.#currentChallenge, this.#challenges.length));
        if(this.#challenges[realcurrentChallenge - 1].startsWith("/")) {
            mdUrl += this.#challenges[realcurrentChallenge - 1];
        }
        else {
            mdUrl += "/" + this.#challenges[realcurrentChallenge - 1];
        }
        if(document.getElementById("challengeTitle")) {
            document.getElementById("challengeTitle").innerText = "Challenge " + realcurrentChallenge;
        }
        this.#isSubSite = false;
        document.getElementById("zeromd").src = mdUrl;
    }

    navToPreviousChallenge() {
        if(this.#isSubSite) {
            this.#isSubSite = false;
            this.#render();
            return;
        }
        if(this.#currentChallenge > 1) {
            this.#currentChallenge--;
            this.#render();
        }
    }

    navToCurrentChallenge() {
        if(this.#currentChallenge !== this.#currentStep || this.#isSubSite) {
            this.#isSubSite = false;
            this.#currentChallenge = Math.max(1, Math.min(this.#currentStep, this.#challenges.length));
            this.#render();
        }
    }

    navToNextChallenge() {
        if(this.#currentChallenge < this.#challenges.length) {
            this.#currentChallenge++;
            this.#render();
        }
    }

    async #setApprovedChallenge(challenge) {        
        var data = await fetch("/api/set/challenge", {
            method: "POST",
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify({
                "challenge": challenge
            })
        }).then(response => response.json());
        console.log("Set challenge response", data);
        this.refresh();
    }

    async approveAllChallenges() {
        console.log("Approve all challenges");
        await this.#setApprovedChallenge("last");
    }

    async revertAllApprovals() {
        console.log("Revert all approvals");
        await this.#setApprovedChallenge("first");
    }

    async approveCurrentChallenge() {
        console.log("Approve current challenge");
        await this.#setApprovedChallenge("increase");
    }

    async revertApproval() {
        console.log("Revert approval");
        await this.#setApprovedChallenge("decrease");
    }

    registerHotkeys() {
        // register <- and -> for navigation
        document.addEventListener('keydown', (event) => {
            if(event.target.tagName === 'INPUT' || event.target.tagName === 'TEXTAREA' || event.target.isContentEditable) {
                // ignore when focused on input or textarea or contenteditable
                return;
            }
            this.#closeDialog(); // in case the dialog is open, close it
            if(event.key === 'ArrowLeft' || event.key === 'p') {
                this.navToPreviousChallenge();
                return;
            }
            else if(event.key === 'ArrowRight' || event.key === 'n') {
                this.navToNextChallenge();
                return;
            }
            else if(event.key === 'c') {
                this.navToCurrentChallenge();
                return;
            }
            else if(event.key === 'a') {
                this.approveCurrentChallenge();
                return;
            }
            else if(event.key === 'r') {
                this.revertApproval();
                return;
            }
        });
    }
}


window.challenge = new ChallengeManager();
window.challenge.setPeriodicRefresh(10);
window.challenge.registerHotkeys();


