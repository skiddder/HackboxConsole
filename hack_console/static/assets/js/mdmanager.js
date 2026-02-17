import { Clicker } from './clicker.js';
import { ToolTip } from './tooltip.js';

export class MdManagerSettings {
    #navToPrevious = null;
    #navToCurrent = null;
    #navToNext = null;
    #navToApprove = null;
    #navToRevert = null;
    #navToApproveAll = null;
    #navToRevertAll = null;
    #mdIndex = null;
    #mdTitle = null;
    #mdTitleTemplate = "Challenge {value}";
    #mdSubtitle = null;
    #mdSubtitleTemplate = "Subsite: {value}";
    #zeroMdElement = null;
    #messageDialog = null;
    #allowedMdPaths = [];
    #mdRetrievalEndpoint = '/api/list/challenges';
    #mdRootPath = '/md/challenges/';
    constructor(obj={}, logSettings=false) {
        if(obj.zeroMdElement) {
            this.#zeroMdElement = this.#elementFrom(obj.zeroMdElement);
        }
        else {
            this.#zeroMdElement = this.#elementFrom("zeromd");
        }
        if(this.#zeroMdElement === null) {
            throw new Error("zeroMdElement is required");
        }
        if(obj.navToPrevious) {
            this.#navToPrevious = this.#elementFrom(obj.navToPrevious);
        }
        else {
            this.#navToPrevious = this.#elementFrom("navToPrevious");
        }
        if(obj.navToCurrent) {
            this.#navToCurrent = this.#elementFrom(obj.navToCurrent);
        }
        else {
            this.#navToCurrent = this.#elementFrom("navToCurrent");
        }
        if(obj.navToNext) {
            this.#navToNext = this.#elementFrom(obj.navToNext);
        }
        else {
            this.#navToNext = this.#elementFrom("navToNext");
        }
        if(obj.navToApprove) {
            this.#navToApprove = this.#elementFrom(obj.navToApprove);
        }
        else {
            this.#navToApprove = this.#elementFrom("navToApprove");
        }
        if(obj.navToRevert) {
            this.#navToRevert = this.#elementFrom(obj.navToRevert);
        }
        else {
            this.#navToRevert = this.#elementFrom("navToRevert");
        }
        if(obj.navToApproveAll) {
            this.#navToApproveAll = this.#elementFrom(obj.navToApproveAll);
        }
        else {
            this.#navToApproveAll = this.#elementFrom("navToApproveAll");
        }
        if(obj.navToRevertAll) {
            this.#navToRevertAll = this.#elementFrom(obj.navToRevertAll);
        }
        else {
            this.#navToRevertAll = this.#elementFrom("navToRevertAll");
        }
        if(obj.mdTitle) {
            this.#mdTitle = this.#elementFrom(obj.mdTitle);
        }
        else {
            this.#mdTitle = this.#elementFrom("mdTitle");
        }
        if(obj.mdTitleTemplate) {
            this.#mdTitleTemplate = String(obj.mdTitleTemplate);
            if(this.#mdTitleTemplate.trim() === "") {
                this.#mdTitleTemplate = "Challenge {value}";
            }
            if(!this.#mdTitleTemplate.includes("{value}")) {
                this.#mdTitleTemplate += " {value}";
            }
        }
        if(obj.mdSubtitle) {
            this.#mdSubtitle = this.#elementFrom(obj.mdSubtitle);
        }
        else {
            this.#mdSubtitle = this.#elementFrom("mdSubtitle");
        }
        if(obj.mdSubtitleTemplate) {
            this.#mdSubtitleTemplate = String(obj.mdSubtitleTemplate);
            if(this.#mdSubtitleTemplate.trim() === "") {
                this.#mdSubtitleTemplate = "Subsite: {value}";
            }
            if(!this.#mdSubtitleTemplate.includes("{value}")) {
                this.#mdSubtitleTemplate += " {value}";
            }
        }
        if(obj.mdIndex) {
            this.#mdIndex = this.#elementFrom(obj.mdIndex);
        }
        else {
            this.#mdIndex = this.#elementFrom("mdIndex");
        }
        if(obj.messageDialog) {
            this.#messageDialog = this.#elementFrom(obj.messageDialog);
        }
        else {
            this.#messageDialog = this.#elementFrom("messageDialog");
        }
        if(obj.allowedMdPaths && Array.isArray(obj.allowedMdPaths)) {
            for(let path of obj.allowedMdPaths) {
                if(path === null || path === undefined) {
                    return;
                }
                path = String(path).trim();
                if(path === "") {
                    return;
                }
                // ensure we have an absolute path
                if(!path.startsWith("/")) {
                    let currentPath = window.location.pathname;
                    if(!currentPath.endsWith("/")) {
                        currentPath = currentPath.substring(0, currentPath.lastIndexOf("/")) + "/";
                    }
                    path = currentPath + path;
                }
                this.#allowedMdPaths.push(path);
            }
        }
        else {
            this.#allowedMdPaths = ["/md/challenges/", "/md/solutions/"];
        }

        if(obj.mdRetrievalMode) {
            if(String(obj.mdRetrievalMode).toLowerCase() === "solutions") {
                this.#mdRetrievalEndpoint = '/api/list/solutions';
                this.#mdRootPath = '/md/solutions/';
            }
            else {
                this.#mdRetrievalEndpoint = '/api/list/challenges';
                this.#mdRootPath = '/md/challenges/';
            }
        }

        if(logSettings) {
            console.log("MdManagerSettings initialized", this);
        }
    }

