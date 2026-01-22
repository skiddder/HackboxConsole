import datetime
import json, os
import traceback
from flask import Flask, render_template, request, jsonify, redirect, url_for, send_from_directory
from . import app, all_users, all_tenants, HackBoxUser
from flask_login import login_user, login_required, logout_user, current_user
from azure.data.tables import TableServiceClient
from azure.core.exceptions import ResourceExistsError, ResourceNotFoundError
from typing import Union, Dict, Tuple
import natsort

# get the directory of this file
challenges_dir = os.path.join(os.path.dirname(os.path.realpath(__file__)), "challenges")
solutions_dir = os.path.join(os.path.dirname(os.path.realpath(__file__)), "solutions")

def recursive_list_md_files(directory: str, contains_str: str = "") -> list:
    files = []
    for root, _, filenames in os.walk(directory):
        for filename in filenames:
            if filename.endswith(".md"):
                if contains_str == "" or contains_str in filename.lower():
                    f = os.path.join(root, filename)
                    if f.startswith(directory):
                        f = f[len(directory):]
                        if f.startswith("/"):
                            f = f[1:]
                    files.append(f)
    return natsort.natsorted(files)


challenges_mds = recursive_list_md_files(challenges_dir, "challenge")
solutions_mds = recursive_list_md_files(solutions_dir, "solution")


class HackBoxCredentials:
    _tsc = None
    _tc  = None
    _tenantName = "Default"

    def __init__(self, tenantName : str = "Default"):
        self._tsc = TableServiceClient.from_connection_string(conn_str=os.getenv("HACKBOX_CONNECTION_STRING"))
        self._tc = self._tsc.get_table_client("credentials")
        self._tenantName = str(tenantName).strip()
        if self._tenantName == "":
            self._tenantName = "Default"

    def sanitizeName(self, key: str) -> str:
        return "".join([c for c in key if c.isalnum() or c == "_" or c == "-" or c == " "]).strip()

    def sanitizeGroup(self, group: str) -> str:
        return "".join([c for c in group if c.isalnum() or c == "_" or c == "-"]).strip()

    def add(self, name: str, credential: str, group: str = "Default") -> None:
        name = self.sanitizeName(name)
        group = self.sanitizeGroup(group)
        self._tc.upsert_entity(mode="replace", entity={"PartitionKey": self._tenantName, "RowKey": group + "|" + name, "group": group, "name": name, "Credential": credential})
        return self
    def get(self, name: str, group: str = "Default") -> Union[Dict[str, str], None]:
        name = self.sanitizeName(name)
        group = self.sanitizeGroup(group)
        try:
            entity = self._tc.get_entity(row_key=group + "|" + name, partition_key=self._tenantName)
            del entity["PartitionKey"]
            del entity["RowKey"]
            return entity
        except ResourceNotFoundError:
            return None
    def getGroup(self, group : str = "Default") -> Dict[str, Dict[str, str]]:
        group = self.sanitizeGroup(group)
        
        entities = {}
        for entity in self._tc.query_entities(query_filter=f"PartitionKey eq '{self._tenantName}' and group eq '{group}'"):
            del entity["PartitionKey"]
            del entity["RowKey"]
            entities[entity["name"]] = entity
        return entities
    def getAll(self) -> Dict[str, Dict[str, str]]:
        entities = []
        for entity in self._tc.query_entities(query_filter=f"PartitionKey eq '{self._tenantName}'"):
            del entity["PartitionKey"]
            del entity["RowKey"]
            entities.append(entity)
        return entities

