class ProgressBarManager {
    #challenges = [];
    #currentStep = null;
    #currentChallenge = null;
    #progressBarElements = [];
    #refreshSeconds = 0;
    #refreshTimeout = null;
    #progressBarUpdateListeners = [];
    constructor(progressBarCssSelector) {
        this.#progressBarElements = document.querySelectorAll(progressBarCssSelector);
        this.#progressBarElements.forEach(el => {
            if(!el.hasAttribute('aria-valuemin')) {
                el.setAttribute('aria-valuemin', '0');
            }
            var minval = parseInt(el.getAttribute('aria-valuemin'));
            if(isNaN(minval) || minval < 0) {
                el.setAttribute('aria-valuemin', '0');
            }
            else {
                el.setAttribute('aria-valuemin', String(minval));
            }
            if(!el.hasAttribute('aria-valuemax')) {
                el.setAttribute('aria-valuemax', String(minval + 100));
            }
            else {
                var maxval = parseInt(el.getAttribute('aria-valuemax'));
                if(isNaN(maxval) || maxval <= minval) {
                    el.setAttribute('aria-valuemax', String(minval + 100));
                }
            }
            el.setAttribute('aria-valuenow', el.getAttribute('aria-valuemin'));
            try {
                el.querySelector('.progress-fill').style.width = '0%';
            }
            catch {}
        });

        this.refresh();
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
                    }
                    this.#currentStep = currentStep;
                    if(this.#currentChallenge === null) {
                        this.#currentChallenge = this.#currentStep;
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

    #render() {
        console.log("Rendering progress bar", this.#currentStep, this.#challenges);
        this.#progressBarElements.forEach(el => {
            console.log("Rendering element", el);
            try {
                el.setAttribute('aria-valuenow', String(Math.max(this.#currentStep - 1, 0)));
                if(this.#currentStep <= this.#challenges.length) {
                    el.setAttribute('aria-tooltip', `Working on challenge ${this.#currentStep} out of ${this.#challenges.length} challenges`);
                    el.setAttribute('title', `Working on challenge ${this.#currentStep} out of ${this.#challenges.length} challenges`);
                }
                else {
                    el.setAttribute('aria-tooltip', `All challenges completed!`);
                    el.setAttribute('title', `All challenges completed!`);
                }
                el.setAttribute('aria-valuemin', '0');
                el.setAttribute('aria-valuemax', String(this.#challenges.length));
                var nowval = parseInt(el.getAttribute('aria-valuenow'));
                var minval = parseInt(el.getAttribute('aria-valuemin'));
                var maxval = parseInt(el.getAttribute('aria-valuemax'));
                var percent = Math.round(((nowval - minval) / (maxval - minval)) * 100);
                if(percent < 0) {
                    percent = 0;
                }
                if(percent > 100) {
                    percent = 100;
                }
                el.querySelector('.progress-fill').style.width = percent + '%';
            }
            catch {}
            finally {
                this.#progressBarUpdateListeners.forEach(l => {
                    try {
                        l(el, minval, maxval, nowval, percent);
                    }
                    catch {}
                });
            }
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

    addProgressBarUpdateListener(listener) {
        if(typeof listener === 'function') {
            this.#progressBarUpdateListeners.push(listener);
        }
    }
}


window.progressbars = new ProgressBarManager('.progress-bar');
window.progressbars.setPeriodicRefresh(10);