    getMdEndpoints() {
        return {
            mdRetrievalEndpoint: this.#mdRetrievalEndpoint,
            mdRootPath: this.#mdRootPath
        };
    }

    getZeroMdElement() {
        return this.#zeroMdElement;
    }

    getTemplates() {
        return {
            mdTitleTemplate: this.#mdTitleTemplate,
            mdSubtitleTemplate: this.#mdSubtitleTemplate,
        };
    }

    getElements() {
        return {
            navToPrevious: this.#navToPrevious,
            navToCurrent: this.#navToCurrent,
            navToNext: this.#navToNext,
            navToApprove: this.#navToApprove,
            navToRevert: this.#navToRevert,
            navToApproveAll: this.#navToApproveAll,
            navToRevertAll: this.#navToRevertAll,
            mdTitle: this.#mdTitle,
            mdSubtitle: this.#mdSubtitle,
            mdIndex: this.#mdIndex,
            messageDialog: this.#messageDialog,
            zeroMdElement: this.#zeroMdElement,
        };
    }

    getAllowedMdPaths() {
        return this.#allowedMdPaths;
    }

    #elementFrom(value) {
        if(value === null || value === undefined) {
            return null;
        }
        // is an HTMLElement?
        if(value instanceof HTMLElement) {
            return value;
        }
        // is a string?
        if(typeof value === "string") {
            if(value.trim() === "") {
                return null;
            }
            return document.getElementById(value);
        }
        return null;
    }
}


export class MdManager {
    #challenges = [];
    #currentStep = null;
    #currentChallenge = null;
    #refreshSeconds = 0;
    #refreshTimeout = null;
    #isSubSite = false;
    #cachedSecrets = null;
    #chachedSecretsRefreshing = false;
    #templates = {};
    #elements = {};
    #allowedMdPaths = [];
    #mdEndpoints = {};
    #tooltip = new ToolTip();
    #rdpClient = null;

