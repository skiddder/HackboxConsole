
export class ToolTip {
    #tooltip=null;
    #tooltipTimeout=null;
    #defaultTimeoutMs=1200;
    #hideCallbacks=[];
    #cacheMousePosition=false;
    #followMouse=true;
    #lastMouseEvent=null;

    constructor(defaultTimeoutMs = 1200, cacheMousePosition = false, followMouse = false) {
        this.#defaultTimeoutMs = defaultTimeoutMs;
        this.#cacheMousePosition = cacheMousePosition;
        this.#followMouse = followMouse;
        if(this.#followMouse) {
            this.#cacheMousePosition = true;
        }
        if(this.#cacheMousePosition) {
            window.addEventListener('mousemove', (event) => {
                this.#lastMouseEvent = event;
                if(this.#followMouse && this.#tooltip) {
                    this.#positionTooltip(event);
                }
            });
        }
    }

    #positionTooltip(event) {
        if(!this.#tooltip) {
            return;
        }
        this.#tooltip.style.position = 'absolute';

        this.#tooltip.style.left = (event.pageX + 10) + 'px';
        this.#tooltip.style.top = (event.pageY + 10) + 'px';
        // and ensure it is not off screen
        const tooltipRect = this.#tooltip.getBoundingClientRect();
        if(tooltipRect.right > window.innerWidth) {
            this.#tooltip.style.left = (window.innerWidth - tooltipRect.width - 10) + 'px';
        }
        if(tooltipRect.bottom > window.innerHeight) {
            this.#tooltip.style.top = (window.innerHeight - tooltipRect.height - 10) + 'px';
        }
        if(tooltipRect.left < 0) {
            this.#tooltip.style.left = (tooltipRect.width + 10) + 'px';
        }
        if(tooltipRect.top < 0) {
            this.#tooltip.style.top = (tooltipRect.height + 10) + 'px';
        }
    }

    show(message, timeoutMs = null, event = null) {
        if (this.#tooltipTimeout) {
            clearTimeout(this.#tooltipTimeout);
            this.#tooltipTimeout = null;
        }
        if(this.#tooltip) {
            this.#tooltip.remove();
            this.#tooltip = null;
        }

        if(this.#followMouse) {
            if(event !== undefined && event !== null && event.pageX && event.pageY) {
                console.warn("Follow mouse is enabled, ignoring provided event for tooltip positioning.");
            }
            event = this.#lastMouseEvent;
        }
        else if(event === undefined || event === null || !event.pageX || !event.pageY) {
            if (this.#cacheMousePosition && this.#lastMouseEvent) {
                event = this.#lastMouseEvent;
            }
            else {
                console.warn("No mouse event provided for tooltip and no cached position available. Using center of screen.");
                // get the position of the mouse
                event = {
                    pageX: window.innerWidth / 2,
                    pageY: window.innerHeight / 2
                };
            }
        }


        // is timeout an integer?
        if (!Number.isInteger(timeoutMs)) {
            timeoutMs = this.#defaultTimeoutMs;
        }
        // is timeout between 100 and 100000?
        if (timeoutMs < 100 || timeoutMs > 100000) {
            timeoutMs = this.#defaultTimeoutMs;
        }

        // add fading tooltip
        this.#tooltip = document.createElement('div');
        this.#tooltip.classList.add('tooltip');
        this.#tooltip.innerText = message ? message : '📑 Copied!';
        document.body.appendChild(this.#tooltip);

        this.#positionTooltip(event);

        // set timeout to hide
        this.#tooltipTimeout = setTimeout(this.hide.bind(this), timeoutMs);
    }

    onHideOnce(callback) {
        if (typeof callback === 'function') {
            this.#hideCallbacks.push(callback);
        }
    }

    hide() {
        if (this.#tooltipTimeout) {
            clearTimeout(this.#tooltipTimeout);
            this.#tooltipTimeout = null;
        }
        if(this.#tooltip) {
            this.#tooltip.remove();
            this.#tooltip = null;
        }
        // pop all callbacks
        while(this.#hideCallbacks.length > 0) {
            let callback = this.#hideCallbacks.shift();
            callback();
        }
    }
}


let instance = null;
export function getToolTip() {
    if (!instance) {
        instance = new ToolTip(1200, true, true);
    }
    return instance;
}