class HackBoxSettings:
    _tsc = None
    _tc  = None
    _tenantName = "Default"

    def __init__(self, tenantName : str = "Default"):
        self._tsc = TableServiceClient.from_connection_string(conn_str=os.getenv("HACKBOX_CONNECTION_STRING"))
        self._tc = self._tsc.get_table_client("settings")
        self._tenantName = str(tenantName).strip()
        self._tenantName = "".join([c for c in self._tenantName if c.isalnum() or c == "_" or c == "-" ]).strip()
        if self._tenantName == "":
            self._tenantName = "Default"
    
    def getAllDefaultTenantSettings(self) -> Dict[str, Union[str, int, bool]]:
        entities = self.getAllTenantSettings("Default")
        for tenant in entities:
            if "Stopwatch" in entities[tenant]:
                entities[tenant]["Stopwatch"] = self._validateStopwatch(entities[tenant]["Stopwatch"])
            else:
                entities[tenant]["Stopwatch"] = self._validateStopwatch(None)
            if "CurrentStep" in entities[tenant]:
                entities[tenant]["CurrentStep"] = self._validateStep(entities[tenant]["CurrentStep"])
            else:
                entities[tenant]["CurrentStep"] = self._validateStep(None)
        return entities
    def getAllTenantSettings(self, group : str = "Default") -> Dict[str, Dict[str, Union[str, int, bool]]]:
        group = self.sanitizeGroup(group)
        entities = {}
        for tenant in all_tenants:
            entities[tenant] = {
            }
        for entity in self._tc.query_entities(query_filter=f"group eq '{group}'"):
            tenant = entity["PartitionKey"]
            if tenant not in entities:
                continue
            del entity["PartitionKey"]
            del entity["RowKey"]
            entities[tenant][entity["key"]] = entity
        return entities

    def sanitizeKey(self, key: str) -> str:
        return "".join([c for c in key if c.isalnum() or c == "_" or c == "-" or c == " "]).strip()
    
    def sanitizeGroup(self, group: str) -> str:
        return "".join([c for c in group if c.isalnum() or c == "_" or c == "-"]).strip()

    def setPropagatedStep(self, step: Union[int, str]) -> None:
        reset_triggered = False
        previous_step = self.getStep()
        if isinstance(step, str):
            if str(step).lower().strip() == "decrease":
                step = previous_step - 1
            elif str(step).lower().strip() == "increase":
                step = previous_step + 1
            elif str(step).lower().strip() == "first":
                step = 1
                reset_triggered = True
            elif str(step).lower().strip() == "last":
                step = len(challenges_mds) + 1
        step = int(step)
        self.setStep(step)
        # log challenge time for previous step
        try:
            if reset_triggered:
                self.set("ChallengeCompletionSeconds", {}, group="Statistics")
            elif previous_step <= len(challenges_mds):
                if step > previous_step:
                    # log the challenge time
                    status, startTime, secondsElapsed = self.getStopwatch()
                    if status == "running" and startTime is not None:
                        # calculate elapsed time
                        secondsElapsed = (datetime.datetime.now(datetime.timezone.utc) - startTime).total_seconds()
                        challengeTimes = self.get("ChallengeCompletionSeconds", group="Statistics")
                        if challengeTimes is None:
                            challengeTimes = {}
                        challengeTimes[f"Challenge{previous_step:03d}"] = float(secondsElapsed)
                        self.set("ChallengeCompletionSeconds", challengeTimes, group="Statistics")
                        print(f"Logged challenge time for challenge {previous_step:d} for tenant {self._tenantName}: {secondsElapsed} seconds")
                else:
                    challengeTimes = self.get("ChallengeCompletionSeconds", group="Statistics")
                    if f"Challenge{previous_step:03d}" in challengeTimes:
                        del challengeTimes[f"Challenge{previous_step:03d}"]
                        self.set("ChallengeCompletionSeconds", challengeTimes, group="Statistics")
                        print(f"Removed challenge time for challenge {previous_step:d} for tenant {self._tenantName} due to step decrease")

        except Exception as e:
            print("Could not log challenge time", e)
            traceback.print_exc()
        # reset stopwatch
        try:
            if step > len(challenges_mds):
                self.setStopwatch("stopped", None, 0)
            else:
                self.setStopwatch("running", datetime.datetime.now(datetime.timezone.utc), 0)
        except Exception as e:
            print("Could not reset stopwatch:", e)
            pass
        
    def setStep(self, step: int) -> None:    
        if step < 1 or step > len(challenges_mds) + 1:
            raise ValueError("Step cannot be less than 1")
        self.set("CurrentStep", {"Step": step})
    def _validateStep(self, step: Union[Dict[str, Union[str, int, bool]], None]) -> int:
        if step is None:
            return 1
        if "Step" not in step:
            return 1
        return step["Step"]
    def getStep(self) -> int:
        return self._validateStep(self.get("CurrentStep"))

    def setStopwatch(self, status : str, startTime : Union[datetime.datetime, str, None], secondsElapsed: int) -> None:
        if status not in ["running", "stopped"]:
            raise ValueError("status must be 'running' or 'stopped'")
        if startTime is None:
            startTime = ""
        elif isinstance(startTime, datetime.datetime):
            startTime = startTime.isoformat()
        elif isinstance(startTime, str):
            try:
                startTime = datetime.datetime.fromisoformat(startTime).isoformat()
            except Exception:
                raise ValueError("startTime must be a datetime object or an ISO 8601 string")
        else:
            raise ValueError("startTime must be a datetime object or an ISO 8601 string")
        if secondsElapsed < 0:
            secondsElapsed = 0
        else:
            secondsElapsed = int(secondsElapsed)
        self.set("Stopwatch", {"status": status, "startTime": startTime, "secondsElapsed": secondsElapsed})
        return self

    def _validateStopwatch(self, ti: Union[Dict[str, Union[str, int, bool]], None]) -> Tuple[str, Union[datetime.datetime, None], int]:
        status = "stopped"
        startTime = None
        secondsElapsed = 0
        if ti is None:
            return status, startTime, secondsElapsed
        if "status" in ti:
            status = ti["status"]
        if "startTime" in ti:
            startTime = ti["startTime"]
        if "secondsElapsed" in ti:
            secondsElapsed = ti["secondsElapsed"]
        if startTime is not None:
            if startTime == "":
                startTime = None
            else:
                try:
                    startTime = datetime.datetime.fromisoformat(startTime)
                except Exception:
                    startTime = None
        return status, startTime, secondsElapsed
    def getStopwatch(self) -> Tuple[str, Union[datetime.datetime, None], int]:
        return self._validateStopwatch(self.get("Stopwatch"))

    def set(self, key: str, value: Dict[str, Union[str, int, bool]], group : str = "Default") -> None:
        key = self.sanitizeKey(key)
        group = self.sanitizeGroup(group)
        value["key"] = key
        value["group"] = group
        self._tc.upsert_entity(mode="replace", entity={"PartitionKey": self._tenantName, "RowKey": group + "|" + key, **value})
        return self
    def get(self, key, group : str = "Default") -> Union[Dict[str, Union[str, int, bool]], None]:
        key = self.sanitizeKey(key)
        group = self.sanitizeGroup(group)
        try:
            entity = self._tc.get_entity(row_key=group + "|" + key, partition_key=self._tenantName)
            del entity["PartitionKey"]
            del entity["RowKey"]
            return entity
        except ResourceNotFoundError:
            return None
    def getGroup(self, group: str = "Default") -> Dict[str, Union[str, int, bool]]:
        group = self.sanitizeGroup(group)
        entities = {}
        for entity in self._tc.query_entities(query_filter=f"PartitionKey eq '{self._tenantName}' and group eq '{group}'"):
            del entity["PartitionKey"]
            del entity["RowKey"]
            entities[entity["key"]] = entity
        
        return entities




