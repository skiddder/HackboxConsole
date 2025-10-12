window.progressbars.addProgressBarUpdateListener(
    (el, minval, maxval, nowval, percent) => {
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