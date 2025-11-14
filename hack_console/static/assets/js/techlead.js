class TechleadManagement {
    #refreshSeconds = 0;
    #actionsQueue = [];
    #tenantSettings = {};
    #actionTimeout = null;
    #refreshTimeout = null;
    #techleadNode = null;
    #techleadNodeApproveEveryTeam = null;
    #techleadNodeRevertEveryTeam = null;
    #techleadNodeResetEveryTeam = null;
    #techleadNodeTimerStartEveryTeam = null;
    #techleadNodeTimerStopEveryTeam = null;
    #techleadNodeTimerResetEveryTeam = null;
    constructor(
        nodeId = "techlead-management",
        approveEveryTeamId = "challenge-approve-every-team",
        revertEveryTeamId = "challenge-revert-every-team",
        resetEveryTeamId = "challenge-reset-every-team",
        timerStartEveryTeamId = "timer-start-every-team",
        timerStopEveryTeamId = "timer-stop-every-team",
        timerResetEveryTeamId = "timer-reset-every-team"
    ) {
        this.#techleadNode = document.getElementById(nodeId);
        // is it an html node?
        if(!(this.#techleadNode instanceof HTMLElement)) {
            throw "TechleadManagement: Node not found";
        }
        // challenge buttons
        this.#techleadNodeApproveEveryTeam = document.getElementById(approveEveryTeamId);
        if(this.#techleadNodeApproveEveryTeam instanceof HTMLElement) {
            this.#techleadNodeApproveEveryTeam.addEventListener('click', this.approveEveryTeam.bind(this));
        }
        this.#techleadNodeRevertEveryTeam = document.getElementById(revertEveryTeamId);
        if(this.#techleadNodeRevertEveryTeam instanceof HTMLElement) {
            this.#techleadNodeRevertEveryTeam.addEventListener('click', this.revertEveryTeam.bind(this));
        }
        this.#techleadNodeResetEveryTeam = document.getElementById(resetEveryTeamId);
        if(this.#techleadNodeResetEveryTeam instanceof HTMLElement) {
            this.#techleadNodeResetEveryTeam.addEventListener('click', this.resetEveryTeam.bind(this));
        }
        // timer buttons
        this.#techleadNodeTimerStartEveryTeam = document.getElementById(timerStartEveryTeamId);
        if(this.#techleadNodeTimerStartEveryTeam instanceof HTMLElement) {
            this.#techleadNodeTimerStartEveryTeam.addEventListener('click', this.timerStartEveryTeam.bind(this));
        }
        this.#techleadNodeTimerStopEveryTeam = document.getElementById(timerStopEveryTeamId);
        if(this.#techleadNodeTimerStopEveryTeam instanceof HTMLElement) {
            this.#techleadNodeTimerStopEveryTeam.addEventListener('click', this.timerStopEveryTeam.bind(this));
        }
        this.#techleadNodeTimerResetEveryTeam = document.getElementById(timerResetEveryTeamId);
        if(this.#techleadNodeTimerResetEveryTeam instanceof HTMLElement) {
            this.#techleadNodeTimerResetEveryTeam.addEventListener('click', this.timerResetEveryTeam.bind(this));
        }

        this.refresh();
        setInterval(this.renderTimerCells.bind(this), 1000);
    }

    approveEveryTeam() {
        console.log("Approve Every Team");
        this.#queueActionForAllTenants('challenge-approve');
    }
    revertEveryTeam() {
        console.log("Revert Every Team");
        this.#queueActionForAllTenants('challenge-revert');
    }
    resetEveryTeam() {
        console.log("Reset Every Team");
        this.#queueActionForAllTenants('challenge-reset');
    }
    timerStartEveryTeam() {
        console.log("Timer Start Every Team");
        this.#queueActionForAllTenants('timer-start');
    }
    timerStopEveryTeam() {
        console.log("Timer Stop Every Team");
        this.#queueActionForAllTenants('timer-stop');
    }
    timerResetEveryTeam() {
        console.log("Timer Reset Every Team");
        this.#queueActionForAllTenants('timer-reset');
    }

    #queueActionForAllTenants(action) {
        if(!this.#tenantSettings || Object.keys(this.#tenantSettings).length === 0) {
            console.warn("No tenant settings available to queue action for all tenants");
            return;
        }
        for(const tenantId of Object.keys(this.#tenantSettings)) {
            this.#queueAction(tenantId, action);
        }
    }

    async getTenantsSettings() {
        var data = await fetch("/api/get/tenants/settings")
            .then(response => response.json());
        console.log("Tenants Settings", data);
        if(data.success && data.tenants && typeof data.tenants === "object") {
            // sort object keys
            var settings = {};
            var collator = new Intl.Collator(undefined, {numeric: true, sensitivity: 'base'});
            Object.keys(data.tenants).sort(collator.compare).forEach(key => {
                settings[key] = data.tenants[key];
            });
            return settings;
        }
        throw "Invalid Timer Info";
    }

    #renderTimerCell(cell) {
        var elapsedSeconds = 0;
        if(cell.dataset.status === 'running' && cell.dataset.startTime) {
            const startTime = new Date(cell.dataset.startTime);
            elapsedSeconds = Math.floor((Date.now() - startTime.getTime()) / 1000);
            cell.innerText = "running";
        }
        else if(cell.dataset.status === 'stopped' && cell.dataset.elapsedTime) {
            elapsedSeconds = parseInt(cell.dataset.elapsedTime);
            cell.innerText = "stopped";
        }
        else {
            return;
        }
        if(elapsedSeconds > 0) {
            // render in hh:mm:ss
            let hours = Math.floor(elapsedSeconds / 3600);
            let minutes = Math.floor((elapsedSeconds % 3600) / 60);
            let seconds = parseInt(elapsedSeconds % 60);
            cell.innerText += " (" + (hours < 10 ? "0" + hours : hours) + ":" +
                            (minutes < 10 ? "0" + minutes : minutes) + ":" +
                            (seconds < 10 ? "0" + seconds : seconds) + ")";
        }
    }

    renderTimerCells() {
        const timerCells = this.#techleadNode.querySelectorAll('table.generic td[data-status]');
        for(const cell of timerCells) {
            this.#renderTimerCell(cell);
        }
    }

    async #render() {
        var nodeCollection = document.createDocumentFragment();
        for(const [tenantId, settings] of Object.entries(this.#tenantSettings)) {
            const tenantDiv = document.createElement('div');
            tenantDiv.className = 'card tenant-settings';
            // create h2 element with tenantId and pre element with settings json
            const title = document.createElement('h2');
            title.textContent = 'Tenant ' + String(tenantId);
            tenantDiv.appendChild(title);

            const table = document.createElement('table');
            table.className = 'generic';
            table.innerHTML = '<tr><th>Setting</th><th>Value</th></tr>';
            for(const [key, value] of Object.entries(settings)) {
                if(key == 'MaxStep') {
                    continue;
                }
                const row = document.createElement('tr');
                const cellKey = document.createElement('td');
                cellKey.textContent = key;
                const cellValue = document.createElement('td');
                if(key == 'Stopwatch') {
                    cellValue.dataset.status = String(value[0]);
                    if(value.length > 2){
                        if(value[0] === 'running' && value[1]) {
                            cellValue.dataset.startTime = String(value[1]);
                        }
                        if(value[2]) {
                            cellValue.dataset.elapsedTime = String(value[2]);
                        }
                        else {
                            cellValue.dataset.elapsedTime = '0';
                        }
                    }
                    cellValue.textContent = String(value[0]);
                    this.#renderTimerCell(cellValue);
                }
                else {
                    cellValue.textContent = String(value);

                }
                row.appendChild(cellKey);
                row.appendChild(cellValue);
                table.appendChild(row);
            }
            tenantDiv.appendChild(table);


            const toolBarDiv = document.createElement('div');
            toolBarDiv.className = 'toolbar';
            toolBarDiv.innerHTML = `<div class="toolbar-group">
				<a href="#" class="pill-btn success" data-action="challenge-approve">Approve</a>
                <a href="#" class="pill-btn warn" data-action="challenge-approve-all">Approve All</a>
				<a href="#" class="pill-btn warn" data-action="challenge-revert">Revert</a>
                <a href="#" class="pill-btn danger" data-action="challenge-reset">Reset</a>
			</div>
            <div class="toolbar-group highlighted-group">
                <span class="title">Timer</span>
				<a href="#" class="pill-btn success" data-action="timer-start">Start</a>
				<a href="#" class="pill-btn success" data-action="timer-stop">Stop</a>
				<a href="#" class="pill-btn warn" data-action="timer-reset">Reset</a>
			</div>`;
            // timer button visibility
            if(this.#tenantSettings[tenantId]["Stopwatch"]?.[0] === 'running') {
                toolBarDiv.querySelector('a[data-action="timer-start"]').style.display = 'none';
            }
            else {
                toolBarDiv.querySelector('a[data-action="timer-stop"]').style.display = 'none';
            }
            // challenge buttons
            if(this.#tenantSettings[tenantId]["CurrentStep"] == 1) {
                toolBarDiv.querySelector('a[data-action="challenge-revert"]').style.display = 'none';
            }
            if(this.#tenantSettings[tenantId]["CurrentStep"] === this.#tenantSettings[tenantId]["MaxStep"]) {
                toolBarDiv.querySelector('a[data-action="challenge-approve"]').style.display = 'none';
                toolBarDiv.querySelector('a[data-action="challenge-approve-all"]').style.display = 'none';
            }

            for(const btn of toolBarDiv.querySelectorAll('a[data-action]')) {
                btn.addEventListener('click', (event) => {
                    event.preventDefault();
                    const action = btn.dataset.action;
                    this.#queueAction(tenantId, action);
                });
            }
            tenantDiv.appendChild(toolBarDiv);
            
            nodeCollection.appendChild(tenantDiv);
        }
        this.#techleadNode.innerHTML = '';
        this.#techleadNode.appendChild(nodeCollection);
    }

    async refresh() {
        console.log("Refreshing");
        try{
            this.#tenantSettings = await this.getTenantsSettings();
            this.#render();
        }
        finally {
            this.#setRefreshTimer();
        }
    }

    #queueAction(tenantId, action) {
        if(this.#actionTimeout) {
            clearTimeout(this.#actionTimeout);
            this.#actionTimeout = null;
        }
        this.#actionsQueue.push({
            tenantId: tenantId,
            action: action
        });
        this.#actionTimeout = setTimeout(this.#processActionQueue.bind(this), 1000);
    }

    async #processActionQueue() {
        if(this.#actionsQueue.length > 0) {
            const actionQueue = this.#actionsQueue;
            this.#actionsQueue = [];
            const tenantSettings = {};
            for(const { tenantId, action } of actionQueue) {
                if(!tenantSettings[tenantId]) {
                    tenantSettings[tenantId] = {};
                }
                if(action === 'challenge-approve') {
                    tenantSettings[tenantId]["CurrentStep"] = 'increase';
                }
                else if(action === 'challenge-approve-all') {
                    tenantSettings[tenantId]["CurrentStep"] = 'last';
                }
                else if(action === 'challenge-revert') {
                    tenantSettings[tenantId]["CurrentStep"] = 'decrease';
                }
                else if(action === 'challenge-reset') {
                    tenantSettings[tenantId]["CurrentStep"] = 'first';
                }
                else if(action === 'timer-start') {
                    tenantSettings[tenantId]["Stopwatch"] = 'start';
                }
                else if(action === 'timer-stop') {
                    tenantSettings[tenantId]["Stopwatch"] = 'stop';
                }
                else if(action === 'timer-reset') {
                    tenantSettings[tenantId]["Stopwatch"] = 'reset';
                }
            }
            // check for empty tenant settings and remove them
            const tentantKeys = Object.keys(tenantSettings);
            for(const k of tentantKeys) {
                if(Object.keys(tenantSettings[k]).length === 0) {
                    delete tenantSettings[k];
                }
            }
            // empty object?
            if(Object.keys(tenantSettings).length === 0) {
                console.log("No Tenant Settings to update");
                return;
            }
            
            var data = await fetch("/api/set/tenants/settings", {
                method: "POST",
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(tenantSettings)
            })
            .then(response => response.json());
            if(data.success) {
                console.log("Updated Tenant Settings:", tenantSettings);
                console.log("Response Data:", data);
                for(const [tenantId, action] of Object.entries(data.tenants)) {
                    for(const [key, value] of Object.entries(action)) {
                        this.#tenantSettings[tenantId][key] = value;
                    }
                    this.#render();
                }
                this.refresh();
            }
            else {
                console.error("Failed to update Tenant Settings", tenantSettings, data);
            }
        }
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
}

window.techmgmt= new TechleadManagement();
window.techmgmt.setPeriodicRefresh(180);