#region -------- WEB/UI ENDPOINTS --------
@app.route("/")
def home():
    # if the user is not logged in, redirect to the login page
    if not current_user.is_authenticated:
        return redirect(url_for("login"))
    if not isinstance(current_user, HackBoxUser):
        return redirect(url_for("login"))
    return render_template("index.html", user=current_user)

@app.route("/challenges")
def challenges():
    # if the user is not logged in, redirect to the login page
    if not current_user.is_authenticated:
        return redirect(url_for("login"))
    if not isinstance(current_user, HackBoxUser):
        return redirect(url_for("login"))
    return render_template("challenges.html", user=current_user)

@app.route("/solutions")
def solutions():
    if not current_user.is_authenticated:
        return redirect(url_for("login"))
    if not isinstance(current_user, HackBoxUser):
        logout_user()
        return redirect(url_for("login"))
    if current_user.role != "coach":
        return redirect(url_for("home"))
    return render_template("solutions.html", user=current_user)

@app.route("/credentials")
def credentials():
    if not current_user.is_authenticated:
        return redirect(url_for("login"))
    if not isinstance(current_user, HackBoxUser):
        logout_user()
        return redirect(url_for("login"))
    if current_user.role not in ["coach", "hacker"]:
        return redirect(url_for("home"))
    return render_template("credentials.html", user=current_user)

