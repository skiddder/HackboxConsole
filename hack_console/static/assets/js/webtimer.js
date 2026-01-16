class StopWatch {
    #timerInfo = {
        startTime: null,
        status: "stopped",
        secondsElapsed: 0
    };
    #challengeCompletionTimes = [];
    #renderInterval = null;
    #refreshSeconds = 0;
    #refreshTimeout = null;
    constructor() {
        if(document.getElementById("timer-start")) {
            document.getElementById("timer-start").style.display = "none";
            document.getElementById("timer-start").addEventListener("click", this.startTimer.bind(this));
        }
        if(document.getElementById("timer-stop")) {
            document.getElementById("timer-stop").style.display = "none";
            document.getElementById("timer-stop").addEventListener("click", this.stopTimer.bind(this));
        }
        if(document.getElementById("timer-reset")) {
            document.getElementById("timer-reset").addEventListener("click", this.resetTimer.bind(this));
        }

        this.refresh();
    }

    #unsetRenderInterval() {
        if(this.#renderInterval !== null) {
            clearInterval(this.#renderInterval);
            this.#renderInterval = null;
        }
    }
    #setRenderInterval() {
        if(this.#renderInterval === null) {
            this.#renderInterval = setInterval(this.#render.bind(this), 1000);
        }
    }

    async startTimer() {
        if(this.#timerInfo.status !== "running") {
            console.log("Starting Timer");
            await this.#setTimerInfo({
                "status": "running",
                "startTime": this.#timerInfo  && this.#timerInfo.secondsElapsed ? (new Date((new Date()) - (this.#timerInfo.secondsElapsed * 1000))) : new Date(),
                "secondsElapsed": this.#timerInfo  && this.#timerInfo.secondsElapsed ? this.#timerInfo.secondsElapsed : 0
            });
            this.#render();
        }
    }

    async stopTimer() {
        if(this.#timerInfo.status !== "stopped") {
            console.log("Stopping Timer");
            await this.#setTimerInfo({
                "status": "stopped",
                "startTime": this.#timerInfo  && this.#timerInfo.startTime !== null ? this.#timerInfo.startTime : null,
                "secondsElapsed": this.#timerInfo && this.#timerInfo.startTime !== null ? parseInt(Math.ceil(((new Date()).getTime() - this.#timerInfo.startTime.getTime()) / 1000)) : 0
            });
            this.#render();
        }
    }

    async resetTimer() {
        console.log("Resetting Timer");
        await this.#setTimerInfo({
            "status": "stopped",
            "startTime": null,
            "secondsElapsed": 0
        });
        this.#render();
    }


    async refresh() {
        console.log("Refreshing");
        try{
            this.#timerInfo = await this.getTimerInfo();
            this.#render();
            this.#challengeCompletionTimes = await this.getChallengeCompletionTimes();
            this.#renderCompletionTimes();
        }
        finally {
            this.#setRefreshTimer();
        }
    }

    #renderCompletionTimes() {
        if(document.getElementById("challenge-completion-times-table")) {
            let tblEl = document.getElementById("challenge-completion-times-table");
            tblEl.innerHTML = "";
            let trHeader = document.createElement('tr');
            let th1 = document.createElement('th');
            th1.innerText = 'Challenge';
            trHeader.appendChild(th1);
            let th2 = document.createElement('th');
            th2.innerText = 'Elapsed Time';
            trHeader.appendChild(th2);
            tblEl.appendChild(trHeader);
            this.#challengeCompletionTimes.forEach((time, index) => {
                let tr = document.createElement('tr');
                let td1 = document.createElement('td');
                td1.innerText = `Challenge ${index + 1}`;
                tr.appendChild(td1);
                let td2 = document.createElement('td');
                // render in hh:mm:ss
                let hours = Math.floor(time / 3600);
                let minutes = Math.floor((time % 3600) / 60);
                let seconds = parseInt(time % 60);
                td2.innerText = (hours < 10 ? "0" + hours : hours) + ":" +
                                (minutes < 10 ? "0" + minutes : minutes) + ":" +
                                (seconds < 10 ? "0" + seconds : seconds);
                tr.appendChild(td2);
                tblEl.appendChild(tr);
            });
        }
    }

    #render() {
        let seconds = 0;
        let minutes = 0;
        let hours = 0;
        if(this.#timerInfo.status === "running") {
            if(document.getElementById("timer-start")) {
                document.getElementById("timer-start").style.display = "none";
            }
            if(document.getElementById("timer-stop")) {
                document.getElementById("timer-stop").style.display = "block";
            }
            this.#setRenderInterval();
            if(document.getElementById("timer-status")) {
                document.getElementById("timer-status").innerText = "Running";
            }
            // calculate elapsed time
            if(this.#timerInfo.startTime !== null) {
                let diff = (new Date()) - this.#timerInfo.startTime;
                // render elapsed time hh:mm:ss
                seconds = Math.floor(diff / 1000) % 60;
                minutes = Math.floor(diff / (1000 * 60)) % 60;
                hours = Math.floor(diff / (1000 * 60 * 60)) % 24;
            }

        }
        else if(this.#timerInfo.status === "stopped") {
            if(document.getElementById("timer-start")) {
                document.getElementById("timer-start").style.display = "block";
            }
            if(document.getElementById("timer-stop")) {
                document.getElementById("timer-stop").style.display = "none";
            }
            this.#unsetRenderInterval();
            if(document.getElementById("timer-status")) {
                document.getElementById("timer-status").innerText = "Stopped";
            }

            seconds = this.#timerInfo.secondsElapsed % 60;
            minutes = Math.floor(this.#timerInfo.secondsElapsed / 60) % 60;
            hours = Math.floor(this.#timerInfo.secondsElapsed / (60 * 60)) % 24;
        }

        // more specific elements?
        let hel = document.getElementById("timer-time-hours");
        let mil = document.getElementById("timer-time-minutes");
        let sel = document.getElementById("timer-time-seconds");
        if(hel && mil && sel) {
            hel.innerText = hours < 10 ? "0" + hours : hours;
            mil.innerText = minutes < 10 ? "0" + minutes : minutes;
            sel.innerText = seconds < 10 ? "0" + seconds : seconds;
        }
        else {
            let timeString = (hours < 10 ? "0" + hours : hours) + ":" +
                            (minutes < 10 ? "0" + minutes : minutes) + ":" +
                            (seconds < 10 ? "0" + seconds : seconds);
            document.getElementById("timer-time").innerText = timeString;
        }
    }

    async getChallengeCompletionTimes() {
        let data = await fetch("/api/get/statistics/challenge-completion-times")
            .then(response => response.json());
        if(data.challengeTimes && typeof data.challengeTimes === "object") {
            // sort by key
            let completionTimes = [];
            Object.keys(data.challengeTimes).sort().forEach(function(key) {
                if(key.toLowerCase().startsWith("challenge")) {
                    completionTimes.push(data.challengeTimes[key]);
                }
            });
            console.log("Challenge Completion Times", completionTimes);
            return completionTimes;
        }
        throw "Invalid Challenge Completion Times";
    }

    async getTimerInfo() {
        let data = await fetch("/api/get/stopwatch")
            .then(response => response.json());
        console.log("Current Timer Info", data);
        if(data.status && (data.status === "running" || data.status === "stopped")) {
            if(data.startTime) {
                data.startTime = new Date(data.startTime);
            }
            return {
                status: data.status,
                startTime: data.startTime ? data.startTime : null,
                secondsElapsed: data.secondsElapsed ? parseInt(data.secondsElapsed) : 0
            }
        }
        throw "Invalid Timer Info";
    }

    async #setTimerInfo(info) {
        let data = await fetch("/api/set/stopwatch", {
            method: "POST",
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                "status": info.status,
                "startTime": info.startTime === null ? null : info.startTime.toISOString(),
                "secondsElapsed": info.secondsElapsed ? parseInt(info.secondsElapsed) : 0
            })
        })
        .then(response => response.json());
        console.log("Set Timer Info", data);
        if(data.status && (data.status === "running" || data.status === "stopped")) {
            data = {
                status: data.status,
                startTime: new Date(data.startTime),
                secondsElapsed: data.secondsElapsed ? parseInt(data.secondsElapsed) : 0
            };
        }
        else {
            throw "Invalid Timer Info";
        }
        this.#timerInfo = info;
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


window.webStopWatch = new StopWatch();
window.webStopWatch.setPeriodicRefresh(10);
