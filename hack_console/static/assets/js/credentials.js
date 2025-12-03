
// one off loader
(async function() {
    var creds = await fetch('/api/show/credentials').then(response => response.json());
    const rootEl = document.getElementById('credentials');
    rootEl.innerHTML = '';

    var newDict = {};
    for (var i in creds) {
        var g = creds[i].group;
        if(!(g in newDict)) {
            newDict[g] = [];
        }
        newDict[g].push(creds[i]);
    }

    // iterate over dict
    for (var key in newDict) {
        var title = document.createElement('h2');
        title.innerText = "Credential Group " + String(key);
        rootEl.appendChild(title);

        var tblEl = document.createElement('table');
        var trHeader = document.createElement('tr');
        var th1 = document.createElement('th');
        th1.innerText = 'Name';
        trHeader.appendChild(th1);
        var th2 = document.createElement('th');
        th2.innerText = 'Credential';
        trHeader.appendChild(th2);
        tblEl.appendChild(trHeader);
        newDict[key].forEach(cred => {
            var tr = document.createElement('tr');
            
            var td1 = document.createElement('td');
            td1.innerText = cred.name;
            td1.classList.add('name');
            tr.appendChild(td1);

            var td2 = document.createElement('td');
            td2.dataset.Credential = cred.Credential;
            td2.classList.add('hidden');
            td2.classList.add('credential');
            td2.innerText = '••••••••' + '•'.repeat(Math.max(cred.Credential.length - 8, 0));
            td2.title = 'Double click to copy credential.';
            if(cred.note) {
                const noteStr = String(cred.note).trim();
                td2.title += " (Note: " + noteStr + ")";
            }
            td2.addEventListener('click', function(event) {
                this.classList.toggle('hidden');
                if (this.classList.contains('hidden')) {
                    this.innerText = '••••••••' + '•'.repeat(Math.max(cred.Credential.length - 8, 0));
                }
                else {
                    this.innerText = this.dataset.Credential;
                }
            });
            var tooltip=null;
            var tooltipTimeout=null;
            // double click to copy
            td2.addEventListener('dblclick', function(event) {
                if(tooltipTimeout) {
                    clearTimeout(tooltipTimeout);
                    tooltipTimeout = null;
                }
                if(tooltip) {
                    tooltip.remove();
                    tooltip = null;
                }
                navigator.clipboard.writeText(this.dataset.Credential);
                // add fading tooltip
                tooltip = document.createElement('div');
                tooltip.classList.add('credentialtooltip');
                tooltip.innerText = '📑 Copied!';
                document.body.appendChild(tooltip);

                // add to mouse position
                tooltip.style.position = 'absolute';
                tooltip.style.left = (event.pageX + 10) + 'px';
                tooltip.style.top = (event.pageY + 10) + 'px';
                // and ensure it is not off screen
                const tooltipRect = tooltip.getBoundingClientRect();
                if(tooltipRect.right > window.innerWidth) {
                    tooltip.style.left = (window.innerWidth - tooltipRect.width - 10) + 'px';
                }
                if(tooltipRect.bottom > window.innerHeight) {
                    tooltip.style.top = (window.innerHeight - tooltipRect.height - 10) + 'px';
                }
                tooltipTimeout = setTimeout(() => {
                    tooltip.remove();
                    // hide credential
                    if(!this.classList.contains('hidden')) {
                        this.classList.add('hidden');
                        this.innerText = '••••••••' + '•'.repeat(Math.max(cred.Credential.length - 8, 0));
                    }
                    tooltip = null;
                    tooltipTimeout = null;
                }, 1200);
            });
            tr.appendChild(td2);

            tblEl.appendChild(tr);
        });
        rootEl.appendChild(tblEl);
    }

})();