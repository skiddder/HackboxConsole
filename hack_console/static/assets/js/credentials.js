import { Clicker } from './clicker.js';
import { ToolTip } from './tooltip.js';

// one off loader
(async function() {
    // tooltip variables
    let tooltip = new ToolTip(1200);

    let creds = await fetch('/api/show/credentials').then(response => response.json());
    const rootEl = document.getElementById('credentials');
    rootEl.innerHTML = '';

    let newDict = {};
    for (let i in creds) {
        let g = creds[i].group;
        if(!(g in newDict)) {
            newDict[g] = [];
        }
        newDict[g].push(creds[i]);
    }

    // iterate over dict
    for (let key in newDict) {
        let title = document.createElement('h2');
        title.innerText = "Credential Group " + String(key);
        rootEl.appendChild(title);

        let tblEl = document.createElement('table');
        let trHeader = document.createElement('tr');
        let th1 = document.createElement('th');
        th1.innerText = 'Name';
        trHeader.appendChild(th1);
        let th2 = document.createElement('th');
        th2.innerText = 'Credential';
        trHeader.appendChild(th2);
        tblEl.appendChild(trHeader);
        newDict[key].forEach(cred => {
            let tr = document.createElement('tr');
            
            let td1 = document.createElement('td');
            td1.innerText = cred.name;
            td1.classList.add('name');
            tr.appendChild(td1);

            let td2 = document.createElement('td');
            td2.dataset.Credential = cred.Credential;
            td2.classList.add('hidden');
            td2.classList.add('credential');
            td2.innerText = '••••••••' + '•'.repeat(Math.max(cred.Credential.length - 8, 0));
            td2.title = 'Double click to copy credential.';
            if(cred.note) {
                const noteStr = String(cred.note).trim();
                td2.title += " (Note: " + noteStr + ")";
            }
            let clicker = new Clicker(td2);
            clicker.onSingleClick(function(event) {
                td2.classList.toggle('hidden');
                if (td2.classList.contains('hidden')) {
                    td2.innerText = '••••••••' + '•'.repeat(Math.max(cred.Credential.length - 8, 0));
                }
                else {
                    td2.innerText = td2.dataset.Credential;
                }
            });
            // double click to copy
            clicker.onDoubleClick(function(event) {
                navigator.clipboard.writeText(td2.dataset.Credential);
                tooltip.show('📑 Copied!', 1200, event);
                tooltip.onHideOnce(() => {
                    // hid credential
                    if(!td2.classList.contains('hidden')) {
                        td2.classList.add('hidden');
                        td2.innerText = '••••••••' + '•'.repeat(Math.max(cred.Credential.length - 8, 0));
                    }
                });
            });
            tr.appendChild(td2);

            tblEl.appendChild(tr);
        });
        rootEl.appendChild(tblEl);
    }

})();