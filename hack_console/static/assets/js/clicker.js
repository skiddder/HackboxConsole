export class Clicker {
    #element = null;
    #clickNum = 0;
    #singleClickDelay = 250;
    #singleClickTimer = null;
    #singleClickCallbacks = [];
    #doubleClickCallbacks = [];

    constructor(element, singleClickDelay=250) {
        this.#element = element;
        if(singleClickDelay >= 100 && singleClickDelay <= 600) {
            this.#singleClickDelay = singleClickDelay;
        }
        // add bindings
        this.#element.addEventListener('click', this.#handleSingleClick.bind(this));
    }
    onSingleClick(callback) {
        this.#singleClickCallbacks.push(callback);
    }
    offSingleClick(callback) {
        this.#singleClickCallbacks = this.#singleClickCallbacks.filter(cb => cb !== callback);
    }
    onDoubleClick(callback) {
        this.#doubleClickCallbacks.push(callback);
    }
    offDoubleClick(callback) {
        this.#doubleClickCallbacks = this.#doubleClickCallbacks.filter(cb => cb !== callback);
    }

    #handleSingleClick(event) {
        // intentionally not using event.detail, as we need a different counting/reset mechanism
        this.#clickNum ++;
        if(this.#clickNum == 1) {
            // set a timer to wait for a double click
            this.#singleClickTimer = setTimeout(() => {
                this.#clickNum = 0;
                this.#singleClickTimer = null;
                // call all single click callbacks
                this.#singleClickCallbacks.forEach(callback => {
                    callback(event);
                });

            }, this.#singleClickDelay);
        }
        else if(this.#clickNum == 2) {
            this.#clickNum = 0;
            if(this.#singleClickTimer) {
                clearTimeout(this.#singleClickTimer);
                this.#singleClickTimer = null;
            }
            // call all double click callbacks
            this.#doubleClickCallbacks.forEach(callback => {
                callback(event);
            });
        }
    }
}