    constructor(settings) {
        if(settings === null || settings === undefined) {
            throw new Error("MdManagerSettings is required");
        }
        if(!(settings instanceof MdManagerSettings)) {
            // a useful object?
            if(
                typeof settings === "object" &&
                settings.hasOwnProperty("navToPrevious") &&
                settings.hasOwnProperty("navToCurrent") &&
                settings.hasOwnProperty("navToNext")
            ) {
                settings = new MdManagerSettings(settings);
            }
            else {
                throw new Error("settings must be an instance of MdManagerSettings");
            }
        }

        this.#allowedMdPaths = settings.getAllowedMdPaths();
        this.#templates = settings.getTemplates();
        this.#elements = settings.getElements();
        this.#mdEndpoints = settings.getMdEndpoints();
        if(this.#mdEndpoints.mdRetrievalEndpoint.trim() == "") {
            throw new Error("retrievalEndpoint is required");
        }
        if(this.#mdEndpoints.mdRootPath.trim() == "") {
            throw new Error("mdRootPath is required");
        }

        if(!(this.#elements.zeroMdElement instanceof HTMLElement)) {
            throw new Error("zeroMdElement is required");
        }

        if(this.#elements.navToPrevious instanceof HTMLElement) {
            this.#elements.navToPrevious.style.display = "none";
            this.#elements.navToPrevious.addEventListener("click", this.navToPreviousChallenge.bind(this));
        }
        if(this.#elements.navToCurrent instanceof HTMLElement) {
            this.#elements.navToCurrent.addEventListener("click", this.navToCurrentChallenge.bind(this));
        }
        if(this.#elements.navToNext instanceof HTMLElement) {
            this.#elements.navToNext.style.display = "none";
            this.#elements.navToNext.addEventListener("click", this.navToNextChallenge.bind(this));
        }
        if(this.#elements.navToApprove instanceof HTMLElement) {
            this.#elements.navToApprove.addEventListener("click", this.approveCurrentChallenge.bind(this));
        }
        if(this.#elements.navToRevert instanceof HTMLElement) {
            this.#elements.navToRevert.addEventListener("click", this.revertApproval.bind(this));
        }
        if(this.#elements.navToApproveAll instanceof HTMLElement) {
            this.#elements.navToApproveAll.addEventListener("click", this.approveAllChallenges.bind(this));
        }
        if(this.#elements.navToRevertAll instanceof HTMLElement) {
            this.#elements.navToRevertAll.addEventListener("click", this.revertAllApprovals.bind(this));
        }

        this.#setZeroMdListener();

        this.refresh();
    }

    #adjustSecretTitles() {
        let rdpActive = this.#rdpClient && this.#rdpClient.isConnected();
        // replace all titles (click handlers are already set to inject into RDP if client is available, so we only need to update the title here)
        this.#elements.zeroMdElement.shadowRoot.querySelectorAll('span.secret').forEach((elem) => {
            if(rdpActive) {
                elem.title = elem.title.replace('Double click to copy credential.', 'Double Click to inject credential into RDP session.');
            }
            else {
                elem.title = elem.title.replace('Double Click to inject credential into RDP session.', 'Double click to copy credential.');
            }
        });

    }

    setRdpClient(rdpClient) {
        this.#rdpClient = rdpClient;
        this.#rdpClient.on("connected", this.#adjustSecretTitles.bind(this));
        this.#rdpClient.on("disconnected", this.#adjustSecretTitles.bind(this));
        this.#adjustSecretTitles();
    }

    gotoSubSiteMd(path) {
        // check for allowed paths
        for(const allowedPath of this.#allowedMdPaths) {
            if(path.startsWith(allowedPath) && path.endsWith(".md")) {
                this.#isSubSite = true;
                if(this.#elements.mdSubtitle instanceof HTMLElement) {
                    this.#elements.mdSubtitle.style.display = "block";
                    this.#elements.mdSubtitle.innerText = this.#templates.mdSubtitleTemplate.replace("{value}", path.substring(path.lastIndexOf("/") + 1));
                }
                this.#elements.zeroMdElement.src = path;
                break;
            }
        }
    }

    async #loadAllSecrets() {
        // wait until refresh is done
        while(this.#chachedSecretsRefreshing) {
            await new Promise(resolve => setTimeout(resolve, 50));
        }
        if(this.#cachedSecrets === null) {
            try {
                this.#chachedSecretsRefreshing = true;
                const secrets = await fetch('/api/show/credentials').then(response => response.json());
                let d = {};
                for (let i in secrets) {
                    let g = String(secrets[i].group).toLowerCase();
                    let n = String(secrets[i].name).toLowerCase();
                    d[`${g}|${n}`] = secrets[i];
                }
                this.#cachedSecrets = d;
            } finally {
                this.#chachedSecretsRefreshing = false;
            }
        }
    }

    async #getSecret(group, name) {
        group = String(group).toLowerCase();
        name = String(name).toLowerCase();
        // wait for secrets to be loaded
        await this.#loadAllSecrets();
        return this.#cachedSecrets[`${group}|${name}`];
    }

    #setZeroMdListener() {
        let that = this;
        let currentUrl = new URL(window.location.href);
        console.log("Current URL", currentUrl);
        this.#elements.zeroMdElement.addEventListener('zero-md-rendered', function() {
            let mdBase = that.#elements.zeroMdElement.src.substring(0, that.#elements.zeroMdElement.src.lastIndexOf("/") + 1);
            console.log("configuring markdown links");
            let nodes = that.#elements.zeroMdElement.shadowRoot.querySelectorAll('a[href]');
            nodes.forEach(function(node) {
                let href = new URL(node.href);
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
            that.#elements.zeroMdElement.shadowRoot.querySelectorAll('img').forEach(function(img) {
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
            console.log("configuring secret groups");
            that.#elements.zeroMdElement.shadowRoot.querySelectorAll('secretgroup').forEach(that.#renderSecretGroup.bind(that));
            console.log("configuring secrets");
            that.#elements.zeroMdElement.shadowRoot.querySelectorAll('secret').forEach(that.#renderSecret.bind(that));
        });
    }

    async #renderSecretGroup(secretGroupElem) {
        // <secretgroup group="azure" show="true|false|alwayshidden" text="Login Information for the Lab Environment" />
        let group = secretGroupElem.getAttribute("group") ? secretGroupElem.getAttribute("group") : "Default";
        let show = secretGroupElem.getAttribute("show") ? secretGroupElem.getAttribute("show").toLowerCase() : "false";
        // replace the elemt with a div
        let tbl = document.createElement("table");
        let thead = document.createElement("thead");
        tbl.appendChild(thead);
        let tbody = document.createElement("tbody");
        tbl.appendChild(tbody);
        // table header
        let headerRow = document.createElement("tr");
        let th1 = document.createElement("th");
        th1.innerText = "Name";
        let th2 = document.createElement("th");
        th2.innerText = "Credential";
        headerRow.appendChild(th1);
        headerRow.appendChild(th2);
        thead.appendChild(headerRow);
        // wait for secrets to be loaded
        await this.#loadAllSecrets();
        for(const k of Object.keys(this.#cachedSecrets)) {
            const secretInfo = this.#cachedSecrets[k];
            if(String(secretInfo.group).toLowerCase() === String(group).toLowerCase()) {
                // create a row for the secret
                let tr = document.createElement("tr");
                let td1 = document.createElement("td");
                td1.innerText = secretInfo.name;
                let td2 = document.createElement("td");
                let secretEl = document.createElement("secret");
                secretEl.setAttribute("group", group);
                secretEl.setAttribute("name", secretInfo.name);
                secretEl.setAttribute("show", show);
                td2.appendChild(secretEl);
                tr.appendChild(td1);
                tr.appendChild(td2);
                tbody.appendChild(tr);
            }
        }

        secretGroupElem.parentElement.replaceChild(tbl, secretGroupElem);
        // also render secrets inside the table
        tbl.querySelectorAll('secret').forEach(this.#renderSecret.bind(this));
    }

    async #renderSecret(secretElem) {
        if(!(secretElem instanceof HTMLElement)) {
            return;
        }
        let that = this;
        // <secret group="groupname" name="secretname" show="true|false|alwayshidden" />
        let group = secretElem.getAttribute("group") ? secretElem.getAttribute("group") : "Default";
        let name = secretElem.getAttribute("name");
        let show = secretElem.getAttribute("show") ? secretElem.getAttribute("show").toLowerCase() : "false";
        if(show !== "true" && show !== "false" && show !== "alwayshidden") {
            show = "false";
        }

        let secret = await this.#getSecret(group, name);
        let secretValue = secret ? String(secret.Credential) : "undefined";


        // replace secret element with span
        let span = document.createElement("span");
        span.classList.add("secret");
        if(this.#rdpClient) {
            span.title = 'Double Click to inject credential into RDP session.';
        }
        else {
            span.title = 'Double click to copy credential.';
        }
        if(secret.note) {
            span.title += ' (Note: ' + secret.note + ')';
        }
        if(show === "true") {
            span.innerText = '📑 ' + secretValue;
        }
        else {
            span.classList.add('hidden');
            span.innerText = '📑 ' + '••••••••' + '•'.repeat(Math.max(secretValue.length - 8, 0));
        }
        secretElem.parentElement.replaceChild(span, secretElem);
        let clicker = new Clicker(span);
        if(show !== "alwayshidden") {
            clicker.onSingleClick(function(event) {
                if(span.classList.contains('hidden')) {
                    span.classList.remove('hidden');
                    span.innerText = '📑 ' + secretValue;
                }
                else {
                    span.classList.add('hidden');
                    span.innerText = '📑 ' + '••••••••' + '•'.repeat(Math.max(secretValue.length - 8, 0));
                } 
            });
        }
        clicker.onDoubleClick(function(event) {
            let useRdpClient = false;
            try {
                if(that.#rdpClient && that.#rdpClient.isConnected()) {
                    useRdpClient = true;
                }
            }
            catch {
                useRdpClient = false;
            }

            if(useRdpClient) {
                try {
                    that.#rdpClient.sendKeys(secretValue);
                }
                catch {
                    console.log("Failed to inject credential into RDP session");
                }
                that.#tooltip.show('📑 Injecting!', 1200, event);
            }
            else {
                navigator.clipboard.writeText(secretValue);
                that.#tooltip.show('📑 Copied!', 1200, event);
            }
            // show tooltip
            that.#tooltip.onHideOnce(() => {
                // set credential to initial state
                if(show === "true") {
                    if(span.classList.contains('hidden')) {
                        span.classList.remove('hidden');
                    }
                    span.innerText = '📑 ' + secretValue;
                }
                else {
                    if(!span.classList.contains('hidden')) {
                        span.classList.add('hidden');
                    }
                    span.innerText = '📑 ' + '••••••••' + '•'.repeat(Math.max(secretValue.length - 8, 0));
                }
            });
        });
    }

    async getChallenges() {
        return fetch(this.#mdEndpoints.mdRetrievalEndpoint)
            .then(response => response.json());
    }

    async getUnlockedStep() {
        let data = await fetch("/api/get/challenge")
            .then(response => response.json());
        console.log("Current challenge", data);
        if(data.challenge) {
            return parseInt(data.challenge);
        }
        return 1;
    }

    async refresh() {
        console.log("Refreshing");
        try{
            let requiresRendering = false;
            try {
                this.#challenges = await this.getChallenges();
                console.log("Challenges", this.#challenges);
            }
            catch(err) {
                console.log("Error fetching challenges", err);
            }
            try {
                let currentStep = await this.getUnlockedStep();
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
            catch(err) {
                console.log("Error fetching current challenge", err);
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
            if(this.#elements.messageDialog instanceof HTMLElement) {
                this.#elements.messageDialog.classList.remove("show");
            }
        }
        catch {}
    }
    #acceptDialog() {
        this.navToCurrentChallenge();
        this.#closeDialog();
    }

    #showDialog(message, title="Challenge Update") {
        if(this.#elements.messageDialog instanceof HTMLElement) {
            try {
                let dialog = this.#elements.messageDialog;
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

        if(this.#elements.mdSubtitle instanceof HTMLElement) {
            this.#elements.mdSubtitle.style.display = "none";
        }

        if(this.#elements.mdIndex instanceof HTMLElement) {
            if(this.#currentStep > this.#challenges.length) {
                this.#elements.mdIndex.innerText = "All done! 🎉";
            }
            else {
                this.#elements.mdIndex.innerText = this.#currentStep;
            }
        }

        // update previous button?
        if(this.#elements.navToPrevious instanceof HTMLElement) {
            // not at the first challenge
            if(this.#currentChallenge > 1) {
                this.#elements.navToPrevious.style.display = "block";
            }
            else {
                this.#elements.navToPrevious.style.display = "none";
            }
        }
        // update next button?
        if(this.#elements.navToNext instanceof HTMLElement) {
            // not at the last challenge
            if(
                this.#currentChallenge < this.#challenges.length &&
                this.#currentChallenge < this.#currentStep

            ){
                this.#elements.navToNext.style.display = "block";
            }
            else {
                this.#elements.navToNext.style.display = "none";
            }
        }
        // approve - not at the last approved challenge
        if(this.#elements.navToApprove instanceof HTMLElement) {
            if(this.#currentStep < this.#challenges.length + 1) {
                this.#elements.navToApprove.style.display = "block";
            }
            else {
                this.#elements.navToApprove.style.display = "none";
            }

        }
        // approve all - not at the last approved challenge
        if(this.#elements.navToApproveAll instanceof HTMLElement) {
            if(this.#currentStep < this.#challenges.length + 1) {
                this.#elements.navToApproveAll.style.display = "block";
            }
            else {
                this.#elements.navToApproveAll.style.display = "none";
            }
        }
        // revert - not at the first approved challenge
        if(this.#elements.navToRevert instanceof HTMLElement) {
            if(this.#currentStep > 1) {
                this.#elements.navToRevert.style.display = "block";
            }
            else {
                this.#elements.navToRevert.style.display = "none";
            }
        }
        // revert all - not at the first approved challenge
        if(this.#elements.navToRevertAll instanceof HTMLElement) {
            if(this.#currentStep > 1) {
                this.#elements.navToRevertAll.style.display = "block";
            }
            else {
                this.#elements.navToRevertAll.style.display = "none";
            }
        }

        let mdUrl = this.#mdEndpoints.mdRootPath;
        if(window.defaultChallengeUrl) {
            mdUrl = window.defaultChallengeUrl;
        }
        if(mdUrl.endsWith("/")) {
            mdUrl = mdUrl.substring(0, mdUrl.length - 1);
        }
        let realcurrentChallenge = Math.max(1, Math.min(this.#currentChallenge, this.#challenges.length));
        if(this.#challenges[realcurrentChallenge - 1].startsWith("/")) {
            mdUrl += this.#challenges[realcurrentChallenge - 1];
        }
        else {
            mdUrl += "/" + this.#challenges[realcurrentChallenge - 1];
        }
        if(this.#elements.mdTitle instanceof HTMLElement) {
            this.#elements.mdTitle.innerText = "Challenge " + realcurrentChallenge;
        }
        this.#isSubSite = false;
        this.#elements.zeroMdElement.src = mdUrl;
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
        let data = await fetch("/api/set/challenge", {
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

    registerHotkeys(ignoreElementIds = []) {
        console.log("Registering hotkeys");
        // register <- and -> for navigation
        const ignoreIds = new Set(ignoreElementIds);
        document.addEventListener('keydown', (event) => {
            if(event.target.tagName === 'INPUT' || event.target.tagName === 'TEXTAREA' || event.target.isContentEditable) {
                // ignore when focused on input or textarea or contenteditable
                return;
            }
            // ignore key presses originating from within ignored containers (e.g. shadow DOM)
            if(ignoreIds.size > 0 && event.composedPath().some(el => el instanceof HTMLElement && ignoreIds.has(el.id))) {
                return;
            }
            // ignore key presses with modifier keys (Ctrl, Alt, Shift, Meta)
            if(event.ctrlKey || event.altKey || event.shiftKey || event.metaKey) {
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

export function getMdManager(settings) {
    return new MdManager(new MdManagerSettings(settings));
}