@app.route("/webtimer")
def webtimer():
    if not current_user.is_authenticated:
        return redirect(url_for("login"))
    if not isinstance(current_user, HackBoxUser):
        logout_user()
        return redirect(url_for("login"))
    if current_user.role not in ["coach", "hacker"]:
        return redirect(url_for("home"))
    return render_template("webtimer.html", user=current_user)

@app.route("/techlead")
def techlead():
    if not current_user.is_authenticated:
        return redirect(url_for("login"))
    if not isinstance(current_user, HackBoxUser):
        logout_user()
        return redirect(url_for("login"))
    if current_user.role not in ["techlead"]:
        return redirect(url_for("home"))
    return render_template("techlead.html", user=current_user)

@app.route("/logout")
def logout():
    logout_user()
    return redirect(url_for("login"))

@app.route("/login", methods=["GET", "POST"])
def login():
    # post request? process the login form
    if request.method == "POST":
        # user exists?
        username = str(request.form.get("username")).lower().strip()
        if username not in all_users:
            return render_template("login.html", message="User not found", user=current_user)
        user = all_users[username]
        # Check the username (again)
        if str(user.username).lower().strip() != username:
            return render_template("login.html", message="Invalid credentials", user=current_user)
        # Check the password
        if user.password == request.form.get("password"):
            # Use the login_user method to log in the user
            login_user(user)
            return redirect(url_for("home"))
        return render_template("login.html", message="Invalid credentials", user=current_user)
    return render_template("login.html", user=current_user)
#endregion -------- WEB/UI ENDPOINTS --------

#region -------- API ENDPOINTS --------

@login_required
@app.route("/api/get/challenge")
def api_get_challenge():
    if not isinstance(current_user, HackBoxUser):
        logout_user()
        return redirect(url_for("login"))
    try:
        hbSettings = HackBoxSettings(current_user.tenant)
        step = hbSettings.getStep()
        try:
            # when the hack begins, start the stopwatch for hackers automatically
            if step == 1 and current_user.role == "hacker":
                status, startTime, secondsElapsed = hbSettings.getStopwatch()
                if status != "running":
                    hbSettings.setStopwatch("running", datetime.datetime.now(datetime.timezone.utc), 0)
        except:
            pass
        return jsonify({"success": True, "challenge" : step })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@login_required
@app.route("/api/set/challenge", methods=["POST"])
def api_set_challenge():
    if not isinstance(current_user, HackBoxUser):
        logout_user()
        return redirect(url_for("login"))
    if current_user.role != "coach":
        return jsonify({"success": False, "error": "Unauthorized"}), 403
    try:
        data = request.get_json()
        if "challenge" not in data:
            return jsonify({"success": False, "error": "Missing challenge"}), 400
        hbSettings = HackBoxSettings(current_user.tenant)
        hbSettings.setPropagatedStep(data["challenge"])
        return jsonify({"success": True, "challenge" : hbSettings.getStep()})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@login_required
@app.route("/api/list/challenges")
def api_challenges():
    if not isinstance(current_user, HackBoxUser):
        logout_user()
        return redirect(url_for("login"))
    if current_user.role not in ["coach", "hacker"]:
        return jsonify({"error": "Unauthorized"}), 403
    return jsonify(challenges_mds)

@login_required
@app.route("/api/list/solutions")
def api_solutions():
    if not isinstance(current_user, HackBoxUser):
        logout_user()
        return redirect(url_for("login"))
    if current_user.role not in ["coach"]:
        return jsonify({"error": "Unauthorized"}), 403
    return jsonify(solutions_mds)

@login_required
@app.route("/api/show/credentials")
def api_credentials():
    if not isinstance(current_user, HackBoxUser):
        logout_user()
        return redirect(url_for("login"))
    if current_user.role not in ["coach", "hacker"]:
        return jsonify({"error": "Unauthorized"}), 403
    hbCredentials = HackBoxCredentials(current_user.tenant)
    return jsonify(hbCredentials.getAll())

@login_required
@app.route("/api/settings", defaults={'group': "Default"})
@app.route("/api/settings/<group>", defaults={'group': "Default"})
def api_config(group : str = 'Default'):
    if not isinstance(current_user, HackBoxUser):
        logout_user()
        return redirect(url_for("login"))
    hbSettings = HackBoxSettings(current_user.tenant)
    return jsonify(hbSettings.getGroup(group))

