import { ProgressBarManager } from "./progressbarmanager.js";

window.progressbars = new ProgressBarManager('.progress-bar');
window.progressbars.setPeriodicRefresh(10);
window.progressbars.addProgressBarUpdateListener(
    (el, minval, maxval, nowval, percent) => {
        console.log(`Progress bar updated: ${el.id} - ${percent}%`);
        if(document.getElementById("celebration")) {
            if (percent === 100) {
                document.getElementById("celebration").style.display = "block";
            }
            else {
                document.getElementById("celebration").style.display = "none";
            }
        }
    }
);
window.progressbars.addProgressBarUpdateListener((el) => {
    console.log("Updated progress bar:", el.id);
});