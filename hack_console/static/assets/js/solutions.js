class SolutionManager {
    #solutions = [];
    #currentStep = null;
    #currentSolution = null;
    #refreshSeconds = 0;
    #refreshTimeout = null;
    #isSubSite = false;
    constructor() {
        document.getElementById("navToPreviousSolution").style.display = "none";
        document.getElementById("navToPreviousSolution").addEventListener("click", this.navToPreviousSolution.bind(this));
        document.getElementById("navToCurrentSolution").addEventListener("click", this.navToCurrentSolution.bind(this));
        document.getElementById("navToNextSolution").style.display = "none";
        document.getElementById("navToNextSolution").addEventListener("click", this.navToNextSolution.bind(this));

        this.#setZeroMdListener();

        this.refresh();
    }

    gotoSubSiteMd(path) {
        if(path.startsWith("/md/challenges/") || path.startsWith("/md/solutions/") && path.endsWith(".md")) {
            this.#isSubSite = true;
            document.getElementById("zeromd").src = path;
        }
    }

    #setZeroMdListener() {
        var that = this;
        var currentUrl = new URL(window.location.href);
        console.log("Current URL", currentUrl);
        document.getElementById("zeromd").addEventListener('zero-md-rendered', function() {
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
        });
    }

    async getSolutions() {
        return fetch("/api/list/solutions")
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
            console.log("Error fetching current unlocked solution");
            return 1;
        }
        return 1;
    }

    async refresh() {
        console.log("Refreshing");
        try{
            var requiresRendering = false;
            try {
                this.#solutions = await this.getSolutions();
                console.log("Solutions", this.#solutions);
            }
            catch {
                console.log("Error fetching solutions");
            }
            try {
                var currentStep = await this.getUnlockedStep();
                if(currentStep > 0) {
                    if(this.#currentStep !== currentStep) {
                        requiresRendering = true;
                        if(this.#currentStep !== null) {
                            if(currentStep > this.#currentStep ) {
                                this.#informUserOfNewStep();
                            }
                            else {
                                this.#informUserOfRevokedStep();
                            }
                        }                            
                    }
                    this.#currentStep = currentStep;
                    if(this.#currentSolution === null) {
                        this.#currentSolution = Math.max(1, Math.min(this.#currentStep, this.#solutions.length));
                        requiresRendering = true;

                    }
                }
            }
            catch {
                console.log("Error fetching current solution");
            }
            if(requiresRendering) {
                this.#render();
            }
        }
        finally {
            this.#setRefreshTimer();
        }
    }

    #showDialog(message) {
        alert(message);
    }

    #informUserOfNewStep() {
        this.#showDialog("Solution got approved, you have unlocked another solution!");
    }
    #informUserOfRevokedStep() {
        this.#showDialog("Solution got revoked, back to the previous solution!");
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
        if(this.#currentStep < this.#currentSolution) {
            this.#currentSolution = this.#currentStep;
        }
        if(this.#solutions.length === 0) {
            console.log("No solutions available");
            return;
        }

        if(this.#currentStep > this.#solutions.length) {
            document.getElementById("solutionIndex").innerText = "All done! 🎉";
        }
        else {
            document.getElementById("solutionIndex").innerText = this.#currentStep;
        }

        // not at the first challenge
        if(this.#currentSolution > 1) {
            document.getElementById("navToPreviousSolution").style.display = "block";
        }
        else {
            document.getElementById("navToPreviousSolution").style.display = "none";
        }
        // not at the last challenge
        if(
            this.#currentSolution < this.#solutions.length &&
            this.#currentSolution < this.#currentStep

        ){
            document.getElementById("navToNextSolution").style.display = "block";
        }
        else {
            document.getElementById("navToNextSolution").style.display = "none";
        }

        var mdUrl = "/md/challenges/";
        if(window.defaultSolutionUrl) {
            mdUrl = window.defaultSolutionUrl;
        }
        if(mdUrl.endsWith("/")) {
            mdUrl = mdUrl.substring(0, mdUrl.length - 1);
        }
        var realcurrentSolution = Math.max(1, Math.min(this.#currentSolution, this.#solutions.length));
        if(this.#solutions[realcurrentSolution - 1].startsWith("/")) {
            mdUrl += this.#solutions[realcurrentSolution - 1];
        }
        else {
            mdUrl += "/" + this.#solutions[realcurrentSolution - 1];
        }
        if(document.getElementById("solutionTitle")) {
            document.getElementById("solutionTitle").innerText = "Solution " + realcurrentSolution;
        }
        this.#isSubSite = false;
        document.getElementById("zeromd").src = mdUrl;        
    }

    navToPreviousSolution() {
        if(this.#currentSolution > 1) {
            this.#currentSolution--;
            this.#render();
        }
    }

    navToCurrentSolution() {
        if(this.#currentSolution !== this.#currentStep || this.#isSubSite) {
            this.#isSubSite = false;
            this.#currentSolution = Math.max(1, Math.min(this.#currentStep, this.#solutions.length));
            this.#render();
        }
    }

    navToNextSolution() {
        if(this.#currentSolution < this.#solutions.length) {
            this.#currentSolution++;
            this.#render();
        }
    }

    registerHotkeys() {
        // register <- and -> for navigation
        document.addEventListener('keydown', (event) => {
            if(event.target.tagName === 'INPUT' || event.target.tagName === 'TEXTAREA' || event.target.isContentEditable) {
                // ignore when focused on input or textarea or contenteditable
                return;
            }
            if(event.key === 'ArrowLeft' || event.key === 'p') {
                if(this.#isSubSite) {
                    this.navToCurrentSolution();
                    return;
                }
                this.navToPreviousSolution();
                return;
            }
            else if(event.key === 'ArrowRight' || event.key === 'n') {
                this.navToNextSolution();
                return;
            }
            else if(event.key === 'c') {
                this.navToCurrentSolution();
                return;
            }
        });
    }
}


window.solution = new SolutionManager();
window.solution.setPeriodicRefresh(10);
window.solution.registerHotkeys();