@login_required
@app.route("/api/get/stopwatch")
def api_get_stopwatch():
    if not isinstance(current_user, HackBoxUser):
        logout_user()
        return redirect(url_for("login"))
    try:
        hbSettings = HackBoxSettings(current_user.tenant)
        status, startTime, secondsElapsed = hbSettings.getStopwatch()
        if startTime is not None:
            startTime = startTime.isoformat()
        return jsonify({"success": True, "status" : status, "startTime": startTime, "secondsElapsed": secondsElapsed })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@login_required
@app.route("/api/set/stopwatch", methods=["POST"])
def api_set_stopwatch():
    if not isinstance(current_user, HackBoxUser):
        logout_user()
        return redirect(url_for("login"))
    if current_user.role != "coach":
        return jsonify({"success": False, "error": "Unauthorized"}), 403
    try:
        data = request.get_json()
        if "status" not in data:
            return jsonify({"success": False, "error": "Missing status"}), 400
        if "startTime" not in data:
            return jsonify({"success": False, "error": "Missing startTime"}), 400
        if "secondsElapsed" not in data:
            return jsonify({"success": False, "error": "Missing secondsElapsed"}), 400
        hbSettings = HackBoxSettings(current_user.tenant)
        hbSettings.setStopwatch(data["status"], data["startTime"], data["secondsElapsed"])
        status, startTime, secondsElapsed = hbSettings.getStopwatch()
        if startTime is not None:
            startTime = startTime.isoformat()
        return jsonify({"success": True, "status" : status, "startTime": startTime, "secondsElapsed": secondsElapsed})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@login_required
@app.route("/api/get/statistics/challenge-completion-times")
def api_get_statistics_challenge_completion_times():
    if not isinstance(current_user, HackBoxUser):
        logout_user()
        return redirect(url_for("login"))
    try:
        hbSettings = HackBoxSettings(current_user.tenant)
        challengeTimes = hbSettings.get("ChallengeCompletionSeconds", group="Statistics")
        if challengeTimes is None:
            challengeTimes = {}
        if "key" in challengeTimes:
            del challengeTimes["key"]
        if "group" in challengeTimes:
            del challengeTimes["group"]
        return jsonify({"success": True, "challengeTimes": challengeTimes})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@login_required
@app.route("/api/get/tenants/settings")
def api_get_tenants_settings():
    if not isinstance(current_user, HackBoxUser):
        logout_user()
        return redirect(url_for("login"))
    if current_user.role != "techlead":
        return jsonify({"success": False, "error": "Unauthorized"}), 403
    try:
        tenants_settings = {}
        max_steps = len(challenges_mds) + 1
        hbSettings = HackBoxSettings()
        tenants_settings = hbSettings.getAllDefaultTenantSettings()
        for tenant in tenants_settings:
            tenants_settings[tenant]["MaxStep"] = max_steps
            if "Stopwatch" in tenants_settings[tenant]:
                if tenants_settings[tenant]["Stopwatch"][1] is not None:
                    tenants_settings[tenant]["Stopwatch"] = (
                        tenants_settings[tenant]["Stopwatch"][0],
                        tenants_settings[tenant]["Stopwatch"][1].isoformat(),
                        tenants_settings[tenant]["Stopwatch"][2]
                    )
        return jsonify({"success": True, "tenants": tenants_settings})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500
    
@login_required
@app.route("/api/set/tenants/settings", methods=["POST"])
def api_set_tenants_settings():
    if not isinstance(current_user, HackBoxUser):
        logout_user()
        return redirect(url_for("login"))
    if current_user.role != "techlead":
        return jsonify({"success": False, "error": "Unauthorized"}), 403
    try:
        data = request.get_json()
        # data is a dict
        if not isinstance(data, dict):
            return jsonify({"success": False, "error": "Invalid data"}), 400
        for tenant in data:
            if tenant not in all_tenants:
                continue
            hbSettings = HackBoxSettings(tenant)
            if "CurrentStep" in data[tenant]:
                try:
                    hbSettings.setPropagatedStep(data[tenant]["CurrentStep"])
                except:
                    print(f"Could not set step for tenant {tenant}")
                data[tenant]["CurrentStep"] = hbSettings.getStep()
            if "Stopwatch" in data[tenant]:
                if isinstance(data[tenant]["Stopwatch"], list) and len(data[tenant]["Stopwatch"]) == 3:
                    hbSettings.setStopwatch(*data[tenant]["Stopwatch"])
                elif isinstance(data[tenant]["Stopwatch"], str):
                    data[tenant]["Stopwatch"] = data[tenant]["Stopwatch"].lower().strip()
                    if data[tenant]["Stopwatch"] == "reset":
                        hbSettings.setStopwatch("stopped", None, 0)
                    elif data[tenant]["Stopwatch"] == "stop":
                        status, startTime, secondsElapsed = hbSettings.getStopwatch()
                        if status == "running" and startTime is not None:
                            # calculate elapsed time
                            secondsElapsed += (datetime.datetime.now(datetime.timezone.utc) - startTime).total_seconds()
                            hbSettings.setStopwatch("stopped", None, int(secondsElapsed))
                    elif data[tenant]["Stopwatch"] == "start":
                        status, startTime, secondsElapsed = hbSettings.getStopwatch()
                        if status != "running":
                            hbSettings.setStopwatch("running", datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=secondsElapsed), 0)
                    elif data[tenant]["Stopwatch"] == "reset":
                        hbSettings.setStopwatch("stopped", None, 0)
                status, startTime, secondsElapsed = hbSettings.getStopwatch()
                if startTime is not None:
                    startTime = startTime.isoformat()
                data[tenant]["Stopwatch"] = (status, startTime, secondsElapsed)
        return jsonify({"success": True, "tenants": data})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/get/rdp-connection", methods=["GET"])
def api_get_rdp_connection():
    raw_rdp_endpoints = os.getenv("HACKBOX_RDP_WEBSOCKET_ENDPOINTS", "")
    endpoints = [ep.strip() for ep in raw_rdp_endpoints.split(",") if ep and ep.strip()]
    if len(endpoints) == 0:
        return jsonify({"endpoints": []}), 200
    if not isinstance(current_user, HackBoxUser):
        return jsonify({"endpoints": endpoints }), 200
    if current_user.role not in ["coach", "hacker"]:
        # todo retrieve rdp connections information for the current user
        rdpconnection = {
            "user": None,
            "pass": None,
            "host": None,
            "port": 3389
        }
        return jsonify({"endpoints": endpoints, "rdpconnection": rdpconnection}), 200
    return jsonify({"endpoints": endpoints})

#endregion -------- API ENDPOINTS --------

#region -------- STATIC ENDPOINTS --------
@login_required
@app.route('/md/solutions/<path:filename>')
def static_solutions(filename):
    if not isinstance(current_user, HackBoxUser):
        logout_user()
        return redirect(url_for("login"))
    if current_user.role == "coach":
        return send_from_directory(solutions_dir, filename)
    return redirect(url_for("login"))

@login_required
@app.route('/md/challenges/<path:filename>')
def static_challenges(filename):
    if not isinstance(current_user, HackBoxUser):
        logout_user()
        return redirect(url_for("login"))
    if current_user.role in ["coach", "hacker"]:
        # file name should be challenge*.md
        if filename.endswith(".md") and "challenge" in filename.split("/")[-1].lower():
            # is it in the list of challenges?
            if filename in challenges_mds:
                # get the position in the array
                idx = challenges_mds.index(filename) + 1
                # get the current challenge
                hbSettings = HackBoxSettings(current_user.tenant)
                current_challenge = hbSettings.getStep()
                # if the challenge is not available, return an error
                if idx > current_challenge:
                    return "# Challenge not yet available", 404, {"Content-Type": "text/markdown"}
        return send_from_directory(challenges_dir, filename)
    return redirect(url_for("login"))

@app.route('/favicon.ico')
def static_favicon():
    return send_from_directory(os.path.join(os.path.dirname(os.path.realpath(__file__)), "static", "assets"), 'img/favicon.ico', mimetype='image/x-icon')
@app.route('/site.webmanifest.json')
def static_webmanifest():
    return send_from_directory(os.path.join(os.path.dirname(os.path.realpath(__file__)), "static", "assets"), 'img/site.webmanifest.json', mimetype='application/manifest+json')
#endregion -------- STATIC ENDPOINTS --------
